import time
from celery import shared_task

@shared_task
def noop():
    time.sleep(0.01)
    return {"ok": True}
