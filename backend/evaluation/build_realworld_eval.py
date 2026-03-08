#!/usr/bin/env python3
"""
Build a real-world eval dataset from MS-LaTTE (Microsoft, 10101 tasks).

Maps MS-LaTTE tasks to VOKL's 8 domains, samples ~200 tasks stratified by domain,
matches them to the eval task tree for parent assignment, and outputs an eval config
in the same format as the existing eval harness.

Usage:
    python build_realworld_eval.py              # Full run, writes output file
    python build_realworld_eval.py --dry-run    # Stats only, no file write
"""

import argparse
import json
import random
import re
from collections import Counter, defaultdict
from pathlib import Path

# ── Constants ──────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent
DATA_FILE = SCRIPT_DIR / "data" / "ms_latte.json"
TASK_TREE_FILE = SCRIPT_DIR / "task_tree.json"
OUTPUT_FILE = SCRIPT_DIR / "eval_realworld_draft.json"

TARGET_TOTAL = 200
TARGET_PER_DOMAIN = 25
DOMAINS = ["career", "finance", "health", "relationships", "growth", "recreation", "home", "community"]

SEED = 42

# ── Domain Mapping: ListTitle → domain ─────────────────────────────────────────

LIST_TITLE_MAP = {
    # Home
    "home": "home", "groceries": "home", "grocery": "home", "shopping": "home",
    "chores": "home", "house": "home", "cleaning": "home", "errands": "home",
    "cooking": "home", "recipes": "home", "garden": "home",
    # Career
    "work": "career", "office": "career", "meetings": "career", "projects": "career",
    "job": "career", "business": "career", "clients": "career",
    # Health
    "health": "health", "fitness": "health", "exercise": "health", "medical": "health",
    "doctor": "health", "gym": "health", "wellness": "health", "diet": "health",
    # Finance
    "finance": "finance", "bills": "finance", "budget": "finance", "money": "finance",
    "banking": "finance", "taxes": "finance", "insurance": "finance",
    # Relationships
    "family": "relationships", "friends": "relationships", "social": "relationships",
    "gifts": "relationships", "birthday": "relationships", "wedding": "relationships",
    # Growth
    "school": "growth", "study": "growth", "learn": "growth", "education": "growth",
    "books": "growth", "reading": "growth", "courses": "growth", "college": "growth",
    "university": "growth", "class": "growth", "homework": "growth",
    # Recreation
    "fun": "recreation", "travel": "recreation", "vacation": "recreation",
    "hobbies": "recreation", "movies": "recreation", "music": "recreation",
    "games": "recreation", "entertainment": "recreation", "weekend": "recreation",
    # Community
    "volunteer": "community", "church": "community", "charity": "community",
    "community": "community", "neighborhood": "community",
}

CONTENT_KEYWORDS = {
    "home": ["clean", "fix", "repair", "grocery", "cook", "laundry", "mow", "vacuum",
             "dishes", "trash", "recycle", "organize", "declutter", "paint", "shelf",
             "plumber", "electrician", "furniture", "appliance", "garden", "yard"],
    "career": ["meeting", "email", "report", "deadline", "presentation", "client",
               "project", "review", "submit", "boss", "coworker", "office", "resume",
               "interview", "promotion", "salary", "invoice"],
    "health": ["doctor", "dentist", "gym", "run", "workout", "medicine", "prescription",
               "appointment", "therapy", "vitamin", "diet", "weight", "sleep", "mental",
               "meditation", "yoga", "exercise", "checkup", "vaccine", "optometrist"],
    "finance": ["pay", "bill", "bank", "tax", "budget", "save", "invest", "insurance",
                "mortgage", "rent", "loan", "credit", "account", "transfer", "refund"],
    "relationships": ["call mom", "call dad", "birthday", "gift", "visit", "dinner with",
                       "lunch with", "text", "thank you", "anniversary", "wedding",
                       "baby shower", "family", "friend"],
    "growth": ["read", "study", "learn", "course", "class", "practice", "book",
               "tutorial", "certificate", "exam", "homework", "research", "write paper"],
    "recreation": ["movie", "concert", "hike", "travel", "trip", "game", "play",
                   "watch", "listen", "restaurant", "bar", "museum", "park", "beach",
                   "camping", "fishing", "photography", "paint", "draw", "craft"],
    "community": ["volunteer", "donate", "church", "temple", "mosque", "charity",
                  "neighborhood", "community", "coach", "mentor", "tutor"],
}

# Generic list titles that need content-based inference
GENERIC_LIST_TITLES = {
    "default list", "to do", "to-do", "todo", "today", "tasks", "my tasks",
    "list", "reminders", "stuff", "things", "misc", "other", "general",
    "personal", "my list", "daily", "weekly",
}

# ── Filtering ──────────────────────────────────────────────────────────────────

GIBBERISH_PATTERNS = [
    re.compile(r"^\d+\s+\w+$"),  # "0 cucumbers" pattern
    re.compile(r"^[^a-zA-Z]*$"),  # No letters at all
]

SINGLE_WORD_GARBAGE = {"stuff", "things", "misc", "other", "item", "task", "todo", "test", "asdf", "aaa", "xxx"}


def should_filter(task_text: str) -> bool:
    """Return True if task should be excluded."""
    text = task_text.strip()
    if len(text) < 3:
        return True
    for pat in GIBBERISH_PATTERNS:
        if pat.match(text):
            return True
    # Single generic word
    if len(text.split()) == 1 and text.lower() in SINGLE_WORD_GARBAGE:
        return True
    return False


# ── Domain Mapping ─────────────────────────────────────────────────────────────

def map_domain_from_list_title(list_title: str) -> str | None:
    """Map ListTitle to domain. Returns None if generic/unmapped."""
    title_lower = list_title.strip().lower()
    if title_lower in GENERIC_LIST_TITLES:
        return None
    # Direct match
    if title_lower in LIST_TITLE_MAP:
        return LIST_TITLE_MAP[title_lower]
    # Substring match (e.g., "work stuff" → career)
    for key, domain in LIST_TITLE_MAP.items():
        if key in title_lower:
            return domain
    return None


def map_domain_from_content(task_text: str) -> tuple[str | None, list[str]]:
    """
    Infer domain from task text content using keyword matching.
    Returns (best_domain, all_matching_domains).
    """
    text_lower = task_text.lower()
    scores: dict[str, int] = defaultdict(int)

    for domain, keywords in CONTENT_KEYWORDS.items():
        for kw in keywords:
            if kw in text_lower:
                scores[domain] += 1

    if not scores:
        return None, []

    sorted_domains = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    all_matches = [d for d, _ in sorted_domains]

    # Only return confident match if top score is clearly better
    if len(sorted_domains) == 1 or sorted_domains[0][1] > sorted_domains[1][1]:
        return sorted_domains[0][0], all_matches
    else:
        return None, all_matches  # Ambiguous


def classify_task(entry: dict) -> dict | None:
    """
    Classify an MS-LaTTE entry. Returns enriched dict or None if filtered out.
    """
    task_text = entry.get("TaskTitle", "").strip()
    list_title = entry.get("ListTitle", "").strip()
    source_id = entry.get("ID", "")

    if should_filter(task_text):
        return None

    # Try list title first
    domain = map_domain_from_list_title(list_title)
    domain_source = "list_title"
    ambiguous_domains = []

    if domain is None:
        # Fall back to content
        domain, ambiguous_domains = map_domain_from_content(task_text)
        domain_source = "content"

    if domain is None:
        return None  # Can't classify

    return {
        "task_text": task_text,
        "source_id": source_id,
        "source_list": list_title,
        "domain": domain,
        "domain_source": domain_source,
        "ambiguous_domains": ambiguous_domains,
        "word_count": len(task_text.split()),
    }


# ── Task Tree Parent Matching ──────────────────────────────────────────────────

def load_task_tree(path: Path) -> list[dict]:
    """Load task tree JSON."""
    with open(path) as f:
        return json.load(f)


def build_domain_parents(tree: list[dict]) -> dict[str, list[dict]]:
    """
    Build a map of domain → list of potential parent nodes.
    Includes all nodes (not just roots) for more flexible matching.
    """
    domain_nodes: dict[str, list[dict]] = defaultdict(list)
    for node in tree:
        cat = node.get("category", "")
        if cat in DOMAINS:
            domain_nodes[cat].append(node)
    return domain_nodes



# Words that are too generic to serve as meaningful parent-task connectors
PARENT_MATCH_STOP_WORDS = {
    "a", "an", "the", "to", "for", "of", "in", "on", "and", "or", "my", "is", "it",
    "up", "out", "get", "set", "new", "do", "make", "take", "go", "put", "run",
    # Action verbs that appear everywhere — matching on "pay" alone is meaningless
    "pay", "buy", "call", "plan", "check", "update", "review", "schedule", "find",
    "order", "write", "send", "complete", "finish", "start", "build", "create",
    "prepare", "organize", "clean", "fix", "add", "change", "move", "track",
}


def find_parent_match(task_text: str, domain: str, domain_parents: dict[str, list[dict]]) -> tuple[str | None, float]:
    """
    Try to match task text to a parent in the task tree.
    Returns (parent_title, confidence) or (None, 0).

    Matching requires SEMANTIC relevance — shared domain-specific nouns,
    not generic verbs or stop words.
    """
    nodes = domain_parents.get(domain, [])
    if not nodes:
        return None, 0

    text_lower = task_text.lower()
    text_words = set(text_lower.split())

    # Only consider nodes that have children (i.e., are actual parents/groups)
    parent_ids = {n["id"] for n in nodes}
    nodes_with_children = [n for n in nodes if any(
        other.get("parent_id") == n["id"] for other in nodes
    )]
    # Also include root-level grouping nodes (parent_id is None)
    root_groups = [n for n in nodes if n.get("parent_id") is None]
    candidate_parents = list({n["id"]: n for n in nodes_with_children + root_groups}.values())

    if not candidate_parents:
        candidate_parents = nodes  # fallback

    best_match = None
    best_score = 0.0

    for node in candidate_parents:
        title = node["title"]
        title_lower = title.lower()
        title_words = set(title_lower.split())

        # Skip very generic single-word parent titles
        if title_lower in {"home", "finance", "family", "fitness"}:
            continue

        # Find meaningful word overlap (exclude generic verbs/stops)
        meaningful_text = text_words - PARENT_MATCH_STOP_WORDS
        meaningful_title = title_words - PARENT_MATCH_STOP_WORDS

        if not meaningful_title:
            continue  # Parent title is all generic words

        common = meaningful_text & meaningful_title

        # Also try substring matching for compound words
        # e.g., "running" in text matches "running" in "marathon training" title
        if not common:
            for tw in meaningful_text:
                if len(tw) >= 5:  # Only longer words to avoid false matches
                    for pw in meaningful_title:
                        if len(pw) >= 5 and (tw in pw or pw in tw):
                            common.add(tw)

        if not common:
            continue

        # Score: require meaningful overlap, penalize single-word matches on short words
        coverage = len(common) / len(meaningful_title)
        # Bonus for matching multiple meaningful words
        multi_word_bonus = 0.3 if len(common) >= 2 else 0.0
        # Bonus for matching long, specific words (e.g., "marathon", "kitchen", "insurance")
        specificity_bonus = 0.2 if any(len(w) >= 6 for w in common) else 0.0

        score = coverage * 0.5 + multi_word_bonus + specificity_bonus

        if score > best_score:
            best_score = score
            best_match = title

    # Require higher threshold to avoid false positives
    if best_score >= 0.4:
        return best_match, best_score
    return None, 0


# ── Transcription Naturalization ───────────────────────────────────────────────

# Articles to add before common nouns
ARTICLE_PATTERNS = [
    (re.compile(r"\b(fix|clean|organize|replace|buy|get|check|wash|change)\s+(\w+)", re.I),
     lambda m: f"{m.group(1)} the {m.group(2)}" if m.group(2).lower() not in {"a", "an", "the", "my", "some", "our"} else m.group(0)),
]


def naturalize_text(text: str) -> str:
    """
    Convert terse typed task text to natural speech format.
    Light touch — don't over-embellish.
    """
    result = text.strip()

    # Don't modify if already starts with a verb+article or is a sentence
    if any(result.lower().startswith(p) for p in ["i need to", "i have to", "i should", "i want to", "please"]):
        return result

    # Add articles for common verb+noun patterns only if no article present
    for pattern, replacer in ARTICLE_PATTERNS:
        # Only apply once to avoid double articles
        match = pattern.search(result)
        if match:
            start = result[:match.start()]
            replaced = replacer(match)
            end = result[match.end():]
            result = start + replaced + end
            break  # Only one substitution

    return result


# ── Category & Difficulty Assignment ───────────────────────────────────────────

def assign_category(task: dict, parent_title: str | None, parent_confidence: float) -> str:
    """Assign eval category: RW_CLEAR, RW_ROOT, RW_TERSE, RW_AMBIGUOUS_DOMAIN."""
    if task["word_count"] <= 3:
        return "RW_TERSE"
    if len(task["ambiguous_domains"]) >= 2 and task["domain_source"] == "content":
        return "RW_AMBIGUOUS_DOMAIN"
    if parent_title is not None and parent_confidence >= 0.3:
        return "RW_CLEAR"
    return "RW_ROOT"


def assign_difficulty(task: dict, category: str, parent_confidence: float) -> str:
    """Assign difficulty: easy, medium, hard."""
    if category == "RW_TERSE":
        return "hard"
    if category == "RW_AMBIGUOUS_DOMAIN":
        return "hard"
    if category == "RW_CLEAR" and parent_confidence >= 0.5 and task["domain_source"] == "list_title":
        return "easy"
    if category == "RW_CLEAR":
        return "medium"
    if category == "RW_ROOT" and task["domain_source"] == "list_title":
        return "easy"
    return "medium"


# ── Sampling ───────────────────────────────────────────────────────────────────

def stratified_sample(classified: list[dict], target_total: int, target_per_domain: int) -> list[dict]:
    """
    Sample tasks stratified by domain.
    Prefer tasks 3-15 words, high confidence domain signal, diverse topics.
    """
    rng = random.Random(SEED)

    # Group by domain
    by_domain: dict[str, list[dict]] = defaultdict(list)
    for t in classified:
        by_domain[t["domain"]].append(t)

    # Score and sort within each domain
    for domain in by_domain:
        tasks = by_domain[domain]
        for t in tasks:
            score = 0
            wc = t["word_count"]
            # Prefer 3-15 words
            if 3 <= wc <= 15:
                score += 3
            elif wc > 15:
                score += 1
            # Prefer list_title source (higher confidence)
            if t["domain_source"] == "list_title":
                score += 2
            # Penalize ambiguous
            if len(t["ambiguous_domains"]) >= 2:
                score -= 1
            t["_score"] = score
        # Sort by score desc, then shuffle within same score for diversity
        tasks.sort(key=lambda x: x["_score"], reverse=True)

    # Phase 1: take up to target_per_domain from each
    sampled: list[dict] = []
    remaining_slots = target_total
    deficit_domains: list[str] = []

    for domain in DOMAINS:
        pool = by_domain.get(domain, [])
        take = min(target_per_domain, len(pool))
        if take < target_per_domain:
            deficit_domains.append(domain)
        # Take top-scored, but shuffle among top to get diversity
        top_pool = pool[:max(take * 3, take)]  # Consider top 3x for diversity
        rng.shuffle(top_pool)
        selected = top_pool[:take]
        sampled.extend(selected)
        remaining_slots -= take
        # Remove selected from pool
        selected_ids = {t["source_id"] for t in selected}
        by_domain[domain] = [t for t in pool if t["source_id"] not in selected_ids]

    # Phase 2: redistribute remaining slots to domains with surplus
    if remaining_slots > 0:
        surplus_domains = [d for d in DOMAINS if d not in deficit_domains and by_domain.get(d)]
        while remaining_slots > 0 and surplus_domains:
            for domain in list(surplus_domains):
                if remaining_slots <= 0:
                    break
                pool = by_domain.get(domain, [])
                if pool:
                    pick = pool.pop(0)
                    sampled.append(pick)
                    remaining_slots -= 1
                else:
                    surplus_domains.remove(domain)

    return sampled


# ── Output Generation ─────────────────────────────────────────────────────────

def build_eval_case(task: dict, index: int, parent_title: str | None,
                    parent_confidence: float) -> dict:
    """Build a single eval case in the expected format."""
    category = assign_category(task, parent_title, parent_confidence)
    difficulty = assign_difficulty(task, category, parent_confidence)

    case_id = f"rw_{category.lower().replace('rw_', '')}_{index:03d}"
    transcription = naturalize_text(task["task_text"])

    checks: dict = {
        "content_contains": _extract_key_phrase(task["task_text"]),
        "confidence_gte": 0.5,
    }

    # Domain assignment
    if category == "RW_AMBIGUOUS_DOMAIN" and len(task["ambiguous_domains"]) >= 2:
        checks["category_in"] = task["ambiguous_domains"][:3]
    else:
        checks["category_exact"] = task["domain"]

    # Parent assignment
    if parent_title is not None and parent_confidence >= 0.3:
        checks["parentQuery_contains"] = parent_title
    else:
        checks["parentQuery_null"] = True

    return {
        "id": case_id,
        "transcription": transcription,
        "difficulty": difficulty,
        "category": category,
        "source_id": task["source_id"],
        "source_list": task["source_list"],
        "expected_action_count": 1,
        "expected_actions": [{
            "action": "add",
            "checks": checks,
        }],
    }


def _extract_key_phrase(text: str) -> str:
    """Extract the most meaningful phrase from task text for content_contains check."""
    words = text.strip().split()
    # For short tasks, use the whole thing
    if len(words) <= 4:
        return text.strip().lower()
    # For longer tasks, take the first 3-4 meaningful words
    stop = {"a", "an", "the", "to", "for", "of", "in", "on", "and", "or", "my", "i", "need"}
    meaningful = [w for w in words if w.lower() not in stop]
    if len(meaningful) >= 2:
        return " ".join(meaningful[:3]).lower()
    return " ".join(words[:3]).lower()


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Build real-world eval from MS-LaTTE")
    parser.add_argument("--dry-run", action="store_true", help="Print stats only, don't write output")
    args = parser.parse_args()

    # Load data
    print(f"Loading MS-LaTTE from {DATA_FILE}...")
    with open(DATA_FILE) as f:
        raw_tasks = json.load(f)
    print(f"  Loaded {len(raw_tasks)} tasks")

    # Load task tree
    print(f"Loading task tree from {TASK_TREE_FILE}...")
    tree = load_task_tree(TASK_TREE_FILE)
    domain_parents = build_domain_parents(tree)
    print(f"  Loaded {len(tree)} tree nodes across {len(domain_parents)} domains")

    # Classify all tasks
    print("\nClassifying tasks...")
    classified = []
    filtered_count = 0
    unmapped_count = 0
    for entry in raw_tasks:
        result = classify_task(entry)
        if result is None:
            task_text = entry.get("TaskTitle", "").strip()
            if should_filter(task_text):
                filtered_count += 1
            else:
                unmapped_count += 1
        else:
            classified.append(result)

    print(f"  Classified: {len(classified)}")
    print(f"  Filtered (gibberish/short): {filtered_count}")
    print(f"  Unmapped (no domain signal): {unmapped_count}")

    # Domain distribution before sampling
    domain_counts = Counter(t["domain"] for t in classified)
    print("\n  Domain distribution (pre-sampling):")
    for domain in DOMAINS:
        count = domain_counts.get(domain, 0)
        print(f"    {domain:15s}: {count:5d}")

    # Sample
    print(f"\nSampling {TARGET_TOTAL} tasks (target {TARGET_PER_DOMAIN}/domain)...")
    sampled = stratified_sample(classified, TARGET_TOTAL, TARGET_PER_DOMAIN)
    print(f"  Sampled: {len(sampled)}")

    # Match parents and build eval cases
    print("\nMatching parents and building eval cases...")
    cases = []
    counters: dict[str, int] = defaultdict(int)

    for task in sampled:
        parent_title, parent_conf = find_parent_match(
            task["task_text"], task["domain"], domain_parents
        )
        cat = assign_category(task, parent_title, parent_conf)
        counters[cat] += 1
        case = build_eval_case(task, len(cases) + 1, parent_title, parent_conf)
        cases.append(case)

    # ── Add RW_VOICE cases (voice-phrased variants of sampled tasks) ──
    voice_templates = [
        "um {task}",
        "uh I need to {task}",
        "oh yeah {task}",
        "so I should probably {task}",
        "hey can you add {task}",
        "um so like {task}",
        "I was thinking I need to {task}",
        "oh right I forgot to {task}",
        "add uh {task} please",
        "{task} oh and also that's important",
    ]

    # Pick ~40 tasks from the sampled set, create voice variants
    rng = random.Random(SEED + 1)
    voice_source = rng.sample(cases, min(40, len(cases)))
    for vc in voice_source:
        template = rng.choice(voice_templates)
        original_text = vc["transcription"]
        voice_text = template.format(task=original_text.lower())

        voice_case = {
            "id": "",  # numbered below
            "transcription": voice_text,
            "difficulty": "medium",
            "category": "RW_VOICE",
            "source_id": vc.get("source_id", ""),
            "source_list": vc.get("source_list", ""),
            "expected_action_count": 1,
            "expected_actions": vc["expected_actions"][:],  # same expectations
        }
        cases.append(voice_case)

    # ── Add RW_AMBIGUOUS_DOMAIN cases (hand-crafted cross-domain tasks) ──
    ambiguous_cases = [
        {"text": "pick up mom's prescription", "domains": ["health", "relationships"],
         "content": "prescription", "difficulty": "hard"},
        {"text": "team lunch on Friday", "domains": ["career", "recreation"],
         "content": "team lunch", "difficulty": "hard"},
        {"text": "budget for vacation", "domains": ["finance", "recreation"],
         "content": "budget vacation", "difficulty": "hard"},
        {"text": "read leadership book", "domains": ["career", "growth"],
         "content": "leadership book", "difficulty": "hard"},
        {"text": "buy birthday gift for coworker", "domains": ["career", "relationships"],
         "content": "birthday gift", "difficulty": "hard"},
        {"text": "sign up for yoga class", "domains": ["health", "recreation"],
         "content": "yoga class", "difficulty": "hard"},
        {"text": "call insurance company about claim", "domains": ["finance", "health"],
         "content": "insurance claim", "difficulty": "hard"},
        {"text": "plan company retreat activities", "domains": ["career", "recreation"],
         "content": "retreat activities", "difficulty": "hard"},
        {"text": "research MBA programs", "domains": ["career", "growth"],
         "content": "MBA programs", "difficulty": "hard"},
        {"text": "cook healthy meal prep for the week", "domains": ["health", "home"],
         "content": "meal prep", "difficulty": "medium"},
        {"text": "organize charity run at work", "domains": ["career", "community"],
         "content": "charity run", "difficulty": "hard"},
        {"text": "buy supplies for kid's school project", "domains": ["home", "relationships"],
         "content": "school project", "difficulty": "hard"},
        {"text": "schedule financial advisor meeting", "domains": ["finance", "career"],
         "content": "financial advisor", "difficulty": "medium"},
        {"text": "find a therapist covered by insurance", "domains": ["health", "finance"],
         "content": "therapist insurance", "difficulty": "hard"},
        {"text": "set up study group with classmates", "domains": ["growth", "relationships"],
         "content": "study group", "difficulty": "hard"},
        {"text": "volunteer coaching at the gym", "domains": ["community", "health"],
         "content": "coaching gym", "difficulty": "hard"},
        {"text": "book flights for family reunion", "domains": ["relationships", "recreation"],
         "content": "family reunion", "difficulty": "hard"},
        {"text": "renew gym membership", "domains": ["health", "finance"],
         "content": "gym membership", "difficulty": "medium"},
        {"text": "practice Spanish before trip", "domains": ["growth", "recreation"],
         "content": "practice Spanish", "difficulty": "hard"},
        {"text": "buy ergonomic chair for home office", "domains": ["home", "career"],
         "content": "ergonomic chair", "difficulty": "hard"},
        {"text": "write thank you notes for wedding gifts", "domains": ["relationships", "home"],
         "content": "thank you notes", "difficulty": "medium"},
        {"text": "register kids for summer camp", "domains": ["relationships", "recreation"],
         "content": "summer camp", "difficulty": "hard"},
        {"text": "fix bike for weekend ride", "domains": ["home", "recreation"],
         "content": "fix bike", "difficulty": "medium"},
        {"text": "mentor new intern at work", "domains": ["career", "community"],
         "content": "mentor intern", "difficulty": "hard"},
        {"text": "review retirement account options", "domains": ["finance", "growth"],
         "content": "retirement account", "difficulty": "medium"},
        {"text": "plan neighborhood block party", "domains": ["community", "recreation"],
         "content": "block party", "difficulty": "hard"},
        {"text": "take dog to vet", "domains": ["home", "health"],
         "content": "dog vet", "difficulty": "medium"},
        {"text": "submit expense reports", "domains": ["career", "finance"],
         "content": "expense reports", "difficulty": "medium"},
        {"text": "declutter and donate old clothes", "domains": ["home", "community"],
         "content": "donate clothes", "difficulty": "medium"},
        {"text": "learn first aid for coaching", "domains": ["growth", "community", "health"],
         "content": "first aid", "difficulty": "hard"},
    ]

    for amb in ambiguous_cases:
        case = {
            "id": "",
            "transcription": amb["text"],
            "difficulty": amb["difficulty"],
            "category": "RW_AMBIGUOUS_DOMAIN",
            "source_id": "manual",
            "source_list": "manual",
            "expected_action_count": 1,
            "expected_actions": [{
                "action": "add",
                "checks": {
                    "content_contains": amb["content"],
                    "category_in": amb["domains"],
                    "confidence_gte": 0.5,
                },
            }],
        }
        cases.append(case)

    # Re-number by category for cleaner IDs
    cat_counters: dict[str, int] = defaultdict(int)
    for case in cases:
        cat_key = case["category"].lower().replace("rw_", "")
        cat_counters[cat_key] += 1
        case["id"] = f"rw_{cat_key}_{cat_counters[cat_key]:03d}"

    # Print summary stats
    print("\n" + "=" * 60)
    print("SUMMARY STATS")
    print("=" * 60)

    print(f"\nTotal cases: {len(cases)}")

    print("\nBy domain:")
    domain_sample_counts = Counter()
    for case in cases:
        actions = case["expected_actions"]
        for action in actions:
            checks = action["checks"]
            if "category_exact" in checks:
                domain_sample_counts[checks["category_exact"]] += 1
            elif "category_in" in checks:
                domain_sample_counts[checks["category_in"][0]] += 1  # Count first
    for domain in DOMAINS:
        print(f"  {domain:15s}: {domain_sample_counts.get(domain, 0):3d}")

    print("\nBy category:")
    cat_counts = Counter(c["category"] for c in cases)
    for cat in sorted(cat_counts):
        print(f"  {cat:25s}: {cat_counts[cat]:3d}")

    print("\nBy difficulty:")
    diff_counts = Counter(c["difficulty"] for c in cases)
    for diff in ["easy", "medium", "hard"]:
        print(f"  {diff:10s}: {diff_counts.get(diff, 0):3d}")

    parent_matched = sum(1 for c in cases
                         if "parentQuery_contains" in c["expected_actions"][0]["checks"])
    print(f"\nParent matched: {parent_matched} / {len(cases)} ({100*parent_matched/len(cases):.1f}%)")

    # Write output
    if args.dry_run:
        print("\n[DRY RUN] Skipping output file write.")
    else:
        output = {
            "dataset_name": "Real-World Brain Dump Eval v1",
            "source": "MS-LaTTE (Microsoft, 10101 tasks) + manual curation",
            "cases": cases,
        }
        OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(OUTPUT_FILE, "w") as f:
            json.dump(output, f, indent=2)
        print(f"\nWrote {len(cases)} cases to {OUTPUT_FILE}")

    print("\nDone.")


if __name__ == "__main__":
    main()
