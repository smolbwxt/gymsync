"""Route transcripts by the GRAMMAR of an instruction, not its topic.

Owner 2026-08-26, on whether to derive Coach's rule levers from the
corpus rather than guessing them: "Should we preemptively build out a
register of levers based on the transcripts that we have registered?"

WHY THIS ROUTER IS DIFFERENT FROM EVERY OTHER ONE HERE. All the previous
routers match topic vocabulary - volume, tempo, equipment, olympic. This
one matches SYNTAX: the shape of an imperative, whatever its subject.

    "never do behind-the-neck press"
    "never train legs on a Monday"

are one grammar over two different slot types. A topic router files them
in separate areas and sees two unrelated findings; a syntax router sees
one pattern with N instances. That difference is the whole point, because
what we need to learn is not what coaches believe - the corpus already
holds 2,251 findings on that - but what SHAPES a training instruction
comes in.

WHAT IT IS FOR. RuleClassifier's vocabulary (PAIR / AVOID / ORDER /
LIGHT) is currently invented, written from four example rules. If real
instructions are dominated by "cap X at N" or "swap X for Y when Z", the
enum is carved wrong at the root, every athlete typing those lands in
.unknown forever, and the unknown queue can only ever report THAT
something failed - never what shape it was. This is the only instrument
that can tell us in advance.

WHAT IT IS NOT FOR. Corpus frequency is a prior on GRAMMAR, not evidence
of DEMAND. Coaches prescribe; athletes ask. A grammar common here is a
candidate lever, not a justified one - ship it only when the substrate is
nearly free, or when real athlete requests confirm it.

Usage:  python route_grammar.py [--top 90]
"""
import argparse
import glob
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Each entry is (label, pattern). The label is the hypothesis: a rule
# grammar the classifier might need to recognise. Counting them per
# transcript is what ranks a transcript as worth an agent's attention.
GRAMMARS = [
    ("absolute",   r"\b(?:always|never)\s+(?:do|use|go|train|start|end|let|allow|skip|take)\b"),
    ("prohibition", r"\b(?:don't|do not|avoid|stop|quit)\s+\w+ing\b"),
    ("order",      r"\b\w+\s+(?:before|after)\s+(?:your\s+)?\w+\b"),
    ("pairing",    r"\b(?:pair|superset|combine|stack)\w*\s+\w+\s+(?:with|and)\b"),
    ("cap",        r"\b(?:cap|limit|keep|no more than|at most|under)\s+(?:it\s+)?(?:at|to|below|under)?\s*\d+"),
    ("floor",      r"\b(?:at least|minimum of|no less than|make sure you get)\s+\d+"),
    ("swap",       r"\b(?:swap|replace|substitute|switch)\s+\w+\s+(?:for|with|out for)\b"),
    ("bookend",    r"\b(?:start|begin|finish|end)\s+(?:your|the|every|each)?\s*\w*\s*(?:with|on)\b"),
    ("conditional", r"\bif\s+(?:you|your|it|that)\b[^.?!]{0,60}\b(?:then|just|switch|drop|stop|go)\b"),
    ("cadence",    r"\bevery\s+\d+\s*(?:weeks?|sessions?|workouts?|days?)\b"),
    ("frequency",  r"\b\d+\s*(?:x|times)\s*(?:a|per)\s*week\b"),
    ("priority",   r"\b(?:prioriti[sz]e|focus on|lead with|put)\s+\w+\s+(?:first|up front|at the start)\b"),
    ("tempo_rule", r"\b(?:control|slow|pause|hold)\s+(?:the|it|for)\s*(?:\d+|eccentric|negative|bottom|top)\b"),
    ("scope_all",  r"\b(?:every|each|all)\s+(?:set|rep|session|workout|exercise|lift)\b"),
]
COMPILED = [(label, re.compile(p, re.I)) for label, p in GRAMMARS]

# An instruction only counts if it is about training. Without this, every
# "start with" in a cooking tangent scores.
CONTEXT = re.compile(
    r"\b(set|rep|lift|exercise|movement|muscle|train(ing)?|workout|session|"
    r"program|routine|split|weight|bar|machine|cable|dumbbell|press|squat|"
    r"row|curl|deadlift|pull|push|chest|back|leg|shoulder|arm|bicep|tricep)",
    re.I)
WINDOW = 140
PASS = "grammar"
MIN_HITS = 12
BATCH_WORDS = 24_000


def grammar_hits(text: str):
    """Per-label counts, context-gated."""
    counts = {}
    for label, pat in COMPILED:
        n = 0
        for m in pat.finditer(text):
            lo = max(0, m.start() - WINDOW)
            if CONTEXT.search(text[lo:m.end() + WINDOW]):
                n += 1
        if n:
            counts[label] = n
    return counts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=90)
    ap.add_argument("--pass-name", default=PASS)
    args = ap.parse_args()

    scored, totals = [], {}
    for f in glob.glob("transcripts/*.json"):
        try:
            t = json.load(open(f, encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(t, dict) or "id" not in t:
            continue
        words = int(t.get("words", 0) or 0)
        if words < 600:
            continue
        counts = grammar_hits(t.get("text", ""))
        hits = sum(counts.values())
        if hits < MIN_HITS:
            continue
        for k, v in counts.items():
            totals[k] = totals.get(k, 0) + v
        # VARIETY over volume: a transcript exhibiting eight different
        # grammars teaches more about the taxonomy than one repeating a
        # single phrase forty times.
        variety = len(counts)
        density = hits / max(words, 1) * 1000
        scored.append((variety * 10 + density * 4, hits, variety, t))

    scored.sort(key=lambda s: -s[0])
    print("CORPUS-WIDE grammar frequency (context-gated, all transcripts):")
    for label, n in sorted(totals.items(), key=lambda kv: -kv[1]):
        print("  %-13s %6d" % (label, n))
    print("\ntranscripts scoring >= %d hits: %d" % (MIN_HITS, len(scored)))
    for sc, hits, variety, t in scored[:10]:
        print("  %6.1f  h=%-4d g=%-2d [%-14s] %s"
              % (sc, hits, variety, t.get("channel", "?")[:14],
                 (t.get("title") or "")[:56]))

    out_dir = "passes/%s" % args.pass_name
    os.makedirs(out_dir, exist_ok=True)
    for old in glob.glob("%s/b-*.json" % out_dir):
        os.remove(old)

    batch, used, n = [], 0, 0
    for _, _, _, t in scored[:args.top]:
        w = int(t.get("words", 0) or 0)
        if used + w > BATCH_WORDS and batch:
            n += 1
            json.dump(batch, open("%s/b-%02d.json" % (out_dir, n), "w",
                                  encoding="utf-8"))
            batch, used = [], 0
        batch.append({"id": t["id"], "title": t.get("title", ""),
                      "channel": t.get("channel", ""),
                      "channel_name": t.get("channel_name", t.get("channel", "")),
                      "words": w, "text": t["text"]})
        used += w
    if batch:
        n += 1
        json.dump(batch, open("%s/b-%02d.json" % (out_dir, n), "w",
                              encoding="utf-8"))
    print("\nwrote %d batches -> %s/" % (n, out_dir))


if __name__ == "__main__":
    main()
