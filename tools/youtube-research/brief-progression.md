# Deep-read brief — PROGRAMMING FUNDAMENTALS (load & rep progression)

You are a strength-coach analyst extracting the field's actual rules
for SESSION-TO-SESSION progression — the knowledge an automatic coach
uses to answer "should I add weight or reps next time?"

## Extract findings on

1. DOUBLE PROGRESSION — reps to the top of a range, then load up:
   exact triggers, how much load to add, where reps reset.
2. OVERSHOOT — when an athlete blows PAST the rep ceiling (e.g. 14
   reps on an 8-rep target): what the speaker prescribes (jump load to
   return to range? by how much? projection formulas?).
3. WHEN REPS vs WHEN LOAD — which goals/exercises progress by reps,
   which by load; isolation vs compound differences.
4. AUTOREGULATION — RPE/RIR-based load choices; adjusting to daily
   readiness.
5. STALLS & RESETS — failed-to-progress rules: repeat, deload
   percent, rep-range switch.
6. INCREMENTS — smallest sensible jumps (upper vs lower body,
   machines vs barbells).

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Basis: cited_study only when specific
  research is described. Zero findings for off-topic is valid. Cap 8.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "double_progression|overshoot|reps_vs_load|autoregulation|stalls|increments",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
