"""
Load seed data from fixtures/seed.json into the database.

Usage:
    python manage.py seed                  # load default seed.json
    python manage.py seed --file path.json # load custom seed file
    python manage.py seed --reset          # truncate and re-seed
"""

import json
from pathlib import Path

from django.core.management.base import BaseCommand
from django.db import transaction

from evals.models import TestSet, TestCase
from evals.vocab_learner import extract_from_prompt


class Command(BaseCommand):
    help = "Seed test sets and test cases from a JSON fixture"

    def add_arguments(self, parser):
        parser.add_argument(
            "--file",
            default=str(Path(__file__).resolve().parent.parent.parent / "fixtures" / "seed.json"),
            help="Path to seed JSON file (default: evals/fixtures/seed.json)",
        )
        parser.add_argument(
            "--reset",
            action="store_true",
            help="Truncate existing test sets and test cases before seeding",
        )

    @transaction.atomic
    def handle(self, *args, **options):
        seed_path = options["file"]
        reset = options["reset"]

        with open(seed_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        if reset:
            n_tc = TestCase.objects.all().delete()[0]
            n_ts = TestSet.objects.all().delete()[0]
            self.stdout.write(f"  Reset: deleted {n_tc} test cases, {n_ts} test sets")

        # ── Test Sets ──────────────────────────────────
        sets_data = data.get("test_sets", [])
        set_map = {}  # name -> TestSet
        created_sets = 0
        for ts in sets_data:
            obj, created = TestSet.objects.get_or_create(
                name=ts["name"],
                defaults={
                    "description": ts.get("description", ""),
                    "is_active": ts.get("is_active", True),
                },
            )
            set_map[ts["name"]] = obj
            if created:
                created_sets += 1

        self.stdout.write(f"  Test sets: {created_sets} created, {len(sets_data) - created_sets} existing")

        # ── Test Cases ─────────────────────────────────
        cases_data = data.get("test_cases", [])
        created_cases = 0
        skipped = 0
        for tc in cases_data:
            slug = tc["slug"]
            if TestCase.objects.filter(slug=slug).exists():
                skipped += 1
                continue

            test_set = set_map.get(tc.get("test_set"))
            prompt = tc["prompt"]

            TestCase.objects.create(
                slug=slug,
                title=tc.get("title", ""),
                prompt=prompt,
                tags=tc.get("tags"),
                is_active=tc.get("is_active", True),
                test_set=test_set,
                learned_vocab=extract_from_prompt(prompt),
            )
            created_cases += 1

        self.stdout.write(
            self.style.SUCCESS(
                f"  Test cases: {created_cases} created, {skipped} skipped (slug exists)"
            )
        )
        self.stdout.write(self.style.SUCCESS("  Seed complete."))
