"""Per-sport router: football / baseball / wrestling S&C content.

Owner 2026-08-21 ("Football, baseball, wrestling. Lets get to work"):
select the densest sport-specific programming transcripts per sport for
the deep-read swarm. Same length-bias discipline as route_core: triggers
count only near training vocabulary, density-normalized, channel rigor
weighting - here rigor means SPORT-SPECIFIC authority, not general
research rigor (Driveline outranks RP on baseball).

Usage:  python route_sport.py [--top 12]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SPORTS = {
    "football": {
        "triggers": re.compile(
            r"\b(football|lineman|linebacker|quarterback|running back|"
            r"wide receiver|combine|40.?yard|sprint speed|blocking|"
            r"tackl\w+|gridiron|d1|special teams)\b", re.I),
        "rigor": {"GarageStrength": 5, "OvertimeAthletes": 5,
                  "westsidebarbellofficial": 4, "DaruStrong": 2,
                  "PJFPerformance": 2},
    },
    "baseball": {
        # S&C for throwers, NOT hitting analytics - the first routing
        # surfaced Driveline's bat-speed product talk, which teaches the
        # generator nothing about programming a lifter.
        "triggers": re.compile(
            r"\b(pitcher|pitching|throwing (athlete|program|arm)|"
            r"arm care|rotator cuff|scapula\w*|ulnar|tommy john|"
            r"(in|off).?season (lifting|training|strength)|"
            r"baseball (strength|lifting|training|player))\b", re.I),
        "rigor": {"EricCressey": 5, "TreadAthletics": 5,
                  "DrivelineBaseball": 4, "GarageStrength": 2},
    },
    "wrestling": {
        "triggers": re.compile(
            r"\b(wrestl\w+|grappl\w+|takedown|combat (athlete|sport)|"
            r"mma|bjj|jiu.?jitsu|fight camp|weight cut|mat strength|"
            r"clinch|neck (training|strength))\b", re.I),
        "rigor": {"DaruStrong": 5, "GarageStrength": 4,
                  "westsidebarbellofficial": 2},
    },
}
CONTEXT = re.compile(
    r"\b(sets?|reps?|volume|program|train(ing)?|exercise|strength|"
    r"power|speed|explosive|off.?season|in.?season|workout|lift\w*)\b", re.I)
WINDOW = 180


def contextual_hits(rx, text):
    hits = 0
    for m in rx.finditer(text):
        lo = max(0, m.start() - WINDOW)
        if CONTEXT.search(text[lo:m.end() + WINDOW]):
            hits += 1
    return hits


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=12)
    args = ap.parse_args()

    transcripts = []
    for f in glob.glob("transcripts/*.json"):
        try:
            t = json.load(open(f, encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if isinstance(t, dict) and t.get("id") and t.get("words", 0) >= 400:
            transcripts.append(t)
    print(f"usable transcripts: {len(transcripts)}")

    used = set()   # a video reads for ONE sport - its densest
    for sport, cfg in SPORTS.items():
        scored = []
        for t in transcripts:
            if t["id"] in used:
                continue
            rigor = cfg["rigor"].get(t.get("channel", ""), 0)
            if rigor == 0:
                continue   # only sport-authoritative channels per sport
            hits = contextual_hits(cfg["triggers"], t.get("text", ""))
            if hits < 6:
                continue
            density = hits / max(t["words"], 1) * 1000
            scored.append((density * 8 + min(hits, 30) * 0.5 + rigor * 3,
                           hits, density, t))
        scored.sort(key=lambda s: -s[0])
        print(f"\n{sport}: {len(scored)} candidates")
        picks = []
        for sc, hits, dens, t in scored[:args.top]:
            used.add(t["id"])
            picks.append(t)
            print(f"  {sc:6.1f}  h={hits:<3} d={dens:4.1f}  "
                  f"[{t['channel'][:14]:<14}] {t['title'][:66]}")
        outdir = f"passes/sport-{sport}"
        os.makedirs(outdir, exist_ok=True)
        for i in range(0, len(picks), 4):
            out = [{"id": t["id"], "title": t["title"], "channel": t["channel"],
                    "channel_name": t.get("channel_name", t["channel"]),
                    "words": t["words"], "text": t["text"]}
                   for t in picks[i:i + 4]]
            json.dump(out, open(f"{outdir}/b-{i // 4 + 1:02d}.json", "w",
                                encoding="utf-8"))
        print(f"  wrote {(len(picks) + 3) // 4} batches -> {outdir}/")


if __name__ == "__main__":
    main()
