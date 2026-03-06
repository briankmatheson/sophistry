#!/usr/bin/env python3
"""Convert Sophistry testcases.json v1 → v2 (Braintrust-compatible superset)."""

import json
import sys

DIFFICULTY_TAGS = {"easy", "medium", "hard"}

def infer_category(tags):
    """First tag that isn't a difficulty level."""
    for t in tags:
        if t not in DIFFICULTY_TAGS:
            return t
    return "general"

def infer_difficulty(tags):
    """Last tag that is a difficulty level, or 'medium' default."""
    for t in reversed(tags):
        if t in DIFFICULTY_TAGS:
            return t
    return "medium"

def convert_record(rec):
    tags = rec.get("tags", [])
    expected_raw = rec.get("expected", {})

    # Build expected — keep everything that was there, ensure answer exists
    expected = {}
    if isinstance(expected_raw, dict):
        expected = dict(expected_raw)
    if "answer" not in expected:
        expected["answer"] = ""

    # Build metadata
    metadata = {
        "slug": rec.get("slug", ""),
        "title": rec.get("title", ""),
        "tags": tags,
        "category": infer_category(tags),
        "difficulty": infer_difficulty(tags),
        "is_active": rec.get("is_active", True),
    }

    return {
        "input": {
            "prompt": rec.get("prompt", ""),
        },
        "expected": expected,
        "metadata": metadata,
    }

def main():
    input_path = sys.argv[1] if len(sys.argv) > 1 else "testcases.json"
    output_path = sys.argv[2] if len(sys.argv) > 2 else "testcases_v2.json"

    with open(input_path) as f:
        records = json.load(f)

    converted = [convert_record(r) for r in records]

    with open(output_path, "w") as f:
        json.dump(converted, f, indent=2, ensure_ascii=False)

    print(f"Converted {len(converted)} records: {input_path} → {output_path}")

if __name__ == "__main__":
    main()
