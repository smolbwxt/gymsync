"""Targeted retrieval probe — find what the corpus says about a specific
constant we ship.

This is the hand-validated core of the research method: rather than digesting
every transcript, aim a pattern at the corpus, pull the passages that actually
carry a prescription, and rank them by the rigor of their source. Free, local,
instant — and it produced a confirmed generator defect on its first run
(fractional-vs-direct set counting).

Usage:  python probe.py --target rep_range [--limit 12]
        python probe.py --all
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Channels ranked by evidence-grounding (measured: citations per 1k words).
# Passages from rigorous channels sort first — popularity is deliberately
# NOT a factor, it runs inverse to rigor in this corpus.
RIGOR = {
    "HouseofHypertrophy": 5, "MennoHenselmans": 5, "StrongerByScience": 5,
    "DataDrivenStrength": 5, "BarbellMedicine": 4, "3DMuscleJourney": 4,
    "FlowHighPerformance": 4, "JeffNippard": 3, "Physionic": 3,
    "RenaissancePeriodization": 2, "JuggernautTrainingSystems": 2,
    "SquatUniversity": 2, "BiolayneVideo": 2, "JeremyEthier": 1, "athleanx": 1,
}

CITE = re.compile(r"meta[- ]analys|et al|study|studies|research|trial|evidence",
                  re.I)

# Each target names a constant we ship and the language that would challenge it.
TARGETS = {
    "fractional_volume": dict(
        constant="FocusBand.weeklySets 12-20 counted as DIRECT sets; "
                 "secondaryMuscles never read",
        patterns=[r"fractional (?:set|volume)", r"direct (?:set|volume)",
                  r"indirect (?:set|volume)", r"counts? (?:as|toward)s? (?:a )?(?:half|0\.5)"],
    ),
    "junk_volume": dict(
        constant="no per-muscle-per-SESSION set ceiling; only perDayBudget",
        patterns=[r"junk volume", r"maximum (?:number of )?sets",
                  r"too many sets", r"sets? per session", r"diminishing returns"],
    ),
    "rep_range": dict(
        constant="hypertrophy main 6-12 / accessory 8-15 rep bands",
        patterns=[r"rep range", r"hypertrophy rep", r"\d+\s*(?:to|-)\s*\d+\s*reps",
                  r"low reps? (?:vs|versus)", r"high reps?"],
    ),
    "frequency": dict(
        constant="frequency law: >=2x/muscle/week drives the whole split ladder",
        patterns=[r"training frequency", r"times per week", r"(?:once|twice|1x|2x|3x) (?:a|per) week",
                  r"frequency (?:for|and) (?:hypertrophy|growth)"],
    ),
    "reps_at_percent": dict(
        constant="repsAtPercent table (90%=4 ... 60%=16); anchors every main lift",
        patterns=[r"\d+\s*%\s*of (?:your )?(?:1\s*rm|one rep max)",
                  r"percent of (?:your )?(?:1\s*rm|max)", r"reps? (?:at|in reserve)"],
    ),
    "interference": dict(
        constant="flat 6h cardio separation + running steered off leg days",
        patterns=[r"interference effect", r"concurrent training",
                  r"cardio (?:and|before|after) (?:lifting|strength)",
                  r"hours? (?:between|apart)"],
    ),
}


def load_transcripts(path="transcripts"):
    out = []
    for f in glob.glob(os.path.join(path, "*.json")):
        if "_failed" in f:
            continue
        try:
            out.append(json.load(open(f, encoding="utf-8")))
        except Exception:
            pass
    return out


def probe(docs, patterns, window=260, per_video=2):
    """Passages matching any pattern, scored by source rigor + local citation
    density so the strongest evidence surfaces first."""
    hits = []
    regexes = [re.compile(p, re.I) for p in patterns]
    for doc in docs:
        text = doc["text"]
        found = 0
        seen_spans = []
        for rx in regexes:
            for m in rx.finditer(text):
                if found >= per_video:
                    break
                start = max(0, m.start() - window)
                if any(abs(start - s) < window for s in seen_spans):
                    continue
                seen_spans.append(start)
                passage = " ".join(text[start:m.start() + window].split())
                rigor = RIGOR.get(doc["channel"], 1)
                cites = len(CITE.findall(passage))
                nums = len(re.findall(r"\d+", passage))
                hits.append({
                    "rank": rigor * 3 + cites * 2 + min(nums, 6),
                    "channel": doc["channel_name"], "title": doc["title"],
                    "id": doc["id"], "passage": passage,
                })
                found += 1
    hits.sort(key=lambda h: -h["rank"])
    return hits


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=list(TARGETS))
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--limit", type=int, default=10)
    ap.add_argument("--out", default="probes")
    args = ap.parse_args()

    docs = load_transcripts()
    print(f"corpus: {len(docs)} transcripts\n", flush=True)
    os.makedirs(args.out, exist_ok=True)

    names = list(TARGETS) if args.all else [args.target]
    for name in names:
        spec = TARGETS[name]
        hits = probe(docs, spec["patterns"])
        json.dump(hits[:60], open(os.path.join(args.out, f"{name}.json"), "w",
                                  encoding="utf-8"), indent=1)
        print(f"=== {name.upper()} ===")
        print(f"we ship: {spec['constant']}")
        print(f"passages found: {len(hits)}  (top {min(args.limit,len(hits))} below)")
        for hit in hits[:args.limit]:
            print(f"\n  [{hit['rank']:>3}] {hit['channel'][:26]} — {hit['title'][:58]}")
            print(f"       {hit['passage'][:300]}")
        print()


if __name__ == "__main__":
    main()
