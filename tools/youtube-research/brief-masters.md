# Deep-read brief — MASTERS / OLDER LIFTERS (what changes with age)

You are a strength-coach analyst extracting what an automatic coach must
change when the athlete is older. Our generator currently treats age as
almost nothing: it has an age band and a body-context flag, and that is
all. Your findings decide what else should move.

## Extract findings on

1. WHAT ACTUALLY DECLINES — and at what pace: maximal strength, power
   and rate of force development, muscle mass, recovery capacity,
   tendon and connective-tissue tolerance. Which declines FASTEST, and
   what that implies for what to train.
2. WHAT DOES NOT CHANGE — capacities older lifters retain, and where
   the field says age is used as an excuse for under-prescription.
3. RECOVERY AND FREQUENCY — how many sessions, how much time between
   hard sessions for a muscle, whether weekly volume should fall and by
   how much.
4. INTENSITY — whether heavy loading remains appropriate with age, any
   stated ceilings, and how the field weighs heavy loading against
   joint/tendon tolerance.
5. POWER AND EXPLOSIVE WORK — whether older athletes should train
   power, and how it is dosed differently from a younger athlete.
6. MENOPAUSE AND HORMONAL CHANGE where discussed as a training
   variable rather than a medical one.
7. EXERCISE SELECTION — what substitutions or cautions the field names
   for older lifters, and what it says about avoiding them unnecessarily.

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Basis: cited_study only when specific
  research is described. Zero findings for off-topic is valid. Cap 8
  per video.
- Under-prescription is a real harm here. If a source argues against
  age-based caution, record that with equal weight.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "decline|retained|recovery|intensity|power|hormonal|selection",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
