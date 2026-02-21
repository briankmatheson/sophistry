"""Vocabulary learner — extracts keywords from text and manages per-question learned vocab.

On each answer submission, we:
1. Extract meaningful terms from the answer
2. Merge them into TestCase.learned_vocab
3. When scoring, overlay learned_vocab onto the base vocab as a question-specific domain

This means the scorer gets smarter for each question as more people answer it.
"""

from __future__ import annotations

import re
from collections import Counter
from typing import Dict, List, Set, Any, Optional

# Common English stopwords — kept minimal and deterministic
STOPWORDS: Set[str] = {
    "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "shall", "can", "need", "must",
    "i", "you", "he", "she", "it", "we", "they", "me", "him", "her",
    "us", "them", "my", "your", "his", "its", "our", "their",
    "this", "that", "these", "those", "what", "which", "who", "whom",
    "where", "when", "why", "how", "all", "each", "every", "both",
    "few", "more", "most", "other", "some", "such", "no", "not",
    "only", "own", "same", "so", "than", "too", "very",
    "and", "but", "or", "nor", "for", "yet", "of", "to", "in", "on",
    "at", "by", "from", "with", "about", "between", "through", "during",
    "before", "after", "above", "below", "up", "down", "out", "off",
    "over", "under", "again", "then", "once", "here", "there",
    "just", "also", "now", "if", "as", "into", "like", "because",
    "while", "although", "since", "until", "unless", "however",
    "therefore", "thus", "hence", "well", "still", "even", "much",
    "many", "any", "really", "quite", "rather", "often", "always",
    "never", "sometimes", "already", "almost", "actually", "perhaps",
    "simply", "generally", "typically", "especially", "specifically",
    "essentially", "particularly", "certainly", "probably", "possibly",
    "basically", "relatively", "apparently", "effectively", "merely",
    "one", "two", "three", "first", "second", "new", "way",
    "get", "got", "make", "made", "take", "go", "going", "come",
    "say", "said", "tell", "know", "think", "see", "look", "give",
    "thing", "things", "something", "anything", "everything", "nothing",
    "people", "person", "time", "year", "years", "part",
}

# Minimum word length to consider
MIN_WORD_LEN = 3

# Max keywords to store per question
MAX_LEARNED_KEYWORDS = 200


def extract_keywords(text: str, min_len: int = MIN_WORD_LEN) -> List[str]:
    """Extract meaningful keywords from text, removing stopwords and short words.

    Returns lowercased unique terms sorted by frequency (most common first).
    Also extracts bigrams that appear meaningful (noun-noun, adj-noun patterns).
    """
    t = text.strip().lower()
    # Split into words, keeping only alphanumeric + hyphens
    words = re.findall(r"[a-z][a-z0-9'-]*[a-z0-9]|[a-z]", t)

    # Filter
    meaningful = [w for w in words if len(w) >= min_len and w not in STOPWORDS]

    # Count frequencies
    counts = Counter(meaningful)

    # Also extract bigrams (adjacent word pairs)
    bigrams = []
    for i in range(len(meaningful) - 1):
        bg = f"{meaningful[i]} {meaningful[i+1]}"
        bigrams.append(bg)
    bg_counts = Counter(bigrams)

    # Combine: single words + bigrams that appear 2+ times or are long enough
    terms = list(counts.keys())
    for bg, count in bg_counts.items():
        if count >= 1 and len(bg) >= 8:  # keep bigrams that are descriptive
            terms.append(bg)

    return terms


def extract_from_prompt(prompt: str) -> Dict[str, Any]:
    """Bootstrap learned_vocab from a question prompt.

    Returns a learned_vocab dict ready to store on TestCase.
    """
    keywords = extract_keywords(prompt)
    return {
        "domain_keywords": keywords[:MAX_LEARNED_KEYWORDS],
        "from_prompt": True,
        "answer_count": 0,
    }


def merge_answer_vocab(
    existing: Optional[Dict[str, Any]],
    answer_text: str,
) -> Dict[str, Any]:
    """Merge keywords from a new answer into the existing learned_vocab.

    Grows the keyword set over time as more answers come in.
    """
    if existing is None:
        existing = {"domain_keywords": [], "from_prompt": False, "answer_count": 0}

    current_kws: Set[str] = set(existing.get("domain_keywords", []))
    new_kws = extract_keywords(answer_text)

    # Add new terms
    current_kws.update(new_kws)

    # Cap at max
    kw_list = sorted(current_kws)[:MAX_LEARNED_KEYWORDS]

    return {
        "domain_keywords": kw_list,
        "from_prompt": existing.get("from_prompt", False),
        "answer_count": existing.get("answer_count", 0) + 1,
    }


def overlay_vocab(
    base_vocab: Dict[str, Any],
    learned: Optional[Dict[str, Any]],
    question_slug: str = "question",
) -> Dict[str, Any]:
    """Create an augmented vocab dict by adding learned keywords as a question-specific domain.

    The learned keywords become an additional domain entry so the structural scorer
    can match answers against question-specific vocabulary, not just the base vocab.
    """
    if not learned or not learned.get("domain_keywords"):
        return base_vocab

    # Deep-ish copy of domains
    augmented = dict(base_vocab)
    domains = dict(base_vocab.get("domains", {}))

    # Add question-specific domain with learned keywords
    domain_name = f"q_{question_slug}"
    domains[domain_name] = learned["domain_keywords"]
    augmented["domains"] = domains

    return augmented
