from .scoring import score_answer
import random
from django.http import JsonResponse
from rest_framework import decorators, response, status, viewsets
from rest_framework.filters import OrderingFilter
from django_filters.rest_framework import DjangoFilterBackend

from .models import TestCase, Run, Result
from .serializers import TestCaseSerializer, RunSerializer, ResultSerializer


def home(request):
    return JsonResponse({"ok": True, "service": "sophistry-backend", "version": "0.5.0"})


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
    answer = request.data.get("answer", "")

    if not run_uuid or not testcase_id:
        return response.Response(
            {"detail": "run_uuid and testcase_id required"}, status=400
        )

    run = Run.objects.get(run_uuid=run_uuid)
    tc = TestCase.objects.get(id=testcase_id)

    # Score the answer
    score_result = score_answer(tc, answer)
    normalized_score = _normalize_score(tc, answer, score_result)

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
def mobile_create_testcase(request):
    slug = request.data.get("slug")
    prompt = request.data.get("prompt")
    title = request.data.get("title", "")
    if not slug or not prompt:
        return response.Response({"detail": "slug and prompt required"}, status=400)

    tc = TestCase.objects.create(slug=slug, title=title, prompt=prompt, is_active=False)
    return response.Response({"ok": True, "testcase_id": tc.id, "is_active": tc.is_active})


def _normalize_score(tc, answer_text, score_result):
    """Normalize raw points to 0.0-1.0 range."""
    rubric = tc.expected or {}
    must_have = rubric.get("must_have", [])
    nice_to_have = rubric.get("nice_to_have", [])

    max_points = sum(item.get("points", 1) for item in must_have)
    max_points += sum(item.get("points", 1) for item in nice_to_have)

    if max_points == 0:
        # Legacy format — simple keyword match against "answer" field
        answer_key = rubric.get("answer", "")
        if not answer_key:
            return None
        keywords = [w.strip().lower() for w in answer_key.split() if len(w) > 3]
        if not keywords:
            return None
        matches = sum(1 for kw in keywords if kw in answer_text.lower())
        return round(matches / len(keywords), 2)

    raw = score_result.get("raw_points", 0)
    return round(max(0.0, min(1.0, raw / max_points)), 2)
