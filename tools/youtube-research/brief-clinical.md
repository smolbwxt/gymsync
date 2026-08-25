# Deep-read brief — CLINICAL SAFETY (what should stop or change a program)

You are a strength-coach analyst extracting the field's actual SAFETY
BOUNDARIES for an automatic coach that writes training programs.

The product decision this serves is already made: when a red flag is
present, the app will DECLINE to write a program and refer the athlete
to a clinician. Your job is to establish what belongs on that list, what
merely MODIFIES a program rather than stopping it, and where the field
says coaches routinely overstep.

Note the sources: several of these channels are run by practising
physicians and physiologists. Weight their clinical claims accordingly,
and mark anything that is a personal practice preference rather than a
guideline as `experience`.

## Extract findings on

1. STOP SIGNS — symptoms or conditions that mean "do not program, see a
   clinician first": chest pain, syncope/dizziness, uncontrolled blood
   pressure, recent cardiac events, undiagnosed pain, red-flag back
   symptoms. Exact wording of the threshold wherever stated.
2. MODIFIERS, NOT STOPS — conditions that change the prescription but
   do not forbid training: managed hypertension, diabetes, arthritis,
   osteoporosis, hernia, prior injury. What specifically changes?
3. MEDICATION EFFECTS on prescription — above all anything that makes
   heart-rate-based zone prescription invalid or misleading (beta
   blockers are the known case), plus statins, blood thinners, steroids.
4. SCREENING PRACTICE — what a responsible coach asks BEFORE writing a
   program; how the field regards self-screening instruments; what a
   coach is and is not qualified to judge.
5. SCOPE OF PRACTICE — where the field draws the line between coaching
   and clinical care, and the named ways coaches get this wrong.
6. PAIN DURING TRAINING — how to distinguish training discomfort from
   a symptom that needs referral; rules for continuing versus stopping.

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Basis: cited_study only when specific
  research is described. Zero findings for off-topic is valid. Cap 8
  per video.
- SAFETY BIAS: when a source hedges, record the hedge. Do not harden a
  cautious claim into a rule — a false rule here is worse than a gap.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "stop_signs|modifiers|medications|screening|scope|pain",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
