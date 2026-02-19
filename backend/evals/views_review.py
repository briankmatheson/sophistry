from uuid import UUID

from django.db.models import Avg
from rest_framework.decorators import api_view
from rest_framework.response import Response

from evals.models import Run, Result


def _classify(score: float | None) -> str | None:
    if score is None:
        return None
    s = float(score)
    if s >= 0.90:
        return "UNDERSTANDING"
    if s >= 0.70:
        return "REASONING"
    if s >= 0.40:
        return "BELIEF"
    return "FLUENCY"


@api_view(["GET"])
def review(request):
    """
    GET /api/mobile/review/?run_uuid=<uuid>
    """
    run_uuid = request.GET.get("run_uuid")
    if not run_uuid:
        return Response({"detail": "run_uuid required"}, status=400)

    # Validate UUID early (avoids noisy DB errors)
    try:
        UUID(run_uuid)
    except ValueError:
        return Response({"detail": "invalid run_uuid"}, status=400)

    # Resolve run_uuid -> Run
    try:
        run = Run.objects.get(run_uuid=run_uuid)
    except Run.DoesNotExist:
        return Response({"detail": "unknown run_uuid"}, status=404)

    # Get user's results for this run
    user_results = (
        Result.objects.filter(run=run, provider="human", status="done")
        .select_related("testcase")
        .order_by("created_at")
    )

    # IMPORTANT: "not ready yet" is not a 404
    if not user_results.exists():
        return Response(
            {"run_uuid": run_uuid, "status": "pending", "total": 0, "results": []},
            status=200,
        )

    rows = []
    for r in user_results:
        tc = r.testcase

        claude_result = (
            Result.objects.filter(testcase=tc, provider="anthropic", status="done")
            .order_by("-created_at")
            .first()
        )

        human_avg = (
            Result.objects.filter(testcase=tc, provider="human", status="done")
            .aggregate(avg=Avg("score"))["avg"]
        )

        rows.append(
            {
                "testcase_slug": tc.slug,
                "testcase_title": tc.title,
                "prompt": tc.prompt,
                "user_answer": r.output_text,
                "user_score": r.score,
                "user_score_details": r.score_details,
                "user_classification": (r.score_details or {}).get("band") or _classify(r.score),
                "claude_score": claude_result.score if claude_result else None,
                "claude_score_details": claude_result.score_details if claude_result else None,
                "claude_classification": ((claude_result.score_details or {}).get("band") if claude_result else None)
                or (_classify(claude_result.score) if claude_result else None),
                "human_avg_score": round(human_avg, 2) if human_avg is not None else None,
                "human_avg_classification": _classify(human_avg) if human_avg is not None else None,
            }
        )

    return Response(
        {
            "run_uuid": run_uuid,
            "status": "complete",
            "total": len(rows),
            "results": rows,
        }
    )
