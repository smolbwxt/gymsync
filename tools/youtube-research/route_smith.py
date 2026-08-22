"""Targeted router: SMITH MACHINE content across the corpus.

Owner 2026-08-21 (challenging the generator's strength filter, which
strips every isolation slot): "Can you not train strength on isolation
exercises?? Tricep work in isolation for strength is critical! What
does the corpus say about this?" This pass routes the corpus's densest
content on assistance/accessory programming in strength training -
necessity, selection, dose, placement.

Usage:  python route_smith.py [--top 16]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TRIGGERS = re.compile(
    r"(smith machine|smith[- ]?(squat|bench|press|row)|"
    r"guided bar|fixed bar path|machine (squat|bench) vs)", re.I)
CONTEXT = re.compile(
    r"\b(sets?|reps?|volume|program|train(ing)?|strength|powerlift\w*|"
    r"squat|bench|deadlift|press|block|phase|off.?season)\b", re.I)
WINDOW = 180
# Strength authority ranks this pass - the question is about STRENGTH
# programming, so the powerlifting-literate channels lead.
RIGOR = {"StrongerByScience": 5, "BarbellMedicine": 5,
         "JuggernautTrainingSystems": 5, "DataDrivenStrength": 5,
         "westsidebarbellofficial": 4, "RenaissancePeriodization": 4,
         "3DMuscleJourney": 4, "GarageStrength": 3, "HouseofHypertrophy": 3,
         "FlowHighPerformance": 3, "MennoHenselmans": 3, "BiolayneVideo": 2,
         "JeffNippard": 2, "SquatUniversity": 2}


def contextual_hits(text: str) -> int:
    hits = 0
    for m in TRIGGERS.finditer(text):
        lo = max(0, m.start() - WINDOW)
        if CONTEXT.search(text[lo:m.end() + WINDOW]):
            hits += 1
    return hits


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=16)
    args = ap.parse_args()

    scored = []
    for f in glob.glob("transcripts/*.json"):
        try:
            t = json.load(open(f, encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(t, dict) or "id" not in t or t.get("words", 0) < 400:
            continue
        rigor = RIGOR.get(t.get("channel", ""), 0)
        if rigor == 0:
            continue
        hits = contextual_hits(t.get("text", ""))
        if hits < 5:
            continue
        density = hits / max(t["words"], 1) * 1000
        scored.append((density * 8 + min(hits, 30) * 0.5 + rigor * 3,
                       hits, density, t))

    scored.sort(key=lambda s: -s[0])
    print(f"candidates >=5 contextual hits: {len(scored)}")
    os.makedirs("passes/smith", exist_ok=True)
    picks = []
    for sc, hits, dens, t in scored[:args.top]:
        picks.append(t)
        print(f"  {sc:6.1f}  h={hits:<3} d={dens:4.1f}  "
              f"[{t['channel'][:16]:<16}] {t['title'][:64]}")
    for i in range(0, len(picks), 4):
        out = [{"id": t["id"], "title": t["title"], "channel": t["channel"],
                "channel_name": t.get("channel_name", t["channel"]),
                "words": t["words"], "text": t["text"]}
               for t in picks[i:i + 4]]
        json.dump(out, open(f"passes/smith/b-{i // 4 + 1:02d}.json",
                            "w", encoding="utf-8"))
    print(f"wrote {(len(picks) + 3) // 4} batches -> passes/smith/")


if __name__ == "__main__":
    main()
