"""Targeted router: core/ab programming content across the full corpus.

Owner 2026-08-21 (core placement question): consult the corpus on how core
is actually programmed — necessity, placement, frequency, volume. Same
length-bias discipline as route_plateau (triggers only count near training
vocabulary; density-normalized; already-deep-read videos excluded).

Usage:  python route_core.py [--top 15]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TRIGGERS = re.compile(
    r"\b(core training|ab training|ab work|ab day|abs|abdominals?|"
    r"obliques?|six.?pack|rectus abdominis|planks?|crunches|"
    r"anti.?rotation|anti.?extension|trunk stability)\b", re.I)
CONTEXT = re.compile(
    r"\b(sets?|reps?|volume|frequency|program|train(ing)?|exercise|"
    r"hypertrophy|strength|direct work|isolation|compound)\b", re.I)
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
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--exclude", nargs="*",
                    default=["passes/progression", "passes/diagnostics",
                             "passes/plateau"])
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
        if not isinstance(t, dict) or "id" not in t:
            continue
        if t["id"] in seen or t.get("words", 0) < 400:
            continue
        hits = contextual_hits(t.get("text", ""))
        if hits < 6:
            continue
        density = hits / max(t["words"], 1) * 1000
        rigor = RIGOR.get(t.get("channel", ""), 2)
        scored.append((density * 8 + min(hits, 30) * 0.5 + rigor * 2,
                       hits, density, t))

    scored.sort(key=lambda s: -s[0])
    print(f"candidates >=6 contextual hits: {len(scored)} "
          f"(excluded {len(seen)} already-read)")
    for sc, hits, dens, t in scored[:args.top]:
        print(f"  {sc:6.1f}  h={hits:<3} d={dens:4.1f}  "
              f"[{t['channel'][:14]:<14}] {t['title'][:70]}")

    os.makedirs("passes/core", exist_ok=True)
    picks = [t for _, _, _, t in scored[:args.top]]
    for i in range(0, len(picks), 5):
        out = [{"id": t["id"], "title": t["title"], "channel": t["channel"],
                "channel_name": t.get("channel_name", t["channel"]),
                "words": t["words"], "text": t["text"]}
               for t in picks[i:i + 5]]
        path = f"passes/core/b-{i // 5 + 1:02d}.json"
        json.dump(out, open(path, "w", encoding="utf-8"))
    print(f"wrote {(len(picks) + 4) // 5} batches -> passes/core/")


if __name__ == "__main__":
    main()
