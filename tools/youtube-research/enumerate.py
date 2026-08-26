"""Enumerate the research channels' video catalogs (metadata only).

Owner request 2026-08-16: pull the educational fitness corpus so the Coach's
evidence base reflects what the best science-based educators actually teach.

This step is metadata ONLY — id, title, duration, approximate upload date.
It exists to size the job honestly before any transcript work starts:
channel catalogs range from ~200 to a few thousand videos and the last-5-years
window plus a relevance filter is what makes the corpus tractable.

Usage:  python enumerate.py [--channel HANDLE] [--out DIR]
"""
import argparse
import json
import os
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# The 15 educational / science-first fitness channels (owner: "top 15
# educational fitness youtubers"). Chosen for research density — people who
# cite literature and teach programming, not physique vlogs. `weight` marks
# how central the channel is to PROGRAMMING questions specifically, which is
# what the Coach consumes.
CHANNELS = [
    ("JeffNippard", "Jeff Nippard", "high"),
    ("RenaissancePeriodization", "Renaissance Periodization (Israetel)", "high"),
    ("StrongerByScience", "Stronger By Science (Nuckols/Trexler)", "high"),
    ("BarbellMedicine", "Barbell Medicine (Feigenbaum/Baraki)", "high"),
    ("3DMuscleJourney", "3D Muscle Journey (Helms)", "high"),
    ("HouseofHypertrophy", "House of Hypertrophy", "high"),
    ("DataDrivenStrength", "Data Driven Strength", "high"),
    ("FlowHighPerformance", "Flow High Performance", "high"),
    ("MennoHenselmans", "Menno Henselmans", "high"),
    ("JuggernautTrainingSystems", "Juggernaut Training Systems", "high"),
    ("Physionic", "Physionic (Verhoeven)", "medium"),
    ("BiolayneVideo", "Biolayne (Layne Norton)", "medium"),
    ("SquatUniversity", "Squat University (Horschig)", "medium"),
    ("JeremyEthier", "Built With Science (Ethier)", "medium"),
    ("athleanx", "Athlean-X (Cavaliere)", "medium"),
    # ── Sport S&C expansion (owner 2026-08-21: football, baseball,
    # wrestling first; plus the channels every field athlete's S&C
    # actually draws from). resolve_handle self-heals imperfect handles.
    ("GarageStrength", "Garage Strength (Dane Miller — football/throws)", "high"),
    ("OvertimeAthletes", "Overtime Athletes (football/speed)", "high"),
    ("westsidebarbellofficial", "Westside Barbell (conjugate)", "medium"),
    ("DrivelineBaseball", "Driveline Baseball (data-driven baseball)", "high"),
    ("EricCressey", "Eric Cressey (baseball S&C)", "high"),
    ("TreadAthletics", "Tread Athletics (pitching development)", "medium"),
    ("DaruStrong", "Phil Daru (combat/wrestling S&C)", "high"),
    ("PJFPerformance", "PJF Performance (basketball/athleticism)", "medium"),
    # -- Researcher-led / long-form expansion (owner 2026-08-26: "are there
    # other research professionals we can pull from? Think Andrew Huberman,
    # who has fitness researchers like Stacy Sims on").
    #
    # The gap this closes is real and measurable: all 23 channels above are
    # COACH-led. Not one is a researcher or a long-form interview show, and
    # the thinnest area in the whole corpus is `female` at 28 findings --
    # exactly the subject Stacy Sims is the authority on. These are the
    # academic-adjacent sources, not more coaches.
    #
    # resolve_handle self-heals imperfect handles, which matters more here:
    # several of these publish under a show name rather than a person.
    ("hubermanlab", "Huberman Lab (Stanford; hosts Galpin, Sims)", "high"),
    ("PeterAttiaMD", "The Drive (Attia -- zone 2, VO2max, stability)", "high"),
    ("drstacysims", "Dr Stacy Sims (female physiology, cycle)", "high"),
    ("DrAndyGalpin", "Dr Andy Galpin (exercise physiology, testing)", "high"),
    ("FoundMyFitness", "FoundMyFitness (Rhonda Patrick -- recovery)", "medium"),
]


def resolve_handle(name: str, timeout: int = 240):
    """Find a channel's canonical URL by searching for its content — the
    fallback when a guessed @handle 404s (several of these channels use
    handles that don't match their display name)."""
    cmd = [sys.executable, "-m", "yt_dlp", "--flat-playlist", "-J",
           "--playlist-end", "1", f"ytsearch1:{name}"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        data = json.loads(proc.stdout)
        entry = (data.get("entries") or [None])[0]
        if entry and entry.get("channel_id"):
            return f"https://www.youtube.com/channel/{entry['channel_id']}/videos"
    except Exception:
        pass
    return None


def _run_enum(url: str, timeout: int):
    cmd = [
        sys.executable, "-m", "yt_dlp",
        "--flat-playlist", "-J", "--ignore-errors",
        "--extractor-args", "youtubetab:approximate_date",
        url,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if not proc.stdout.strip():
        return None, proc.stderr[-300:]
    try:
        data = json.loads(proc.stdout)
    except Exception as exc:
        return None, f"{type(exc).__name__}: {exc}"
    if not isinstance(data, dict):  # yt-dlp emits bare null for a dead handle
        return None, "no channel at that handle"
    return data, None


def enumerate_channel(handle: str, name: str, timeout: int = 900):
    """All videos on a channel's /videos tab, newest first, with approximate
    upload dates (the extractor arg that makes date filtering possible without
    a per-video metadata fetch)."""
    started = time.time()
    data, err = _run_enum(f"https://www.youtube.com/@{handle}/videos", timeout)
    if data is None:
        url = resolve_handle(name)
        if url:
            data, err = _run_enum(url, timeout)
    elapsed = time.time() - started
    if data is None:
        return None, elapsed, err
    rows = []
    for entry in data.get("entries", []) or []:
        if not entry or not entry.get("id"):
            continue
        rows.append({
            "id": entry["id"],
            "title": entry.get("title") or "",
            "duration": entry.get("duration"),
            "timestamp": entry.get("timestamp"),
            "view_count": entry.get("view_count"),
        })
    return rows, elapsed, None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--channel", help="single handle (default: all 15)")
    ap.add_argument("--out", default="corpus")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    targets = ([(h, n, w) for h, n, w in CHANNELS if h == args.channel]
               if args.channel else CHANNELS)

    summary = []
    for handle, name, weight in targets:
        path = os.path.join(args.out, f"{handle}.json")
        if os.path.exists(path):
            existing = json.load(open(path, encoding="utf-8"))
            print(f"SKIP {handle}: already enumerated ({len(existing['videos'])} videos)",
                  flush=True)
            summary.append((handle, len(existing["videos"]), 0.0))
            continue
        print(f"ENUM {handle} ...", flush=True)
        try:
            rows, elapsed, err = enumerate_channel(handle, name)
        except Exception as exc:  # one dead channel never kills the run
            print(f"  FAIL {handle}: {type(exc).__name__}: {exc}", flush=True)
            continue
        if rows is None:
            print(f"  FAIL {handle}: {err}", flush=True)
            continue
        json.dump({"handle": handle, "name": name, "weight": weight, "videos": rows},
                  open(path, "w", encoding="utf-8"), separators=(",", ":"))
        dated = sum(1 for r in rows if r.get("timestamp"))
        print(f"  {handle}: {len(rows)} videos ({dated} dated) in {elapsed:.0f}s",
              flush=True)
        summary.append((handle, len(rows), elapsed))

    total = sum(n for _, n, _ in summary)
    print(f"\nTOTAL: {total} videos across {len(summary)} channels")


if __name__ == "__main__":
    main()
