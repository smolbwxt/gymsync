"""Targeted router: female physiology and cycle-aware training.

Owner 2026-08-26. `female` is the thinnest real area in the corpus at 28
findings, and the roster explains why: until today all 23 channels were
coach-led and none specialises here. Five researcher-led channels were
added for exactly this, Stacy Sims foremost, and 200 of their episodes are
now on disk.

The owner's standing steer governs what we do with any finding: OFFER
cycle-aware programming to someone who wants it, never impose it. So this
pass looks for what an athlete could CHOOSE, and for the honest boundaries
of the evidence, including where it says the effect is small or absent.

Usage:  python route_female2.py [--top 40]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TRIGGERS = re.compile(
    r"\b(menstrual|menstruation|cycle phase|cycle syncing|cycle tracking|follicular|luteal|ovulation|ovulatory|perimenopause|perimenopausal|menopause|menopausal|postmenopausal|estrogen|oestrogen|progesterone|oral contraceptive|birth control|hormonal contraceptive|female athlete|for women|in women|women|pregnancy|pregnant|postpartum|pelvic floor|relative energy deficiency|amenorrhea|amenorrhoea|bone density|osteoporosis|osteopenia|sex difference|female physiology)\b", re.I)
CONTEXT = re.compile(
    r"\b(sets?|reps?|program|train(ing)?|exercise|lift(ing)?|hypertrophy|strength|cardio|zone 2|intensity|volume|recovery|adaptation|protein|creatine|nutrition|sleep|prescri|protocol|study|research|meta.?analysis|evidence)\b", re.I)
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
PASS = "female2"
MIN_HITS = 10


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
