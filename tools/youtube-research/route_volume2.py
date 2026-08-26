"""Targeted router: optimal volume PER MUSCLE GROUP.

Owner 2026-08-26: "consult the transcripts about optimal volume per muscle
group."

The existing `volume` area (69 findings) covers weekly landmarks in the
aggregate. This pass asks the narrower question the generator actually
needs answered before a per-session cap can be chosen: does the optimum
DIFFER by muscle - do calves, side delts and forearms want more sets than
chest or quads, does a small muscle recover faster, and is there a
per-session ceiling distinct from the weekly one?

The distinction is load-bearing. The audit's own rule 11 says to keep
contested numbers out of hard rules, and the only strong weekly row says
moderate volume beats low - so a session cap cannot be set responsibly
until we know whether the ceiling is per muscle, per session, or neither.

Usage:  python route_volume2.py [--top 40]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TRIGGERS = re.compile(
    r"\b(sets per (muscle|week|session|workout)|weekly (sets|volume)|volume landmark|maximum recoverable volume|minimum effective volume|junk volume|diminishing returns|per muscle group|muscle group|small muscle|large muscle|calves|side delts|rear delts|forearms|optimal volume|how many sets|number of sets|set volume|dose.response|volume ceiling|recovery capacity)\b", re.I)
CONTEXT = re.compile(
    r"\b(hypertrophy|growth|muscle|train(ing)?|program|frequency|recovery|fatigue|stimulus|study|research|meta.?analysis|evidence|per week|session|workout)\b", re.I)
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
PASS = "volume2"
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
