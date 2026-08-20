# Training Profile & Conversational Onboarding — design

**Owner directive (2026-08-20, refining 08-17):** generation stays
deterministic. The onboarding conversation pulls, orders, and weights the
key parameters — goal ordering (hypertrophy over conditioning over power),
split preference (bro / upper-lower / PPL), absolute no-gos ("injury: no
clean and jerk") — pre-populating however many fields are necessary for a
personalized, specific program. The chosen coach personality influences the
weighting.

**Context it fixes (verified 08-17/08-20):** the generator's entire goal
vocabulary is one enum (strength, hypertrophy, weightLoss, conditioning);
the split ladder is hardcoded by day count, with weight-loss/conditioning
forced full-body at ANY day count; a bro split is not representable. One
frequency finding (~2x/muscle/week) was allowed to collapse the design
space — full-body is one solution to that constraint, not the constraint.

---

## 1. The unification

**Personality = profile prior + voice. Conversation = delta. Profile =
truth. Generator = the only thing that prescribes.**

- A persona IS a pre-filled TrainingProfile plus a narration voice. Golden
  Era pick -> split: bro, goals: hypertrophy >> strength, rep_appetite:
  8-15, volume: high. Powerlifting purist -> a different vector.
- This kills the cold-start interrogation (a persona pick answers ~12 of
  ~20 questions), makes personalities REAL programming differences rather
  than cosmetic voices, and avoids impersonation entirely (opinions live in
  a data row we author — archetypes only, never real people's names).
- Persona parameter sets are DERIVED FROM THE CORPUS: 3,228 transcripts of
  named educators' philosophies (tools/youtube-research), per-channel
  consensus rules intact.
- The model never prescribes. It elicits and translates. Every rep, set,
  load, and exercise comes from the deterministic generator reading the
  profile.

## 2. TrainingProfile schema (draft)

```
TrainingProfile
+- identity
|   +- training_age: novice | intermediate | advanced
|   +- age_band: <18 | 18-39 | 40-54 | 55+
|   +- persona: slug            # the PRIOR that seeded this profile
+- goals                         # RANKED list -> normalized weights
|   +- ordering over: hypertrophy, max_strength, power_rfd,
|       conditioning, fat_loss, bone_density, mobility,
|       sport_prep(sport, season), general_health
+- preferences                   # persona-seeded, athlete-overridable
|   +- split: full_body | upper_lower | ppl | bro | hybrid | auto
|   +- days_per_week, session_length_minutes
|   +- rep_appetite: heavy_low | moderate | high_rep_pump
|   +- style_bias: barbell / dumbbell / machine / bodyweight lean
|   +- intensity_appetite: conservative | standard | aggressive
+- hard_constraints              # ABSOLUTE — see section 4
|   +- excluded_exercises: [{slug, reason_class}]
|   +- excluded_patterns:  [{pattern, reason_class}]   # e.g. overhead_press
|   +- caution_joints: [joint]   # deprioritize joint_stress:<joint>
|   +- equipment_available
+- provenance (PER FIELD): persona_default | stated | inferred | confirmed
```

Storage: a training_profiles row per user (jsonb payload + version),
visible and editable in the UI. A black-box profile is worse than a dial.

## 3. Three field classes, three override semantics

| Class | Elicited as | Who can override | Science pushback |
|---|---|---|---|
| Ranked goals | an ORDERING (people can rank; nobody can emit "0.45") | athlete | via drift evidence only |
| Preferences | persona default, adjusted in conversation | athlete | ONCE, with a citation, then recorded and respected |
| Hard constraints | stated facts (injuries, no-gos, equipment) | athlete only | NEVER |

Pushback protocol (owner: "push back when it needs it, back it up with
science"): fires when a preference conflicts with a science gate (bro split
vs 2x frequency; aggressive progression vs novice). Coach states the
evidence once, offers a concrete compromise ("hybrid: each bodypart gets a
second lighter touch"), records the decision with provenance=confirmed, and
never re-litigates inside the block. Adherence beats optimality.

## 4. Hard-constraint propagation

An exclusion carries a reason class; reason determines blast radius:

- injury(joint) -> exclude the movement FAMILY loading that joint pattern,
  plus deprioritize catalog joint_stress:<joint> labels.
- dislike/skill -> exclude the single lift.
- equipment -> filter, as today.

**The substitution graph fills every hole** (exercise_substitutions, 187
provenance-graded edges in prod, injury_pain/equipment triggers): "no
barbell squats" must never silently mean "no quad training." Selection
treats an excluded anchor as missing and takes the best qualifying edge.

## 5. No dead knobs — the field-derivation rule

Audit lesson (08-17 spec section 2): we encode science and skip the
machinery that spends it. Therefore: **a profile field exists only if the
generator reads it and flipping it changes the output program, provably, in
a test.** Fields derive BACKWARDS from generator decision points:

| Generator decision | Governing fields |
|---|---|
| split selection | split preference, days/week |
| exercise scoring | goal weights, style_bias, exclusions, caution_joints |
| sets per slot | volume appetite (goals x training_age) |
| rep bands | rep_appetite, goal weights |
| wave and progression | intensity_appetite, training_age |
| conditioning placement | conditioning weight, session length |

~15-25 fields fall out — derived, not chosen. "20" is not a target.

## 6. What the generator must learn (real gaps, verified)

1. **Split as an input.** Ladder is hardcoded by day count; add bro-split
   day patterns; frequency science becomes the one-time pushback, not a
   wall.
2. **Goal weights blending.** Single-enum focus -> weighted vector across
   the section-2 goal set (power_rfd for the 16-year-old footballer and
   bone_density/cardio_health for the 50-year-old first-timer are
   UNREPRESENTABLE today).
3. **Exclusions at selection time** plus graph-backed replacement
   (section 4).
4. **Persona parameter sets** from corpus philosophies (PRO feature).

## 7. Extraction contract (on-device AI, per the debrief spec's division)

- Conversation -> @Generable struct mirroring section 2. This is
  CLASSIFICATION, not prescription — squarely inside a ~3B model's
  competence.
- Swift validates every extracted value against the schema; unparseable ->
  ask directly.
- **Confirmation card** before commit: "Here's what I heard: hypertrophy
  first, nothing overhead, 45-minute sessions — right?"
- The FORM path is canonical and ships first; the conversation is the
  pleasant skin. Devices without Apple Intelligence lose nothing but charm.
- Layer 1 (profile schema + generator consumption) stays free of platform
  imports — Android port uses ML Kit GenAI over the same schema.

## 8. Evolution (with the 08-17 longitudinal spec)

- After-action debriefs adjust weights SLOWLY (adherence, RPE distribution,
  skipped lifts, cut sessions are evidence about the athlete).
- Drift detection: behavior diverging from profile -> a PROBING QUESTION at
  ~2-week cadence (owner's number), triggered by drift, not the calendar.
- Provenance gates challenges: persona_default fields challengeable any
  time; stated fields only with accumulated evidence; hard constraints
  never auto-challenged (injuries heal on the athlete's say-so, not ours).
- Block-to-block carryover per longitudinal spec 3e.

## 9. Sequencing

1. TrainingProfile schema + deterministic FORM path (extend the wizard)
2. Generator consumes it: goal weights, split input, exclusions (6.1-6.3)
   — each field lands with its flip-the-field test (section 5)
3. Persona priors (corpus-derived parameter sets) seeding the form
4. Conversational skin over the same schema (section 7)
5. Evolution loops (section 8), joined with longitudinal 3e

Steps 1-2 are the value; 3-4 are the charm; 5 is the relationship.
