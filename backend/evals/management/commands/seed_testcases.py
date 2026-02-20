import json
import os
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from evals.models import TestCase

DEFAULT_SEED_PATH = Path(__file__).resolve().parents[3] / "seed_data" / "testcases.json"


def _env_truthy(name: str) -> bool:
    v = os.environ.get(name)
    if v is None:
        return False
    return v.strip().lower() in {"1", "true", "yes", "y", "on"}


class Command(BaseCommand):
    help = "Seed (or update) eval TestCases from a JSON file. Idempotent by slug."

    def add_arguments(self, parser):
        parser.add_argument(
            "--path",
            default=str(DEFAULT_SEED_PATH),
            help=f"Path to JSON seed file (default: {DEFAULT_SEED_PATH})",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Print what would change without writing to the DB",
        )
        parser.add_argument(
            "--allow-prod",
            action="store_true",
            help="Allow seeding when DEBUG=False (still requires SOPHISTRY_ALLOW_SEED=1 unless --allow-prod is used)",
        )

    def handle(self, *args, **opts):
        # Guardrails: by default only seed in DEBUG environments.
        # Override requires an explicit env var (or --allow-prod) to reduce foot-guns.
        if not settings.DEBUG:
            if not opts["allow_prod"] and not _env_truthy("SOPHISTRY_ALLOW_SEED"):
                raise CommandError(
                    "Refusing to seed with DEBUG=False. Set SOPHISTRY_ALLOW_SEED=1 or pass --allow-prod."
                )

        path = Path(opts["path"]).expanduser().resolve()
        if not path.exists():
            raise CommandError(f"Seed file not found: {path}")

        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except Exception as e:
            raise CommandError(f"Failed to parse JSON seed file {path}: {e}")

        if not isinstance(payload, list):
            raise CommandError("Seed file must be a JSON array of objects")

        created = 0
        updated = 0
        unchanged = 0

        def normalize(item):
            return {
                "title": item.get("title", "") or "",
                "prompt": item.get("prompt", "") or "",
                "expected": item.get("expected"),
                "tags": item.get("tags"),
                "is_active": bool(item.get("is_active", True)),
            }

        changes = []

        with transaction.atomic():
            for item in payload:
                if not isinstance(item, dict):
                    raise CommandError("Each seed entry must be a JSON object")

                slug = (item.get("slug") or "").strip()
                if not slug:
                    raise CommandError("Each seed entry must include a non-empty 'slug'")

                data = normalize(item)
                obj, was_created = TestCase.objects.get_or_create(slug=slug, defaults=data)

                if was_created:
                    created += 1
                    changes.append((slug, "created"))
                    continue

                # Determine if we need to update
                dirty = False
                for field, value in data.items():
                    if getattr(obj, field) != value:
                        dirty = True
                        setattr(obj, field, value)

                if dirty:
                    updated += 1
                    changes.append((slug, "updated"))
                    if not opts["dry_run"]:
                        obj.save()
                else:
                    unchanged += 1

            if opts["dry_run"]:
                # Roll back everything in a dry-run
                transaction.set_rollback(True)

        for slug, action in changes:
            self.stdout.write(f"{action}: {slug}")

        self.stdout.write(
            self.style.SUCCESS(
                f"Seed complete. created={created} updated={updated} unchanged={unchanged} dry_run={opts['dry_run']}"
            )
        )
