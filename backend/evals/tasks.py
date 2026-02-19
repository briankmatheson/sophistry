import time
from celery import shared_task
from .models import Run, Result

CATEGORIES = ["noesis", "dianoia", "pistis", "eikasia"]

@shared_task
def score_run(run_id):
    run = Run.objects.get(id=run_id)

    for cat in CATEGORIES:
        Result.objects.create(
            run=run,
            category=cat,
            score=0.75,  # stub for now
            explanation=f"Stub score for {cat}"
        )

    return "done"
