"""Auto-generated migration — TestSet + TestCase.test_set FK."""

from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone
import uuid


class Migration(migrations.Migration):

    initial = True

    dependencies = []

    operations = [
        # ── TestSet ───────────────────────────────────
        migrations.CreateModel(
            name="TestSet",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("name", models.CharField(max_length=80, unique=True)),
                ("description", models.TextField(blank=True, default="")),
                ("is_active", models.BooleanField(default=True)),
                ("created_at", models.DateTimeField(default=django.utils.timezone.now)),
            ],
        ),
        # ── TestCase ──────────────────────────────────
        migrations.CreateModel(
            name="TestCase",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("slug", models.SlugField(max_length=128, unique=True)),
                ("title", models.CharField(blank=True, default="", max_length=200)),
                ("prompt", models.TextField()),
                ("expected", models.JSONField(blank=True, null=True)),
                ("tags", models.JSONField(blank=True, null=True)),
                ("is_active", models.BooleanField(default=True)),
                ("test_set", models.ForeignKey(
                    blank=True, null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name="testcases",
                    to="evals.testset",
                )),
                ("created_at", models.DateTimeField(default=django.utils.timezone.now)),
            ],
        ),
        # ── Participant ───────────────────────────────
        migrations.CreateModel(
            name="Participant",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("session_id", models.UUIDField(db_index=True, default=uuid.uuid4, unique=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
        ),
        # ── Run ───────────────────────────────────────
        migrations.CreateModel(
            name="Run",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("run_uuid", models.UUIDField(db_index=True, default=uuid.uuid4, editable=False, unique=True)),
                ("name", models.CharField(blank=True, default="", max_length=200)),
                ("notes", models.TextField(blank=True, default="")),
                ("created_at", models.DateTimeField(default=django.utils.timezone.now)),
                ("models_requested", models.JSONField(blank=True, null=True)),
                ("filters", models.JSONField(blank=True, null=True)),
                ("status", models.CharField(
                    choices=[("created", "created"), ("running", "running"), ("done", "done"), ("failed", "failed")],
                    default="created", max_length=32,
                )),
                ("total", models.IntegerField(default=0)),
                ("completed", models.IntegerField(default=0)),
                ("failed", models.IntegerField(default=0)),
            ],
        ),
        # ── Result ────────────────────────────────────
        migrations.CreateModel(
            name="Result",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("run_uuid", models.UUIDField(db_index=True)),
                ("provider", models.CharField(max_length=64)),
                ("model", models.CharField(max_length=128)),
                ("input_used", models.TextField()),
                ("output_text", models.TextField(blank=True, default="")),
                ("output_json", models.JSONField(blank=True, null=True)),
                ("latency_ms", models.IntegerField(blank=True, null=True)),
                ("tokens_in", models.IntegerField(blank=True, null=True)),
                ("tokens_out", models.IntegerField(blank=True, null=True)),
                ("score", models.FloatField(blank=True, null=True)),
                ("score_details", models.JSONField(blank=True, null=True)),
                ("error", models.TextField(blank=True, default="")),
                ("status", models.CharField(
                    choices=[("queued", "queued"), ("running", "running"), ("done", "done"), ("failed", "failed")],
                    default="queued", max_length=24,
                )),
                ("started_at", models.DateTimeField(blank=True, null=True)),
                ("finished_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(default=django.utils.timezone.now)),
                ("run", models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name="results",
                    to="evals.run",
                )),
                ("testcase", models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name="results",
                    to="evals.testcase",
                )),
            ],
        ),
    ]
