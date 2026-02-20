"""Scoring entrypoint.

Sophistry v0.5.x used rubric/regex scoring.

Sophistry v0.6+ (this bundle) uses **structural scoring** as the primary score:
how well an answer *structurally matches* the prompt.

Correctness scoring (rubrics / model judges) can be layered later.
"""

from __future__ import annotations

import os
from pathlib import Path

from django.conf import settings

from .structural import score_structural
from .structural_scoring import load_vocab, score_structural_alignment

_VOCAB = None


def _get_vocab() -> dict:
    global _VOCAB
    if _VOCAB is None:
        default = Path(__file__).parent / "structural_vocab.yaml"
        path = os.environ.get("STRUCTURAL_VOCAB_PATH", str(default))
        _VOCAB = load_vocab(path)
    return _VOCAB


def score_case(prompt: str, model_answer: str) -> dict:
    structural = score_structural_alignment(prompt, model_answer, _get_vocab())
    return {
        "score": structural["structural_score"],
        "score_details": structural,
    }


def score_answer(testcase, answer_text: str) -> dict:
    """Return a structured verdict for an answer.

    The returned dict is intended to be stored in Result.score_details.
    """
    expected = testcase.expected or {}
    validation = expected.get("validation") if isinstance(expected, dict) else None

    # Defaults from settings, overridable per-testcase via expected.validation
    min_words = settings.SOPHISTRY_MIN_WORDS
    min_sentences = settings.SOPHISTRY_MIN_SENTENCES

    if isinstance(validation, dict):
        min_words = int(validation.get("min_words") or min_words)
        min_sentences = int(validation.get("min_sentences") or min_sentences)

    v = score_structural(
        testcase.prompt,
        answer_text,
        min_words=min_words,
        min_sentences=min_sentences,
    )

    wc = int(v.signals.get("word_count", 0) or 0)
    sc = int(v.signals.get("sentence_count", 0) or 0)
    val_ok = (wc >= min_words) and (sc >= min_sentences)

    return {
        "score_0_100": v.score_0_100,
        "band": v.band,
        "signals": v.signals,
        "notes": v.notes,
        "validation": {
            "min_words": min_words,
            "min_sentences": min_sentences,
            "word_count": wc,
            "sentence_count": sc,
            "ok": val_ok,
        },
    }
