"""Tier the corpus by value TO THE COACH, and archive what can't inform it.

Owner 2026-08-17: "there are a lot of videos that are of no use... if it's not
a lot that we care about, lets move them to an archive folder."

Scored on free local signals only — never view count, which in this corpus runs
INVERSE to rigor (Athlean-X median 917k views / 0.0 citations per 1k words;
Data Driven Strength 1.6k views / 5.1 citations):

  programming coverage  how many distinct training VARIABLES it discusses
  exercise coverage     how many distinct movements it names
  citation density      evidence grounding per 1k words
  prescription density  numeric set/rep/% claims per 1k words
  channel rigor         measured, not assumed

Tiers: A = deep-read candidate · B = retrieval only · C = archived.
NOTHING IS DELETED. Archive is a move, reversible with --restore, because a
low-scoring video can still hold one useful passage.

Usage:  python triage.py              (dry run: report + samples)
        python triage.py --apply      (move tier C into archive/)
        python triage.py --restore    (move everything back)
"""
import argparse
import glob
import json
import os
import re
import shutil
import sys
from collections import Counter

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

RIGOR = {
    "HouseofHypertrophy": 5, "MennoHenselmans": 5, "StrongerByScience": 5,
    "DataDrivenStrength": 5, "BarbellMedicine": 4, "3DMuscleJourney": 4,
    "FlowHighPerformance": 4, "JeffNippard": 3, "Physionic": 3,
    "RenaissancePeriodization": 2, "JuggernautTrainingSystems": 2,
    "SquatUniversity": 2, "BiolayneVideo": 2, "JeremyEthier": 1, "athleanx": 1,
}

# The variables the generator actually reasons about. Distinct-term COVERAGE
# is the signal (breadth of programming discussion), not raw repetition.
PROGRAMMING = [
    "sets per week", "training volume", "junk volume", "maintenance volume",
    "training frequency", "times per week", "periodization", "mesocycle",
    "progressive overload", "deload", "rep range", "reps in reserve", "rir",
    "rpe", "training to failure", "close to failure", "proximity to failure",
    "effective reps", "rest between sets", "rest period", "training split",
    "full body", "upper lower", "push pull legs", "hypertrophy", "strength training",
    "one rep max", "1rm", "training age", "trained individuals", "untrained",
    "specificity", "exercise selection", "mechanical tension", "muscle damage",
    "range of motion", "lengthened", "partial reps", "tempo", "eccentric",
    "concentric", "warm up", "muscle protein synthesis", "recovery", "overreaching",
    "intensity", "beginner", "advanced lifter", "programming", "routine",
    "supersets", "drop set", "interference effect", "concurrent training",
]
EXERCISES = [
    "squat", "bench press", "deadlift", "overhead press", "row", "pulldown",
    "pull-up", "pull up", "chin up", "dip", "curl", "triceps extension",
    "lateral raise", "leg press", "leg curl", "leg extension", "hip thrust",
    "lunge", "split squat", "calf raise", "fly", "shrug", "pullover", "press",
]
# Content that cannot inform a PROGRAM (archived, not deleted — nutrition work
# would matter again the day GymSync grows a nutrition feature).
OFFTOPIC = [
    "calories", "macros", "keto", "protein powder", "creatine", "supplement",
    "recipe", "meal prep", "weight loss diet", "intermittent fasting",
    "glp-1", "semaglutide", "steroid", "trt", "testosterone replacement",
    "podcast episode", "sponsor", "business", "coaching business",
]


def coverage(text: str, terms) -> int:
    return sum(1 for t in terms if t in text)


def score_doc(doc):
    """Two separate judgments, deliberately not blended:

    RELEVANCE (is this about training programming at all?) decides archiving.
    SCORE (how rich is it?) only ranks what's already relevant into A vs B.

    Blending them was wrong: score scales with length, so a rambling nutrition
    podcast out-scored a short, sharp 'how to target triceps' video. Length is
    a quality signal, never a topicality one.
    """
    text = doc["text"].lower()
    words = max(doc["words"], 1)
    prog = coverage(text, PROGRAMMING)
    exer = coverage(text, EXERCISES)
    off = coverage(text, OFFTOPIC)
    cites = len(re.findall(r"meta[- ]analys|et al|stud(?:y|ies)|research|trial",
                           text)) / words * 1000
    nums = len(re.findall(r"\d+\s*(?:sets?|reps?|%)", text)) / words * 1000
    rigor = RIGOR.get(doc["channel"], 1)

    # Relevance gate: does it discuss training variables or movements?
    relevant = (prog >= 2 or exer >= 3) and not (off >= 3 and prog <= 2)

    score = (prog * 3.0 + exer * 1.5 + cites * 1.2 + nums * 1.5
             + rigor - off * 1.5)
    if doc["words"] < 400:          # brevity limits depth, never topicality
        score -= 4
    return score, relevant, dict(prog=prog, exer=exer, off=off,
                                 cites=round(cites, 1), nums=round(nums, 1))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="transcripts")
    ap.add_argument("--archive", default="archive")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--restore", action="store_true")
    ap.add_argument("--tier-b", type=float, default=14.0)
    ap.add_argument("--tier-a", type=float, default=30.0)
    args = ap.parse_args()

    if args.restore:
        moved = 0
        for f in glob.glob(os.path.join(args.archive, "*.json")):
            shutil.move(f, os.path.join(args.dir, os.path.basename(f)))
            moved += 1
        print(f"restored {moved} transcripts")
        return

    rows = []
    for f in glob.glob(os.path.join(args.dir, "*.json")):
        if "_failed" in f:
            continue
        try:
            doc = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        score, relevant, parts = score_doc(doc)
        rows.append((score, relevant, parts, doc, f))
    rows.sort(key=lambda r: -r[0])

    def tier(score, relevant):
        if not relevant:
            return "C"
        return "A" if score >= args.tier_a else "B"

    counts = Counter(tier(s, rel) for s, rel, _, _, _ in rows)
    print(f"corpus: {len(rows)} transcripts")
    print(f"  A (deep read): {counts['A']:>5}")
    print(f"  B (retrieval): {counts['B']:>5}")
    print(f"  C (archive)  : {counts['C']:>5}\n")

    def sample(t, n=8):
        out = [r for r in rows if tier(r[0], r[1]) == t]
        print(f"--- tier {t} sample ({len(out)}) ---")
        step = max(1, len(out) // n)
        for score, _, parts, doc, _ in out[::step][:n]:
            print(f"  {score:6.1f} prog{parts['prog']:>3} ex{parts['exer']:>3} "
                  f"off{parts['off']:>2} {doc['channel_name'][:20]:<22}"
                  f"{doc['title'][:50]}")
        print()

    sample("A"); sample("B"); sample("C", 12)

    by_ch = Counter(doc["channel"] for s, rel, _, doc, _ in rows
                    if tier(s, rel) == "C")
    print("archived-by-channel:", dict(by_ch.most_common(8)))

    if args.apply:
        os.makedirs(args.archive, exist_ok=True)
        moved = 0
        for score, relevant, _, _, path in rows:
            if tier(score, relevant) == "C":
                shutil.move(path, os.path.join(args.archive, os.path.basename(path)))
                moved += 1
        print(f"\nARCHIVED {moved} transcripts -> {args.archive}/ (reversible: --restore)")
    else:
        print("\n(dry run — rerun with --apply to move tier C)")


if __name__ == "__main__":
    main()
