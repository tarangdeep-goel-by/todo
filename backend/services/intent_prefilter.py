"""Pre-filter for intent detection — catches gibberish before LLM."""
import re
import logging
from typing import Optional, List, Dict

logger = logging.getLogger(__name__)

# Minimum vowel ratio for non-gibberish English
_MIN_VOWEL_RATIO = 0.15


def _is_gibberish(text: str) -> bool:
    """Detect gibberish via vowel ratio and consonant cluster analysis.

    Analyzes each word independently to avoid false positives from
    consonant clusters that span word boundaries.
    """
    words = text.split()
    if not words:
        return False

    # Overall vowel ratio across all alpha chars
    alpha = re.sub(r"[^a-zA-Z]", "", text)
    if len(alpha) < 3:
        return False  # Too short to judge

    vowels = sum(1 for c in alpha.lower() if c in "aeiou")
    ratio = vowels / len(alpha)

    if ratio < _MIN_VOWEL_RATIO:
        logger.info("gibberish detected: vowel ratio %.2f < %.2f", ratio, _MIN_VOWEL_RATIO)
        return True

    # Per-word analysis: any word with 5+ alpha chars and extremely low vowel ratio
    gibberish_words = 0
    for word in words:
        word_alpha = re.sub(r"[^a-zA-Z]", "", word).lower()
        if len(word_alpha) >= 5:
            word_vowels = sum(1 for c in word_alpha if c in "aeiou")
            word_ratio = word_vowels / len(word_alpha)
            if word_ratio < 0.15:
                gibberish_words += 1

    # Check per-word consonant clusters (4+ consecutive consonants)
    suspicious_count = 0
    for word in words:
        word_alpha = re.sub(r"[^a-zA-Z]", "", word)
        clusters = re.findall(r"[^aeiouAEIOU]{4,}", word_alpha)
        for c in clusters:
            if not _is_common_cluster(c):
                suspicious_count += 1

    if gibberish_words >= 2 or (gibberish_words >= 1 and suspicious_count >= 2):
        logger.info("gibberish detected: %d gibberish words, %d suspicious clusters", gibberish_words, suspicious_count)
        return True

    if suspicious_count >= 2:
        logger.info("gibberish detected: %d suspicious consonant clusters", suspicious_count)
        return True

    return False


def _is_common_cluster(cluster: str) -> bool:
    """Check if a consonant cluster is common in English."""
    common = {"ngth", "ghts", "ght", "str", "nds", "nts", "rds", "thr", "scr"}
    cl = cluster.lower()
    return any(c in cl for c in common)


def prefilter(transcription: str) -> Optional[List[Dict]]:
    """Run pre-filters on transcription before LLM call.

    Returns:
        List of intent dicts if pre-filter matched (skip LLM).
        None if no opinion (pass to LLM).
    """
    text = transcription.strip()
    if not text:
        return [{"intent": "UNKNOWN", "confidence": 0.0, "parameters": {}}]

    if _is_gibberish(text):
        return [{"intent": "UNKNOWN", "confidence": 0.1, "parameters": {}}]

    return None
