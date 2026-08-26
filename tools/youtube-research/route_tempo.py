"""Targeted router: tempo, pauses, and range-of-motion modifiers.

Owner 2026-08-26. An axis the app does not touch at all — nothing in the
generator or the catalog prescribes a tempo, a pause, or a ROM modifier.
It matters most exactly where the volume work is heading: once per-session
volume is capped, tempo and range are how stimulus keeps rising without
adding sets. It is also the honest answer for an equipment-limited lifter
who cannot simply add load.

Same discipline as route_core: triggers only count near training
vocabulary, density-normalized, already-deep-read videos excluded.

Usage:  python route_tempo.py [--top 30]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TRIGGERS = re.compile(
    r"\b(tempo|eccentrics?|concentrics?|isometrics?|"
    r"time under tension|"
    r"paused? (rep|squat|bench|deadlift)|paused reps?|"
    r"range of motion|full rom|partials?|lengthened partials?|"
    r"stretch(ed)? position|lengthened position|deep stretch|"
    r"slow (eccentric|negative|rep)|negatives?|"
    r"rep speed|bar speed|explosive intent|"
    r"cluster sets?|rest.?pause|myo.?reps?|drop sets?|"
    r"controlled (eccentric|descent|negative))\b", re.I)
CONTEXT = re.compile(
    r"\b(sets?|reps?|program|train(ing)?|exercise|hypertrophy|strength|"
    r"progress(ion|ive)?|overload|stimulus|fatigue|growth|muscle|"
    r"prescri|protocol|study|research|meta.?analysis)\b", re.I)
WINDOW = 180
RIGOR = {"HouseofHypertrophy": 5, "MennoHenselmans": 5, "StrongerByScience": 5,
         "DataDrivenStrength": 5, "BarbellMedicine": 4, "3DMuscleJourney": 4,
         "RenaissancePeriodization": 4, "FlowHighPerformance": 4,
         "JuggernautTrainingSystems": 3, "BiolayneVideo": 3, "Physionic": 3,
         "JeffNippard": 2, "SquatUniversity": 2, "JeremyEthier": 1, "athleanx": 1}
PASS = "tempo"
MIN_HITS = 8


def contextual_hits(text: str) -> int:
    hits = 0
    for m in TRIGGERS.finditer(text):
        lo = max(0, m.start() - WINDOW)
        if CONTEXT.search(text[lo:m.end() + WINDOW]):
            hits += 1
    return hits


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=30)
    ap.add_argument("--exclude", nargs="*", default=[])
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
        if t["id"] in seen or int(t.get("words", 0) or 0) < 400:
            continue
        hits = contextual_hits(t.get("text", ""))
        if hits < MIN_HITS:
            continue
        words = max(int(t.get("words", 1) or 1), 1)
        density = hits / words * 1000
        rigor = RIGOR.get(t.get("channel", ""), 2)
        scored.append((density * 8 + min(hits, 30) * 0.5 + rigor * 2,
                       hits, density, t))

    scored.sort(key=lambda s: -s[0])
    print(f"candidates >={MIN_HITS} contextual hits: {len(scored)} "
          f"(excluded {len(seen)} already-read)")
    for sc, hits, dens, t in scored[:args.top]:
        print(f"  {sc:6.1f}  h={hits:<3} d={dens:4.1f}  "
              f"[{t['channel'][:14]:<14}] {t['title'][:70]}")

    os.makedirs(f"passes/{PASS}", exist_ok=True)
    picks = [t for _, _, _, t in scored[:args.top]]
    for i in range(0, len(picks), 5):
        out = [{"id": t["id"], "title": t["title"], "channel": t["channel"],
                "channel_name": t.get("channel_name", t["channel"]),
                "words": t["words"], "text": t["text"]}
               for t in picks[i:i + 5]]
        json.dump(out, open(f"passes/{PASS}/b-{i // 5 + 1:02d}.json", "w",
                            encoding="utf-8"))
    print(f"wrote {(len(picks) + 4) // 5} batches -> passes/{PASS}/")


if __name__ == "__main__":
    main()
