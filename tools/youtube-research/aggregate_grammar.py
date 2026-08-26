"""Turn the grammar wave into a ranked lever roadmap.

Counts two things, and the second is the one that matters:

  instances       - how often a shape appears at all
  distinct voices - how many different speakers use it

A grammar used 300 times by one person is that person's verbal tic. Used
40 times across 15 speakers, it is a shape the language actually has.
Ranking on raw instances would put a single long podcast at the top.

Also reports SLOT SIGNATURES per predicate, because the wave surfaced a
failure mode that predicate names alone hide: `avoid(exercise)` and
`avoid(behavior)` share a name, and a resolver built for the first fails
on the second while looking like it matched. A lever registry needs
(predicate, slot_type) pairs, not predicates.

Usage:  python aggregate_grammar.py [--pass-name grammar]
"""
import argparse
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# What RuleClassifier can express today. Everything else is the finding.
KNOWN = {"pair", "avoid", "order", "light"}
# Slot types those known predicates actually resolve against.
KNOWN_SLOTS = {"pair": {"exercise"}, "avoid": {"exercise"},
               "order": {"muscle"}, "light": {"day"}}


def head(grammar: str) -> str:
    """`conditional(symptom, substitution)` -> `conditional`."""
    return re.split(r"[(\s]", str(grammar).strip(), 1)[0].lower()


def signature(row) -> str:
    types = row.get("slot_types")
    if isinstance(types, list) and types:
        return ", ".join(str(t) for t in types)
    m = re.search(r"\((.*)\)", str(row.get("grammar", "")))
    return m.group(1).strip() if m else ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pass-name", default="grammar")
    args = ap.parse_args()

    files = sorted(glob.glob("passes/%s/out-*.json" % args.pass_name))
    instances = Counter()
    voices = defaultdict(set)
    sigs = defaultdict(Counter)
    examples = {}
    scopes = defaultdict(Counter)
    total = 0

    for f in files:
        try:
            rows = json.load(open(f, encoding="utf-8"))
        except Exception as e:
            print("UNREADABLE %s: %s" % (os.path.basename(f), e))
            continue
        if not isinstance(rows, list):
            continue
        for r in rows:
            if not isinstance(r, dict) or not r.get("grammar"):
                continue
            h = head(r["grammar"])
            total += 1
            instances[h] += 1
            src = str(r.get("source") or "")
            # Speaker = the channel half of "<channel> - <title>".
            voices[h].add(re.split(r"\s+[-—]\s+", src, 1)[0].strip().lower())
            s = signature(r)
            if s:
                sigs[h][s] += 1
            if r.get("scope"):
                scopes[h][str(r["scope"])] += 1
            if h not in examples and r.get("verbatim"):
                examples[h] = str(r["verbatim"])[:88]

    print("files: %d   instruction rows: %d   distinct predicates: %d\n"
          % (len(files), total, len(instances)))

    # Rank by voices first, instances second - a shape used by many people
    # is a shape the language has.
    ranked = sorted(instances, key=lambda h: (-len(voices[h]), -instances[h]))

    print("%-22s %6s %7s  %-34s %s"
          % ("PREDICATE", "INST", "VOICES", "SLOT SIGNATURE (top)", "IN ENUM?"))
    print("-" * 104)
    for h in ranked:
        top_sig = sigs[h].most_common(1)[0][0][:34] if sigs[h] else ""
        if h in KNOWN:
            got = {t.strip().lower() for t in (sigs[h].most_common(1)[0][0].split(",")
                                               if sigs[h] else [])}
            mark = "yes" if got & KNOWN_SLOTS.get(h, set()) else "NAME ONLY"
        else:
            mark = "NO"
        print("%-22s %6d %7d  %-34s %s"
              % (h, instances[h], len(voices[h]), top_sig, mark))

    missing = [h for h in ranked if h not in KNOWN]
    covered = sum(instances[h] for h in ranked if h in KNOWN)
    print("\ncoverage: %d of %d instruction rows (%.0f%%) fit the current "
          "four-item vocabulary" % (covered, total, 100.0 * covered / max(total, 1)))
    print("predicates with NO case in RuleIntent: %d" % len(missing))

    print("\nTOP UNCOVERED SHAPES, by distinct voices:")
    for h in missing[:12]:
        print("  %-20s %3d inst / %2d voices  scope=%s"
              % (h, instances[h], len(voices[h]),
                 scopes[h].most_common(1)[0][0] if scopes[h] else "-"))
        if h in examples:
            print("      \"%s\"" % examples[h])

    json.dump({h: {"instances": instances[h], "voices": sorted(voices[h]),
                   "signatures": dict(sigs[h]), "example": examples.get(h)}
               for h in ranked},
              open("passes/%s/roadmap.json" % args.pass_name, "w",
                   encoding="utf-8"), indent=1)
    print("\nwrote passes/%s/roadmap.json" % args.pass_name)


if __name__ == "__main__":
    main()
