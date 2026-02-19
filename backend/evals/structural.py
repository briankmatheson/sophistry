"""Deterministic structural scoring for Sophistry.

Scores whether an answer *structurally matches* the question:
- responsiveness via keyword overlap
- prompt-type compliance (definition/explanation/procedure)
- simple reasoning signals (causal connectors)
- soft length ramp (approach to min words/sentences)

No embeddings, no LLM judge — fast and explainable.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Dict, List


_WORD_RE = re.compile(r"\b[\w']+\b", re.UNICODE)
_SENT_SPLIT_RE = re.compile(r"[.!?]+(?:\s|$)")


CAUSE_WORDS = {"because", "therefore", "thus", "since", "hence", "so"}


@dataclass
class StructuralVerdict:
    score_0_100: int
    band: str
    signals: Dict
    notes: List[str]


def band_from_score(score_0_100: int) -> str:
    s = max(0, min(100, int(score_0_100)))
    if s >= 90:
        return "UNDERSTANDING"
    if s >= 70:
        return "REASONING"
    if s >= 40:
        return "BELIEF"
    return "FLUENCY"


def count_words(text: str) -> int:
    return len(_WORD_RE.findall(text or ""))


def count_sentences(text: str) -> int:
    t = (text or "").strip()
    if not t:
        return 0
    parts = [p for p in _SENT_SPLIT_RE.split(t) if p.strip()]
    return max(1, len(parts))


def classify_prompt_type(prompt: str) -> str:
    p = (prompt or "").strip().lower()
    if p.startswith("what is") or p.startswith("what was"):
        return "DEFINITION"
    if p.startswith("explain") or p.startswith("describe"):
        return "EXPLANATION"
    if "should you" in p or p.startswith("should"):
        return "PROCEDURE"
    if p.startswith("why") or " why " in f" {p} ":
        return "WHY"
    return "EXPLANATION"


def extract_keywords(prompt: str) -> List[str]:
    stop = {
        "the",
        "a",
        "an",
        "is",
        "was",
        "are",
        "and",
        "or",
        "of",
        "to",
        "in",
        "for",
        "its",
        "it",
        "why",
        "what",
        "describe",
        "explain",
        "problem",
        "argument",
        "paradox",
    }
    words = [w.lower() for w in _WORD_RE.findall(prompt or "")]
    kws: List[str] = []
    seen = set()
    for w in words:
        if w in stop or len(w) < 3:
            continue
        if w in seen:
            continue
        seen.add(w)
        kws.append(w)
        if len(kws) >= 12:
            break
    return kws


def keyword_overlap_ratio(answer: str, keywords: List[str]) -> float:
    if not keywords:
        return 0.0
    a = (answer or "").lower()
    hits = 0
    for k in keywords:
        if re.search(rf"\b{re.escape(k)}\b", a):
            hits += 1
    return hits / max(1, len(keywords))


def score_structural(
    prompt: str,
    answer: str,
    *,
    min_words: int = 100,
    min_sentences: int = 3,
) -> StructuralVerdict:
    ans = (answer or "").strip()
    wc = count_words(ans)
    sc = count_sentences(ans)
    ptype = classify_prompt_type(prompt)

    signals: Dict = {
        "prompt_type": ptype,
        "word_count": wc,
        "sentence_count": sc,
    }

    if not ans:
        return StructuralVerdict(
            score_0_100=0,
            band="FLUENCY",
            signals={**signals, "empty": True},
            notes=["Write an answer before checking score."],
        )

    notes: List[str] = []
    score = 0

    kws = extract_keywords(prompt)
    ov = keyword_overlap_ratio(ans, kws)
    signals["keyword_overlap"] = ov
    if ov >= 0.25:
        score += 20
    elif ov >= 0.10:
        score += 12
        notes.append("Bring in more of the question’s key terms.")
    else:
        score += 4
        notes.append("This doesn’t yet look like it’s addressing the question directly.")

    lower = ans.lower()
    has_cause = any(w in lower for w in CAUSE_WORDS)
    signals["has_cause_words"] = has_cause

    if ptype in {"EXPLANATION", "WHY"}:
        if sc >= 3:
            score += 20
        else:
            score += 8
            notes.append("Use multiple sentences to explain the idea.")
        if has_cause:
            score += 15
        else:
            notes.append("Include a causal connector (because/therefore/so) to show reasoning.")
    elif ptype == "DEFINITION":
        if wc >= 12 or (" is " in lower) or (" refers to " in lower):
            score += 20
        else:
            score += 8
            notes.append("Define the term (e.g., “X is …”) and give one distinguishing detail.")
    elif ptype == "PROCEDURE":
        if "should" in lower or "recommend" in lower:
            score += 15
        else:
            notes.append("State a clear recommendation (“you should…”) and justify it.")
        if has_cause:
            score += 10

    if min_words and wc < min_words:
        ratio = wc / max(1, min_words)
        score += int(20 * min(1.0, ratio))
        notes.append(f"Add more detail: {wc}/{min_words} words.")
    else:
        score += 20

    if min_sentences and sc < min_sentences:
        notes.append(f"Use at least {min_sentences} sentences.")

    score = max(0, min(100, int(score)))
    band = band_from_score(score)

    return StructuralVerdict(
        score_0_100=score,
        band=band,
        signals=signals,
        notes=_dedupe(notes),
    )


def _dedupe(items: List[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for i in items:
        if i in seen:
            continue
        seen.add(i)
        out.append(i)
    return out
