"""Filter the PRACTITIONER channels down to the episodes worth fetching.

Owner 2026-08-26: "Chris Bumstead, Sam Sulek, Jeremy Ethier, Greg Doucette,
and anyone else in that vein. Go through and pull lessons from them in the
arenas we have already."

A third kind of source, and the third selector, because the first two do
not fit. select.py is tuned for coach-educators whose whole catalog is
about training; select_research.py is restrictive because general-science
shows are mostly off-topic. These channels are neither: they are physique
and lifestyle catalogs where a genuinely instructive training video sits
between a full-day-of-eating vlog and a car video.

So the filter is BOTH restrictive and vlog-hostile. A title has to earn its
way in on training vocabulary AND survive a long exclusion list, because
the failure mode here is fetching four hundred transcripts of someone
narrating their breakfast.

Note what is NOT filtered out: opinionated, unscientific, or contrarian
content. That is the point of this wave. An elite practitioner explaining
why they do something the literature does not support is a real finding -
it just has to reach the corpus graded `practice` or `opinion`, and where
it contradicts an existing strong row the contradiction IS the finding.

Usage:  python select_practitioner.py [--limit 180]
"""
import argparse
import glob
import json
import os
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PRACTITIONER_CHANNELS = {
    "cbum", "SamSulek", "GregDoucette", "RyanHumiston",
    "WillTennyson", "NoelDeyzel", "JeremyEthier",
}

# Training vocabulary that makes a title worth a transcript.
STRONG = [
    "how to", "technique", "form", "mistakes", "stop doing", "fix your",
    "best exercise", "worst exercise", "exercise selection",
    "program", "routine", "split", "training plan",
    "sets", "reps", "volume", "frequency", "intensity", "failure",
    "progressive overload", "periodization", "deload",
    "hypertrophy", "muscle growth", "build muscle", "grow your",
    "science", "study", "research", "explained", "guide", "tutorial",
    "chest", "back", "legs", "shoulders", "arms", "biceps", "triceps",
    "quads", "hamstrings", "glutes", "calves", "delts",
    "squat", "bench", "deadlift", "row", "press", "curl", "pull up",
]
MEDIUM = [
    "workout", "training", "lifting", "gym", "physique", "prep",
    "offseason", "bulking", "cutting", "diet", "nutrition", "protein",
    "recovery", "sleep", "injury", "rehab", "mobility", "warm up",
    "cardio", "conditioning", "posing", "peak week",
]
# The failure mode this wave exists to avoid.
EXCLUDE = [
    "full day of eating", "what i eat", "cheat meal", "cheat day", "mukbang",
    "vlog", "day in the life", "car", "house tour", "gym tour", "haul",
    "unboxing", "reacts", "reaction", "responds", "tier list", "rating",
    "q&a", "ama", "storytime", "story time", "prank", "challenge",
    "transformation", "physique update", "check in", "road to",
    "announcement", "merch", "giveaway", "podcast", "interview",
    "shorts", "#shorts", "trailer", "teaser", "vs.",
]


def score(title: str) -> int:
    low = title.lower()
    if any(term in low for term in EXCLUDE):
        return -1
    points = sum(4 for term in STRONG if term in low)
    points += sum(1 for term in MEDIUM if term in low)
    return points


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="corpus")
    ap.add_argument("--years", type=float, default=5.0)
    ap.add_argument("--limit", type=int, default=180)
    ap.add_argument("--out", default="practitioner-queue.json")
    args = ap.parse_args()

    cutoff = time.time() - args.years * 365.25 * 86400
    have = {os.path.basename(p)[:-5] for p in glob.glob("transcripts/*.json")}

    queue, stats = [], {}
    for path in glob.glob(os.path.join(args.corpus, "*.json")):
        channel = os.path.basename(path)[:-5]
        if channel not in PRACTITIONER_CHANNELS:
            continue
        try:
            blob = json.load(open(path, encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        videos = blob.get("videos", []) if isinstance(blob, dict) else blob
        name = blob.get("name", channel) if isinstance(blob, dict) else channel
        kept = 0
        for v in videos:
            vid = v.get("id")
            if not vid or vid in have:
                continue
            ts = v.get("timestamp") or 0
            if ts and ts < cutoff:
                continue
            points = score(v.get("title", ""))
            if points <= 0:
                continue
            queue.append({"id": vid, "title": v.get("title", ""),
                          "channel": channel, "channel_name": name,
                          "timestamp": ts, "score": points})
            kept += 1
        stats[channel] = (len(videos), kept)

    queue.sort(key=lambda v: (-v["score"], -(v.get("timestamp") or 0)))

    # Per-channel quota, same reason select_research.py has one: without it
    # the largest catalog takes the whole queue on volume alone, and the
    # point of this wave is a SPREAD of practitioner voices.
    per_channel = max(1, args.limit // max(1, len(stats)))
    taken, balanced = {}, []
    for v in queue:
        if taken.get(v["channel"], 0) >= per_channel:
            continue
        taken[v["channel"]] = taken.get(v["channel"], 0) + 1
        balanced.append(v)
    if len(balanced) < args.limit:
        chosen = {v["id"] for v in balanced}
        balanced += [v for v in queue if v["id"] not in chosen][:args.limit - len(balanced)]
    queue = balanced[:args.limit]

    json.dump(queue, open(args.out, "w", encoding="utf-8"), separators=(",", ":"))
    for ch, (total, kept) in sorted(stats.items()):
        print(f"  {ch:<16} {kept:>4} kept of {total:>5}")
    print(f"\nQUEUE: {len(queue)} videos -> {args.out}")
    for v in queue[:12]:
        print(f"  {v['score']:>3}  [{v['channel'][:12]:<12}] {v['title'][:64]}")


if __name__ == "__main__":
    main()
