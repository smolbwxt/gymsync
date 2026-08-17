"""Fetch and archive transcripts for the ranked queue.

Owner 2026-08-16: "just pull the transcripts and store them for future
reference." That is exactly what this does — the corpus is the deliverable.

Uses yt-dlp's subtitle path rather than youtube-transcript-api: the latter
started returning RecursionError once YouTube got tired of us, while yt-dlp
carries the anti-bot handling and keeps working. Downloads are BATCHED (one
yt-dlp invocation per chunk of ids) so process startup is amortised across
the run.

Resume-safe by construction: one file per video, existing files skipped, so
a kill or a network drop only ever costs the chunk in flight. Best-first
order (select.py ranks by research density) means stopping early still
leaves the most useful corpus.

Storage: transcripts/<video_id>.json — {id, title, channel, channel_name,
timestamp, words, text}. Git-ignored; this is third-party material held
locally for reference, not repo content.

Usage:  python -u fetch.py [--limit N] [--chunk 40]
"""
import argparse
import glob
import json
import os
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def parse_json3(path: str) -> str:
    """json3 subtitle track -> plain text."""
    try:
        data = json.load(open(path, encoding="utf-8"))
    except Exception:
        return ""
    parts = []
    for event in data.get("events") or []:
        for seg in event.get("segs") or []:
            chunk = seg.get("utf8", "")
            if chunk and chunk != "\n":
                parts.append(chunk)
    return " ".join(" ".join(parts).split())


def download_chunk(ids, raw_dir: str, timeout: int) -> None:
    """One yt-dlp call for a chunk of video ids. Errors are ignored per-video
    so a single dead video never costs the chunk."""
    batch_file = os.path.join(raw_dir, "_batch.txt")
    with open(batch_file, "w", encoding="utf-8") as fh:
        for vid in ids:
            fh.write(f"https://www.youtube.com/watch?v={vid}\n")
    cmd = [
        sys.executable, "-m", "yt_dlp",
        "--batch-file", batch_file,
        "--write-auto-sub", "--write-sub", "--sub-lang", "en.*",
        "--sub-format", "json3", "--skip-download",
        "--ignore-errors", "--no-warnings", "--quiet",
        "--sleep-requests", "0.5",
        "-o", os.path.join(raw_dir, "%(id)s"),
    ]
    try:
        subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print("  chunk timed out — moving on (resume will retry)", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--queue", default="queue.json")
    ap.add_argument("--out", default="transcripts")
    ap.add_argument("--raw", default="_raw")
    ap.add_argument("--limit", type=int, default=0, help="0 = whole queue")
    ap.add_argument("--chunk", type=int, default=40)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    os.makedirs(args.raw, exist_ok=True)
    queue = json.load(open(args.queue, encoding="utf-8"))
    if args.limit:
        queue = queue[:args.limit]

    # Skip anything already fetched — including transcripts that triage has
    # since moved to archive/. Without this, archiving would make a video look
    # unfetched and the next run would re-download everything we filtered out.
    def already_have(vid: str) -> bool:
        return (os.path.exists(os.path.join(args.out, f"{vid}.json"))
                or os.path.exists(os.path.join("archive", f"{vid}.json")))

    pending = [v for v in queue if not already_have(v["id"])]
    have = len(queue) - len(pending)
    print(f"queue={len(queue)} already_stored={have} to_fetch={len(pending)}", flush=True)

    started = time.time()
    stored = have
    words_total = 0
    no_subs = 0

    for offset in range(0, len(pending), args.chunk):
        chunk = pending[offset:offset + args.chunk]
        download_chunk([v["id"] for v in chunk], args.raw,
                       timeout=90 + 12 * len(chunk))

        for video in chunk:
            hits = sorted(glob.glob(os.path.join(args.raw, f"{video['id']}*.json3")))
            if not hits:
                no_subs += 1
                continue
            text = ""
            for hit in hits:                       # prefer the richest track
                candidate = parse_json3(hit)
                if len(candidate) > len(text):
                    text = candidate
            for hit in hits:                       # raw files are transient
                try:
                    os.remove(hit)
                except OSError:
                    pass
            if not text:
                no_subs += 1
                continue
            words = len(text.split())
            json.dump({
                "id": video["id"], "title": video["title"],
                "channel": video["channel"], "channel_name": video["channel_name"],
                "timestamp": video.get("timestamp"), "score": video.get("score"),
                "words": words, "text": text,
            }, open(os.path.join(args.out, f"{video['id']}.json"), "w",
                     encoding="utf-8"), separators=(",", ":"))
            stored += 1
            words_total += words

        done = offset + len(chunk)
        rate = done / max(1e-9, (time.time() - started) / 60)
        eta = (len(pending) - done) / rate if rate else 0
        print(f"[{done}/{len(pending)}] stored={stored} no_subs={no_subs} "
              f"words={words_total:,} ({rate:.0f}/min, ~{eta:.0f} min left)",
              flush=True)

    print(f"\nDONE: {stored} transcripts stored, {no_subs} without usable subtitles, "
          f"{words_total:,} words fetched this run, "
          f"{(time.time()-started)/60:.0f} min", flush=True)


if __name__ == "__main__":
    main()
