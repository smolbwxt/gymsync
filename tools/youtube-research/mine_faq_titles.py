"""Mine question-form video titles into FAQ themes.

Owner docket 2026-08-21 ("title-mining FAQ artifact"): the educational
corpus answers the questions athletes actually ask - the titles ARE the
field's FAQ. Channel spread ranks above raw count: a question 15
channels each answer is the field's FAQ; one channel's obsession is not.

Consumers: HelpSheet FAQ content; what Coach should PROACTIVELY explain.
Output: docs/science/title-faq-themes.md

Usage: python mine_faq_titles.py
"""
import collections
import glob
import json
import re

QUESTION = re.compile(r"^(how|should|why|what|when|is|are|do|does|can|will|which|who)\b|[?]", re.I)
THEMES = [
    ("how many sets|sets per week|volume for|junk volume|more sets", "training volume (sets/week)"),
    ("how often|frequency|times a week|once a week|twice", "training frequency"),
    ("to failure|rir|reps in reserve|how hard|intensity", "proximity to failure / effort"),
    ("rep range|how many reps|high reps|low reps", "rep ranges"),
    ("rest between|rest period|how long.*rest", "rest periods"),
    ("protein|creatine|supplement|pre.?workout|caffeine", "nutrition & supplements"),
    ("lose fat|fat loss|cut|calorie|deficit|weight loss", "fat loss"),
    ("build muscle|muscle growth|hypertrophy|bigger", "muscle growth"),
    (r"stronger|strength|1rm|powerlifting|pr\b", "strength"),
    ("full body|split|ppl|upper lower|bro split", "training splits"),
    ("cardio|conditioning|zone 2|running", "cardio & lifting"),
    ("deload|overtraining|recovery|sore|doms|sleep", "recovery & fatigue"),
    ("form|technique|mistake|wrong|cheat", "technique & mistakes"),
    ("stretch|mobility|warm.?up|flexib", "warmup & mobility"),
    ("pain|injur|hurt|knee|shoulder|back pain", "pain & injury"),
    (r"best exercise|better than|vs\.?\b|ranked|tier", "exercise comparisons"),
    ("beginner|novice|first|start", "beginners"),
    ("plateau|stuck|not growing|gains stopped", "plateaus"),
    ("age|older|over 40|senior", "training with age"),
    ("science|study|research|meta", "evidence explainers"),
]


def main():
    themes = [(re.compile(pat, re.I), label) for pat, label in THEMES]
    counts = collections.Counter()
    spread = collections.defaultdict(set)
    examples = collections.defaultdict(list)
    total = 0
    for f in glob.glob("corpus/*.json"):
        data = json.load(open(f, encoding="utf-8"))
        for v in data["videos"]:
            t = (v.get("title") or "").strip()
            if not t or not QUESTION.search(t):
                continue
            total += 1
            for rx, label in themes:
                if rx.search(t):
                    counts[label] += 1
                    spread[label].add(data["handle"])
                    if len(examples[label]) < 4:
                        examples[label].append((t, data["handle"]))
                    break
    rows = sorted(counts.items(), key=lambda kv: (-len(spread[kv[0]]), -kv[1]))
    out = ["# Corpus title-mined FAQ themes", "",
           "What the field spends its breath answering, mined from question-form",
           "video titles across the 23-channel research corpus (enumerate.py",
           "export). Channel spread ranks above raw count: a question 15",
           "channels each answer is the field's FAQ; one channel's obsession is",
           "not. Feeds two consumers: HelpSheet FAQ content, and what Coach",
           "should PROACTIVELY explain (advisory notes, debrief talking points).",
           "", f"Question-form titles found: {total}", "",
           "| Theme | Channels | Titles | Example titles |", "|---|---|---|---|"]
    for label, n in rows:
        ex = "; ".join(t.replace("|", "-") for t, _ in examples[label][:2])
        out.append(f"| {label} | {len(spread[label])} | {n} | {ex} |")
    with open("../../docs/science/title-faq-themes.md", "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print(f"{total} question titles -> {len(rows)} themes -> docs/science/title-faq-themes.md")


if __name__ == "__main__":
    main()
