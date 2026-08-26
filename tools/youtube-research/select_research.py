"""Filter the RESEARCHER-LED channels down to the episodes worth fetching.

Owner 2026-08-26: "are there other research professionals we can pull from?
Think Andrew Huberman, who has fitness researchers like Stacy Sims on."

Separate from select.py on purpose. That scorer is tuned for coach channels
where nearly every upload is about training, so a permissive title score is
the right filter. These five are not that: Huberman Lab and The Drive are
general science shows where most episodes are about sleep, dopamine,
longevity or oncology, and a permissive filter would fetch thousands of
transcripts that can never inform a training program.

So this one is RESTRICTIVE by default: a title has to earn its way in on
training, physiology or female-specific terms, and anything scoring zero is
dropped rather than ranked. Better to fetch 150 episodes that are about
the body under load than 2,000 that mention it.

Usage:  python select_research.py [--limit 200] [--out research-queue.json]
"""
import argparse
import glob
import json
import os
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# The channels this selector governs. Everything else is select.py's job.
RESEARCH_CHANNELS = {
    "hubermanlab", "PeterAttiaMD", "drstacysims", "DrAndyGalpin", "FoundMyFitness",
}

# Terms that make an episode worth a transcript. Weighted by how directly
# each one bears on what the app actually decides.
STRONG = [
    # The subject we are thinnest on, and the reason Sims is here at all.
    "menstrual", "cycle", "perimenopause", "menopause", "female", "women",
    "estrogen", "progesterone", "oral contracept", "pregnan", "postpartum",
    # Training itself.
    "resistance training", "strength training", "hypertrophy", "muscle",
    "training program", "periodization", "progressive overload",
    "exercise physiology", "vo2", "zone 2", "cardio", "endurance",
    "fiber type", "power output", "grip strength",
]
MEDIUM = [
    "protein", "creatine", "recovery", "sleep and performance", "overtraining",
    "tendon", "injury", "mobility", "stability", "aging", "longevity",
    "testosterone", "hormone", "adaptation", "fatigue", "fueling", "nutrition",
    "supplement", "heat", "cold", "sauna", "caffeine", "hydration",
    "bone density", "sarcopenia", "metabolism", "athlete", "performance",
]
# Off-topic for a training app even when excellent.
EXCLUDE = [
    "ask me anything", "ama |", "journal club", "cancer", "oncolog",
    "alzheimer", "dementia", "psychedelic", "dopamine", "adhd", "depression",
    "anxiety", "trauma", "fertility clinic", "crypto", "book launch",
    "announcement", "trailer", "teaser", "#shorts", "shorts",
]


def score(title: str) -> int:
    low = title.lower()
    if any(term in low for term in EXCLUDE):
        return -1
    points = sum(5 for term in STRONG if term in low)
    points += sum(2 for term in MEDIUM if term in low)
    return points


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="corpus")
    ap.add_argument("--years", type=float, default=6.0)
    ap.add_argument("--limit", type=int, default=200)
    ap.add_argument("--out", default="research-queue.json")
    args = ap.parse_args()

    cutoff = time.time() - args.years * 365.25 * 86400
    have = {os.path.basename(p)[:-5] for p in glob.glob("transcripts/*.json")}

    queue, seen_channels = [], {}
    for path in glob.glob(os.path.join(args.corpus, "*.json")):
        channel = os.path.basename(path)[:-5]
        if channel not in RESEARCH_CHANNELS:
            continue
        try:
            blob = json.load(open(path, encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        # enumerate.py writes {handle, name, weight, videos: [...]}.
        videos = blob.get("videos", []) if isinstance(blob, dict) else blob
        channel_name = blob.get("name", channel) if isinstance(blob, dict) else channel
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
                          "channel": channel,
                          "channel_name": channel_name,
                          "timestamp": ts, "score": points})
            kept += 1
        seen_channels[channel] = (len(videos), kept)

    queue.sort(key=lambda v: (-v["score"], -(v.get("timestamp") or 0)))
    # Per-channel quota. Without it Sims takes the whole queue on title
    # score alone - her entire channel is on-topic for us, while Attia and
    # Galpin bury their training episodes among general-health ones. She is
    # the priority (female is our thinnest area at 28 findings), but the
    # zone-2 and physiology evidence only exists on the other channels, and
    # our cardio zones are currently anchored to nothing at all.
    per_channel = max(1, args.limit // max(1, len(seen_channels)))
    taken, balanced = {}, []
    for v in queue:
        if taken.get(v["channel"], 0) >= per_channel:
            continue
        taken[v["channel"]] = taken.get(v["channel"], 0) + 1
        balanced.append(v)
    # Backfill any unused quota with the next-best regardless of channel.
    if len(balanced) < args.limit:
        chosen = {v["id"] for v in balanced}
        balanced += [v for v in queue if v["id"] not in chosen][:args.limit - len(balanced)]
    queue = balanced[:args.limit]
    json.dump(queue, open(args.out, "w", encoding="utf-8"), separators=(",", ":"))

    for ch, (total, kept) in sorted(seen_channels.items()):
        print(f"  {ch:<18} {kept:>4} kept of {total:>5}")
    print(f"\nQUEUE: {len(queue)} episodes -> {args.out}")
    for v in queue[:12]:
        print(f"  {v['score']:>3}  [{v['channel'][:14]:<14}] {v['title'][:66]}")


if __name__ == "__main__":
    main()
