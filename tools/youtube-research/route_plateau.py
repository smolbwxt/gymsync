"""Targeted router: plateau-breaking content across the FULL active corpus.

The general progression pass deep-read only its top 30 transcripts; this
sweep hunts specifically for stall/plateau protocols everywhere else. Same
length-bias discipline as route.py (third time that bug appeared): triggers
only count within WINDOW chars of training vocabulary, scores are
density-normalized, and already-deep-read videos are excluded.

Usage:  python route_plateau.py [--top 20] [--exclude passes/progression passes/diagnostics]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TRIGGERS = re.compile(
    r"plateau|stall(ed|ing)?|sticking point|stuck at|break(ing)? through|"
    r"bust(ing)? (a|the|your)|stopped (grow|progress|gain)|"
    r"no longer (grow|progress|gain)|can'?t (add|increase|progress)|"
    r"same weight for (week|month)", re.I)
CONTEXT = re.compile(
    r"\b(sets?|reps?|volume|deload|progress|overload|1rm|strength|"
    r"hypertrophy|muscle|lift|bench|squat|deadlift|training|program|"
    r"mesocycle|rpe|rir|failure)\b", re.I)
WINDOW = 180
RIGOR = {"HouseofHypertrophy": 5, "MennoHenselmans": 5, "StrongerByScience": 5,
         "DataDrivenStrength": 5, "BarbellMedicine": 4, "3DMuscleJourney": 4,
         "RenaissancePeriodization": 4, "FlowHighPerformance": 4,
         "JuggernautTrainingSystems": 3, "BiolayneVideo": 3, "Physionic": 3,
         "JeffNippard": 2, "SquatUniversity": 2, "JeremyEthier": 1, "athleanx": 1}


def contextual_hits(text: str) -> int:
    hits = 0
    for m in TRIGGERS.finditer(text):
        lo = max(0, m.start() - WINDOW)
        if CONTEXT.search(text[lo:m.end() + WINDOW]):
            hits += 1
    return hits


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--exclude", nargs="*",
                    default=["passes/progression", "passes/diagnostics"])
    args = ap.parse_args()

    seen = set()
    for d in args.exclude:
        for f in glob.glob(os.path.join(d, "*.json")):
            for rec in json.load(open(f, encoding="utf-8")):
                seen.add(rec["id"])

    scored = []
    for f in glob.glob("transcripts/*.json"):
        try:
            t = json.load(open(f, encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        # A handful of fetch-era files are malformed — skip, never crash.
        if not isinstance(t, dict) or "id" not in t:
            continue
        if t["id"] in seen or t.get("words", 0) < 400:
            continue
        hits = contextual_hits(t.get("text", ""))
        if hits < 4:
            continue
        density = hits / max(t["words"], 1) * 1000
        rigor = RIGOR.get(t.get("channel", ""), 2)
        scored.append((density * 8 + min(hits, 30) * 0.5 + rigor * 2,
                       hits, density, t))

    scored.sort(key=lambda s: -s[0])
    print(f"candidates >=4 contextual hits: {len(scored)} "
          f"(excluded {len(seen)} already-read)")
    for sc, hits, dens, t in scored[:args.top]:
        print(f"  {sc:6.1f}  h={hits:<3} d={dens:4.1f}  "
              f"[{t['channel'][:14]:<14}] {t['title'][:70]}")

    os.makedirs("passes/plateau", exist_ok=True)
    picks = [t for _, _, _, t in scored[:args.top]]
    for i in range(0, len(picks), 5):
        out = [{"id": t["id"], "title": t["title"], "channel": t["channel"],
                "channel_name": t.get("channel_name", t["channel"]),
                "words": t["words"], "text": t["text"]}
               for t in picks[i:i + 5]]
        path = f"passes/plateau/b-{i // 5 + 1:02d}.json"
        json.dump(out, open(path, "w", encoding="utf-8"))
    print(f"wrote {(len(picks) + 4) // 5} batches -> passes/plateau/")


if __name__ == "__main__":
    main()
