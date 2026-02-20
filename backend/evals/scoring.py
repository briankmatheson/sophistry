"""Scoring entrypoint.

Sophistry v0.5.x used rubric/regex scoring.

Sophistry v0.6+ (this bundle) uses **structural scoring** as the primary score:
how well an answer *structurally matches* the prompt.

Correctness scoring (rubrics / model judges) can be layered later.
"""

from __future__ import annotations

from .structural import score_structural
from .structural_scoring import load_vocab, score_structural_alignment

VOCAB = load_vocab("./evals/structural_vocab.yaml")

def score_case(prompt: str, model_answer: str) -> dict:
    structural = score_structural_alignment(prompt, model_answer, VOCAB)
    return {
        "score": structural["structural_score"],
        "score_details": structural,
    }
