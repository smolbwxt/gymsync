# Deep-read brief — PERIODIZATION (phases, blocks, and the shape of a cycle)

You are a strength-coach analyst extracting the field's actual PHASE
MODEL — the knowledge an automatic coach needs to answer "what is week
3 of this block FOR, and how is it different from week 7?"

The consumer is a deterministic generator that today produces one set
of training days repeated for a whole block, with only volume and
intensity multipliers moving week to week. It needs to know whether a
named phase taxonomy is real, what distinguishes phases, and how long
each runs — or whether the field says such labels are unhelpful.

## Extract findings on

1. PHASE TAXONOMY — what phases a training cycle is actually divided
   into and what each is called (accumulation / intensification /
   realization / peaking / deload / base / hypertrophy / strength /
   taper). Are these real, distinct prescriptions or just labels? If a
   speaker rejects the taxonomy, that is a finding.
2. PHASE DURATION — how many weeks each phase runs; how long a
   mesocycle runs before a deload; how many mesocycles make a
   macrocycle.
3. PHASE MARKERS — precisely HOW a phase differs in prescription:
   weekly sets, rep ranges, %1RM or RPE, exercise selection, accessory
   dose. Numbers wherever stated.
4. DELOAD — when it is triggered (fixed schedule vs autoregulated),
   how deep the cut is (volume %, intensity %), how long it lasts.
5. PERIODIZATION MODELS — linear vs block vs daily-undulating (DUP) vs
   conjugate: what distinguishes them, evidence comparing them, and
   which suits which athlete (training age, goal, schedule).
6. TRANSITIONS AND ORDERING — must hypertrophy precede strength? What
   carries over between phases? How does a block end and the next
   begin? Does exercise selection change at a phase boundary, and if
   so which lifts change and which hold?

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Basis: cited_study only when specific
  research is described. Zero findings for off-topic is valid. Cap 8
  per video.
- Disagreement is signal: if the field splits on whether periodization
  beats consistent training, record BOTH sides.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "taxonomy|duration|markers|deload|models|transitions",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
