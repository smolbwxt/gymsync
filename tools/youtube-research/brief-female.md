# Deep-read brief — FEMALE-SPECIFIC TRAINING

You are a strength-coach analyst extracting what an automatic coach
should change — or deliberately NOT change — for female athletes.

Our generator already carries a few sex deltas: greater fatigue
resistance at higher reps, shorter prescribed rest, and a modest weekly
volume scalar. Two open questions drove this pass. The owner asked
whether women should be biased toward more lower-body work, and whether
menstrual-cycle phase should influence programming. Answer both from the
evidence, including if the answer is "no" or "the evidence is too weak."

## Extract findings on

1. FATIGUE AND RECOVERY differences between sexes: recovery between
   sets and sessions, tolerance for volume, and how that should change
   rest periods or weekly sets.
2. REP RANGES AND INTENSITY — whether women respond differently across
   rep ranges or at a given percentage of maximum, and whether
   prescription should differ.
3. LOWER VERSUS UPPER BODY — relative strength, trainability, and
   whether any source argues for biasing distribution by sex. Record
   arguments AGAINST this bias with equal weight.
4. MENSTRUAL CYCLE AND PROGRAMMING — whether phase-based periodisation
   is supported, what the strongest evidence actually shows, and how
   confident the field is. Be careful: this area is known for
   overclaiming. Downgrade confidence aggressively and record hedges.
5. HORMONAL CONTRACEPTION as a training variable, if discussed.
6. PREGNANCY AND POSTPARTUM as it relates to resistance training
   programming — but note we already hold clinical guidance, so prefer
   TRAINING-side claims over medical ones.
7. WHAT SHOULD NOT DIFFER — where the field says programming for women
   is simply programming, and sex-specific advice is unnecessary or
   condescending.

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Basis: cited_study only when specific
  research is described. Zero findings for off-topic is valid. Cap 8
  per video.
- OVERCLAIM WARNING: cycle-based programming is commercially popular
  and scientifically contested. Prefer sources that discuss study
  quality, and mark anything without one as hedged.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "fatigue|reps|distribution|cycle|contraception|perinatal|no_difference",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
