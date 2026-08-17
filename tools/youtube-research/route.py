"""Route transcripts to specialized deep-read passes.

Routing is free and keyword-based; a narrow brief over a well-chosen subset
extracts far better than one generic "tell me what's useful" pass over
everything. Most transcripts feed one pass, some feed several.

Ranking within a pass favors (a) density of that pass's own signals and
(b) measured channel rigor — never view count, which runs inverse to rigor
in this corpus.

Usage:  python route.py --pass substitution --limit 25 --batch 5
        python route.py --pass per_exercise --limit 25 --batch 5
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

RIGOR = {
    "HouseofHypertrophy": 5, "MennoHenselmans": 5, "StrongerByScience": 5,
    "DataDrivenStrength": 5, "BarbellMedicine": 4, "3DMuscleJourney": 4,
    "FlowHighPerformance": 4, "JeffNippard": 3, "Physionic": 3,
    "RenaissancePeriodization": 2, "JuggernautTrainingSystems": 2,
    "SquatUniversity": 2, "BiolayneVideo": 2, "JeremyEthier": 1, "athleanx": 1,
}

# A trigger phrase alone means nothing — "instead of" is ordinary English and
# a long podcast contains it a dozen times while never discussing training.
# What identifies a real claim is a trigger NEAR training vocabulary, so every
# pass scores on proximity within a window, then normalizes by length.
CONTEXT_TERMS = [
    "squat", "bench", "deadlift", "press", "row", "pulldown", "pull-up",
    "pull up", "chin-up", "curl", "extension", "raise", "fly", "dip", "lunge",
    "hip thrust", "leg press", "leg curl", "calf", "shrug", "pullover",
    "exercise", "movement", "lift", "machine", "dumbbell", "barbell", "cable",
    "sets", "reps", "rep range", "muscle", "hypertrophy", "training",
]
CONTEXT_RX = re.compile("|".join(re.escape(t) for t in CONTEXT_TERMS), re.I)
WINDOW = 180  # chars either side of the trigger


PASSES = {
    # "if your gym doesn't have X, do Y" — the substitution graph.
    "substitution": [
        r"instead of", r"alternative to", r"alternatives? for",
        r"if you don'?t have", r"substitut", r"swap (?:out|for|it)",
        r"replace (?:the|it|that) with", r"in place of", r"no access to",
        r"can'?t do (?:the|a)", r"similar (?:exercise|movement)",
    ],
    # Ranking / comparison / tier-list content -> per-exercise judgments.
    "per_exercise": [
        r"tier list", r"ranked", r"ranking", r"best (?:\d+ )?exercises?",
        r"worst exercises?", r"(?:vs\.?|versus) ", r"better than",
        r"most effective exercise", r"stop doing", r"overrated", r"underrated",
    ],
    # Progression / autoregulation logic.
    "progression": [
        r"progressive overload", r"add (?:weight|reps|sets)", r"double progression",
        r"autoregulat", r"stall", r"plateau", r"deload", r"when to increase",
        r"linear progression", r"amrap",
    ],
    # Failure modes -> the diagnostic layer.
    "diagnostics": [
        r"mistakes?", r"not growing", r"no gains", r"stalled", r"overtrain",
        r"overreach", r"why you'?re not", r"doing it wrong", r"red flag",
        r"warning sign", r"junk volume",
    ],
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pass", dest="pass_name", required=True, choices=list(PASSES))
    ap.add_argument("--dir", default="transcripts")
    ap.add_argument("--limit", type=int, default=25)
    ap.add_argument("--batch", type=int, default=5)
    ap.add_argument("--out", default="passes")
    args = ap.parse_args()

    patterns = [re.compile(p, re.I) for p in PASSES[args.pass_name]]
    rows = []
    for f in glob.glob(os.path.join(args.dir, "*.json")):
        if "_failed" in f:
            continue
        try:
            doc = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        text = doc["text"]
        # Count only triggers that sit near training vocabulary, and track
        # which trigger TYPES fired (breadth beats one repeated phrase).
        hits = 0
        kinds = set()
        for p in patterns:
            for m in p.finditer(text):
                lo = max(0, m.start() - WINDOW)
                if CONTEXT_RX.search(text[lo:m.end() + WINDOW]):
                    hits += 1
                    kinds.add(p.pattern)
        if len(kinds) < 2 or hits < 3:       # needs breadth AND substance
            continue
        # Density, not raw count — otherwise long podcasts always win.
        density = hits / max(doc["words"], 1) * 1000
        score = density * 10 + len(kinds) * 4 + RIGOR.get(doc["channel"], 1) * 3
        rows.append((score, hits, doc))

    rows.sort(key=lambda r: -r[0])
    picked = rows[:args.limit]
    print(f"pass={args.pass_name} candidates={len(rows)} picked={len(picked)}")
    for score, hits, doc in picked[:10]:
        print(f"  {score:>5} hits{hits:>4}  {doc['channel_name'][:22]:<24}"
              f"{doc['title'][:52]}")

    out_dir = os.path.join(args.out, args.pass_name)
    os.makedirs(out_dir, exist_ok=True)
    files = []
    for i in range(0, len(picked), args.batch):
        chunk = picked[i:i + args.batch]
        name = f"b-{i // args.batch + 1:02d}.json"
        json.dump([{
            "id": d["id"], "title": d["title"], "channel": d["channel"],
            "channel_name": d["channel_name"], "words": d["words"],
            "text": d["text"],
        } for _, _, d in chunk], open(os.path.join(out_dir, name), "w",
                                      encoding="utf-8"), separators=(",", ":"))
        files.append(name)
    print(f"\nwrote {len(files)} batches -> {out_dir}/")
    print(json.dumps(files))


if __name__ == "__main__":
    main()
