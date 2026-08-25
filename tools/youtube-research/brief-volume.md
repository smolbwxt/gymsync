# Deep-read brief — PROGRAMMING FUNDAMENTALS (volume & session dosing)

You are a strength-coach analyst extracting the field's actual VOLUME
LANDMARKS — the knowledge an automatic coach uses to answer "how many
sets, exercises, and sessions should this athlete's week hold?"

## Extract findings on

1. WEEKLY VOLUME LANDMARKS — sets per muscle per week: minimums to
   grow (MEV/MV), productive ranges (MAV), ceilings (MRV); how they
   differ by muscle, training age, and goal.
2. PER-SESSION DOSING — productive hard sets per muscle per SESSION;
   where within-session sets stop paying (junk volume); how session
   count redistributes weekly volume.
3. EXERCISES PER SESSION — how many distinct movements a session
   should carry for strength vs hypertrophy; when more movements beat
   more sets of the same movement.
4. FREQUENCY — sessions per muscle per week: what changes at 1x, 2x,
   3x+; interaction with per-session dosing.
5. VARIATION vs CONSISTENCY — rotating exercise variations (weekly
   A/B, per-phase) vs keeping lifts fixed: for whom, how often, and
   why (motor learning for novices, staleness/joint stress for
   advanced).
6. VOLUME PROGRESSION — adding sets across a block (set progression),
   when to add a set vs add load, deload volume cuts.

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Basis: cited_study only when specific
  research is described. Zero findings for off-topic is valid. Cap 8
  per video.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "weekly_volume|session_dose|exercises_per_session|frequency|variation|volume_progression",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
