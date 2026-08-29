# Coach Backlog — 2026-08-26

Everything from today's session that is **not 100% complete**, plus a
verification brief for Fable at the end.

**Provenance.** Nothing here was written from recollection. Every entry was
re-derived against the working tree by a 13-agent adversarial verification
pass after the session's work shipped. Where the session's own belief was
wrong, the entry says so — three of them were, and one was a blocker the
session had authored itself and rated as working.

**Method for anything added later:** to claim something EXISTS, cite the
**call site**, not the definition. This repo's signature defect is complete
logic with no caller. To claim something is MISSING, show either that no
definition exists or that one does with no caller. `file:line` for both ends.

**Ranking rule:** athlete impact, with anything that *silently discards an
athlete's input* at the top. A missing feature is honest. A silent discard
lies, and a silent discard that also writes a receipt saying it worked is
worse than never having built the feature.

---

## STATUS UPDATE (later the same day)

Commit `bbbb481` closed: **P0.2** (receipts stamp what fired, via
`Inputs.appliedRuleIDs`), **P1.1** (titration wired - `runVolumeTitration`
in the wizard, before the targets read), **P1.2 both hosts** (offer sheet
and calendar land on the schedule), **P2.1** (rules list + retire +
honest confirm copy). All device-unverified; Fable's brief applies to
them in full.

## STATUS UPDATE 2 (2026-08-27)

Shipped in `d4f8227` and its ancestors, closing most of this document:
- **P2.1-adjacent / owner directives**: MY PROGRAM opens the program
  LEDGER (current block pinned, past blocks with after-action Coach
  threads, build-options frozen per enrollment from now on);
  ProgramScheduleView gained HOW THIS WAS BUILT + SINCE THE START + the
  full block payload on its ask door.
- **P3.1 CLOSED by owner decision**: "Max volume: 25 sets per day" - a
  final generator pass, mains untouched, honest trim note, tested.
- **Chat is a change surface** (owner directive): exercise SWAPS via
  RoutineEditProposal.swapToExerciseName honoured by BOTH writers;
  standing rules capturable from any thread (source "chat"), same
  consent card, shared vocabulary constant.
- **P4.1 CLOSED**: Context.isYouth deleted; tests corrected.
- **O2 CLOSED**: the KG/LBS toggle survives an anchors skip.
- **UI wave**: all five You faces wrap at full size; one door recipe on
  Coach; day-row/week-chip/hub clipping fixed; LOCKER deleted (owner).
- **Chat input unburied** (.gsHidesDock on the thread view).
- Consult closes in a chat with Coach; onboarding routes through the
  consult; goal chips reworded to plain language.

Still open: P2.2 (Home vs the program - owner decision pending), P3.2
(wizard dead code: previewSection/previewSeedPounds/view-reroll/
scheduleHint confirmed zero live callers, delete next), P3.3/P3.4 (cue
render site; lightDay weekday identity), O1 (onboarding resume), O3-O5,
P5.1 (RIR persistence - still unverified), week-schedule overrides are
display-only (needs series-link design), screenshot-suite flakes
(testCatalogBodyWeightLog, testActivityFeed), and the mid-block
condition APPLIER (Coach proposing the stored conditional swap when the
athlete reports the trigger in chat - the rules and the swap tool now
both exist, the join is what remains).

## P0 — Fixed today, verify on device

These were found by the verification pass and fixed in `9ad4c5f`/`HEAD`.
They are listed because **they have only ever been checked by a compiler**.

### P0.1 — `avoid` and `swap` levers were destroyed after being set ✅ fixed

`TrainingProfile.generatorInputs` inserted the avoided / swapped-from
exercise into `excludedExerciseIDs`, then reassigned that entire set from
the profile's own exclusions with a plain `=` forty-seven lines later.
`CoachWizardView` inserted the swapped-to exercise into
`starredExerciseIDs`, then reassigned it from starred routines. Three
levers, two assignments, all three dead.

Worse than a silent drop: `markApplied` (CoachWizardView) stamps
`applied_at` on any rule that is buildable + confirmed, so the rule
recorded itself as honoured. An athlete typing *"never overhead barbell"*
— usually injury-driven — saw Coach read it back, pressed **YES, BUILD
IT**, got overhead barbell anyway, and finished with a database row
asserting it had been applied.

**Fixed:** both sites are `formUnion` now. `RuleLeverTests.swift` is new
and asserts the END of the chain; every test in it fails against this
morning's code.

**Still to verify:** that a real athlete's avoid rule survives a real
build on device. Not covered by any test that runs in CI.

### P0.2 — `markApplied` stamps intent-is-buildable, not lever-actually-fired

Now *incidentally* truthful because P0.1 made the levers fire. It is still
the wrong predicate: it asks "was this intent buildable?" rather than "did
this rule change the program?" If a future lever is added and mis-wired,
this stamps it as honoured again. Have `generatorInputs` return the ids it
actually applied and stamp those.
**Size:** S. **Files:** `TrainingProfile.swift`, `CoachWizardView.swift:~1727`.

---

## P1 — Blockers still open

### P1.1 — The volume titration has no production caller

`VolumeTitration.decide` / `apply` / `startingPoint`,
`VolumeTargetRepository.all` / `set`, `RecoveryProbeRepository.history`
all exist and are complete. **Nothing calls `decide()`.** So
`Inputs.volumeTargets` is always empty and every athlete gets the
population band 12–25 forever — the exact thing `VolumeTitration.swift:14-22`
documents as wrong.

Second harm, and it is the one that lies: the recovery probe asks the
athlete how they recovered, session after session, and nothing ever reads
the answers into a prescription. We are collecting data and visibly
implying it is used.

**Next:** one function, invoked either after a probe is answered
(`WorkoutSessionView.swift:~4227`, right after `RecoveryProbeRepository.answer`
succeeds) or on the next generation (`CoachWizardView.readTrainingHistory`,
before the `all()` read). For each recently-trained muscle: read history →
`decide` → `VolumeTargetRepository.set`.
**Size:** M. **Owner decision:** none — the owner already specified the
policy ("prescribe middle of the road, perturb every couple of weeks").

### P1.2 — Post-build landing is wired for exactly one of three hosts

`CoachHomeView` answers `.handled` and lands on the schedule. The other
two do not:

- **`RootView` onboarding sheet** (`RootView.swift:111-117`) passes no
  `onCreated`, so it defaults to `.dismiss`. A brand-new athlete taps
  *"Let Coach build your week"*, fills every dial, presses **Build my
  program** — and the sheet just closes. Their program exists and they are
  never shown it. This is the **first** experience a new user has.
  **Fix:** ~5 lines mirroring `CoachHomeView.swift:108-111`.
- **`BlockCalendarView`** (`:255-263`) passes `.dismiss` deliberately,
  because its `enrollment`/`weeks` are `let` values captured before the
  build. Popping back shows the block they just replaced — old start date,
  old week arc. **Fix:** give it a `route` and answer `.handled`, same
  pattern.

**Size:** S each. **Both are the same five-line pattern**, already proven.

---

## P2 — High

### P2.1 — No way to see or retire a standing rule

`TrainingRulesRepository.retire(_:)` is defined (`TrainingRules.swift:232`)
and has **zero callers** — grep for "retire" across the app returns only
doc comments and unrelated features. There is no screen listing the rules
Coach holds.

This was harmless while the table was empty. As of today rules persist AND
feed Coach's chat prompt, so a throwaway remark in one consult shapes Coach
indefinitely with no way to drop it. The type's own doc comment says rows
exist "so Coach can CITE one and the athlete can RETIRE one"; half of that
is unbuilt.

**Next:** a rules list in `CoachHomeView` showing **all** of
`active()` — not the two narrow filters at `:480-481` — with each row's
status (needs confirmation / waiting on a lever / live / heard-not-
understood) and a destructive `contextMenu` calling `retire(_:)`. The
precedent is in the same file at `:609` (chat-thread delete).
**Size:** M.

### P2.2 — Home ignores the program entirely

`loadTodaysRoutine()` (`HomeView.swift:1539`, called at `:1399`) selects
`historySessions.first(where: { $0.routineID != nil })?.routineID ??
ownedRoutines.first?.id` — the last-used routine, or an arbitrary one. It
has no knowledge of the enrolled block or which day it schedules.

The athlete finishes the wizard, gets a block, per-day routines and booked
sessions — then opens Home, the app's primary surface, and finds no trace.

**Do not file this as one ticket.** Decide the surface first: either delete
the dead path (`soloSubtitle:562`, `todaysRoutine`/`todaysRoutineExercises`
`:51-52`, `loadTodaysRoutine:1539` and its call) and stop paying a
per-refresh network fetch for nothing — or commit to a today's-routine
surface and feed it from the enrollment.
**Size:** M–L. **Owner decision required:** does Home lead with today's
prescribed session, or not?

---

## P3 — Medium

### P3.1 — No per-session per-muscle volume cap

`weeklyMuscleSets` sums across days; `balanceWeeklyVolume` enforces only
the weekly band and never touches mains; `perDayBudget` is per-slot. A
bro-split hypertrophy athlete gets a chest day carrying ~17 direct chest
sets — roughly double any per-session recommendation in the corpus.

**Owner decision required.** The session's own research pass argued
*against* a naive cap: trimming 17→8 pushes the week under the
demonstrated-penalty band, and the candidate ceiling numbers are
unpublished or rat-derived. The honest options are (a) cap per session and
redistribute across days, (b) cap and accept lower weekly volume, (c) leave
it and surface the number so the athlete sees it.

### P3.2 — Dead code in `CoachWizardView` after the flow change

The inline-preview render was removed but `previewSection(_:)`,
`reroll(dayName:exerciseIndex:)`, `previewSeedPounds(...)` and
`scheduleHint` may now have zero readers. Unused private methods do not
fail a Swift build, **so CI green does not mean this is clean.** Verified
as PARTIALLY_DONE — no athlete input is discarded, this is hygiene.
**Size:** S.

### P3.3 — `cue` lever needs a render site

`RoutineExercise.notes` is carried through every constructor and rendered
**nowhere** — the only occurrence in `WorkoutSessionView` is `notes: nil`.
`RuleIntent.cue` is therefore classified and correctly reports
`isBuildable == false`. 27 instances in the grammar wave; it becomes cheap
the moment notes render.
**Size:** S (render) + S (lever).

### P3.4 — `lightDay` needs weekday identity

The generator emits *N days* with no weekday; weekdays are assigned later
at `bookTrainingDays()`. "Keep Saturdays light" needs the two halves to
talk. Architectural, not missing code.
**Size:** M.

---

## P4 — Low

### P4.1 — `ConsultProbe.Context.isYouth` is dead
Declared at `ConsultProbe.swift:77`, written only by tests, read by no
selector. The youth ceiling is delivered by a different live path, so
deleting it changes no question and no prescribed load. Delete the field
and the test parameter, or wire it. Leaving it is the pattern that produces
false confidence.

### P4.2 — Screenshots job flake
`testCatalogBodyWeightLog` failed once with *"Failed to terminate
app.gymsync.ios"* — a simulator teardown flake in an area unrelated to any
change. Passed on later runs. Watch; do not chase yet.

---

## P5 — Unverified

### P5.1 — RIR dropped at the persistence boundary ⚠️ NOT VERIFIED
The claim: `ProgramGenerator.Exercise.rirLow/rirHigh` are computed per
exercise but `RoutineExercise` has no RIR fields, so a prescription of
"2 RIR" never reaches the athlete. **The verifying agent died on an API
error.** This is the one entry in this document with no evidence behind it.
Verify before acting.

---

## P6 — Research → product

### P6.1 — The rule vocabulary covers 9% of real language
Measured against 656 instructions from 30 transcripts
(`tools/youtube-research/route_grammar.py`, roadmap at
`passes/grammar/roadmap.json`). 104 predicates have no case.

Shipped today in response: `conditional` as a `WHEN` dimension rather than
a case; buildability keyed on `(predicate, slot_type)`; `swap`, `order`,
`cap`, `floor` levers.

Still open, ranked by distinct speakers: `dose`/`prescribe` (73 instances)
— sets×reps per exercise, which would override the generator's own
prescription logic and needs a who-wins rule; `require` (4 voices);
`bookend` (3 voices, 13 instances) — start/finish a session with a
category; `prefer`, `progress`, `technique`.

**Standing caveat:** corpus frequency is a prior on GRAMMAR, not evidence
of DEMAND. Coaches prescribe; athletes ask. Ship a lever when the substrate
is nearly free — as `avoid` and `swap` were — or when the unknown queue
(`training_rules.intent = 'unknown'`) shows real athletes asking.

### P6.2 — Eric Cressey's catalog is enumerated but unfetched
1,040 videos. He is the `sport-baseball` RIGOR-4 authority and that area's
87 findings were built while his slot was occupied by Mike Robertson's
podcast (see `feedback_fail_open_resolution` in memory). Worth its own wave.

### P6.3 — 12 unincorporated corpus lessons
From the generator audit. Not re-verified today; treat as a lead list, not
a work list.

---

## P6.4 — Block catalog + after-action report (owner idea, 2026-08-27)

Owner: "It would be cool if when you clicked the my program widget, it
took you to a catalog of your previous and current blocks, and you're
able to engage in an afteraction report. Coach would be fed a prompt of
everything about that block, and if it was performed, the data from all
of the exercises from that block. Maybe it doesn't live exactly here,
but I like this idea."

The substrate is mostly present: `program_enrollments` keeps ended blocks
(`endedAt`, reason), `ProgramTemplateStore` holds generated templates,
`TrainingProfile.lastBuild` carries the reasoning, and the debrief engine
already builds computed-prompt + chat sessions per WORKOUT - a per-BLOCK
debrief is the same shape at a coarser grain. Missing: a block-history
list view, a block-level computed prompt (per-exercise aggregates across
the block's sessions), and the entry point (the My Program widget).
**Size:** L. **Owner note:** placement undecided ("maybe it doesn't live
exactly here").

## P6.5 — Onboarding routes through the consult (owner directive, 2026-08-27)

Owner: "We should route everything through the consult, then give people
the option to edit the rules of their current block, and see what their
previous blocks consisted of and what drove them there."

The offer sheet currently mounts the wizard bare (RootView.swift). It
should present the consult (which now closes in the Coach chat where
rules are discussed) and only then the wizard. Needs applyConsult's
persistence extracted from CoachHomeView so both hosts share it.
**Size:** M. First half of the vision that P6.4 completes.

## P7 — Unresolved

### P7.1 — A truncated instruction
The owner's message ending *"…and edit the"* was never completed. Ask
before assuming.

---

# Verification brief for Fable

Opus ran this session. **Double-check the work.** Below is what to attack
and, more usefully, *how it went wrong today*, so you can aim at the right
class of defect.

## The failure mode to hunt

Not bugs in the code — **confident wrong explanations.** Three times today
Opus produced a story that fit every available observation and was false:

1. *"Bumstead's catalog is Shorts under 400 words."* The enumerator had
   silently resolved `@cbum` to a motivation-reupload channel. The
   explanation fit the data perfectly and was about the wrong channel
   entirely. The owner caught it, not the pipeline.
2. *"The scheduling fix shipped, so you're on an old build."* The fix had
   shipped. It was also the wrong design, and that was the actual reason
   the complaint recurred.
3. *"`avoid` and `pairWith` are the two working levers."* Written into a
   commit message. `avoid` was dead — clobbered by an assignment 47 lines
   later — and stamped as applied in the database. An adversarial pass
   found it hours later.

The technique that catches this class is not "review the diff". For each
claim, **construct the observation that would be identical if the claim
were false.** All three above survive a normal review because the code
reads correctly at every individual line.

## Ground rules

- **CI green ≠ correct.** Everything today was verified by the Swift
  compiler and pure-logic XCTest. There are **no view tests** in this repo
  — 116 test files, zero ViewInspector, nothing instantiates a View. Every
  UI claim in this document is unverified by anything but reading.
- **Green suites hide dead features.** `StandingRulesTests` was fully
  green while its feature was dead in two independent ways, and its own
  header asserted a false premise. Before trusting a suite, check *what it
  actually exercises* — the fixture there left `intent` as `.unknown`, so
  it never touched a live lever.
- **Call sites, not definitions.** Stated above; it is the repo's
  signature defect and it recurred twice today.

## Specific things to attack, with the counter-test

1. **`RuleLeverTests` — do the tests actually fail against the old code?**
   Opus asserts every test in that file fails against this morning's
   version. Check out the parent commit, run them, confirm. If any passes,
   it is not testing what it claims and the lever may still be dead.

2. **Does `formUnion` fix it, or move it?** Verify no *other* assignment in
   `generatorInputs` clobbers a field the standing-rule loop writes.
   `supersetEveryWith`, `orderMuscleBefore`, `volumeCaps`, `volumeFloors`
   were checked; re-derive rather than trust that. The bug class is
   assignment-after-insert, and the loop is not the last thing in the
   function.

3. **The 9% coverage figure.** Derived by an agent swarm from
   agent-extracted predicates, aggregated by `aggregate_grammar.py`. The
   `order` regex in `route_grammar.py` is loose and will match "before you
   know it". Sample the raw rows in `passes/grammar/out-*.json` and judge
   whether the extraction is sound before anyone plans work around that
   number.

4. **Is `conditional` really a dimension?** The whole taxonomy restructure
   rests on it. The evidence is that agents returned it fused into other
   predicates. Read actual `verbatim` fields and check whether the fusion
   is in the language or in the agents' prompt — the brief showed
   `swap(exercise, exercise, condition)` as an example, which may have
   anchored them.

5. **The commit messages.** They are long and assert a lot. Treat each
   factual claim as a hypothesis. Particularly: "the substrate already
   existed so the lever was two lines" — verify `starredExerciseIDs`
   genuinely biases selection rather than merely being read.

6. **Anything marked ✅ in P0.** Those were fixed and never seen running.

## What Opus believes and cannot prove

- That the one-button build flow lands correctly on a device.
- That the confirmation card renders and its buttons work.
- That the reasoning card shows on `ProgramScheduleView`.
- That the drop-set and superset badges appear.
- That the on-device classifier returns anything parseable — CI builds with
  `canImport(FoundationModels) == false`, so `RuleClassifier.parse` is
  tested and the model path has **never executed anywhere**.

That last one is the largest untested surface in the change.

---

# Appendix: onboarding audit (PARTIAL - one agent of nine survived)

The onboarding audit's path-trace agent completed; the seven probe lenses
and the ranker died on a session limit. So the findings below are from a
SINGLE agent and are un-verified by an adversarial pass - trust the
file:line citations, re-derive the conclusions. The seven lenses
(dead-ends, dropped input, first-run emptiness, health gate, copy,
navigation, first workout) have NOT run; re-launch the audit workflow
when limits reset (script is preserved, resumable:
`gymsync-onboarding-audit-wf_bbe552fd-5a1.js`).

## O1 - Kill after username creation permanently skips half of onboarding [high]
`isNewSignup` is `@State` on OnboardingCoordinator, set only from the
UsernameView binding. `loadProfile()` sets `appState.currentProfile` the
moment a profile row exists, which flips RootView to MainTabView. Kill
the app after the username is created and before "Enter Gym Sync":
screens 4-7 (home gym, lift anchors, push priming, welcome) never appear
again - and screen 7 is the only setter of `pendingCoachOffer`, so the
Coach offer never fires for that athlete. Evidence:
OnboardingCoordinator.swift:15,37,72; RootView.swift:59.

## O2 - The KG/LBS choice is silently discarded [high - silent input discard]
`LiftAnchorsView.swift:191` writes `settings.unitSystem` DOWNSTREAM of the
empty-anchors early return at :180-183. An athlete flips the unit toggle,
enters no anchors, presses "SET MY STARTS" - and the button is
byte-identical to Skip: their unit choice is dropped without a word. This
is the session's signature defect class, in onboarding.

## O3 - Walkthrough state is device-local and non-resumable [medium]
Kill on page 2 of 4 -> replays from page 0 (flag written only in onDone;
`.interactiveDismissDisabled()` blocks escape). Second account on the
same device gets NO walkthrough, and `pendingCoachOffer` is consumed on
plain `onAppear` instead - a different first-run per account. Evidence:
OneShotFlags.swift:16-18,35; RootView.swift:36,92-107; WalkthroughView.swift:17,94.

## O4 - Step numbering is broken [low]
No screen says "STEP 1 OF 4"; the first numbered screen is "STEP 2 OF 4".
Three different pip grammars across four screens (UsernameView.swift:33-37
three pips two filled; HomeGymSetupView.swift:135-145 three pips all
filled; LiftAnchorsView.swift:41-50 no pips).

## O5 - No true first-run replay for QA [low]
`OneShotFlags.resetAll()` (SettingsView.swift:489) clears tips and tours
but not the profile, screening, training profile, or gym - there is no
in-app way to re-run a genuine first run, which is part of why this path
goes unexercised.


---

# STATUS UPDATE 3 (2026-08-27, field report round — `910040f`)

Owner's five-item field report, all five built in one commit. What
shipped, what it replaced, and what it leaves open.

## F1 - Consult builds directly; the wizard is out of the flow — DONE
- `CoachHomeView` door: THE CONSULT → **BUILD MY PROGRAM**; header of the
  consult screen renamed to match.
- `Models/ProgramBuilder.swift` — `CoachWizardView.create()` lifted
  verbatim (same write order: profile → snapshot → write routines →
  delete superseded → template → enroll (retires old first) → plan →
  markApplied). `VolumeTitrationRunner` lifted alongside so the titration
  still runs before the targets read. Booking REMOVED from build (the
  program page owns it now).
- `Features/Coach/ConsultEntryView.swift` — the one entry: loads
  profile/catalog/cadence, hosts the consult, `ConsultPersistence.apply`
  THEN `ProgramBuilder.build`, then `onBuilt()`. Used by CoachOfferFlow
  (rewritten to three lines), ProgramLedgerView.buildDoor,
  BlockCalendarView's PLAN THE NEXT BLOCK. CoachHomeView keeps its own
  host (route-swap semantics) and calls the same two functions.
- `CoachConsultView.onFinish` is `async`; a `.building` phase shows
  COACH IS BUILDING YOUR PROGRAM. On a failed build the consult returns
  to its last card; the host shows the error.
- Silent discard closed: `ConsultPersistence` now writes
  `answers.liftAnchors` into `UserSettings.liftAnchors` (merged). The
  probe had been parsed and dropped since it shipped.
- **Left open:** `CoachWizardView.swift` still compiles and
  `CoachHomeView.Route.wizard` still references it — nothing routes
  there. Delete the file + the enum case + the dead helpers
  (previewSection/previewSeedPounds/view-reroll/scheduleHint) in one
  sweep. Birth year: the builder passes `birthYear: nil` (the profile
  never carried it; only the wizard's text field did) — youth ceilings
  are inactive until the builder reads it from the account profile.

## F2 - Weeks scheduler at the top of the program page — DONE
- `ProgramScheduleView.arcCard` replaced: SCHEDULE YOUR WEEKS HERE, one
  line of context (WEEK n · phase/mesocycle · prescription · dates), a
  4-column grid of extruded WK n buttons whose second line reads the
  chosen days ("M W F") or SET DAYS / DELOAD. Tap → `WeekScheduleSheet`.
  Old `weekChips`/`phaseLine`/`chipFace`/`chipInk`/`phaseSpan` removed.
- `WeekScheduleSheet` gained `totalWeeks`/`startedOn`, an APPLY TO ALL n
  WEEKS toggle, fetches the block's "Coach · " routines itself, and
  **books real sessions** via `Models/WeekBooker.swift` (owner's answer:
  "Book real sessions"): clears the window's solo sessions (series-born
  via `cancelOccurrence`, plain via `deleteSession`; group sessions
  untouched), books one per weekday Monday-first cycling the routines,
  skips days already past, EventKit-syncs when the pref is on. SAME AS
  THE BLOCK now also clears the booked sessions.
- ASK COACH FOR A CHANGE is the page's one accent-faced door.
- **Left open:** `upcoming()` scope — verify it returns only the
  athlete's own sessions (organizer or invitee) so the clear step can
  never touch someone else's booking. The calendar's own sheet also books
  now (same struct) — its planned-dots layer is redundant with real
  scheduled dots and could go.

## F3 - Structured probes — DONE
- `AnchorEntryView`: rows of [lift menu over LiftAnchorMath's four slugs
  → −/weight/+ stepping one `displayIncrement` in the athlete's unit,
  stored in pounds → ×], ADD A LIFT. Records "slug=pounds" so
  `ConsultAnswers.liftAnchors` reads it unchanged.
- Cautions: `ConsultVocabulary.knownJoints` pins the seven catalog joints
  with plain details ("Deadlifts, heavy squats, bent-over rows"); catalog
  extras append. Never falls to free text again.
- Copy: anchor ask/clarifier, comfort ask/clarifier, cautions clarifier
  rewritten in plain language.

## F4 - "NONE OF THESE" over typed text — DONE
Footer label is NONE OF THESE only when `multi && !options.isEmpty &&
selection.isEmpty`. The free-text fallback on a multi probe showed it
over a typed answer.

## F5 - Adaptive complexity ladder — DONE (integer cap; float recorded)
- `ComfortLadderView`: pool = catalog minus aliases, minus lifts whose
  `jointStress` meets the joints just named (plus profile cautions),
  minus equipment not on hand. Three lifts at the current rung; tap = I
  CAN DO THAT → vanishes, next candidate at the same rung fills the slot;
  quota met → rung up; THAT'S MY LIMIT stops; at the start rung with
  nothing confirmed it steps DOWN to rung 1 once. Reports `cap=N`
  (highest fully-confirmed rung), `float=X` (cap + fraction on the rung
  above), and the accepted ids.
- `ConsultAnswers.apply`: a `cap=` token sets `derivedComplexityCap`
  directly and derives `comfortAnswers` from it (probe.complexity ≤ cap);
  the legacy checklist path is unchanged.
- **Left open (owner's "confident on a float"):** the generator still
  reads the integer cap. Next step is a soft tilt: `float`'s fraction
  biases selection toward the rung above without unlocking it. Also the
  ladder's within-rung order is catalog order — a popularity/rank sort
  would put bench before decline-close-grip at the same rung.

## F6 - Close chat voice — DONE
`CoachThinkingRow` (spinner + pulsing COACH IS THINKING) replaces the
"…" bubble; the same row is the consult's building state. Instructions
and the opener prompt now demand consequences ("you're comfortable with
technical lifts, so barbell work leads your days") and forbid the
readback. Model-path only — CI never exercises it; verify on device.

## Fable double-check for this round
1. `ProgramBuilder.build` vs the deleted-in-spirit `CoachWizardView.create`
   — diff the write ORDER line by line; any reordering is a regression.
2. `WeekBooker.book` clear step: prove `SessionRepository.upcoming()`
   cannot return another athlete's session (RLS + query).
3. Ladder: with a catalog where rung 3 has exactly one joint-safe lift,
   `capacity(3) == 1` — one accept must step up, and `cap` must be 3.
4. `ConsultAnswers.apply` with values `["cap=4","float=4.33", ...]` →
   `derivedComplexityCap == 4`, `comfortAnswers[goblet-squat] == true`.
5. The `Route.wizard` case in CoachHomeView is unreachable — confirm, then
   delete with the wizard file.

## F7 - Focus lifts as a picker; availability asked every consult — DONE (`85757c8`)
Owner on the focus-lift screen: dropdown of common compounds + catalog
door, multiple lifts; and "Coach just assumed number of days and gym
time cap".
- `FocusLiftPickerView` (15 curated compounds resolved by exact catalog
  name, fail-closed; ANY LIFT FROM THE CATALOG → `CatalogLiftSheet`,
  compounds first). Values are exercise ids on the multi-select commit.
- `ConsultAnswers.focusLifts(in:)` → `TrainingProfile.focusExerciseIDs`
  → `ProgramGenerator.Inputs.focusExerciseIDs` → `select(priority:)`:
  a focus lift wins its MAIN pattern slot before scoring (starred was a
  dead-last tiebreak — too weak for a promise). Config records "focus
  lifts".
- `days` / `session_length` always asked; `Context.knownDaysPerWeek` /
  `knownSessionMinutes` make the question cite last time's answer.
- **Left open:** a focus lift that loads a cautioned joint is still
  forced (the athlete named it; the caution sort is bypassed) — decide
  whether Coach should say so in the close. Equipment is still skipped
  when known; owner only named days + time. The reroll path
  (`select` call at ~:1628) does not pass priority — rerolling a focus
  lift's slot can replace it; probably correct (reroll = "not this one").

## F8 - Program page = calendar on top + housed routines; injury severity; routine threads — DONE (`2a561d8`, `2e4a376`, `6d6e0b0`)
- `BlockCalendarView(embedded:)` renders the block-in-time card inside
  ProgramScheduleView (one grid, no copy); ON THE CALENDAR door removed;
  `refreshToken`/`onScheduleChanged` keep grid and week buttons in step.
  Day rows housed in YOUR ROUTINE · BUILT FOR YOU.
- Injury severity (owner: "I'm not squatting or deadlifting if my hip is
  severely injured"): `cautions` asked every consult, pre-selected from
  the profile, REPLACES on answer; `injury_severity` follows (WORKING
  AROUND IT = caution/sort-last, INJURED = exclusion).
  `TrainingProfile.injuredJoints` → `Inputs.injuredJoints` →
  `usableCatalog` drops every lift labeled with the joint (upstream of
  every sort key, the focus-lift lever, the last-resort fill); the block
  notes say what is out. Digest renders it in plain words.
- Routine threads: `RoutineThreadDoor` computes prescription + rationale
  + build notes + unhonored rules + constraints as `seededContext`
  (instructions only). `send()` waits for `open()`; `reply()` waits out
  `isResponding` and retries once; instructions forbid answering with an
  announcement.
- **Left open:** healing path — a joint is un-injured only by unticking
  it in the next consult; "my hip is healed" in chat should propose the
  same (mid-block applier join). A focus lift that loads a CAUTIONED
  joint is still forced; injured now wins over it. The two dead runs
  (`85757c8` red on a fixture bug + missing tunables registry entries)
  cost nothing but time. Hypertrophy focus-areas cap of 2: see the
  owner note in the session — the generator only PREFERS focus muscles
  in selection; nothing adds sets; the probe's "I'll give them the
  volume" is unfulfilled. Decision pending.

## F9 - Focus volume lever + prescription audit (`2e51af8`)
Full report: docs/science/2026-08-28-prescription-audit.md. Focus floors
at band top / others hold band floor (UI caps three areas — prefix(2)
dropped a third pick alphabetically); WL LISS buy-out built (design was
2026-08-13, never shipped); .toFailure → targetFailure on accessories;
beginner band 8-12; titration targets clamped to band ceiling; female
rep-top re-clamped to repMax; reroll honors bandOverride; coverage dose
names dropped orphans; deload comment/code agree; maxHardDaysPerWeek
rename; GS.dayCapSets named; dead advanced RIR constants deleted.
**P5.1 RESOLVED-CONFIRMED**: RIR never persisted (3 refs total); full
persistence = v0.x migration. **P6.3 re-pointed**: the "12 lessons" list
does not exist on disk — died with the audit scratchpad; use the
deferred lists in the audit report instead. **P3.1 note**: per-session
cap stays closed (overnight decision + 25/day owner policy).
Still open from this round: specialization-duration rule (focus tilt
runs the whole block; corpus says 4-12 wks then cut), RIR trajectory
(3-4 → 0-1 across the block), cardio auto-periodization.

## F10 - Home = the block's today; bookings carry + heal routines (`832b6d7`)
Owner decisions 2026-08-28. `ProgramToday.resolveRoutine` is the one
answer to "which routine is today's" (session's own → block's next Coach
day not done this week → nil); resolving a routine-less session ATTACHES
the routine (setRoutine existed, zero callers). Home's last-used guess
deleted; LobbyView resolves+attaches on load; WeekBooker fetches the
block's routines when handed an empty list; builder reads birth year
from the account profile (E3 CLOSED).
**E1 CLOSED with receipts**: upcoming() = inner join on my participant
rows + RLS select policy; deletes gated by "organizer deletes own
scheduled sessions" (organizer_id = auth.uid() AND state='scheduled').
**P5.1 CLOSED**: RIR confirmed never persisted (audit 2026-08-28);
persistence = v0.x migration.
**Untested by CI** (repos have no seams): ProgramToday's week-wrap pick
and the lobby attach - field-verify: check into a Coach-booked session,
the prescribed day should load without picking anything.
Remaining v0 code: O1/O3 onboarding resume (review-critical), M2 gates
(blocked on ASC products).
