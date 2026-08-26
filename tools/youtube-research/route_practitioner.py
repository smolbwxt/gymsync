"""Route the PRACTITIONER wave into the arenas the corpus already has.

Owner 2026-08-26: "Go through and pull lessons from them in the arenas
we have already and add them to the corpus."

So this router does NOT open a new area. Every finding this wave produces
lands in one of the 21 areas already in `corpus_findings`, which is a
constraint on the AGENTS, not on the regex - a reader who has just heard
Bumstead describe how he trains back knows whether that belongs in
volume-per-muscle or strength-accessories far better than a keyword list
does.

What this file decides is therefore only WHICH transcripts are worth an
agent's attention, and in what order. The scoring is deliberately generic
- coaching-instruction density rather than one topic's trigger list -
because the whole point of the wave is that we do not know in advance
which arena a given practitioner video speaks to.

Two differences from the evidence routers:

1. NO RIGOR TABLE. The evidence passes rank channels by how carefully
   they handle studies. Ranking these channels that way would be a
   category error: none of them is a research channel, and the one that
   cites studies most confidently is not thereby the most trustworthy.
   Ordering here is by instruction density alone.

2. WORD-BUDGETED BATCHES rather than fixed counts. These transcripts run
   from 400 to 12,000 words - a fixed batch size would hand one agent
   four times another's reading.

Usage:  python route_practitioner.py [--top 120]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PRACTITIONER = {"cbum", "SamSulek", "GregDoucette", "RyanHumiston",
                "WillTennyson", "NoelDeyzel", "JeremyEthier"}

# An instruction, not a topic: the speaker is telling you to DO something
# or explaining why they do it. That is the unit this wave collects.
TRIGGERS = re.compile(
    r"\b(i (do|use|like|prefer|always|never|start|finish|go|keep|train)|"
    r"you (want|should|need to|have to|gotta)|make sure|the key is|"
    r"what i('m| am)? (doing|looking for)|the way i|my (go.to|favorite)|"
    r"sets? of|reps?|rir|failure|tempo|squeeze|stretch|contract|"
    r"range of motion|form|technique|cue|mind.muscle|"
    r"rest|superset|drop set|partial|lengthened|"
    r"progressive overload|volume|frequency|split|"
    r"warm.?up|deload|recovery|soreness)\b", re.I)
CONTEXT = re.compile(
    r"\b(muscle|chest|back|legs?|shoulders?|arms?|biceps|triceps|quads|"
    r"hamstrings?|glutes|calves|delts|lats|traps|"
    r"exercise|movement|lift|press|row|curl|squat|deadlift|extension|"
    r"train(ing)?|workout|session|program|grow(th)?|hypertrophy|strength)\b",
    re.I)
WINDOW = 160
PASS = "practitioner"
MIN_HITS = 15
# Wave 2 runs bigger batches than wave 1 because its transcripts are
# bigger: Sulek posts 33-minute training sessions where Ethier posts
# 8-minute explainers. A budget tuned for the short ones fragments the
# long ones into batches of two.
BATCH_WORDS = 26_000


def contextual_hits(text: str) -> int:
    hits = 0
    for m in TRIGGERS.finditer(text):
        lo = max(0, m.start() - WINDOW)
        if CONTEXT.search(text[lo:m.end() + WINDOW]):
            hits += 1
    return hits


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=120)
    ap.add_argument("--pass-name", default=PASS)
    # Wave 2 (2026-08-26) exists because wave 1 read the wrong channels
    # for Bumstead and Sulek. The transcripts wave 1 DID read correctly
    # are already in the corpus, so they must be excluded here or the
    # swarm pays to read them a second time and the corpus gets doubles.
    ap.add_argument("--exclude-pass", nargs="*", default=[],
                    help="pass directories whose batched ids to skip")
    args = ap.parse_args()

    already = set()
    for d in args.exclude_pass:
        for bf in glob.glob(os.path.join("passes", d, "b-*.json")):
            for rec in json.load(open(bf, encoding="utf-8")):
                already.add(rec["id"])
    if already:
        print("excluding %d transcripts already batched in %s"
              % (len(already), ", ".join(args.exclude_pass)))

    scored, skipped = [], 0
    for f in glob.glob("transcripts/*.json"):
        try:
            t = json.load(open(f, encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(t, dict) or "id" not in t:
            continue
        if t.get("channel") not in PRACTITIONER:
            continue
        if t["id"] in already:
            continue
        words = int(t.get("words", 0) or 0)
        if words < 400:
            skipped += 1
            continue
        hits = contextual_hits(t.get("text", ""))
        if hits < MIN_HITS:
            skipped += 1
            continue
        density = hits / max(words, 1) * 1000
        scored.append((density * 6 + min(hits, 60) * 0.4, hits, density, t))

    scored.sort(key=lambda s: -s[0])
    print(f"practitioner transcripts scoring >= {MIN_HITS} hits: "
          f"{len(scored)}  (skipped {skipped})")
    by_channel = {}
    for _, _, _, t in scored[:args.top]:
        by_channel[t["channel"]] = by_channel.get(t["channel"], 0) + 1
    for ch, n in sorted(by_channel.items(), key=lambda kv: -kv[1]):
        print(f"  {ch:<16} {n:>3}")
    print()
    for sc, hits, dens, t in scored[:12]:
        print(f"  {sc:6.1f}  h={hits:<4} d={dens:5.1f}  "
              f"[{t['channel'][:13]:<13}] {t['title'][:64]}")

    out_dir = f"passes/{args.pass_name}"
    os.makedirs(out_dir, exist_ok=True)
    for old in glob.glob(f"{out_dir}/b-*.json"):
        os.remove(old)

    batch, used, n = [], 0, 0
    def flush():
        nonlocal batch, used, n
        if not batch:
            return
        n += 1
        json.dump(batch, open(f"{out_dir}/b-{n:02d}.json", "w",
                              encoding="utf-8"))
        batch, used = [], 0

    for _, _, _, t in scored[:args.top]:
        w = int(t.get("words", 0) or 0)
        if used + w > BATCH_WORDS and batch:
            flush()
        batch.append({"id": t["id"], "title": t["title"],
                      "channel": t["channel"],
                      "channel_name": t.get("channel_name", t["channel"]),
                      "words": w, "text": t["text"]})
        used += w
    flush()
    print(f"\nwrote {n} word-budgeted batches -> {out_dir}/")


if __name__ == "__main__":
    main()
