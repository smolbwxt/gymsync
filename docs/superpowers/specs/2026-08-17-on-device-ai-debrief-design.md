# On-Device AI Debrief — design stub (DEFERRED)

**Status:** docketed 2026-08-17, owner-gated on Fable credits. Not started.
**Owner ask:** "pass some kind of agentic report to the built-in AI in
people's iPhones / androids in a way that doesn't switch apps... an after
action report / conversation with AI that has the full statistics of your
workout and the context and personality that we pass it."
**Port expectation:** owner expects an Android port, so the architecture is
deliberately platform-neutral below the model layer.

## The load-bearing rule

**Compute the truth in Swift; let the model narrate it.**

The on-device model (~3B params) is strong at conversation and explanation,
unreliable at arithmetic. Every number already exists deterministically —
`StatMath` (e1RM, volume), `PersonalRecordMath`, `WorkingWeight`,
`RestRecoveryMath`, the failure doctrine's `completedReps`, adherence from
`set_logs`. The model receives those as structured context and NEVER
computes. A hallucinated PR in a training app is a trust-ending bug.

## Three layers, built in this order

### 1. `WorkoutDebrief` — deterministic payload (ships to 100% of devices)

A pure, testable struct assembled from existing math. This is the foundation
and the fallback: rendered as a static recap screen it is a real feature on
its own, on every device, with no AI at all.

**Context budget — layered, not dumped.** The on-device model has a small
context window; six months of history will not fit inline and stuffing it
degrades the answer. So the payload is a compact CORE that always fits, plus
TOOLS the model calls when a question needs depth. Core answers "how did today
go"; tools answer "how does this compare to March".

#### CORE (always inline)

*What was asked of them* — the prescription, so the model can judge
compliance rather than guess it:
- focus, experience, week N of M, deload/taper flag, session-length cap
- per exercise: target sets, rep range (low/high), %1RM anchor, prescribed
  rest, `targetFailure`, `setType` (straight/drop/burnout), superset group,
  cardio zone + minutes
- `prescribedBy` (trainer) and the program/block name
- the generator's own notes for this block (they explain the intent)

*What they actually did* — per exercise and per set:
- reps, weight, RPE, `isFailed`, `completedReps` (failure doctrine: n+FAIL =
  n−1 at true RIR 0), `isPenalty`, drop-set segments, actual rest taken
- honest tonnage via `effectiveWeightPounds` (added load + body weight)
- e1RM per exercise (`StatMath`, RPE-aware, failure-authoritative)
- PRs hit this session (weighted, rep, and bodyweight-rep records)
- session duration vs `StatMath.estimatedMinutes` estimate
- HR data when a watch was connected: zones, `RestRecoveryMath` recovery drops

*Immediate trajectory* — the minimum needed to say "better or worse":
- same-routine comparison vs last performance
- per-exercise: last session's top set and e1RM direction
- `SetProgression` stall state (consecutive stalls per lift)
- week-to-date volume per muscle vs the band *(depends on the volume
  accounting layer — the highest-value defect from the corpus probe)*
- consecutive hard days (recovery ceiling proximity)
- adherence: sessions completed vs scheduled, current streak

*Who they are* — enough to personalize safely:
- experience, sex, birth year (HR bands), units preference
- available equipment (home gym / hub inventory)
- goal focus, lifting days, session-length preference
- Pro vs free (bounds what may be offered)

*Safety flags — rendered identically under every personality:*
- failed sets, RPE 10s, missed rep targets
- `joint_stress` labels on the movements performed
- recovery-ceiling and deload-due signals

#### TOOLS (called on demand)
`exerciseHistory(exercise, range)` · `volumeByMuscle(range)` ·
`prTimeline(exercise)` · `bodyWeightTrend(range)` · `programOverview()` ·
`adherence(range)`. Each returns computed facts, never raw rows — the model
must never be in a position to do arithmetic.

### 2. Conversation — Apple Foundation Models (availability-gated)
`import FoundationModels` · `LanguageModelSession` · `@Generable` for guided
generation · tool calling so the model can pull *more* facts from layer 1
rather than invent them.

- In-app: no app switch, which was the owner's requirement.
- Free (no per-token cost), private (health data stays on device — this
  SIMPLIFIES the privacy story), offline (gyms have no signal).
- Gate: Apple Intelligence-capable hardware (iPhone 15 Pro+) on iOS 26+.
  App ships `deploymentTarget: iOS 17.0`, so this is `@available`-gated with
  layer 1 as the graceful fallback.

**Personalities compose here and ONLY here.** A Coach personality (The Golden
Era / The Minimalist / …) is the session's instructions — it changes how the
same numbers are narrated, never the prescription. Zero risk to programming
safety, which stays governed by the evidence floor in `GeneratorScience`.

#### Personality resolution — getting the RIGHT one to answer

Owner 2026-08-17: "making sure that the proper personality responds is
important." The failure mode is subtle: a user generates a block under one
archetype, switches their global preference months later, and their old
program starts debriefing in a voice that never wrote it. Or worse — a human
trainer's prescription gets narrated by a bodybuilder caricature.

**Personality is persisted state on the BLOCK, not a live UI setting.** Store
it on the generated program/template row at creation time, exactly as
`prescribedBy` is stored on a routine. What generated the plan is what
debriefs the plan.

Resolution precedence, first match wins:

1. **Trainer-prescribed routine → trainer-deference mode.** No archetype. The
   voice is a neutral assistant that *references* the trainer ("Mark
   prescribed 4×6 here") and never impersonates them, never contradicts their
   prescription, and never coaches against it. A real human's professional
   judgment is not a costume for a language model.
2. **Block's stored personality** — the archetype that generated this program.
3. **User's default personality preference** — for freeform/unprogrammed
   sessions with no block context.
4. **Neutral house voice** — the fallback, and the only voice on devices
   without on-device model support.

**Rails that hold under every personality:**
- Numbers, PRs, and safety flags render identically. Tone may change; a
  failed set, a joint-stress flag, or a recovery-ceiling warning may not be
  softened, dramatized, or omitted by a persona.
- No persona may encourage training through a safety flag. "The Mass Monster"
  is a narration style, not a licence to push someone into injury.
- Archetypes only — never real people's names or likenesses (publicity
  rights; see the personalities discussion in the restructure ledger).
- Personality is recorded on the debrief so the UI can label who is speaking.

### 3. System surface — App Intents + `AppEntity`
Publish workouts, exercises, and PRs as entities so Siri/Spotlight can answer
"how did my bench go this month?" without opening the app. Different
mechanism from layer 2 (system-wide vs in-app), and the same entities feed
widgets and the Watch app.

## Android port

Equivalent stack: ML Kit GenAI APIs over Gemini Nano via AICore for layer 2;
App Actions / App Shortcuts for layer 3. Less mature and more device-
fragmented than Apple's. Because layer 1 is pure Swift *logic* (not platform
API), it's the part that ports conceptually intact — keep it free of UIKit /
SwiftUI / FoundationModels imports so the port is a translation, not a
rewrite.

## Open questions for build time

- Does the debrief live in `SessionRecapView` or a new surface?
- Conversation persistence — one-shot debrief, or a thread per session?
- Does the trainer arm get client debriefs (scope-gated) too?
