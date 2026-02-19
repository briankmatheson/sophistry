from django.db.models import Avg
from rest_framework.decorators import api_view
from rest_framework.response import Response
from evals.models import Result, Run


@api_view(["GET"])
def review(request):
    """
    GET /api/mobile/review/?run_uuid=<uuid>

    Returns per-question comparison:
      - user's score + output
      - claude's most recent score for that testcase
      - average human score for that testcase
      - divided line classification
    """
    run_uuid = request.GET.get("run_uuid")
    if not run_uuid:
        return Response({"detail": "run_uuid required"}, status=400)

    # Get user's results for this run
    user_results = (
        Result.objects.filter(run_uuid=run_uuid, provider="human", status="done")
        .select_related("testcase")
        .order_by("created_at")
    )

    if not user_results.exists():
        return Response({"detail": "no results for this run"}, status=404)

    rows = []
    for r in user_results:
        tc = r.testcase

        # Claude's most recent result for this testcase
        claude_result = (
            Result.objects.filter(
                testcase=tc, provider="anthropic", status="done"
            )
            .order_by("-created_at")
            .first()
        )

        # Average human score for this testcase
        human_avg = Result.objects.filter(
            testcase=tc, provider="human", status="done"
        ).aggregate(avg=Avg("score"))["avg"]

        rows.append(
            {
                "testcase_slug": tc.slug,
                "testcase_title": tc.title,
                "prompt": tc.prompt,
                "user_answer": r.output_text,
                "user_score": r.score,
                "user_score_details": r.score_details,
                "user_classification": _classify(r.score),
                "claude_score": claude_result.score if claude_result else None,
                "claude_score_details": (
                    claude_result.score_details if claude_result else None
                ),
                "claude_classification": (
                    _classify(claude_result.score) if claude_result else None
                ),
                "human_avg_score": round(human_avg, 2) if human_avg else None,
                "human_avg_classification": (
                    _classify(human_avg) if human_avg else None
                ),
            }
        )

    return Response(
        {
            "run_uuid": run_uuid,
            "total": len(rows),
            "results": rows,
        }
    )


def _classify(score):
    """Map score to Divided Line classification."""
    if score is None:
        return None
    if score >= 0.85:
        return {"level": "Noesis", "label": "Understanding", "icon": "☀️"}
    elif score >= 0.65:
        return {"level": "Dianoia", "label": "Reasoning", "icon": "📐"}
    elif score >= 0.40:
        return {"level": "Pistis", "label": "Belief", "icon": "🤝"}
    else:
        return {"level": "Eikasia", "label": "Imagination", "icon": "🪞"}
