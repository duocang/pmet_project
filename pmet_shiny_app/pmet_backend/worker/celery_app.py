from celery import Celery
import os

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

celery_app = Celery(
    "pmet_worker",
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=["pmet_backend.worker.tasks.pmet"],
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=3600 * 24,  # 24 hours
    result_expires=3600 * 24 * 7,  # 7 days
    worker_prefetch_multiplier=1,
    worker_concurrency=int(os.getenv("PMET_WORKERS", "2")),
)
