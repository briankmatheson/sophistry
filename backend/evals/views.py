from .scoring import score_case
import os
import random
from django.http import JsonResponse
from rest_framework import decorators, response, status, viewsets
from rest_framework.filters import OrderingFilter
from django_filters.rest_framework import DjangoFilterBackend

from .models import TestSet, TestCase, Run, Result
from .serializers import TestSetSerializer, TestCaseSerializer, RunSerializer, ResultSerializer
from evals.tasks import score_run
from .vocab_learner import extract_from_prompt, merge_answer_vocab

def perform_create(self, serializer):
    run = serializer.save()
    score_run.delay(str(run.id))

def home(request):
    return JsonResponse({"ok": True, "service": "sophistry-backend", "version": os.environ.get("APP_VERSION", "dev")})


@decorators.api_view(["GET"])
def mobile_info(request):
    """Read-only constants the client needs."""
    from django.conf import settings as _s
    test_sets = list(
        TestSet.objects.filter(is_active=True)
        .order_by("name")
        .values("id", "name", "description")
    )
    return response.Response({
        "version": os.environ.get("APP_VERSION", "dev"),
        "min_words": _s.SOPHISTRY_MIN_WORDS,
        "min_sentences": _s.SOPHISTRY_MIN_SENTENCES,
        "questions_per_session": int(os.environ.get("QUESTIONS_PER_SESSION", 4)),
        "test_sets": test_sets,
    })



@decorators.api_view(["GET"])
def mobile_question_sets(request):
    """Return available question sets for dropdowns.

    Optional query param:
      - run_uuid: include answered counts for that run (human provider).
    """
    run_uuid = request.query_params.get("run_uuid")

    answered_ids = set()
    if run_uuid:
        answered_ids = set(
            Result.objects.filter(run_uuid=run_uuid, provider="human")
            .values_list("testcase_id", flat=True)
        )

    sets = []
    qs = TestSet.objects.all().order_by("name")
    for s in qs:
        total = TestCase.objects.filter(is_active=True, test_set=s).count()
        if total == 0 and s.is_active is False:
            # hide empty + inactive sets
            continue
        answered = 0
        if answered_ids:
            answered = TestCase.objects.filter(id__in=answered_ids, test_set=s).count()
        sets.append({
            "id": s.id,
            "name": s.name,
            "description": s.description,
            "is_active": s.is_active,
            "count": total,
            "answered": answered,
        })

    # Pseudo-set: all active questions
    all_total = TestCase.objects.filter(is_active=True).count()
    all_answered = len(answered_ids) if answered_ids else 0
    sets.insert(0, {
        "id": None,
        "name": "all",
        "description": "All active questions",
        "is_active": True,
        "count": all_total,
        "answered": all_answered,
    })

    return response.Response({"ok": True, "sets": sets})


class TestCaseViewSet(viewsets.ModelViewSet):
    queryset = TestCase.objects.all().order_by("id")
    serializer_class = TestCaseSerializer
    filter_backends = [DjangoFilterBackend, OrderingFilter]
    filterset_fields = ["is_active"]
    ordering_fields = ["id", "slug", "created_at"]


class RunViewSet(viewsets.ModelViewSet):
    lookup_field = "run_uuid"
    queryset = Run.objects.all().order_by("-created_at")
    serializer_class = RunSerializer


class ResultViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = (
        Result.objects.select_related("testcase", "run")
        .all()
        .order_by("-created_at")
    )
    serializer_class = ResultSerializer
    filter_backends = [DjangoFilterBackend, OrderingFilter]
    filterset_fields = ["run_uuid", "provider", "model", "status"]
    ordering_fields = ["created_at", "latency_ms", "score"]


# ─── Mobile endpoints ─────────────────────────────────────


@decorators.api_view(["POST"])
def mobile_create_run(request):
    test_set_id = request.data.get("test_set_id")
    test_set_name = request.data.get("test_set") or request.data.get("set")
    filters = {}
    if test_set_id:
        filters["test_set_id"] = int(test_set_id)
    elif test_set_name:
        try:
            ts = TestSet.objects.get(name=str(test_set_name))
            filters["test_set_id"] = int(ts.id)
        except TestSet.DoesNotExist:
            pass
    run = Run.objects.create(
        name="mobile",
        notes="anonymized mobile run",
        status="created",
        filters=filters or None,
    )
    return response.Response({"run_uuid": str(run.run_uuid)})


@decorators.api_view(["GET"])
def mobile_question(request):
    run_uuid = request.query_params.get("run_uuid")
    if not run_uuid:
        return response.Response({"detail": "run_uuid required"}, status=400)

    # Resolve test_set_id from query param or from the run's filters
    # Supported params:
    #   - test_set_id=<int>
    #   - test_set=<name>  (e.g. "Quantum Mechanics" or "benchmark")
    #   - set=<name>       (alias)
    test_set_id = request.query_params.get("test_set_id")
    test_set_name = request.query_params.get("test_set") or request.query_params.get("set")

    if test_set_name:
        if test_set_name.strip().lower() == "all":
            test_set_id = None
        elif not test_set_id:
            try:
                ts = TestSet.objects.get(name=test_set_name)
                test_set_id = ts.id
            except TestSet.DoesNotExist:
                # ignore unknown set name (acts like "all")
                test_set_id = None

    if not test_set_id:
        try:
            run = Run.objects.get(run_uuid=run_uuid)
            test_set_id = (run.filters or {}).get("test_set_id")
        except Run.DoesNotExist:
            pass

    # Exclude questions already answered in this run
    answered_ids = list(
        Result.objects.filter(run_uuid=run_uuid, provider="human")
        .values_list("testcase_id", flat=True)
    )
    remaining = TestCase.objects.filter(is_active=True).exclude(id__in=answered_ids)
    if test_set_id:
        remaining = remaining.filter(test_set_id=int(test_set_id))
    ids = list(remaining.values_list("id", flat=True))

    if not ids:
        return response.Response({"detail": "no more questions"}, status=404)

    tc = TestCase.objects.get(id=random.choice(ids))

    # Seed learned_vocab from prompt if not yet populated
    if not tc.learned_vocab:
        tc.learned_vocab = extract_from_prompt(tc.prompt)
        tc.save(update_fields=["learned_vocab"])

    return response.Response({
        "testcase_id": tc.id,
        "slug": tc.slug,
        "title": tc.title,
        "prompt": tc.prompt,
    })


@decorators.api_view(["POST"])
def mobile_answer(request):
    run_uuid = request.data.get("run_uuid")
    testcase_id = request.data.get("testcase_id")
    # Back-compat: clients may send either "answer" or "output_text"
    answer = request.data.get("answer")
    if answer is None:
        answer = request.data.get("output_text", "")

    if not run_uuid or not testcase_id:
        return response.Response(
            {"detail": "run_uuid and testcase_id required"}, status=400
        )

    run = Run.objects.get(run_uuid=run_uuid)
    tc = TestCase.objects.get(id=testcase_id)

    # Learn vocabulary from this answer
    tc.learned_vocab = merge_answer_vocab(tc.learned_vocab, answer)
    tc.save(update_fields=["learned_vocab"])

    # Structural scoring with learned vocab
    score_result = score_case(tc.prompt, answer, learned_vocab=tc.learned_vocab, question_slug=tc.slug)
    raw = score_result.get("score", 0) or 0
    # score is already 0..1 from structural_scoring; normalize defensively
    normalized_score = round(raw if raw <= 1.0 else raw / 100.0, 2)

    r = Result.objects.create(
        run=run,
        testcase=tc,
        run_uuid=run.run_uuid,
        provider="human",
        model="web",
        input_used=tc.prompt,
        output_text=answer,
        score=normalized_score,
        score_details=score_result,
        status="done",
    )

    # Update run counters
    run.completed = Result.objects.filter(run_uuid=run.run_uuid, status="done").count()
    run.total = max(run.total, run.completed)
    run.save(update_fields=["completed", "total"])

    return response.Response({
        "ok": True,
        "result_id": r.id,
        "score": normalized_score,
        "score_details": score_result,
    })


@decorators.api_view(["POST"])
def mobile_preview_score(request):
    """Preview structural score without creating a Result."""
    testcase_id = request.data.get("testcase_id")
    answer = request.data.get("answer")
    if answer is None:
        answer = request.data.get("output_text", "")

    if not testcase_id:
        return response.Response({"detail": "testcase_id required"}, status=400)

    try:
        tc = TestCase.objects.get(id=testcase_id)
    except TestCase.DoesNotExist:
        return response.Response({"detail": "unknown testcase_id"}, status=404)

    score_result = score_case(tc.prompt, answer, learned_vocab=tc.learned_vocab, question_slug=tc.slug)
    raw = score_result.get("score", 0) or 0
    normalized_score = round(raw if raw <= 1.0 else raw / 100.0, 2)

    return response.Response(
        {
            "ok": True,
            "score": normalized_score,
            "score_details": score_result,
        }
    )


@decorators.api_view(["POST"])
def mobile_validate(request):
    """Validate answer text (min chars / sentences) and optionally score when
    both a question prompt and answer are provided.  Never persists anything."""
    answer = request.data.get("answer") or request.data.get("output_text") or ""
    prompt = request.data.get("prompt")          # free-text question
    testcase_id = request.data.get("testcase_id")  # OR existing testcase

    from django.conf import settings as _s
    min_words = int(request.data.get("min_words", _s.SOPHISTRY_MIN_WORDS))
    min_sentences = int(request.data.get("min_sentences", _s.SOPHISTRY_MIN_SENTENCES))

    # --- basic validation (always returned) ---
    from .structural import count_words, count_sentences
    wc = count_words(answer)
    sc = count_sentences(answer)
    validation = {
        "word_count": wc,
        "sentence_count": sc,
        "min_words": min_words,
        "min_sentences": min_sentences,
        "words_ok": wc >= min_words,
        "sentences_ok": sc >= min_sentences,
        "ok": wc >= min_words and sc >= min_sentences,
    }

    payload = {"ok": True, "validation": validation}

    # --- optional scoring (needs a prompt) ---
    question_text = None
    learned = None
    slug = "q"
    tc = None
    if testcase_id:
        try:
            tc = TestCase.objects.get(id=testcase_id)
            question_text = tc.prompt
            learned = tc.learned_vocab
            slug = tc.slug
        except TestCase.DoesNotExist:
            pass
    if not question_text and prompt:
        question_text = prompt

    if question_text and answer.strip():
        score_result = score_case(question_text, answer, learned_vocab=learned, question_slug=slug)
        raw = score_result.get("score", 0) or 0
        normalized_score = round(raw if raw <= 1.0 else raw / 100.0, 2)
        payload["scored"] = True
        payload["score"] = normalized_score
        payload["score_details"] = score_result
    else:
        payload["scored"] = False

    return response.Response(payload)


@decorators.api_view(["POST"])
def mobile_create_testcase(request):
    slug = request.data.get("slug")
    prompt = request.data.get("prompt")
    title = request.data.get("title", "")
    test_set_id = request.data.get("test_set_id")
    test_set_name = request.data.get("test_set") or request.data.get("set")
    if not slug or not prompt:
        return response.Response({"detail": "slug and prompt required"}, status=400)

    # User submissions go to "unmoderated" set by default
    if not test_set_id:
        unmod, _ = TestSet.objects.get_or_create(
            name="unmoderated",
            defaults={"description": "User-submitted questions awaiting review", "is_active": False},
        )
        test_set_id = unmod.id

    sample_answer = request.data.get("sample_answer", "")

    # Seed learned vocab from prompt + sample answer
    learned = extract_from_prompt(prompt)
    if sample_answer.strip():
        learned = merge_answer_vocab(learned, sample_answer)

    tc = TestCase.objects.create(
        slug=slug, title=title, prompt=prompt,
        is_active=False, test_set_id=test_set_id,
        learned_vocab=learned,
    )
    return response.Response({"ok": True, "testcase_id": tc.id, "is_active": tc.is_active})


def _normalize_score(tc, answer_text, score_result):
    """Deprecated (rubric scoring). Kept for any legacy callsites."""
    return round((score_result.get("score_0_100", 0) or 0) / 100.0, 2)
