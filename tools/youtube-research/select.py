"""Filter + rank the enumerated catalog into a fetch queue.

Two jobs:
  1. Cut the corpus to what can actually inform PROGRAMMING decisions —
     last 5 years, real videos (not shorts), research/teaching content rather
     than vlogs, hauls, and physique updates.
  2. Rank what survives by research density, so the fetch runs best-first and
     stopping early still leaves the most useful corpus.

Usage:  python select.py [--years 5] [--min-seconds 180] [--out queue.json]
"""
import argparse
import json
import os
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Terms that mark a video as teaching a training VARIABLE — the things the
# generator actually reasons about. Weighted: a title promising a study
# breakdown on volume beats a generic "best exercises" list.
STRONG = [
    "study", "studies", "research", "meta-analysis", "meta analysis", "science",
    "evidence", "systematic review", "data", "literature",
    "hypertrophy", "muscle growth", "volume", "frequency", "intensity",
    "periodization", "periodisation", "progressive overload", "programming",
    "program design", "rep range", "reps", "rir", "rpe", "failure",
    "deload", "recovery", "rest time", "rest period", "tempo",
    "range of motion", "lengthened", "partial", "stretch mediated",
    "exercise selection", "split", "full body", "upper lower", "push pull legs",
    "interference", "concurrent", "hypertrophy vs strength", "sets per week",
    "junk volume", "mechanical tension", "muscle damage", "specificity",
    "novice", "beginner", "intermediate", "advanced", "detraining",
    "warm up", "warm-up", "mind muscle", "eccentric", "cadence",
]
MEDIUM = [
    "how to", "guide", "explained", "mistakes", "myth", "optimal", "best way",
    "technique", "form", "mechanics", "anatomy", "biomechanics", "should you",
    "vs", "versus", "better", "training", "workout", "routine", "plan",
]
# Content that will not inform a program even when it is excellent content.
EXCLUDE = [
    "vlog", "what i eat", "full day of eating", "cheat day", "haul", "unboxing",
    "reacts", "reaction", "day in the life", "gym tour", "physique update",
    "transformation", "prank", "q&a", "ama", "announcement", "merch",
    "giveaway", "shorts", "#shorts", "trailer", "teaser", "podcast clip",
]


def score(title: str, weight: str) -> int:
    """Research density of a title. Channel weight breaks ties between
    equally-titled videos from a research channel and a general one."""
    low = title.lower()
    if any(term in low for term in EXCLUDE):
        return -1
    points = sum(4 for term in STRONG if term in low)
    points += sum(1 for term in MEDIUM if term in low)
    if weight == "high":
        points += 2
    return points


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="corpus")
    ap.add_argument("--years", type=float, default=5.0)
    ap.add_argument("--min-seconds", type=int, default=180)
    ap.add_argument("--out", default="queue.json")
    args = ap.parse_args()

    cutoff = time.time() - args.years * 365.25 * 86400
    queue, stats = [], []
    for fname in sorted(os.listdir(args.corpus)):
        if not fname.endswith(".json"):
            continue
        data = json.load(open(os.path.join(args.corpus, fname), encoding="utf-8"))
        handle, weight = data["handle"], data.get("weight", "medium")
        total = len(data["videos"])
        in_window = fresh = kept = 0
        for video in data["videos"]:
            ts = video.get("timestamp")
            if ts and ts < cutoff:
                continue
            in_window += 1
            duration = video.get("duration") or 0
            if duration and duration < args.min_seconds:
                continue
            fresh += 1
            points = score(video["title"], weight)
            if points <= 0:
                continue
            kept += 1
            queue.append({
                "id": video["id"], "title": video["title"], "channel": handle,
                "channel_name": data["name"], "duration": duration,
                "timestamp": ts, "score": points,
            })
        stats.append((handle, total, in_window, fresh, kept))

    queue.sort(key=lambda v: (-v["score"], -(v.get("timestamp") or 0)))
    json.dump(queue, open(args.out, "w", encoding="utf-8"), separators=(",", ":"))

    print(f"{'channel':<28}{'all':>7}{'<=5yr':>8}{'>=3min':>8}{'kept':>7}")
    for handle, total, in_window, fresh, kept in stats:
        print(f"{handle:<28}{total:>7}{in_window:>8}{fresh:>8}{kept:>7}")
    print(f"\nQUEUE: {len(queue)} videos "
          f"(~{sum(v['duration'] or 0 for v in queue)/3600:.0f} hours of material)")


if __name__ == "__main__":
    main()
