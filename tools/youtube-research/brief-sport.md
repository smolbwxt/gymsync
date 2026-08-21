# Deep-read brief — SPORT S&C PROGRAMMING

You are a strength-coach analyst answering one design question for an
automatic program generator: HOW SHOULD LIFTING BE PROGRAMMED FOR AN
ATHLETE IN A SPECIFIC SPORT (football / baseball / wrestling)? The
generator has a sport_prep goal with an in-season flag; we need the
field's actual per-sport parameters.

## Extract findings on

1. SEASONS — off-season vs in-season structure: what changes (volume,
   intensity, frequency), and what the in-season MAINTENANCE dose is.
2. SELECTION — which lifts/patterns the speaker prioritizes for this
   sport and why; what they avoid or deprioritize (and why).
3. POWER — explosive/speed work: dose, placement, progression, and how
   it trades off against heavy strength work.
4. INJURY PREVENTION — sport-specific priorities (arm care for
   throwers, neck for collision sports, etc.): what, how much, when.
5. CONDITIONING — energy-system work for the sport and how it
   coexists with lifting.
6. WEIGHT MANAGEMENT — weight-class or mass-gain guidance where the
   sport demands it.

## Rules

- Your own words only; never reproduce transcript wording.
- A usable finding is a claim with a position, not a topic mention.
- Quantities only when stated. Note the speaker's basis strictly:
  cited_study only when specific research is described.
- Zero findings for an off-topic video is valid.
- Cap 8 findings per video.

## Output

Write JSON to the output path given in your prompt:
{"findings": [{"claim": "<=35 words", "topic": "seasons|selection|power|injury_prevention|conditioning|weight_management",
  "sport": "football|baseball|wrestling|general",
  "quantities": {...} or omit, "basis": "cited_study|mechanistic|experience",
  "confidence": "strong|moderate|hedged", "video_id": "..."}],
 "disagreements": ["<=25 words", ...]}
Then return ONLY {"file": "<path>", "videos": <n>, "findings": <n>}.
