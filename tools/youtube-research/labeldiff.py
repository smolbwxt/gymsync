"""Diff mined per-exercise judgments against the labels we actually ship.

Our 1,305 catalog labels were authored by a swarm reasoning from first
principles. This finds where practitioners who cite research disagree.

Consensus is counted PER CHANNEL, never per claim: RP alone is 36% of the
corpus, so counting raw assertions would let one prolific educator become
"the field." A disagreement backed by one channel is flagged single-source
and does not qualify as a correction.

Usage:  python labeldiff.py --claims <dir> [--min-channels 2]
"""
import argparse
import glob
import json
import os
import subprocess
import sys
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from graph import tokens, resolve, CATALOG  # noqa: E402  (shared resolver)

# Two Windows gotchas here: the extensionless npm shim is not executable from
# subprocess (need the .cmd wrapper), and Windows resolves the executable
# against the PROCESS cwd rather than the `cwd=` argument — so this must be
# absolute.
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    "..", ".."))
SUPABASE = os.path.join(
    REPO, "node_modules", ".bin",
    "supabase.cmd" if os.name == "nt" else "supabase")


def db_labels():
    """Current shipped labels, straight from prod."""
    sql = ("SELECT slug, name, lengthened_bias, unilateral, complexity, "
           "joint_stress, (focus_scores->>'hypertrophy')::int AS hyp "
           "FROM public.exercises")
    proc = subprocess.run(
        [SUPABASE, "db", "query", "--linked", "--output-format", "json", sql],
        capture_output=True, text=True, cwd=REPO, timeout=300)
    raw = proc.stdout
    rows = json.loads(raw[raw.find("["):raw.rfind("]") + 1])
    return {r["slug"]: r for r in rows}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--claims", required=True)
    ap.add_argument("--min-channels", type=int, default=2)
    args = ap.parse_args()

    raw = open(CATALOG, encoding="utf-8").read()
    catalog = json.loads(raw[raw.find("["):raw.rfind("]") + 1])
    catalog_tokens = {}
    for ex in catalog:
        h, s = tokens(ex["name"])
        catalog_tokens[ex["slug"]] = (set(h), set(s), ex["name"])

    judgments = []
    for f in glob.glob(os.path.join(args.claims, "*.json")):
        judgments += json.load(open(f, encoding="utf-8")).get("judgments", [])
    print(f"judgments in: {len(judgments)}")

    # video_id -> channel, so consensus can be counted per channel.
    vid_channel = {}
    for f in glob.glob("passes/per_exercise/*.json"):
        for rec in json.load(open(f, encoding="utf-8")):
            vid_channel[rec["id"]] = rec["channel"]

    # slug -> flag -> set(channels)
    flags = defaultdict(lambda: defaultdict(set))
    resolved_names = {}
    unresolved = 0
    for j in judgments:
        hit, _ = resolve(j.get("exercise", ""), catalog_tokens)
        if not hit:
            unresolved += 1
            continue
        slug, name = hit
        resolved_names[slug] = name
        ch = vid_channel.get(j.get("video_id"), "unknown")
        for fl in (j.get("attribute_flags") or []):
            flags[slug][fl].add(ch)

    labels = db_labels()
    print(f"resolved to {len(resolved_names)} catalog exercises "
          f"({unresolved} unresolved)\n")

    corrections, single = [], []
    for slug, fl in flags.items():
        row = labels.get(slug)
        if not row:
            continue
        for flag, channels in fl.items():
            claim = None
            if flag == "lengthened_bias" and not row["lengthened_bias"]:
                claim = ("lengthened_bias", "false", "true")
            elif flag == "unilateral" and not row["unilateral"]:
                claim = ("unilateral", "false", "true")
            elif flag == "high_skill" and (row["complexity"] or 0) < 4:
                claim = ("complexity", str(row["complexity"]), ">=4")
            elif flag.startswith("joint_stress:"):
                joint = flag.split(":", 1)[1]
                if joint not in (row["joint_stress"] or []):
                    claim = ("joint_stress", str(row["joint_stress"]),
                             f"+{joint}")
            if not claim:
                continue
            entry = (len(channels), resolved_names[slug], claim[0],
                     claim[1], claim[2], sorted(channels))
            (corrections if len(channels) >= args.min_channels
             else single).append(entry)

    corrections.sort(key=lambda e: -e[0])
    print(f"=== CORRECTIONS ({args.min_channels}+ independent channels): "
          f"{len(corrections)} ===")
    for n, name, field, cur, want, chans in corrections[:25]:
        print(f"  {n}ch  {name[:30]:<32}{field:<16}{cur:>8} -> {want:<8}"
              f"{','.join(c[:12] for c in chans)}")
    print(f"\n=== SINGLE-SOURCE (informational, not applied): {len(single)} ===")
    for n, name, field, cur, want, chans in single[:12]:
        print(f"  1ch  {name[:30]:<32}{field:<16}{cur:>8} -> {want:<8}{chans[0][:16]}")

    json.dump([{"channels": n, "exercise": name, "field": f, "current": c,
                "proposed": w, "sources": ch}
               for n, name, f, c, w, ch in corrections],
              open("label_corrections.json", "w", encoding="utf-8"), indent=1)
    print(f"\nwrote label_corrections.json ({len(corrections)} entries)")


if __name__ == "__main__":
    main()
