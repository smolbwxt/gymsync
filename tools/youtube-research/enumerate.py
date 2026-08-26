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
import re
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
    # -- Practitioner / physique wave (owner 2026-08-26: "Chris Bumstead,
    # Sam Sulek, Jeremy Ethier, Greg Doucette, and anyone else in that
    # vein").
    #
    # A deliberately DIFFERENT kind of source from the two waves above, and
    # the difference has to survive into the corpus. These are elite
    # practitioners and high-reach coaches, not researchers: the signal is
    # what people at the top of the sport actually DO and how they talk
    # about it, which the science channels rarely show. The cost is rigor -
    # very little here is cited, and some of it contradicts the evidence
    # rows we already hold.
    #
    # So they carry weight "low", and every router's RIGOR map scores them
    # at the bottom. A claim from here should reach the corpus graded
    # `practice` or `opinion`, never `study`, and where it CONTRADICTS an
    # existing strong row the contradiction is the finding.
    #
    # Jeremy Ethier was already enumerated in the first wave; the owner
    # named him again, and re-listing is a no-op (enumerate.py skips
    # channels already on disk).
    ("cbum", "Chris Bumstead (5x Classic Physique Olympia)", "low"),
    ("SamSulek", "Sam Sulek (high-volume physique training)", "low"),
    ("GregDoucette", "Greg Doucette (IFBB pro, coaching content)", "low"),
    ("RyanHumiston", "Ryan Humiston (physique, exercise selection)", "low"),
    ("WillTennyson", "Will Tennyson (experiments, self-testing)", "low"),
    # Arrived by accident (a dead @EricCressey handle searched into
    # his channel) and kept on purpose: 1037 episodes of a real S&C
    # podcast, now under his own name and his own weight.
    ("MikeRobertson", "Mike Robertson (Physical Preparation Podcast)", "medium"),
    ("NoelDeyzel", "Noel Deyzel (physique, technique cues)", "low"),
]


# Channels whose real URL is not youtube.com/@<handle>. The keys stay the
# handle strings because they are also the corpus filenames and the
# `channel` field on every stored transcript; only the URL is overridden.
#
# Added 2026-08-26 after the search fallback below was caught adopting the
# WRONG CHANNEL in silence. @cbum, @SamSulek and @EricCressey were all
# dead handles, so each fell through to a video search that returned,
# respectively, a motivation-reupload channel called CHAMPION MENTALITY,
# Jeff Nippard, and Mike Robertson. Nothing downstream could tell the
# difference: the corpus recorded our own intended label and never what
# was actually fetched, so the mistake could only be found by reading
# video titles and noticing they belonged to someone else.
CHANNEL_URL = {
    "cbum": "https://www.youtube.com/@ChrisBumstead/videos",
    "SamSulek": "https://www.youtube.com/@sam_sulek/videos",
    "EricCressey":
        "https://www.youtube.com/channel/UCNkYtGj3dwmJB3KW4G-cRrg/videos",
}


# Words that describe what a channel is ABOUT rather than who it is. They
# have to be stripped or two unrelated baseball coaches would "match".
_GLOSS = {"the", "and", "dr", "coach", "coaching", "training", "fitness",
          "official", "channel", "performance", "strength", "team", "tv",
          "baseball", "football", "wrestling", "combat", "physique",
          "classic", "olympia", "exercise", "science", "based", "high",
          "volume", "technique", "cues", "self", "testing", "experiments",
          "recovery", "medicine", "pro", "ifbb", "natural", "lifting",
          "gym", "health", "sports", "sport", "powerlifting", "hypertrophy",
          "physiology", "nutrition", "content"}


def _tokens(text: str):
    """Identity words from the WHOLE label, gloss removed.

    The parenthetical is kept rather than discarded, because for several
    of these channels it holds the actual person: "Biolayne (Layne
    Norton)" resolves to a channel called "Dr. Layne Norton", and only the
    parenthetical connects them.
    """
    return {w for w in re.findall(r"[a-z0-9]+", text.lower())
            if len(w) > 2 and w not in _GLOSS}


def _acronym(text: str) -> str:
    """First letters of the head, digits kept whole: "3D Muscle Journey"
    becomes "3dmj", which is how Team3DMJ names itself."""
    words = [w for w in re.findall(r"[a-z0-9]+", text.split("(")[0].lower())
             if w not in _GLOSS]
    return "".join(w if w[0].isdigit() else w[0] for w in words)


def looks_like(intended: str, resolved: str) -> bool:
    """Does the channel we landed on plausibly BELONG to who we asked for?

    Deliberately generous about formatting and strict about identity.
    Team3DMJ really is 3D Muscle Journey and "Dr. Layne Norton" really is
    Biolayne, so an exact string match would throw away good data. But
    CHAMPION MENTALITY shares no identity token with Chris Bumstead, and
    Jeff Nippard shares none with Sam Sulek - which is the entire class of
    failure this exists to stop.
    """
    a, b = _tokens(intended), _tokens(resolved)
    if not a or not b:
        return False
    # A shared identity word. Covers the ordinary case and, thanks to
    # _tokens keeping the parenthetical, "Biolayne (Layne Norton)" against
    # "Dr. Layne Norton".
    if a & b:
        return True
    # One name nested in another: "layne" inside "biolayne". Long tokens
    # only - short ones collide by accident.
    if any(x in y or y in x
           for x in a if len(x) >= 5
           for y in b if len(y) >= 5):
        return True
    # An acronym the channel uses as its name. Three characters minimum,
    # because two-letter initials match far too much: "Chris Bumstead"
    # would otherwise be "cb", and cb appears inside ordinary words.
    for full, other in ((intended, b), (resolved, a)):
        acr = _acronym(full)
        if len(acr) >= 3 and any(acr in tok for tok in other):
            return True
    return False


def resolve_handle(name: str, timeout: int = 240):
    """Search for a channel by name - and REFUSE the result unless the
    channel found is plausibly the one asked for.

    The verification is the entire point. Without it this function is a
    machine for fabricating corpora: every dead handle silently becomes
    somebody else's channel, and that channel then inherits the rigor
    weight assigned to the person we thought we were reading. Returning
    None and failing loudly is strictly better than returning a stranger.
    """
    cmd = [sys.executable, "-m", "yt_dlp", "--flat-playlist", "-J",
           "--playlist-end", "1", f"ytsearch1:{name}"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        data = json.loads(proc.stdout)
        entry = (data.get("entries") or [None])[0]
        if entry and entry.get("channel_id"):
            got = entry.get("channel") or ""
            if not looks_like(name, got):
                print("  REFUSED fallback for %r: search returned %r, "
                      "which is a different channel" % (name, got), flush=True)
                return None
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
    data, err = _run_enum(CHANNEL_URL.get(
        handle, f"https://www.youtube.com/@{handle}/videos"), timeout)
    if data is None:
        url = resolve_handle(name)
        if url:
            data, err = _run_enum(url, timeout)
    elapsed = time.time() - started
    if data is None:
        return None, elapsed, err
    # The second gate, and the one that would have caught this on day one:
    # check what came back even when the URL was taken at face value, so a
    # hijacked or renamed handle cannot pass either.
    resolved = data.get("channel") or data.get("title") or ""
    if resolved and not looks_like(name, resolved):
        return None, elapsed, ("resolved to %r, which is not %r - refusing "
                               "to store it" % (resolved, name))
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
    return {"rows": rows, "resolved": resolved}, elapsed, None


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
        resolved, rows = rows["resolved"], rows["rows"]
        # Store what was ACTUALLY fetched. The old file recorded only our
        # own intended label, which is why a wrong channel was invisible.
        json.dump({"handle": handle, "name": name, "weight": weight,
                   "resolved_channel": resolved, "videos": rows},
                  open(path, "w", encoding="utf-8"), separators=(",", ":"))
        print(f"  resolved_channel={resolved!r}", flush=True)
        dated = sum(1 for r in rows if r.get("timestamp"))
        print(f"  {handle}: {len(rows)} videos ({dated} dated) in {elapsed:.0f}s",
              flush=True)
        summary.append((handle, len(rows), elapsed))

    total = sum(n for _, n, _ in summary)
    print(f"\nTOTAL: {total} videos across {len(summary)} channels")


if __name__ == "__main__":
    main()
