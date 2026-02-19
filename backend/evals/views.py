from .scoring import score_answer
import random
from django.http import JsonResponse
from rest_framework import decorators, response, status, viewsets
from rest_framework.filters import OrderingFilter
from django_filters.rest_framework import DjangoFilterBackend

from .models import TestCase, Run, Result
from .serializers import TestCaseSerializer, RunSerializer, ResultSerializer

def home(request):
    return JsonResponse({"ok": True, "service": "sophistry-backend", "version": "0.3.0"})

class TestCaseViewSet(viewsets.ModelViewSet):
    queryset = TestCase.objects.all().order_by("id")
    serializer_class = TestCaseSerializer
    filter_backends = [DjangoFilterBackend, OrderingFilter]
    filterset_fields = ["is_active"]
    ordering_fields = ["id","slug","created_at"]

class RunViewSet(viewsets.ModelViewSet):
    lookup_field = "run_uuid"
    queryset = Run.objects.all().order_by("-created_at")
    serializer_class = RunSerializer

class ResultViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Result.objects.select_related("testcase","run").all().order_by("-created_at")
    serializer_class = ResultSerializer
    filter_backends = [DjangoFilterBackend, OrderingFilter]
    filterset_fields = ["run_uuid","provider","model","status"]
    ordering_fields = ["created_at","latency_ms","score"]

# Mobile endpoints
@decorators.api_view(["POST"])
def mobile_create_run(request):
    run = Run.objects.create(name="mobile", notes="anonymized mobile run", status="created")
    return response.Response({"run_uuid": str(run.run_uuid)})

@decorators.api_view(["GET"])
def mobile_question(request):
    run_uuid = request.query_params.get("run_uuid")
    if not run_uuid:
        return response.Response({"detail":"run_uuid required"}, status=400)

    ids = list(TestCase.objects.filter(is_active=True).values_list("id", flat=True))
    if not ids:
        return response.Response({"detail":"no active testcases"}, status=404)

    tc = TestCase.objects.get(id=random.choice(ids))
    return response.Response({"testcase_id": tc.id, "slug": tc.slug, "prompt": tc.prompt})

@decorators.api_view(["POST"])
def mobile_answer(request):
    run_uuid = request.data.get("run_uuid")
    testcase_id = request.data.get("testcase_id")
    answer = request.data.get("answer", "")

    if not run_uuid or not testcase_id:
        return response.Response({"detail":"run_uuid and testcase_id required"}, status=400)

    run = Run.objects.get(run_uuid=run_uuid)
    tc = TestCase.objects.get(id=testcase_id)

    r = Result.objects.create(
        run=run,
        testcase=tc,
        run_uuid=run.run_uuid,
        provider="user",
        model="flutter",
        input_used=tc.prompt,
        output_text=answer,
        status="done",
    )
    return response.Response({"ok": True, "result_id": r.id})

@decorators.api_view(["POST"])
def mobile_create_testcase(request):
    slug = request.data.get("slug")
    prompt = request.data.get("prompt")
    title = request.data.get("title", "")
    if not slug or not prompt:
        return response.Response({"detail":"slug and prompt required"}, status=400)

    tc = TestCase.objects.create(slug=slug, title=title, prompt=prompt, is_active=False)
    return response.Response({"ok": True, "testcase_id": tc.id, "is_active": tc.is_active})


from rest_framework.decorators import api_view
from rest_framework.response import Response
from .models import Result

@api_view(["GET"])
def mobile_results(request):
    run_uuid = request.GET.get("run_uuid")
    testcase_id = request.GET.get("testcase_id")

    results = Result.objects.filter(run_uuid=run_uuid, testcase_id=testcase_id)

    grouped = {
        "me": [],
        "claude": [],
        "humans": [],
        "other": []
    }

    for r in results:
        provider = (r.provider or "").lower()
        entry = {
            "id": r.id,
            "score": r.score,
            "score_details": r.score_details,
            "provider": r.provider
        }

        if provider == "me":
            grouped["me"].append(entry)
        elif "claude" in provider:
            grouped["claude"].append(entry)
        elif provider == "human":
            grouped["humans"].append(entry)
        else:
            grouped["other"].append(entry)

    return Response(grouped)
