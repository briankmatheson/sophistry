from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Dict, List, Set, Tuple, Any, Optional

try:
    import yaml  # pip install pyyaml
except Exception:
    yaml = None


@dataclass(frozen=True)
class StructuralVector:
    domain: str
    intent: Set[str]
    level: Set[str]
    mode: Set[str]
    scope: str


def _normalize(text: str) -> str:
    # keep simple; deterministic
    t = text.strip().lower()
    # normalize punctuation spacing a bit
    t = re.sub(r"\s+", " ", t)
    return t


def _compile_patterns(patterns: List[str]) -> List[re.Pattern]:
    compiled: List[re.Pattern] = []
    for p in patterns:
        compiled.append(re.compile(p, re.IGNORECASE))
    return compiled


def load_vocab(path: str) -> Dict[str, Any]:
    if yaml is None:
        raise RuntimeError("PyYAML not available. Install pyyaml or load vocab as dict.")
    with open(path, "r", encoding="utf-8") as f:
        vocab = yaml.safe_load(f)
    return vocab


def _score_domain(text: str, domains: Dict[str, List[str]]) -> Tuple[str, Dict[str, int]]:
    """
    Deterministic: count keyword hits for each domain.
    Return best domain (or 'mixed' if tie/close) + hit counts for debugging.
    """
    t = _normalize(text)
    counts: Dict[str, int] = {d: 0 for d in domains.keys()}

    for domain, kws in domains.items():
        for kw in kws:
            # keyword treated as literal token-ish; cheap + stable
            if kw.lower() in t:
                counts[domain] += 1

    # pick best
    best_domain = max(counts.items(), key=lambda kv: kv[1])[0]
    best_score = counts[best_domain]

    # detect mixed: if second best is close
    sorted_counts = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)
    if len(sorted_counts) > 1:
        second_domain, second_score = sorted_counts[1]
        # mixed if both have meaningful hits and close
        if best_score >= 2 and second_score >= best_score - 1 and second_score > 0:
            return "mixed", counts

    if best_score == 0:
        return "other", counts

    return best_domain, counts


def _match_labels(text: str, label_patterns: Dict[str, List[str]]) -> Set[str]:
    t = _normalize(text)
    out: Set[str] = set()
    for label, patterns in label_patterns.items():
        compiled = _compile_patterns(patterns)
        if any(p.search(t) for p in compiled):
            out.add(label)
    return out


def _pick_scope(text: str, scope_patterns: Dict[str, List[str]]) -> str:
    t = _normalize(text)
    # order matters: boundary_extremes should win if present
    priority = ["boundary_extremes", "concrete_case", "general_principle"]
    for k in priority:
        if k not in scope_patterns:
            continue
        compiled = _compile_patterns(scope_patterns[k])
        if any(p.search(t) for p in compiled):
            return k
    return "mixed"


def infer_structural_vector(text: str, vocab: Dict[str, Any]) -> Tuple[StructuralVector, Dict[str, Any]]:
    """
    Infer a structural vector + debug info for transparency.
    """
    domains = vocab.get("domains", {})
    intent_markers = vocab.get("intent_markers", {})
    level_markers = vocab.get("level_markers", {})
    mode_markers = vocab.get("mode_markers", {})
    scope_markers = vocab.get("scope_markers", {})

    domain, domain_counts = _score_domain(text, domains)
    intent = _match_labels(text, intent_markers)
    level = _match_labels(text, level_markers)
    mode = _match_labels(text, mode_markers)
    scope = _pick_scope(text, scope_markers)

    # default fallback labels if nothing detected (keeps scoring stable)
    if not intent:
        intent = {"describe_process"}
    if not level:
        level = {"interpretive"}
    if not mode:
        mode = {"descriptive"}

    vec = StructuralVector(domain=domain, intent=intent, level=level, mode=mode, scope=scope)
    debug = {
        "domain_counts": domain_counts,
        "intent": sorted(intent),
        "level": sorted(level),
        "mode": sorted(mode),
        "scope": scope,
    }
    return vec, debug


def jaccard(a: Set[str], b: Set[str]) -> float:
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union if union else 0.0


def _sim_domain(q: str, a: str) -> float:
    if q == a:
        return 1.0
    if q == "mixed" and a != "other":
        return 0.7
    if a == "mixed" and q != "other":
        return 0.7
    return 0.0


def _sim_scope(q: str, a: str) -> float:
    if q == a:
        return 1.0
    if q == "mixed" or a == "mixed":
        return 0.7
    return 0.0


def detect_flags(
    q_vec: StructuralVector,
    a_vec: StructuralVector,
    q_text: str,
    a_text: str,
) -> Dict[str, bool]:
    """
    Rule-based flags for category errors & drift.
    Deterministic, intentionally conservative.
    """
    qt = _normalize(q_text)
    at = _normalize(a_text)

    # Off-topic: domain mismatch + weak overlap on intent/level
    off_topic = (_sim_domain(q_vec.domain, a_vec.domain) == 0.0) and (jaccard(q_vec.intent, a_vec.intent) < 0.34)

    # Category error: question asks mechanism/limits/evidence but answer is purely normative/historical
    q_needs = {"explain_mechanism", "analyze_limits", "interpret_evidence"}
    a_bad_levels = {"normative", "historical"}

    category_error = False
    if q_vec.intent & q_needs:
        if (a_vec.level <= a_bad_levels) or (len(a_vec.level & a_bad_levels) == len(a_vec.level)):
            category_error = True

    # Scope mismatch: question boundary_extremes but answer not boundary/mixed
    scope_mismatch = (q_vec.scope == "boundary_extremes") and (a_vec.scope not in {"boundary_extremes", "mixed"})

    # Stays on topic heuristic: shared domain OR strong overlap in intent/level
    stays_on_topic = (q_vec.domain == a_vec.domain) or (jaccard(q_vec.intent, a_vec.intent) >= 0.5) or (jaccard(q_vec.level, a_vec.level) >= 0.5)

    return {
        "off_topic": off_topic,
        "category_error": category_error,
        "scope_mismatch": scope_mismatch,
        "stays_on_topic": stays_on_topic,
    }


def score_structural_alignment(
    question: str,
    answer: str,
    vocab: Dict[str, Any],
    weights: Optional[Dict[str, float]] = None,
) -> Dict[str, Any]:
    """
    Returns a rich score payload for your dial:
    - structural_score in [0,1]
    - axis_scores
    - flags + penalties
    - inferred vectors + debug counts
    """
    if weights is None:
        weights = {"domain": 0.25, "intent": 0.25, "level": 0.20, "mode": 0.15, "scope": 0.15}

    q_vec, q_dbg = infer_structural_vector(question, vocab)
    a_vec, a_dbg = infer_structural_vector(answer, vocab)

    axis_scores = {
        "domain": _sim_domain(q_vec.domain, a_vec.domain),
        "intent": jaccard(q_vec.intent, a_vec.intent),
        "level": jaccard(q_vec.level, a_vec.level),
        "mode": jaccard(q_vec.mode, a_vec.mode),
        "scope": _sim_scope(q_vec.scope, a_vec.scope),
    }

    base = 0.0
    for k, w in weights.items():
        base += w * axis_scores.get(k, 0.0)

    flags = detect_flags(q_vec, a_vec, question, answer)

    # penalties
    score = base
    penalties: List[str] = []
    if flags["category_error"]:
        score *= 0.6
        penalties.append("category_error x0.6")
    if flags["off_topic"]:
        score *= 0.5
        penalties.append("off_topic x0.5")
    if flags["scope_mismatch"]:
        score *= 0.85
        penalties.append("scope_mismatch x0.85")

    # clamp
    score = max(0.0, min(1.0, score))

    # explain top mismatches (for dial UX)
    mismatches = sorted(axis_scores.items(), key=lambda kv: kv[1])
    explain = []
    for axis, s in mismatches[:2]:
        if s < 0.6:
            explain.append(f"Low alignment on {axis} (score {s:.2f}).")

    if flags["category_error"]:
        explain.append("Category error: answer operates in a different explanatory level than the question asks for.")
    if flags["scope_mismatch"]:
        explain.append("Scope mismatch: question stresses boundary/extremes but answer stays generic.")
    if flags["off_topic"]:
        explain.append("Off-topic drift: domain/intent overlap is too weak.")

    return {
        "structural_score": round(score, 4),
        "base_score": round(base, 4),
        "axis_scores": {k: round(v, 4) for k, v in axis_scores.items()},
        "flags": flags,
        "penalties": penalties,
        "question_vector": {
            "domain": q_vec.domain,
            "intent": sorted(q_vec.intent),
            "level": sorted(q_vec.level),
            "mode": sorted(q_vec.mode),
            "scope": q_vec.scope,
        },
        "answer_vector": {
            "domain": a_vec.domain,
            "intent": sorted(a_vec.intent),
            "level": sorted(a_vec.level),
            "mode": sorted(a_vec.mode),
            "scope": a_vec.scope,
        },
        "debug": {"question": q_dbg, "answer": a_dbg},
        "explain": explain,
    }


if __name__ == "__main__":
    # quick smoke test
    sample_q = (
        "Consider a double-slit experiment where single electrons are fired one at a time. "
        "Explain how interference can arise, why measurement changes the outcome, and what that implies about certainty."
    )
    sample_a = (
        "Quantum theory treats the electron as a wavefunction that encodes probabilities. "
        "Interference occurs when alternatives remain coherent, but measurement entangles the system with the environment. "
        "This changes what we can predict and connects to uncertainty and decoherence."
    )

    vocab = load_vocab("structural_vocab.yaml")
    print(score_structural_alignment(sample_q, sample_a, vocab))
