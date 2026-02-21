import uuid
from django.db import models
from django.utils import timezone


class TestSet(models.Model):
    name = models.CharField(max_length=80, unique=True)
    description = models.TextField(blank=True, default="")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(default=timezone.now)

    def __str__(self):
        return self.name


class TestCase(models.Model):
    slug = models.SlugField(max_length=128, unique=True)
    title = models.CharField(max_length=200, blank=True, default="")
    prompt = models.TextField()
    expected = models.JSONField(blank=True, null=True)
    tags = models.JSONField(blank=True, null=True)
    is_active = models.BooleanField(default=True)
    test_set = models.ForeignKey(
        TestSet, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="testcases",
    )
    learned_vocab = models.JSONField(
        blank=True, null=True,
        help_text="Auto-learned keywords from prompt + answers. Merged into scoring vocab.",
    )
    created_at = models.DateTimeField(default=timezone.now)

    def __str__(self):
        return self.slug

class Run(models.Model):
    run_uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False, db_index=True)
    name = models.CharField(max_length=200, blank=True, default="")
    notes = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(default=timezone.now)

    models_requested = models.JSONField(blank=True, null=True)
    filters = models.JSONField(blank=True, null=True)

    status = models.CharField(
        max_length=32,
        default="created",
        choices=[("created","created"),("running","running"),("done","done"),("failed","failed")],
    )
    total = models.IntegerField(default=0)
    completed = models.IntegerField(default=0)
    failed = models.IntegerField(default=0)

class Result(models.Model):
    run_uuid = models.UUIDField(db_index=True)
    run = models.ForeignKey(Run, on_delete=models.CASCADE, related_name="results")
    testcase = models.ForeignKey(TestCase, on_delete=models.CASCADE, related_name="results")

    provider = models.CharField(max_length=64)
    model = models.CharField(max_length=128)

    input_used = models.TextField()
    output_text = models.TextField(blank=True, default="")
    output_json = models.JSONField(blank=True, null=True)

    latency_ms = models.IntegerField(blank=True, null=True)
    tokens_in = models.IntegerField(blank=True, null=True)
    tokens_out = models.IntegerField(blank=True, null=True)

    score = models.FloatField(blank=True, null=True)
    score_details = models.JSONField(blank=True, null=True)

    error = models.TextField(blank=True, default="")

    status = models.CharField(
        max_length=24,
        default="queued",
        choices=[("queued","queued"),("running","running"),("done","done"),("failed","failed")],
    )
    started_at = models.DateTimeField(blank=True, null=True)
    finished_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now)

class Participant(models.Model):
    session_id = models.UUIDField(default=uuid.uuid4, unique=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return str(self.session_id)
