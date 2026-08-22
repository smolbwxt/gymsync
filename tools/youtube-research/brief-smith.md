# Deep-read brief — SMITH MACHINE

You are a strength-coach analyst answering one design question for an
automatic program generator: HOW SHOULD THE SMITH MACHINE BE TREATED IN
SELECTION? The generator currently treats it as generic "machine"
equipment (accessory-friendly, demoted for mains). The owner suspects
Smith machines are underrated, including for strength work.

## Extract findings on

1. HYPERTROPHY — Smith vs free-bar for muscle growth: what does the
   speaker claim, on what evidence?
2. STRENGTH — does Smith work build strength that transfers to free
   lifts / real-world strength? Stabilizer arguments pro and con.
3. USE CASES — when the speaker actively PREFERS the Smith (safety to
   failure, no spotter, fatigue, injury, isolation of a target muscle,
   specific exercises where it shines).
4. CAUTIONS — when it's the wrong tool; bar-path or joint concerns;
   which exercises fit it poorly.
5. SPECIFIC EXERCISES — which Smith variations the speaker rates
   highly or poorly, and why.

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Basis strictly: cited_study only when
  specific research is described.
- Zero findings for an off-topic video is valid. Cap 8 per video.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "hypertrophy|strength|use_cases|cautions|exercises",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
