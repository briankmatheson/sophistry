
import re

BANDS = ["FLUENCY", "BELIEF", "REASONING", "UNDERSTANDING"]

def score_answer(testcase, answer_text) -> dict:
    rubric = testcase.expected or {}
    must_have = rubric.get("must_have", [])
    nice_to_have = rubric.get("nice_to_have", [])
    penalties = rubric.get("penalties", [])

    raw_points = 0
    matched = []
    missed = []
    penalty_hits = []

    # must_have scoring
    for item in must_have:
        pattern = item.get("pattern")
        points = item.get("points", 1)
        if pattern and re.search(pattern, answer_text, re.IGNORECASE):
            raw_points += points
            matched.append(pattern)
        else:
            missed.append(pattern)

    # nice_to_have scoring
    for item in nice_to_have:
        pattern = item.get("pattern")
        points = item.get("points", 1)
        if pattern and re.search(pattern, answer_text, re.IGNORECASE):
            raw_points += points
            matched.append(pattern)

    # penalties
    for item in penalties:
        pattern = item.get("pattern")
        points = item.get("points", 1)
        if pattern and re.search(pattern, answer_text, re.IGNORECASE):
            raw_points -= points
            penalty_hits.append(pattern)

    band = rubric.get("band", "REASONING")
    if band not in BANDS:
        band = "REASONING"

    return {
        "raw_points": raw_points,
        "band": band,
        "matched": matched,
        "missed": missed,
        "penalties": penalty_hits,
    }
