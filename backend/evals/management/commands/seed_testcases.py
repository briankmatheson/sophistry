"""
Seed (or update) eval TestCases from a JSON file. Idempotent by slug.

Supports two formats:

  v2 (Braintrust-compatible):
    { "input": {"prompt": "..."}, "expected": {...}, "metadata": {"slug": ..., "tags": [...], ...} }

  v1 (legacy Sophistry):
    { "slug": "...", "prompt": "...", "expected": {...}, "tags": [...], ... }

Auto-detected per record.
"""

import json
import os
from pathlib import Path
from typing import Optional

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from evals.models import TestCase, TestSet

DEFAULT_SEED_PATH = Path(__file__).resolve().parents[3] / "seed_data" / "testcases.json"


def _env_truthy(name: str) -> bool:
    v = os.environ.get(name)
    if v is None:
        return False
    return v.strip().lower() in {"1", "true", "yes", "y", "on"}


def _is_v2(item: dict) -> bool:
    """Detect Braintrust v2 format by presence of top-level 'input' dict."""
    return isinstance(item.get("input"), dict)


def _normalize(item: dict) -> dict:
    """Normalize a v1 or v2 record into flat fields matching TestCase model."""
    if _is_v2(item):
        inp = item.get("input", {})
        exp = item.get("expected", {})
        meta = item.get("metadata", {})
        return {
            "slug": meta.get("slug", ""),
            "title": meta.get("title", ""),
            "prompt": inp.get("prompt", ""),
            "expected": exp if exp else None,
            "tags": meta.get("tags"),
            "is_active": bool(meta.get("is_active", True)),
        }
    else:
        return {
            "slug": item.get("slug", ""),
            "title": item.get("title", "") or "",
            "prompt": item.get("prompt", "") or "",
            "expected": item.get("expected"),
            "tags": item.get("tags"),
            "is_active": bool(item.get("is_active", True)),
        }


# Tag -> TestSet name mapping
TAG_MAP = {
    "quantum-mechanics": "Quantum Mechanics",
    "physics": "Physics",
    "phlogiston": "Phlogiston",
    "sociobiology": "Sociobiology",
    "socio-biology": "Sociobiology",
    "philosophy": "Philosophy",
    "cs": "Computer Science",
    "computer-science": "Computer Science",
    "math": "Mathematics",
    "mathematics": "Mathematics",
    "science": "Science",
    "science-history": "Science History",
    "biology": "Biology",
    "medicine": "Medicine",
    "geology": "Geology",
    "earth-science": "Earth Science",
    "statistics": "Statistics",
    "psychology": "Psychology",
    "economics": "Economics",
    "game-theory": "Game Theory",
    "logic": "Logic",
    "linguistics": "Linguistics",
    "methodology": "Methodology",
    "pop-culture": "Pop Culture",
    "current-events": "Current Events",
    "paradoxes": "Paradoxes & Puzzles",
}


def infer_test_set_name(item: dict) -> Optional[str]:
    """Determine TestSet name from explicit field, metadata.category, or tags."""
    # v2: check metadata.category first
    if _is_v2(item):
        meta = item.get("metadata", {})
        cat = meta.get("category", "")
        if cat and cat in TAG_MAP:
            return TAG_MAP[cat]
        # explicit test_set in metadata
        ts = meta.get("test_set") or meta.get("test_set_name")
        if isinstance(ts, str) and ts.strip():
            return ts.strip()
        tags = meta.get("tags", [])
    else:
        # v1: explicit field
        ts = item.get("test_set") or item.get("test_set_name")
        if isinstance(ts, str) and ts.strip():
            return ts.strip()
        tags = item.get("tags") or []

    if not isinstance(tags, list):
        tags = []

    for tag in tags:
        if not isinstance(tag, str):
            continue
        if tag in TAG_MAP:
            return TAG_MAP[tag]

    # fallback: promote first hyphenated tag
    for tag in tags:
        if isinstance(tag, str) and tag and len(tag) <= 40 and "-" in tag:
            return tag.replace("-", " ").title()

    return None


class Command(BaseCommand):
    help = "Seed (or update) eval TestCases from a JSON file (v1 or v2 format). Idempotent by slug."

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
            help="Allow seeding when DEBUG=False",
        )

    def handle(self, *args, **opts):
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
        changes = []

        with transaction.atomic():
            for item in payload:
                if not isinstance(item, dict):
                    raise CommandError("Each seed entry must be a JSON object")

                data = _normalize(item)
                slug = (data.pop("slug", "") or "").strip()
                if not slug:
                    raise CommandError("Each seed entry must include a non-empty slug")

                # Resolve TestSet
                test_set_name = infer_test_set_name(item)
                test_set_obj = None
                if test_set_name:
                    test_set_obj, _ = TestSet.objects.get_or_create(
                        name=test_set_name,
                        defaults={
                            "description": f"Seeded set: {test_set_name}",
                            "is_active": True,
                        },
                    )

                defaults = {**data}
                if test_set_obj:
                    defaults["test_set"] = test_set_obj

                obj, was_created = TestCase.objects.get_or_create(
                    slug=slug, defaults=defaults
                )

                if was_created:
                    created += 1
                    changes.append((slug, "created"))
                    continue

                # Check if update needed
                dirty = False
                for field, value in data.items():
                    if getattr(obj, field) != value:
                        dirty = True
                        setattr(obj, field, value)

                desired_ts_id = test_set_obj.id if test_set_obj else None
                if obj.test_set_id != desired_ts_id:
                    dirty = True
                    obj.test_set = test_set_obj

                if dirty:
                    updated += 1
                    changes.append((slug, "updated"))
                    if not opts["dry_run"]:
                        obj.save()
                else:
                    unchanged += 1

            if opts["dry_run"]:
                transaction.set_rollback(True)

        for slug, action in changes:
            self.stdout.write(f"{action}: {slug}")

        self.stdout.write(
            self.style.SUCCESS(
                f"Seed complete. created={created} updated={updated} "
                f"unchanged={unchanged} dry_run={opts['dry_run']}"
            )
        )
