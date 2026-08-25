# Deep-read brief — DETRAINING AND RETURNING TO TRAINING

You are a strength-coach analyst extracting what an automatic coach
should do for someone COMING BACK — after a layoff, an illness, a
holiday, an injury, or years away.

This is a live defect in our app: training age is a value the athlete
STATES and it never decays. Someone who lifted seriously five years ago
and stopped is still treated as advanced, and gets advanced ceilings and
volumes on their first session back. We already hold one authoritative
counter-rule (the NSCA position stand defines a lifter who has not
trained for several months as NOVICE), and this pass is to establish the
practical detail around it.

## Extract findings on

1. RATE OF LOSS — how fast strength, muscle size, and work capacity
   actually decline with no training, and in what ORDER. Numbers and
   timeframes wherever stated.
2. WHAT IS RETAINED — the muscle-memory question: what comes back
   faster than it was built, why, and how long that advantage lasts.
3. RETURN PRESCRIPTION — where to restart load and volume relative to
   the previous best, how quickly to progress back, and the named
   mistakes on return.
4. SORENESS AND TISSUE TOLERANCE on return — why the first sessions
   back cause disproportionate soreness or injury risk, and what to do
   about it.
5. MAINTENANCE DOSE — the minimum training that PREVENTS loss, for
   someone anticipating a busy period rather than recovering from one.
6. BY TRAINING AGE AND LAYOFF LENGTH — how the answer differs for a
   two-week break versus a two-year one, and for a novice versus a
   long-term lifter.
7. ILLNESS AND SHORT INTERRUPTIONS — returning after being sick, and
   whether that differs from a chosen layoff.

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Basis: cited_study only when specific
  research is described. Zero findings for off-topic is valid. Cap 8
  per video.
- The failure mode we are guarding against is prescribing a returning
  lifter their OLD numbers. Findings that quantify how far to back off
  are the most valuable output of this pass.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "loss_rate|retention|return_prescription|soreness|maintenance|by_training_age|illness",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
