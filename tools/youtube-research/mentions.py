"""How much of our exercise catalog does the corpus actually discuss?

Owner hypothesis 2026-08-17: "if an exercise doesn't even make it to the
discussion, then it shouldn't really be suggested by the coach."

This measures it. For each catalog exercise, count how many distinct videos
and distinct CHANNELS mention it — channels matter more than raw mentions,
because one prolific educator must not manufacture consensus on his own.

Matching is deliberately generous: catalog names carry equipment qualifiers
("Barbell Romanian Deadlift") that nobody says aloud, so we also match the
core movement name and a small alias table for the abbreviations lifters
actually use.

Usage:  python mentions.py [--out mentions.json]
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

# Qualifiers a coach drops in speech: "Barbell Back Squat" -> "back squat".
QUALIFIERS = [
    "barbell", "dumbbell", "cable", "machine", "smith machine", "kettlebell",
    "band", "resistance band", "bodyweight", "landmine", "trap bar", "hex bar",
    "ez bar", "ez-bar", "plate loaded", "plate-loaded", "lever", "sled",
    "assisted", "weighted", "seated", "standing", "lying", "incline", "decline",
]

# What lifters actually say -> what our catalog calls it.
ALIASES = {
    "rdl": "romanian deadlift",
    "rdls": "romanian deadlift",
    "bss": "bulgarian split squat",
    "rfess": "bulgarian split squat",
    "ohp": "overhead press",
    "bench": "bench press",
    "pulldown": "lat pulldown",
    "pull down": "lat pulldown",
    "chin up": "chin-up",
    "pull up": "pull-up",
    "push up": "push-up",
    "hip thrust": "hip thrust",
    "leg curl": "leg curl",
    "leg extension": "leg extension",
    "skullcrusher": "skull crusher",
    "lateral raise": "lateral raise",
    "rear delt fly": "rear delt fly",
    "good morning": "good morning",
}


def normalize(name: str) -> str:
    name = name.lower()
    name = re.sub(r"[^a-z0-9 \-]", " ", name)
    return " ".join(name.split())


def core_name(name: str) -> str:
    """Strip leading equipment/position qualifiers to get the movement."""
    words = normalize(name).split()
    changed = True
    while changed and len(words) > 1:
        changed = False
        for q in sorted(QUALIFIERS, key=lambda x: -len(x.split())):
            qw = q.split()
            if words[:len(qw)] == qw and len(words) > len(qw):
                words = words[len(qw):]
                changed = True
                break
    return " ".join(words)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="mentions.json")
    ap.add_argument("--transcripts", default="transcripts")
    args = ap.parse_args()

    # The export is CLI-wrapped (envelope around the row array) — pull the
    # array out rather than assuming a bare list.
    raw = open(CATALOG, encoding="utf-8").read()
    catalog = json.loads(raw[raw.find("["):raw.rfind("]") + 1])
    docs = []
    for f in glob.glob(os.path.join(args.transcripts, "*.json")):
        if "_failed" in f:
            continue
        try:
            d = json.load(open(f, encoding="utf-8"))
            docs.append((d["channel"], normalize(d["text"])))
        except Exception:
            pass
    print(f"catalog: {len(catalog)} exercises | corpus: {len(docs)} transcripts",
          flush=True)

    # Build the search terms per exercise: full name + core name (+ aliases).
    terms = {}
    for ex in catalog:
        full = normalize(ex["name"])
        core = core_name(ex["name"])
        cand = {full}
        if len(core.split()) >= 2:          # "squat" alone is too generic
            cand.add(core)
        for alias, canonical in ALIASES.items():
            if canonical in full or canonical == core:
                cand.add(alias)
        terms[ex["slug"]] = (ex["name"], [c for c in cand if len(c) >= 6])

    videos = defaultdict(set)
    channels = defaultdict(set)
    for idx, (channel, text) in enumerate(docs, 1):
        for slug, (_, cands) in terms.items():
            for c in cands:
                if c in text:
                    videos[slug].add(idx)
                    channels[slug].add(channel)
                    break
        if idx % 200 == 0:
            print(f"  scanned {idx}/{len(docs)} transcripts", flush=True)

    rows = []
    for slug, (name, _) in terms.items():
        rows.append({"slug": slug, "name": name,
                     "videos": len(videos[slug]), "channels": len(channels[slug])})
    rows.sort(key=lambda r: (-r["channels"], -r["videos"]))
    json.dump(rows, open(args.out, "w", encoding="utf-8"), separators=(",", ":"))

    attested = [r for r in rows if r["channels"] >= 2]
    weak = [r for r in rows if r["channels"] == 1]
    silent = [r for r in rows if r["channels"] == 0]
    print(f"\nATTESTED (>=2 channels): {len(attested)}")
    print(f"WEAK      (1 channel)  : {len(weak)}")
    print(f"SILENT    (0 channels) : {len(silent)}")
    print("\ntop 12 most-discussed:")
    for r in rows[:12]:
        print(f"  {r['channels']:>2}ch {r['videos']:>4}vid  {r['name']}")
    print("\nsample of SILENT exercises:")
    for r in silent[:12]:
        print(f"      {r['name']}")


if __name__ == "__main__":
    main()
