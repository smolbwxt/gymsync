"""Build the exercise substitution graph from mined claims.

Owner 2026-08-17. The corpus tells us when one exercise legitimately stands
in for another ("no GHR machine? a partner-held Nordic curl reproduces the
same lengthening action"). Coach can currently only walk a ranked list, which
is not the same thing as knowing a swap.

The hard part is NAME RESOLUTION: educators say "dips (chest-focused)" and
"seated hamstring curl"; our catalog says "Chest Dip" and "Seated Leg Curl".
Matching is scored on significant-token overlap after stripping the equipment
and position qualifiers nobody says aloud, with a threshold that prefers
dropping an edge over inventing a wrong one — a bad substitution is worse
than a missing one, because it silently changes what a lifter trains.

Usage:  python graph.py --claims <dir> [--emit-sql out.sql]
"""
import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

CATALOG = (r"C:/Users/smola/AppData/Local/Temp/claude/"
           r"g--Projects-Midas/8b1c0384-7019-4dba-a881-6f70f8d158ca/"
           r"scratchpad/audit/label_source.json")

# Words that carry no identity — dropped before token comparison.
NOISE = {
    "the", "a", "an", "with", "for", "and", "or", "of", "on", "in", "to",
    "variation", "variations", "style", "type", "exercise", "movement",
    "machine", "version", "focused", "focus", "standard", "regular",
}
# Equipment/position qualifiers: informative but not identity-defining, so
# they score at reduced weight rather than being required to match.
SOFT = {
    "barbell", "dumbbell", "cable", "smith", "kettlebell", "band", "banded",
    "bodyweight", "landmine", "trap", "hex", "ez", "plate", "loaded", "lever",
    "seated", "standing", "lying", "incline", "decline", "flat", "bent",
    "single", "one", "two", "arm", "leg", "unilateral", "assisted", "weighted",
    "close", "wide", "neutral", "grip", "reverse", "front", "rear", "side",
    "overhead", "high", "low", "chest", "supported", "prone", "supine",
}
SYNONYM = {
    "pulldown": "pulldown", "pull-down": "pulldown", "pull": "pull",
    "ohp": "overhead press", "rdl": "romanian deadlift",
    "ghr": "glute ham raise", "bss": "bulgarian split squat",
    "rfess": "bulgarian split squat", "pushdown": "pushdown",
    "ext": "extension", "curls": "curl", "raises": "raise", "rows": "row",
    "presses": "press", "squats": "squat", "deadlifts": "deadlift",
    "dips": "dip", "extensions": "extension", "flyes": "fly", "flys": "fly",
    "flies": "fly",
}


def tokens(name: str):
    name = name.lower()
    name = re.sub(r"\(.*?\)", " ", name)          # drop parentheticals
    name = re.sub(r"[^a-z0-9 \-]", " ", name)
    raw = [SYNONYM.get(w, w) for w in name.split()]
    flat = []
    for w in raw:
        flat.extend(w.split())
    hard = [w for w in flat if w not in NOISE and w not in SOFT]
    soft = [w for w in flat if w in SOFT]
    return hard, soft


def token_match(a: str, b: str) -> bool:
    """Equal, or one a prefix of the other (>=4 chars). Catches the
    abbreviations educators speak: ham/hamstring, ab/abdominal, quad/quads."""
    if a == b:
        return True
    if len(a) >= 4 and len(b) >= 4:
        return a.startswith(b) or b.startswith(a)
    return False


def fuzzy_overlap(xs, ys) -> int:
    """Greedy 1:1 count of matching tokens across two sets."""
    remaining = list(ys)
    hits = 0
    for x in xs:
        for i, y in enumerate(remaining):
            if token_match(x, y):
                hits += 1
                remaining.pop(i)
                break
    return hits


def resolve(name: str, catalog_tokens, threshold: float = 0.6):
    """Best catalog match, or None. Conservative by design — dropping an edge
    beats inventing a wrong one, because a bad substitution silently changes
    what a lifter trains."""
    hard, soft = tokens(name)
    if not hard:
        return None, 0.0
    hs, ss = set(hard), set(soft)
    best, best_score = None, 0.0
    for slug, (chard, csoft, cname) in catalog_tokens.items():
        if not chard:
            continue
        overlap = fuzzy_overlap(hs, chard)
        if not overlap:
            continue
        # Identity tokens dominate; qualifiers only break ties.
        union = len(hs) + len(chard) - overlap
        score = overlap / max(union, 1)
        if ss or csoft:
            soft_hits = fuzzy_overlap(ss, csoft)
            score += 0.15 * (soft_hits / max(len(ss) + len(csoft) - soft_hits, 1))
        if score > best_score:
            best, best_score = (slug, cname), score
    return (best if best_score >= threshold else None), best_score


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--claims", required=True, help="dir of *-out.json")
    ap.add_argument("--emit-sql")
    ap.add_argument("--threshold", type=float, default=0.6)
    args = ap.parse_args()

    raw = open(CATALOG, encoding="utf-8").read()
    catalog = json.loads(raw[raw.find("["):raw.rfind("]") + 1])
    catalog_tokens = {}
    for ex in catalog:
        h, s = tokens(ex["name"])
        catalog_tokens[ex["slug"]] = (set(h), set(s), ex["name"])

    claims = []
    for f in glob.glob(os.path.join(args.claims, "*.json")):
        claims += json.load(open(f, encoding="utf-8")).get("claims", [])
    print(f"claims in: {len(claims)}")

    edges, unresolved = [], []
    for c in claims:
        src, s1 = resolve(c.get("from_exercise", ""), catalog_tokens, args.threshold)
        dst, s2 = resolve(c.get("to_exercise", ""), catalog_tokens, args.threshold)
        if not src or not dst:
            unresolved.append((c.get("from_exercise"), c.get("to_exercise"),
                               round(s1, 2), round(s2, 2)))
            continue
        if src[0] == dst[0]:
            continue                                # same exercise, no edge
        edges.append({
            "from_slug": src[0], "from_name": src[1],
            "to_slug": dst[0], "to_name": dst[1],
            "equivalence": c.get("equivalence", "partial"),
            "trigger": c.get("trigger", "preference"),
            "reason": (c.get("reason") or "")[:300],
            "basis": c.get("basis", "experience"),
            "confidence": c.get("confidence", "moderate"),
            "video_id": c.get("video_id", ""),
        })

    # Collapse duplicates; independent sources strengthen an edge.
    merged = {}
    for e in edges:
        key = (e["from_slug"], e["to_slug"])
        if key in merged:
            merged[key]["sources"] += 1
            continue
        e["sources"] = 1
        merged[key] = e
    out = sorted(merged.values(), key=lambda e: (-e["sources"], e["from_name"]))

    print(f"resolved edges: {len(out)}  (from {len(edges)} claims)")
    print(f"unresolved:     {len(unresolved)}  "
          f"({len(unresolved)/max(len(claims),1)*100:.0f}% of claims)")
    print("\n--- graph sample ---")
    for e in out[:14]:
        print(f"  {e['from_name'][:26]:<28}-> {e['to_name'][:26]:<28}"
              f"{e['equivalence']}/{e['trigger']}")
    print("\n--- unresolved sample (name gaps) ---")
    for f_, t_, s1, s2 in unresolved[:10]:
        print(f"  {str(f_)[:32]:<34}-> {str(t_)[:32]:<34}({s1}/{s2})")

    json.dump(out, open("substitutions.json", "w", encoding="utf-8"), indent=1)
    print(f"\nwrote substitutions.json ({len(out)} edges)")

    if args.emit_sql:
        def q(s):
            return "'" + str(s).replace("'", "''") + "'"
        rows = ",\n".join(
            f"  ({q(e['from_slug'])}, {q(e['to_slug'])}, {q(e['equivalence'])}, "
            f"{q(e['trigger'])}, {q(e['reason'])}, {q(e['basis'])}, "
            f"{q(e['confidence'])}, {e['sources']})" for e in out)
        sql = (
            "-- Substitution graph, mined from the educational-fitness corpus.\n"
            "-- Generated by tools/youtube-research/graph.py — do not hand-edit.\n"
            "INSERT INTO public.exercise_substitutions\n"
            "  (from_slug, to_slug, equivalence, trigger, reason, basis, "
            "confidence, sources)\nVALUES\n" + rows +
            "\nON CONFLICT (from_slug, to_slug) DO UPDATE SET\n"
            "  equivalence = EXCLUDED.equivalence, trigger = EXCLUDED.trigger,\n"
            "  reason = EXCLUDED.reason, basis = EXCLUDED.basis,\n"
            "  confidence = EXCLUDED.confidence, sources = EXCLUDED.sources;\n")
        open(args.emit_sql, "w", encoding="utf-8", newline="\n").write(sql)
        print(f"wrote {args.emit_sql}")


if __name__ == "__main__":
    main()
