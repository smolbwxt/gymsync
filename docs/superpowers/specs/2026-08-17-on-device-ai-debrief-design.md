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
A pure, testable struct assembled from existing math: sets, tonnage (honest
`effectiveWeightPounds`), per-exercise e1RM deltas, PRs hit, RPE/RIR
distribution, failed sets at completed reps, rest adherence, session duration
vs `StatMath.estimatedMinutes`, and the program context (which Coach block,
week N of M, deload/taper status).

This is the foundation and the fallback: rendered as a static recap screen it
is a real feature on its own, on every device, with no AI at all.

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
