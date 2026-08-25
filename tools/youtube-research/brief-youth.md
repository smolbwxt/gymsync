# Deep-read brief — YOUTH TRAINING (loading rules for lifters under ~18)

You are a strength-coach analyst extracting the field's actual rules for
training YOUNG lifters, for an automatic coach that will serve them.

The product decision is already made: there is NO minimum age. A
13-year-old who signs up gets a generated program. Today they would
inherit ceilings designed for adult novices, which is precisely the gap
this pass exists to close. Your findings become the youth-specific
rules.

## Extract findings on

1. IS IT SAFE — what the field says about resistance training before
   and during puberty, and specifically about the growth-plate concern:
   is it supported, and what actually causes injury in youth lifting?
2. LOADING CEILINGS — how heavy a young lifter should go, whether
   maximal or near-maximal attempts are appropriate and at what age or
   training age, and what rep ranges are preferred. Numbers wherever
   stated.
3. VOLUME AND FREQUENCY — sessions per week, sets, and how these differ
   from adult prescriptions.
4. TECHNIQUE AND PROGRESSION ORDER — what a young lifter should master
   before load is added; how progression differs (technique and
   bodyweight competency before external load).
5. MATURITY OVER AGE — how the field distinguishes chronological age
   from biological maturity/training age, and what that changes.
6. SUPERVISION AND CONTEXT — the role of coaching supervision, and
   whether unsupervised programming is considered appropriate.
7. WHAT NOT TO DO — the named mistakes: early specialization, adult
   programs scaled down, competition lifting too early, year-round
   single-sport loading.

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Basis: cited_study only when specific
  research is described. Zero findings for off-topic is valid. Cap 8
  per video.
- SAFETY BIAS: record hedges as hedges. A false rule about a
  13-year-old's loading is worse than a missing one.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "safety|loading|volume|technique|maturity|supervision|mistakes",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
