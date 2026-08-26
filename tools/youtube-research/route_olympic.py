"""Targeted router: Olympic weightlifting and its derivatives.

Owner 2026-08-26. The largest unmined queue in the store, and the app has
no Olympic-lift programming at all — so this pass is deliberately scoped to
what a GENERAL strength app can use: whether and when to program cleans,
snatches and their derivatives for power, how to teach and progress them
safely, and which derivatives (high pull, hang variations, jerk) carry the
benefit at a lower technical cost. NOT meet preparation, which is parked.

Same discipline as route_core: triggers only count near training
vocabulary, density-normalized, already-deep-read videos excluded.

Usage:  python route_olympic.py [--top 30]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TRIGGERS = re.compile(
    r"\b(olympic (lift(ing|s)?|weightlifting)|weightlifting|"
    r"power cleans?|hang cleans?|clean and jerk|clean pulls?|"
    r"snatch(es)?|hang snatch|power snatch|snatch pulls?|"
    r"high pulls?|jerks?|split jerk|push jerk|"
    r"triple extension|catch position|front rack|"
    r"rate of force development|explosive strength|"
    r"barbell (cycling|complex))\b", re.I)
CONTEXT = re.compile(
    r"\b(sets?|reps?|program|train(ing)?|exercise|technique|teach|coach|"
    r"progress(ion|ive)?|power|athlete|strength|load|percentage|"
    r"prescri|protocol|study|research|derivative|variation)\b", re.I)
WINDOW = 180
RIGOR = {"HouseofHypertrophy": 5, "MennoHenselmans": 5, "StrongerByScience": 5,
         "DataDrivenStrength": 5, "BarbellMedicine": 4, "3DMuscleJourney": 4,
         "RenaissancePeriodization": 4, "FlowHighPerformance": 4,
         "JuggernautTrainingSystems": 3, "BiolayneVideo": 3, "Physionic": 3,
         # This pass's authorities are different from the hypertrophy
         # passes': the weightlifting and field-sport channels carry the
         # coaching detail here, so they rank above the meta-analysis
         # channels for THIS topic only.
         "GarageStrength": 5, "PJFPerformance": 4, "OvertimeAthletes": 3,
         "DaruStrong": 3, "TreadAthletics": 3, "EricCressey": 4,
         "JeffNippard": 2, "SquatUniversity": 3, "JeremyEthier": 1, "athleanx": 1}
PASS = "olympic"
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
