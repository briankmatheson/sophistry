from .scoring import score_case
import os
import random
from django.http import JsonResponse
from rest_framework import decorators, response, status, viewsets
from rest_framework.filters import OrderingFilter
from django_filters.rest_framework import DjangoFilterBackend

from .models import TestCase, Run, Result
from .serializers import TestCaseSerializer, RunSerializer, ResultSerializer
from evals.tasks import score_run

def perform_create(self, serializer):
    run = serializer.save()
    score_run.delay(str(run.id))

def home(request):
    return JsonResponse({"ok": True, "service": "sophistry-backend", "version": os.environ.get("APP_VERSION", "dev")})


@decorators.api_view(["GET"])
def mobile_info(request):
    """Read-only constants the client needs."""
    from django.conf import settings as _s
    return response.Response({
        "version": os.environ.get("APP_VERSION", "dev"),
        "min_words": _s.SOPHISTRY_MIN_WORDS,
        "min_sentences": _s.SOPHISTRY_MIN_SENTENCES,
        "questions_per_session": int(os.environ.get("QUESTIONS_PER_SESSION", 4)),
    })


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
    run = Run.objects.create(name="mobile", notes="anonymized mobile run", status="created")
    return response.Response({"run_uuid": str(run.run_uuid)})


@decorators.api_view(["GET"])
def mobile_question(request):
    run_uuid = request.query_params.get("run_uuid")
    if not run_uuid:
        return response.Response({"detail": "run_uuid required"}, status=400)

    # Exclude questions already answered in this run
    answered_ids = list(
        Result.objects.filter(run_uuid=run_uuid, provider="human")
        .values_list("testcase_id", flat=True)
    )
    remaining = TestCase.objects.filter(is_active=True).exclude(id__in=answered_ids)
    ids = list(remaining.values_list("id", flat=True))

    if not ids:
        return response.Response({"detail": "no more questions"}, status=404)

    tc = TestCase.objects.get(id=random.choice(ids))
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

    # Structural scoring (primary)
    score_result = score_case(tc.prompt, answer)
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

    score_result = score_case(tc.prompt, answer)
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
    if testcase_id:
        try:
            tc = TestCase.objects.get(id=testcase_id)
            question_text = tc.prompt
        except TestCase.DoesNotExist:
            pass
    if not question_text and prompt:
        question_text = prompt

    if question_text and answer.strip():
        score_result = score_case(question_text, answer)
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
    if not slug or not prompt:
        return response.Response({"detail": "slug and prompt required"}, status=400)

    tc = TestCase.objects.create(slug=slug, title=title, prompt=prompt, is_active=False)
    return response.Response({"ok": True, "testcase_id": tc.id, "is_active": tc.is_active})


def _normalize_score(tc, answer_text, score_result):
    """Deprecated (rubric scoring). Kept for any legacy callsites."""
    return round((score_result.get("score_0_100", 0) or 0) / 100.0, 2)
