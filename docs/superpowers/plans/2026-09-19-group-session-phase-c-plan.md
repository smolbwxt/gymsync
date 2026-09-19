# The ad-hoc workout adopts the one session body — Phase C1 — implementation plan

**For agentic workers.** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Every task below is
one subagent, one commit, one review. Do not batch tasks; do not start a Stream S task before the Stream D
gate it names has been applied to the live project. **The intended model is written beside every task** and
in the sequencing table (token addendum, 2026-09-13).

**Goal.** Phase B gave the crew session one body that moves three ways. Phase C makes the **ad-hoc solo
workout the same session** — same row, same state machine, same warm-up screen, same live body — so that
`Features/Workout/WorkoutSessionView.swift` (4,443 lines) and `Features/Sessions/WarmUpPhaseView.swift`
(416 lines) can be deleted with nothing lost. **C1, this plan, is the half that makes an ad-hoc solo
session RUN in the one body**: a durable, slot-keyed swap layer; set attribution by routine slot; an
ad-hoc start that creates a session the router already accepts; the entry points re-pointed; the solo
furniture proved. **C2, outlined at the end, is the half that moves the remaining capabilities and
deletes both files.** The old view still ships at the end of C1 — nothing is deleted until C2 — and that
is deliberate: the owner trains on this screen today.

**Architecture.** Five moves, in this order of dependence:

1. **The swap layer becomes durable, and it becomes slot-keyed.** This is a **prerequisite**, not a
   nicety: the 2026-09-18 root cause (`.superpowers/sdd/2026-09-19-group-session-phase-c/debug-swap-state.md`)
   showed the swap layer is `@State` in **both** bodies and that the progress cursor is derived per
   `exerciseID` against the **original** routine — so sets logged under a substitute vanish from the
   cursor and the session double-logs. Routing solo through the one body inherits that bug rather than
   fixing it. C1's S1 gives the layer two durable homes (`session_participants.self_swaps` for my own,
   `sessions.squad_swaps` for the crew's agreed one) and re-keys `RoutineLayering.apply` from
   `exerciseID` to the **routine-exercise row id** — the SLOT — which also fixes the known flaw that a
   routine naming one lift twice swaps both of its slots at once.
2. **A logged set records the slot it was logged for.** `set_logs.routine_exercise_id uuid NULL`. It is
   what makes a swap mid-exercise honest, a twice-named lift countable, and the recap's volume immune to
   the double count. **No backfill**: new sets only, with the per-`exerciseID` fallback preserved for
   every row written before the column existed.
3. **An ad-hoc start stops being a bypass.** `SessionRepository.startSolo` already inserts a row that
   `SessionRouter.route` reads correctly — `state: "in_progress"` with `lifting_started_at IS NULL` is
   **exactly** `WarmUpGate.isWarmingUp`, i.e. `.warmUp` (`SessionEntryView.swift:39-42`). What it does
   not do is choose a style honestly (`sessions.style` defaults to `'rounds'`,
   `20260913000101:25-26`) — a solo lifter must never see a rotation strip or a round wait. S3 makes an
   ad-hoc solo session **`.freestyle`**, which is the style whose `LogFollowUp.calls(for:)` row calls
   neither `advanceTurn` nor `advance_round`, so the round engine is never walked for a one-person
   roster. Check-in stays what `startSolo` already writes — `check_in_state: "ready"` at insert — and
   `checkin_window_guard` fails open on `scheduled_for IS NULL` (verified, `20260715000003:37-41`), so an
   ad-hoc lifter never waits on a window. Spec §2's "solo checks in and warms up" is satisfied at the
   moment of the tap.
4. **The entry points re-point, and the presentation stops orphaning the session.** Four production call
   sites construct `WorkoutSessionView`; all four become `SessionEntryView(session:)`, the app's one
   entry point. The solo session stops being a push inside a dismissible sheet
   (`HomeView.swift:280-282`, `:2207-2218`, `RootView.swift:431-433`) — `.fullScreenCover` with an
   explicit MINIMISE control, and the SESSION LIVE pill as the deliberate way back.
5. **The solo shape of the one body is proved, not assumed.** Three hermetic catalog frames photograph a
   one-participant freestyle session, its personal rest window and its swap sheet, so the owner can see
   an ad-hoc workout in the one body before anything is deleted.

**Tech stack.** Swift 6 / SwiftUI (iOS 17 target), Supabase Postgres + PostgREST + RLS, pgTAP, XCTest +
XCUITest, Deno (edge functions), GitHub Actions (`ios.yml`, `backend.yml`), XcodeGen
(`GymSyncApp/project.yml` — `sources:` is a directory glob, so no project.yml edit is needed for any file
added or deleted under `Features/`).

**Spec (the authority):** `docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md`.
**Sections §2 (solo: check in, warm up, lift), §3.4 (the two change modes), §4 (the suggestion
principle) and §8 bind this plan.** Gate documents: the design language
(`docs/superpowers/specs/2026-09-05-design-language.md`) and the goal-first spec
(`docs/superpowers/specs/2026-09-07-goal-first-programming-design.md`). Round artefacts, **all of whose
line numbers were re-verified against the base `d74d95a` on 2026-09-18 and corrected where they were
stale**: the Phase C context map (`.superpowers/sdd/2026-09-19-group-session-phase-c/context-map.md` —
corrections in "Spec corrections" below), the root-cause report (`…/debug-swap-state.md` — the binding
input, with two corrections below), the functional audit (`…/functional-gaps.md`), the hotfix dispatch
(`…/dispatch-hotfix-solo-swap.md`), the Phase B2 plan and the owner-decisions plan (the shape this plan
copies and the source of Global Constraints 1-21). Format exemplar: the owner-decisions plan.

**Owner directive (2026-09-18), binding on this plan.** **Function before design.** *"Let's get phase 3
complete, and come back to perfecting the design when the app is functionally complete."* So: **no design
rounds, no variation frames, no owner-pick gates in this plan.** Capabilities that move into the one body
keep the UI they have today, restated on the existing design language only where they must be. The later
design pass owns the your-turn logging screen, the You page, the Trainer page and the PR celebration —
frames 151 and 152 stay live and are **not** this plan's to retire. Heart rate's place on the logging
screen is design backlog: **no task here may make that slot harder to repurpose**, and no task here
repurposes it.

---

## Base branch — read this first

**This plan is committed on `feat/group-session-phase-c`, which already exists at `d74d95a`**
(`feat/owner-decisions-2026-09-18`, PR #76 — master + the owner-decisions round, which merges as a merge
commit shortly, so this base lands on master unchanged). The worktree
`G:/Projects/GymSync-wt/wt-phase-c-release` already exists on that branch with no upstream; a previous
planner created both and nothing else. **Do not create a new branch or worktree, and do not switch any
other checkout.** Verified on 2026-09-18 in that worktree at `d74d95a`:

```
git log --oneline -1                                                        # d74d95a
grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1                        # FLOOR=135  (line 462)
python -c "import json;d=json.load(open('docs/design/frame-map.json'));print(len(d), max(v['frame'] for v in d.values()))"
                                                                            # 92 154
grep -c '^    case ' GymSyncApp/GymSync/App/CatalogHostView.swift           # 113
wc -l GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift          # 4443
wc -l GymSyncApp/GymSync/Features/Sessions/Live/SessionLiveView.swift       # 5501
```

| | Stream D and Stream S, from `d74d95a` |
|---|---|
| base | `feat/group-session-phase-c` @ `d74d95a` (= `feat/owner-decisions-2026-09-18`, PR #76) |
| `FLOOR` in `ios.yml:462` | **135** (includes the two rejected celebration ids 151/152 — **they stay**) |
| frames taken | 1-154, zero duplicates |
| next free frames | **155, 156, 157** — a retired number is never reused |
| `CatalogScreen` cases | 113 |
| `CatalogScreenTests` ids | 113 (set-equal to `allCases`) |
| **real `captureCatalog("…")` calls** | **111** — `grep -c 'captureCatalog('` prints 114 because it also counts the function's own definition (`ScreenshotTests.swift:543`) and two comments (`:500`, `:506`). |
| `solo-live-set` | id **and** capture exist (`CatalogHostView.swift:79`, `:276`, `:1939-1954`; `ScreenshotTests.swift:649`; `CatalogScreenTests.swift:59`), frame **66** in `frame-map.json`. **Retires in C2, with the view it photographs — not in C1.** |
| `sessions.style` | present, `NOT NULL DEFAULT 'rounds'`, CHECK in (`rounds`,`freestyle`,`together`) |
| `sessions.lifting_started_at` | present (`20260803000004`), NULL = warming up |
| `sessions.venue_id` / `session_participants.todays_scale` | present, **applied live** `20260918191614` |
| `private.session_round_guard` / `session_venue_insert_guard` | present, applied `20260918193441` / `20260918195107` |
| `set_logs.routine_exercise_id` | **does not exist** |
| `session_participants.self_swaps` / `sessions.squad_swaps` | **do not exist** |
| `WarmUpPhaseView` call sites | **exactly one**, `WorkoutSessionView.swift:1292` — see spec correction 1 |
| `LiveSessionTimerStore` | present (48 lines), **memory-only** — see spec correction 2 |
| pgTAP fixture namespaces taken | `01xx`-`13xx`, `15xx`, `16xx`. **This plan takes `17xx` (D2) and `18xx` (D4).** |
| in flight beside this plan | `fix/solo-swap-rest-durability` (the hotfix, off the same base). **Plan on it having merged**; S1 and S3 delete its stopgap — see decision 2. |

---

## Global Constraints

These bind **every** task. A task that breaks one says so in its commit body, and why. Constraints 1-21
are the owner-decisions round's, carried forward verbatim where they are still true, with the changes
marked **[C]**.

1. **One release branch, `feat/group-session-phase-c`, and this plan is its first commit.** The branch and
   its worktree (`G:/Projects/GymSync-wt/wt-phase-c-release`) already exist at `d74d95a`; commit this
   file and push with `-u`. Every task below lands on that branch. One PR at the end (I3).

2. **Two streams, and only because their files are disjoint by path.**
   - **Stream D** touches `supabase/**` and `scripts/**` and nothing else.
   - **Stream S** touches `GymSyncApp/**`, `docs/design/**` and `.github/workflows/ios.yml` and nothing
     else.

   **[C] S1-S6 run sequentially, in number order** — S1, S2, S3 and S5 all edit the 5,501-line
   `SessionLiveView.swift`, and two workers on one file is the gamble this rule exists to forbid. Stream D
   may run beside Stream S throughout, subject to constraint 8's gates. **At most two Opus agents at
   once** (one per stream); dispatch the long pole first.

3. **Swift compiles only in CI.** No macOS toolchain on this machine: no `xcodebuild`, no `swift build`,
   no simulator. Read the code you are changing in full, reason about the types, push.
   `.github/workflows/ios.yml` is the compiler.
   **[C] and the Release configuration compiles only in `deploy-testflight` on master.** A `catalog`-style
   DEBUG-only member read from outside `#if DEBUG` is green on every PR and red on the deploy job; the
   owner-decisions round nearly shipped one. Every `catalogFixture*` / `catalogSkipLoad` reference S6
   writes is inside `#if DEBUG` or behind a member that exists in both configurations.

4. **Implementers do not wait on CI.** Push and hand the task back with a **written report file**
   (`<workspace>/<stream>-pushN.md`, ≤ 25 lines returned). **The controller monitors the run** (one event
   per run) and opens a fix task if it is red. Fix rounds **resume the same implementer**; a fresh agent
   only after round 3 or a model escalation. Implementers are **retired at push points after ≥ 4 tasks**.
   **Reviewers write their own review file** (`<workspace>/review-<stream>-pushN.md`) and return ≤ 15
   lines.

5. **One commit per task**, with this trailer, verbatim:
   ```
   Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
   ```
   Use `git commit -F <file>` or a single-quoted heredoc. A `-m` message containing backticked identifiers
   has silently deleted words in this repo before.

6. **The catalog four-part contract, in ONE commit per id.** A new `CatalogScreen` id lands in all four
   places in the *same* commit: the `case` **and** its builder arm in `App/CatalogHostView.swift`; the id
   string in `GymSyncTests/CatalogScreenTests.swift`'s `ids` array; a
   `func testCatalog…() { captureCatalog("<id>") }` in `GymSyncUITests/ScreenshotTests.swift`; an entry
   in `docs/design/frame-map.json`. **And the same contract in reverse for a retirement**: the `case`,
   the builder arm **and the view struct it renders**, the id string, the capture method and the
   frame-map entry all leave in one commit. **A retired frame number is never reused.**

7. **The FLOOR is `±N over master's FLOOR at integration`, never a literal.** **[C]** This plan's N is
   **+3** — three production captures in (155, 156, 157), none out. `solo-live-set` (frame 66) and its
   capture **stay live through C1** and retire in C2 with the view they photograph. Against the verified
   base (`135`) that is `135 → 138`; I1 re-derives the literal on the day by counting the exported files
   in the last green `app-screenshots` artifact.

8. **Migrations are gates.** `.github/workflows/backend.yml:24-27` runs `node scripts/run_pgtap.js`
   against the **live** `SUPABASE_DB_URL`; there is no `supabase db push` anywhere in CI. A pgTAP test for
   an object that has not been applied to project `chjkkwqwdlmaxacwglzm` **will fail**. So each migration
   task ends: **commit, stop, hand back.** The controller applies it live (Supabase MCP `apply_migration`),
   says "applied", and only then does the matching pgTAP task — and any Swift task that reads the new
   column — start. Each commit body records the timestamp it was applied. **Subagents never run DDL or
   DML against the live project, not even inside a rolled-back transaction.** **[C] the test-retirement /
   guard change merges in the same window as the gate**, because pgTAP runs against the live database and
   a guard change pushed without its migration reddens `backend.yml` on master's next `supabase/` push.

9. **THE IRREVERSIBLE GATE.** **[C] this plan has no irreversible change.** All three migrations are
   **additive nullable columns, one guard clause and one new function**; nothing is dropped, nothing is
   narrowed, and every one is reversible by a later `DROP COLUMN` / `CREATE OR REPLACE`. **The one-way
   step in C1 is `set_logs.routine_exercise_id` beginning to be written** (D3 → S2): from that commit on,
   rows are attributed by slot, and rows written before it are not. That is why D3's header states the
   **no-backfill** stance and S2 ships the per-`exerciseID` fallback in the same commit as the write.
   **Deletion of `WorkoutSessionView` is not in this plan at all** — it is C2's last task, after every
   capability has a proven home.

10. **Never request HealthKit or LOCATION authorization outside their one permitted call site, and never
    from a test.** A raised sheet hung `build-test` for 45 minutes once. The permitted sites are
    `LobbyView.initiateCheckIn()`, `SessionRunnerView`'s check-in control and `CheckInService`. **[C] S3
    is the task this constraint is aimed at**: an ad-hoc start writes `check_in_state: "ready"` directly
    on the participant row it inserts, exactly as `startSolo` does today — it adds **no** location read,
    no `CLLocationManager`, and no call to `CheckInService`. `HealthKitBridge.exportWorkout` stays where
    it is, at session end, and C1 does not move it.

11. **No live repository, and no `Date.now`, reachable from a catalog builder.** Every `content_*` renders
    from fixture integers, strings and dates built from components. **[C] S6's three frames use
    `SessionLiveView`'s existing `#if DEBUG` fixture initializer** (`SessionLiveView.swift:95-127`,
    already proved hermetic by the owner-decisions round) with new one-participant fixture worlds in
    `LiveFixtures.swift` — no repository, no `Date()`, no `.shared`, and no reachable path to
    `WatchConnectivityBridge.activateIfNeeded()`, `HeartRateBroadcastService`, the voice room or
    `LiveSessionTimerStore` (whose writes are already `catalogSkipLoad`-guarded at
    `SessionLiveView.swift:2168-2190`).

12. **Every report claim is verified against `git show <sha> --stat` and the CI artifact, not memory — and
    grep the CALL SITE of every new function before claiming it is live.** Download artifacts **into a
    fresh directory**. A definition is not a feature: `git grep -n "<symbol>("` must show a caller outside
    the symbol's own file and its tests. **[C] the cautionary case for this plan is
    `compare_features`-shaped**: a durable swap layer with a repository, a migration, pgTAP and no reader
    in `effectiveRoutineExercises` would look complete and change nothing. S1's report greps the reader.

13. **Design rules, by number** (`2026-09-05-design-language.md`). **[C] the owner directive forbids a
    design round; these are the floor a moved capability must not fall below, not an invitation to
    restyle.**
    - **1** — two raised surfaces only: `.gs3DCard` to read, `.gs3DCardStyle`/`.gs3D` to press; furniture
      inside a raised box stays flat; strips are `surface` at 14 pt. **Never `theme.surface` or
      `theme.bg` as a face.** The two radii are `GSMetrics.radiusMd` (24, cards) and `GSMetrics.radiusSm`
      (16, tiles).
    - **2** — **accent is spent once per screen.** On the live body the accent is already the LOG card;
      nothing C1 adds spends a second. `Color.gsSuccess` means done/present; **gold is streak and
      check-in ONLY**; red is errors.
    - **3** — kickers 10-11 pt caps, 0.1-0.13 em tracking, muted; numbers tabular (`.monospacedDigit()`).
    - **9** — sentence case for sentences, caps for kickers; a button says exactly what happens. **No
      decorative emoji; SF Symbols for glyphs.**

14. **The frozen frames must not move.** **[C]** Phase A's seven (129-135), Phase B1's six (136-141),
    Phase B2's five (142-146), the owner-decisions round's (147-154, including 151/152) and the two Home
    canaries (81, 82) are owner-approved compositions. **No task in this plan may change what any of them
    renders.** "Unchanged" means 0 % of pixels differ below the status bar and above the home-indicator
    band. **`session-warmup-solo` is the one to watch**: S3 routes an ad-hoc session into the SAME
    `WarmUpScreen` that frame renders, and it must do so without touching the fixture that frame uses.

15. **Do not rename an existing `CatalogScreen` raw value, and do not reuse a retired one.** **[C]** The
    three new ids are `session-solo-live`, `session-solo-rest` and `session-solo-swap` — prefixed
    `session-` like every other one-body frame. `solo-live-set` is **not** renamed and **not** retired in
    C1.

16. **Live-DB tests use the `TestSession` teardown factory and far-future rows.**
    `GymSyncTests/TestSession.swift` is the only place a test may create a session; register cleanup with
    `addTeardownBlock` **before** the write. Every date a live-DB test controls is **2099**.

17. **pgTAP conventions.** `BEGIN;` → `CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;` →
    `SELECT plan(N);` → a comment naming the migration under test and declaring the fixture block →
    `auth.users` inserted before `profiles` → role switching with `SET LOCAL role authenticated;
    SET LOCAL request.jwt.claim.sub = '<uuid>';` → **reset the role and claim before inserting the next
    fixture block** → `SELECT * FROM finish(); ROLLBACK;`. **An emptied suite is deleted, never left at
    `plan(0)`** (pgTAP aborts the whole run with "No tests run!"). **Assert a delete's effect in a second
    statement, never inside a data-modifying CTE.**
    **Namespaces taken:** `01xx`-`13xx`, `15xx`, `16xx`. **This plan takes `17xx` (D2) and `18xx` (D4).**

18. **`XCTUnwrap(await …)` does not compile — bind, then unwrap.**

19. **The UI-test target's compile risk, named.** `GymSyncUITests` is built by the **screenshots** job
    (`ios.yml:326-329`), which runs **after** the seed step — `build-test` does **not** build it. So a
    task that edits `ScreenshotTests.swift` (S6) is not proven by a green `build-test`: **its proof is a
    green screenshots job**, and the controller re-runs the job rather than assuming.

20. **Do not change the shipped session-engine contracts.** `start_session`, `advance_turn`,
    `advance_round`, `set_session_stations`, `mark_warmup_ready`, `start_lifting`, `evaluate_lateness`,
    `mark_no_shows`, `claim_session_venue`, `check_in_to_venue`, the `check_in_state` CHECK, the
    five-state `sessions.state` CHECK and `session_participants`' four policies are frozen. **[C] this
    plan adds three nullable columns, one RPC and one clause to `private.session_round_guard`; it changes
    no shipped contract and drops nothing.** In particular **S3 does not add a new start RPC**: an ad-hoc
    session reaches lifting through the shipped `start_lifting`, called from the shipped `WarmUpScreen`.

21. **[C] THE LOG PATH IS FROZEN, AND ITS SEAM IS THE FIRST REVIEW QUESTION.** Every prior round kept
    `LogFollowUp.calls(for:)`, `commitInlineLog()`, `prefillLogInputs()` and `turnEntryCard` byte-identical.
    **C1 keeps all four byte-identical too** — a solo ad-hoc session is a `.freestyle` session with a
    one-person roster, which those four already serve (decision 4). The **only** change any task in this
    plan makes anywhere near them is S2's one added field on the `SetLog` value that
    `logSetAndAdvance(...)` inserts, and S2's review must state in writing which of the four it touched
    (the answer must be: none of their bodies). **This is the highest-risk seam in the whole adoption and
    it is asked at S2, not at the final review.**

22. **[C] ViewBuilder hygiene, because the one body's type-checker budget is spent.** No local `func`
    declarations and no explicit `return` inside a `ViewBuilder` closure; ten children maximum per
    container. `SessionLiveView.body` is already at its budget — **every new modifier or subview this
    plan adds goes into an extracted layer** (a `private var` returning `some View`, or a new file), never
    inline in `body`.

---

## File structure

### Created

| File | Responsibility | Task |
|---|---|---|
| `supabase/migrations/20260919000101_session_swap_layer.sql` | `session_participants.self_swaps jsonb NULL`, `sessions.squad_swaps jsonb NULL`, `public.apply_squad_swap(uuid, uuid, uuid)` SECURITY DEFINER, and one clause in `private.session_round_guard` refusing a client write of `squad_swaps` | D1 |
| `supabase/tests/session_swap_layer_test.sql` | pgTAP (`17xx`): both columns; the own-row write; the other-row rejection; the guard's refusal of a direct `squad_swaps` PATCH; `apply_squad_swap` from a participant and the stranger's raise; both BEFORE UPDATE triggers passing a `self_swaps`-only write through | D2 |
| `supabase/migrations/20260919000102_set_logs_routine_slot.sql` | `set_logs.routine_exercise_id uuid NULL` + a partial index; the header states the **no-backfill** stance | D3 |
| `supabase/tests/set_logs_routine_slot_test.sql` | pgTAP (`18xx`): the column, its nullability, the insert policy still admitting a row with and without it, the index | D4 |
| `GymSyncApp/GymSync/Models/SessionSwapLayer.swift` | `SessionSwapLayer` — the durable layer's value type (`[UUID: UUID]` keyed by **routine-exercise row id**), its JSON codec, and `SessionSwapRepository.loadSelf/saveSelf/applySquad` | S1 |
| `GymSyncApp/GymSyncTests/SessionSwapLayerTests.swift` | the codec round-trip; the empty layer; an unknown slot id ignored; the twice-named-lift case (two slots, one exercise id, one swapped) | S1 |
| `GymSyncApp/GymSyncTests/RoutineSlotProgressTests.swift` | the cursor derivation the root-cause report specified: `[A(3), C(3)]`, slot A swapped to B, logs `3×B + 2×C` → `(index 1, set 3)`; no-swap parity with today; a swap with no sets yet; the twice-named lift | S2 |
| `GymSyncApp/GymSync/Features/Sessions/Live/SoloSessionLayer.swift` | the solo-only presentation layer the one body mounts when `rosterCount == 1` and the session is ad-hoc: the MINIMISE control, and the extracted modifiers constraint 22 forbids inlining | S4 |
| `GymSyncApp/GymSyncTests/SoloSessionShapeTests.swift` | `SoloSessionShape.isAdHocSolo(...)` — the pure predicate, every branch | S4 |

### Modified

| File | Change | Task |
|---|---|---|
| `GymSyncApp/GymSync/Models/RoutineLayering.swift` | `apply(_:squadSwaps:selfScale:todaysScale:)` re-keyed from `exerciseID` to the routine-exercise row id (`re.id`); `swapped(_:to:)` gains `setType`/`dropSteps`/`dropPercent` if the hotfix has not already added them | S1 |
| `GymSyncApp/GymSyncTests/RoutineLayeringTests.swift` | the order assertions re-stated against slot ids; one new case: two slots, one exercise id, one swapped | S1 |
| `GymSyncApp/GymSync/Models/RoutineProgression.swift` | `currentExercise(routine:completedSets:)` gains a slot-keyed sibling; the `exerciseID` spelling is kept as the documented fallback for pre-column rows | S2 |
| `GymSyncApp/GymSync/Models/SetLog.swift` | `var routineExerciseID: UUID? = nil` + its `CodingKey`; trailing default keeps every construction site compiling | S2 |
| `GymSyncApp/GymSync/Models/SessionRepository.swift` | `startSolo` sets `style: .freestyle` and takes the routine's exercises for the style default; `logSet` carries the new field unchanged (it is on the value) | S2, S3 |
| `GymSyncApp/GymSync/Features/Sessions/Live/SessionLiveView.swift` | S1 points `effectiveRoutineExercises` (`:621-637` region) at the durable layer and `selfScales`/`squadSwaps` become its cache, not its truth; S2 stamps `routineExerciseID` on the inserted `SetLog` and re-points `currentExerciseForSheet` (`:2901-2915`); S3 nothing; S4 mounts `SoloSessionLayer` and the solo furniture gates; S5 nothing | S1, S2, S4 |
| `GymSyncApp/GymSync/Features/Sessions/Live/RoundPieces.swift` | `TurnStrip` is not rendered for a one-person roster (S4's furniture gate) | S4 |
| `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift` | S1 points its swap layer at the same repository and DELETES the hotfix's `AppState` mirror; S2 stamps the slot on its insert and uses the slot-keyed cursor. **The file is not deleted in C1.** | S1, S2 |
| `GymSyncApp/GymSync/App/AppState.swift` | `LiveSoloSession`'s hotfix-added swap/rest mirror fields removed (`:150`, `:158` region); the struct itself stays until C2 | S1 |
| `GymSyncApp/GymSync/Features/Home/HomeView.swift` | `RoutinePickerSheet` (`:2104-2132`, `:2208-2217`) starts the session and presents `SessionEntryView`; `showRoutinePicker` (`:280-281`) unchanged in purpose | S3 |
| `GymSyncApp/GymSync/App/RootView.swift` | the resume sheet (`:461-469`) becomes a `.fullScreenCover` over `SessionEntryView`; the SESSION LIVE pill's comment (`:431-433`) stops describing an orphaned session | S3 |
| `GymSyncApp/GymSync/Features/Library/RoutinesListView.swift` | "Start Workout" (`:339-342`) starts the session, then presents `SessionEntryView` | S3 |
| `GymSyncApp/GymSync/Features/Library/DiscoverWorkoutDetailView.swift` | "Attempt Solo" (`:186-192`) the same, with `attemptOptIn` fired after creation as today (`:173-184`) | S3 |
| `GymSyncApp/GymSync/Models/SessionRepository.swift` | `liveForCurrentUser` (`:532`) stops excluding solo, so Home's live pill routes an ad-hoc session like any other | S3 |
| `GymSyncApp/GymSync/Features/Sessions/SessionRunnerView.swift` | nothing new — it already routes `.warmUp`/`.live`; S3's report proves it by reading, not by editing | — |
| `GymSyncApp/GymSync/Features/Sessions/Live/LiveFixtures.swift` | three one-participant freestyle worlds | S6 |
| `GymSyncApp/GymSync/App/CatalogHostView.swift` | three ids in | S6 |
| `GymSyncApp/GymSyncTests/CatalogScreenTests.swift` | three ids in | S6 |
| `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` | three capture methods in | S6 |
| `docs/design/frame-map.json` | 155, 156, 157 in | S6 |
| `.github/workflows/ios.yml` | the FLOOR, once | I1, and only I1 |
| `docs/design/accepted-deviations.json` | entries appended | I1 |

### Deleted

| File / symbol | Why | Task |
|---|---|---|
| The hotfix's `AppState.LiveSoloSession` swap/rest mirror (H1) | It was a named stopgap for exactly this: an in-memory mirror keeping the solo swap alive across a sheet dismiss until the durable layer landed. S1 lands the durable layer; the mirror's doc comment already names Phase C as its executioner. If `hotfix-report.md` exists when S1 starts, its symbol names come from there; if it does not, S1 greps `AppState.swift` and `WorkoutSessionView.swift` for the fields the hotfix added and names them in its report. | S1 |
| `WorkoutSessionView.swift`'s inline swapped-row rebuild (`:1193-1200`) | Superseded by `RoutineLayering.swapped` (the hotfix's H6 may already have done this; S1 verifies rather than assumes). | S1 |

**Not deleted, deliberately:** `WorkoutSessionView.swift` and `WarmUpPhaseView.swift` (**C2**, after every
capability has a proven home — the owner trains on this screen today); `solo-live-set` and its capture
(C2, with the view); `SessionRoutineEditor.swift` and `FormClipCapture.swift` (C2 moves them); frames 151
and 152 (the design pass retires them, not this plan); `RoutineProgression.currentExercise`'s
`exerciseID` spelling (S2 keeps it as the documented fallback for rows written before D3).

---

## The seven decisions, stated

### 1. An ad-hoc solo session is a real session in the one body's state machine, and it is `.freestyle`

**The map called this "the sharpest data-model seam in the whole adoption." Read against the code, it is
narrower than that.** `SessionRepository.startSolo` (`:21-57`) already inserts `state: "in_progress"` with
`lifting_started_at` never set — and `WarmUpGate.isWarmingUp(state:liftingStartedAt:)`
(`WarmUpScreen.swift:25-27`) is **exactly** `state == "in_progress" && liftingStartedAt == nil`. So
`SessionRouter.route` (`SessionEntryView.swift:29-56`) already sends that row to `.warmUp` →
`SessionRunnerView` → `WarmUpScreen`, and `start_lifting` already stamps the column that moves it to
`.live` → `SessionInProgressView` → `SessionLiveView`. **The row `startSolo` writes today is a row the one
body accepts.** Nothing in C1 needs a new start RPC, and constraint 20 is not strained.

**What must change is the style.** `sessions.style` is `NOT NULL DEFAULT 'rounds'`
(`20260913000101:25-26`), and `'rounds'` is the one style whose body carries a rotation strip, a round
wait and a server-owned round. An ad-hoc lifter must never see any of them. **`startSolo` writes
`style: .freestyle`**, which is:
- the style `LogFollowUp.calls(for:)` maps to *neither* `advanceTurn` *nor* an offered round close (the
  table's own comment block, `RoundPieces.swift:41-47`) — so **the round engine is never walked for an
  ad-hoc solo row**, which answers the brief's question without a special case;
- frozen by `private.session_round_guard` the moment `lifting_started_at` is stamped
  (`20260913000102:120-123`), so a solo session cannot change arm underneath itself;
- the only style whose live body is a self-paced rail rather than a turn, which is what a lifter alone
  in a gym is doing.

**A scheduled solo session keeps whatever style scheduling chose.** C1 changes the ad-hoc insert only.

**What check-in means for a lifter who just tapped START SOLO WORKOUT.** Nothing he has to do.
`startSolo` already inserts the participant row at `check_in_state: "ready"` (`:46-54`), and that is the
honest reading of spec §2: he is here, the session is now, presence is not in question. The guards were
walked, not assumed:
- **`checkin_window_guard`** (`20260715000003`) guards only the transition *to* `'ready'`. The ad-hoc row
  is inserted at `'ready'` — a BEFORE **UPDATE** trigger never sees an INSERT — and on any later UPDATE
  `NEW.check_in_state = OLD = 'ready'`, so the guard runs its window check and finds
  `v_scheduled_for IS NULL`, which **fails open by design** (`:36-41`, its own comment). **PASSES.**
- **`engine_guard`** (`20260714000001:45-70`) raises only when `late_minutes`, `burpees_owed` or
  `turn_order` change. An ad-hoc insert and a `self_swaps` write change none. **PASSES.**
- **`session_venue_insert_guard`** (`20260918000204`) refuses a non-NULL `venue_id` on INSERT.
  `startSolo`'s struct literal leaves it NULL. **PASSES.** A solo lifter may still claim a venue
  afterwards through the shipped `claim_session_venue`, exactly as a crew member does.
- **`private.session_round_guard`** is BEFORE UPDATE on `sessions`; the ad-hoc insert never reaches it,
  and the only `sessions` UPDATE C1 adds is `apply_squad_swap`'s, which sets the engine GUC.
- **the round engine** (`advance_round`, `advance_turn`) is unreachable: `.freestyle` calls neither.

**pgTAP proves the walk, not the prose.** D2 asserts a `.freestyle`, `scheduled_for IS NULL`,
`check_in_state = 'ready'` row can be inserted and can take a `self_swaps` UPDATE with every trigger
live. That assertion is the migration gate the brief asked for.

### 2. The durable swap layer: two homes, and it is keyed by the SLOT

**This is the prerequisite.** Today the layer is `@State` in both bodies — `soloSwapOverrides`
(`WorkoutSessionView.swift:290`), `selfScales`/`squadSwaps` (`SessionLiveView.swift:345`, `:347`) — and
the crew's is distributed only by an **ephemeral broadcast** with no replay, so a lifter who joins or
foregrounds late never learns of an applied swap. `RoutineLayering.apply` is a pure function that already
takes its layers as parameters (`RoutineLayering.swift:70-84`), so it is the correct seam; what is missing
is storage behind it.

**Two homes, and the difference between them is who may write.**

| layer | home | write path | why |
|---|---|---|---|
| **my own quiet swap** | `session_participants.self_swaps jsonb NULL` | a direct own-row PATCH — **no new policy** | "participant updates own check-in" (`20260712000001:22-25`) is `USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid())` with **no column list**, so a lifter can already write their own row, and "participants readable by other participants" (`20260726000001:182-187`) is row-level, so the crew can already read it. This is verbatim the reasoning `todays_scale` shipped on a day earlier (`20260918000202:71-96`), and a third policy here would be permissive-ORed with those and would grant nothing while looking like it granted something. |
| **the crew's agreed swap** | `sessions.squad_swaps jsonb NULL` | **`public.apply_squad_swap(p_session_id, p_slot_id, p_replacement_id)`**, SECURITY DEFINER, gated on `private.is_session_participant`, plus a **new clause in `private.session_round_guard`** refusing a client write of `squad_swaps` | The `sessions` UPDATE policy admits the organizer **and every participant** with no column list — exactly the hole `session_venue_guard` closed for `venue_id` a day earlier (`20260918000203`, its own header). Without the guard clause **one lifter could PATCH `squad_swaps` alone**, and the consent card's unanimity would become decorative. The guard is the same idiom, one clause longer. |

**Keyed by the routine-exercise row id, not the exercise id.** `RoutineLayering.apply` keys
`squadSwaps`/`selfScale` by `re.exerciseID` today (`:80-82`), and `RoutineProgression.currentExercise`
counts by `completedSets(re.exerciseID)` (`:41-50`). Both are wrong for a routine that names one lift
twice: swapping slot 3's bench swaps slot 7's bench too, and slot 7's sets count toward slot 3. **C1
re-keys the layer to `re.id`.** `todaysScale` keeps its `exerciseID` keying, because a set reduction the
athlete accepted at the warm-up was accepted against a *lift*, not a slot — and that is the semantics
`RoutineLayering`'s own header already documents (`:14-18`).

**The wire is extended, not replaced.** `SessionBroadcastService.SwapEvent`
(`SessionBroadcastService.swift:52-60`) carries `exerciseID`/`replacementID`; B2's constraint 21 froze
it. C1 adds **one optional field, `routineExerciseID`**, decoded if present. An installed build that
sends the old shape still applies its swap to every slot bearing that exercise id — today's behaviour,
which is correct whenever the routine names the lift once. **The durable row, not the broadcast, is the
truth**: `reload()` reads `squad_swaps` and `self_swaps`, so a late joiner and a relaunching lifter both
see what the crew sees, which is what the broadcast has never been able to promise.

**The hotfix's stopgap is deleted here.** `fix/solo-swap-rest-durability` H1 mirrors the solo swap and
rest into `AppState.liveSoloSession` in memory, and H2 extracts the cursor into a pure function. **S1
deletes the H1 mirror** (its own doc comment names Phase C as the durable fix) and **keeps H2's pure
function**, which S2 re-points at slot ids. If `hotfix-report.md` exists in
`.superpowers/sdd/2026-09-19-group-session-phase-c/` when S1 starts, its symbol names come from there; if
it does not, S1 greps `AppState.swift` for the fields the hotfix added and names them in its report.

### 3. Slot-based set attribution: yes, `set_logs.routine_exercise_id`, and no backfill

**The real table is `set_logs`** (`20260709000007`), not `session_sets`. It has `exercise_id NOT NULL`
and no notion of which routine row a set was logged for.

**It gains `routine_exercise_id uuid NULL`**, written on every insert from both bodies. It is what makes
three things honest at once:
- **a swap mid-exercise** — the owner's complaint B3 exists only because a slot with sets under two
  exercise ids breaks per-id counting (`debug-swap-state.md` §3, and the deliberate gate at
  `WorkoutSessionView.swift:1616`). With slot attribution the gate can be lifted; **C1 does not lift it —
  C2 does**, because the gate lives in a view C1 is not rewriting.
- **a routine naming one lift twice** — the known flaw in the owner-decisions round's R-OD-3.
- **the recap's volume** — the double count `debug-swap-state.md` §5 measured (volume and set count
  inflated, PRs not cross-contaminated) is a per-id sum with no per-slot dedupe.

**No foreign key, deliberately.** `routine_exercises` rows are deleted when a routine is edited, and a
logged set is history: an FK with `ON DELETE CASCADE` would delete the set and one with `RESTRICT` would
block the edit. The column is a **recorded intent**, not a live reference, and the header says so. A
freeform ad-hoc workout writes NULL — its synthesized rows are never persisted
(`WorkoutSessionView.swift:249-254`), so there is no slot to name; the per-id fallback is exactly right
for them, forever.

**No backfill.** Every row written before the migration keeps `NULL`, and every cursor reader keeps the
per-`exerciseID` path for those rows. S2's rule, stated once and tested: *a slot's completed count is the
number of rows whose `routine_exercise_id` equals the slot id, plus — only when the slot has zero such
rows — the number of rows whose `exercise_id` equals the slot's exercise id and whose
`routine_exercise_id` is NULL.* That gives byte-identical behaviour for an all-old session, correct
behaviour for an all-new one, and the old behaviour for the one session that straddles the deploy.

**Every reader of the cursor is re-pointed, named here so none is missed:**
`SessionLiveView.currentExerciseForSheet` (`:2901-2915`) and `mySetCount(for:)`;
**`SessionLiveView.currentRoutineExercise` (`:628-631`)**, which resolves the slot by
`first(where: { $0.exerciseID == ex.id })` — after a swap that finds the row bearing the *substitute's*
id, which is right today only because the layer is keyed the same wrong way, and must become a lookup
by slot id once S1 lands (**the same one-line trap at `:630`, `:3075`, `:2924` and `:3843`**);
`WorkoutSessionView.restoreLoggedProgress` (`:3713-3756`, or the hotfix's extracted function),
`soloCurrentExerciseSets` (`:897-899`), `nextSetIndex` on the watch payload (`:939`);
`RoutineProgression.currentExercise` itself. **Not re-pointed, on purpose** — `lastTimeByExercise`
(`:253`), `prBasisByExercise` (`:138`), `soloCeilings` (`:209`) and `BlockProgression.decide(history:)`
(`:1129`): those are *history* reads keyed by lift across sessions, and a lift's history is per lift, not
per slot. S2's report states that distinction explicitly.

### 4. The log path: nothing changes in the four frozen symbols, because solo is a style they already serve

`LogFollowUp.calls(for:)`, `commitInlineLog()`, `prefillLogInputs()` and `turnEntryCard` **stay
byte-identical in C1.** The reason is structural, not disciplinary:

- `logControlIsMine` (`SessionLiveView.swift:468-470`, `LogControlGate.isMine(style:isMyTurn:)`) is
  **unconditional for `.freestyle`**. A solo lifter's control is always his.
- `prefillLogInputs()` (`:2929-2982`) is gated on `logControlIsMine` flipping true, which for
  `.freestyle` happens once, at mount. Solo's `soloPrefill()` (`WorkoutSessionView.swift:1069-1181`) is
  called from a `.task(id:)` instead, *because* there is no turn to gate on — but the ladder logic inside
  them is the same, and `prefillLogInputs` is the surviving spelling.
- `LogFollowUp.calls(for: .freestyle)` calls neither `advanceTurn` nor an offered round close. Solo's
  `log(...)` (`:3810-4149`) inlines "advance set/exercise, superset handoff, start rest" where the one
  body delegates it — those three are the one body's own, and they are **already written** for
  `.freestyle`.
- **R-OD-3 already aligned `setsLogged`**, so the set-index semantics the map worried about are the same
  on both sides.

**What the solo path was doing that the one body does not — the honest list.** `prBasis` by exercise:
both hold `pendingPRs: [UUID: PRFiring.Pending]` and both route through `PersonalRecordMath`
(`SessionLiveView.swift:5052-5053`; `WorkoutSessionView` via `prBasis`/`Self.pairs`), and the
owner-decisions round's S1 put both behind the same `PRFiring.shouldCelebrate`. `sessionPRs` and the
duplicate `isLoggingSet` guard are duplications, not divergences. **So the convergence at the log path is
a deletion (C2), not a rewrite (C1).**

**S2's review must answer this in writing**, naming each of the four symbols and stating that its body is
unchanged in the diff (constraint 21).

### 5. The rest window: the one body already has it, and the root-cause report is one step out of date

`debug-swap-state.md` §6 reports the group rest window as "SAME CLASS — `@State`, and `reload()` does not
restore them." **Read against `d74d95a`, that is not the whole picture**, and the correction matters
because it removes a task:

- `SessionLiveView` **has a durable-across-dismissal rest window already**: `LiveSessionTimerStore`
  (`Services/LiveSessionTimerStore.swift`, 48 lines) is written on every change of
  `selfRotationRestUntil` (`SessionLiveView.swift:2168-2184`) and re-seeded by `restoreTimersFromStore()`
  on `.onAppear` (`:3101-3125`), **which also re-arms the lapse `Task` the original view took with it**.
  That store exists because the owner reported the identical bug against the crew body on 2026-08-14 —
  the file's own header says so.
- `SessionLiveView` **has a `scenePhase` handler** (`:2226-2243`); `WorkoutSessionView` has none.

**So adopting the one body fixes the fully-evidenced leg of B4-rest by construction.** What it does not
fix, and what C1 must not claim: the store is **memory-only on purpose** (`LiveSessionTimerStore.swift:14-15`),
so a rest window does **not** survive an app relaunch. That is the honest statement of what a solo lifter
gets after C1:

| event | swaps | cursor | rest |
|---|---|---|---|
| sheet swipe-down → back in | survive (durable row, S1) | correct (slot attribution, S2) | survives (`LiveSessionTimerStore`) |
| lock / unlock | survive | correct | survives (wall-clock end date + `scenePhase` re-derive) |
| app relaunch | survive (durable row) | correct | **lost** — the window is re-derived as elapsed, and the lifter lands on the next set |

**The acceptance test the brief asked for, stated as it will actually be run.** *"A solo session survives
swipe-down, lock and relaunch with its swaps, its cursor and its rest intact"* is split into what a pure
test can prove and what only a device can:
- **Pure (S1, S2, S4):** the layer round-trips through its codec; the slot-keyed cursor lands where the
  root-cause report specified; `SoloSessionShape.isAdHocSolo` is right on every branch;
  `RoutineLayering.apply` keyed by slot.
- **Manual, written by I2 into a TestFlight script for the owner:** start an ad-hoc workout, swap a lift
  mid-exercise, log two sets under the substitute, swipe down, reopen via the pill — the substitute is
  still there and the cursor is on set 3; lock for 30 s with a rest running, unlock — the countdown shows
  the right remaining time; force-quit and reopen — the substitute is still there and the cursor is
  right, **and the rest window is gone, which is the documented limit, not a bug to report.**
- **Not fixed blind:** the lock-screen leg's two candidates (`debug-swap-state.md` §2) stay unproven.
  C1 adds no speculative `scenePhase` handler to any solo path — the one body's handler is the one that
  runs.

### 6. How the solo session is presented: a full-screen cover with a way out, not a sheet that orphans it

Today the ad-hoc session is a **push inside a dismissible sheet** (`HomeView.swift:280-282`,
`:2207-2218`), and `RootView`'s own comment says the quiet part out loud: *"the moment a swipe-down
orphans the session, the pill is the way back in"* (`:431-433`). Swipe-down destroys the view and every
`@State` in it. **That is the single mechanism behind both halves of the owner's field report.**

**C1's decision: `.fullScreenCover`, with MINIMISE as a deliberate act.** The cover cannot be
swipe-dismissed, so minimising is something the lifter chooses: a control in the session's own header
(`SoloSessionLayer`, S4) that dismisses the cover and leaves the SESSION LIVE pill as the way back —
the same pill, now describing a minimised session rather than an orphaned one. The state the lifter
would have lost is durable anyway after S1/S2, so the cover is belt *and* braces; it is chosen because
an accidental gesture should not end a screen the lifter is mid-set on.

**The re-entry path stops being a special case.** `SessionRepository.liveForCurrentUser` (`:532`)
explicitly *excludes* solo from Home's routing today (`:528-531`); S3 removes that exclusion, so an
ad-hoc session is routed by the same pill, through the same `SessionEntryView`, as every other live
session. `AppState.liveSoloSession` — a singleton-shaped resume keyed to `WorkoutSessionView`'s
constructor, carrying a **frozen snapshot** captured at start and never updated
(`WorkoutSessionView.swift:3654-3656`) — stops being the mechanism. **The struct itself is not deleted in
C1** (the old view still reads it); C2 removes it with the view.

### 7. Mid-session routine editing is SOLO-only, and it is C2

`SessionRoutineEditor` (`Features/Workout/SessionRoutineEditor.swift`) — add / reorder / remove exercise,
with the three-way persist at session end (`persistSessionEdits(asNew:)`, `:3316-3351`;
`applyCoachRoutineEdit`, `:3352-3428`) — exists only in the ad-hoc body and has **no home in
`SessionLiveView` at all**. It **moves, for SOLO sessions only**, in **C2**.

**For crews it is explicitly not in scope**, and that is a product decision, not an omission: §3.4 makes
the **consent card** the crew's mode of exercise change, and a session-local routine rebuild by one
member would route around the unanimity the card exists to enforce. It is listed under "What this plan
does not decide" so no C2 task quietly generalises it.

**How it layers.** The editor produces a *different list of slots*; `RoutineLayering.apply` produces *a
different lift or dose per slot*. They compose in that order — edit first, layer second — because a slot
that was removed has no layer to apply and a slot that was added has no swap yet. A **freeform ("empty")
ad-hoc workout** is the degenerate case: `isFreeform` is `routineExercises.isEmpty`
(`WorkoutSessionView.swift:289`), every exercise arrives through the editor's own picker, and every set
writes `routine_exercise_id = NULL` (decision 3) because the synthesized rows are never persisted. C2's
task carries that statement into the one body verbatim.

---

## New catalog ids, and the FLOOR

### In — three production ids, frames 155-157 (S6)

Per the owner directive: every surface that becomes **newly reachable** in the one body gets **one**
hermetic proof frame, built from the existing production views with fixture values. No variation frames,
no compositions to choose between.

| id | frame | what it proves |
|---|---|---|
| `session-solo-live` | 155 | An ad-hoc solo session in the one body: `.freestyle`, one-participant roster, the LOG card as the page's one accent, **and no crew furniture** — no rotation strip, no mic rail, no presence row, no station card, no burpee-debt strip. The map found **no existing frame with a one-participant fixture** (context map §7), so this is the frame that makes the adoption visible. |
| `session-solo-rest` | 156 | The personal rest window for a solo lifter — the one body's `selfRotationRest*` page with a fixture end date built from components, and the swap door on it. |
| `session-solo-swap` | 157 | The durable swap sheet on a solo session: the graph suggestions, and the "Search all exercises" row the hotfix added, over a fixture catalog. |

**No new warm-up frame.** An ad-hoc solo session warms up on the **same `WarmUpScreen`** that
`session-warmup-solo` already photographs (decision 1); a second id would photograph the same view with
the same fixture. Constraint 14 makes the existing frame's byte-identity the proof instead.

### Out — none in C1

`solo-live-set` (frame 66) photographs `WorkoutSessionView`, which still ships at the end of C1. **It
retires in C2, in the same commit as the view**, per the four-part contract in reverse. Frames 151 and
152 are the design pass's to retire, not this plan's.

### The FLOOR

**`FLOOR` moves by `+3` against master's FLOOR at integration** — three captures in, none out. Against
the verified base (`135`) that is `135 → 138`. I1 re-derives the literal on the day by counting the
exported files in the last green `app-screenshots` artifact. **C2's delta is `−1`** (`solo-live-set`
out), so the two phases net `+2` over 135.

**Counts after S6:** `CatalogScreen` = **116** cases, `CatalogScreenTests` ids = **116**, real
`captureCatalog("…")` calls = **114**, `frame-map.json` = **95** entries, max frame **157**, zero
duplicate frame numbers.

**Captures that change content rather than count, and are therefore this plan's best proofs:**
`app-session-warmup-solo`, `app-session-your-turn`, `app-session-scale-down` and `app-solo-live-set` must
all be **byte-identical** after S1, S2 and S4 — the layering re-key and the slot attribution are
behaviour-preserving for a session with no swaps and no pre-column rows, or they are a bug.

---

## Sequencing

```
 feat/group-session-phase-c  d74d95a   (FLOOR 135, frames 1-154)
        │
        ├──► STREAM D · the data  (supabase/**, scripts/**)
        │      D1 self_swaps + squad_swaps + apply_squad_swap + guard clause ──[GATE]──► D2 pgTAP (17xx)
        │      D3 set_logs.routine_exercise_id                              ──[GATE]──► D4 pgTAP (18xx)
        │
        └──► STREAM S · the app (ONE worker at a time, in order)
               S1  the durable, slot-keyed swap layer      L · Opus   ← needs D1 applied
               S2  set attribution by slot                 L · Opus   ← needs D3 applied
               S3  the ad-hoc start, and the entry points  L · Opus
               S4  the solo shape of the one body          M · Opus
               S5  the resume path and the live pill       S · Sonnet
               S6  three proof frames                      M · Sonnet
                          │
                          ▼
                   INTEGRATION  (I1 Sonnet · I2 controller · I3 controller)  →  ONE PR, with proof cards
```

**The hard edges.** S1 → S2 → S3 → S4 are one worker in number order: S1, S2 and S4 all edit
`SessionLiveView.swift`, and S2's cursor cannot be re-keyed before S1's layer is. S3 may not start before
S1 and S2 are pushed — re-pointing the entry points at the one body while the layer is still `@State`
would ship the double-log into the crew body's path. **S1 is gated on D1 applied; S2 on D3 applied.** S5
and S6 are Sonnet tails; S6 is last because its proof is a green screenshots job (constraint 19).

**Model ladder, per the 2026-09-13 token addendum.** Opus for the multi-file judgment calls (S1, S2, S3,
S4). Sonnet 5 for everything mechanical from an exact spec — both migrations, both pgTAP suites, the
resume tail, the catalog frames, I1. **Never Fable, never `fork`.** Two Opus at once, maximum, one per
stream — and Stream D is entirely Sonnet here, so the ceiling is never reached.

**Seams are reviewed early, not at the end.** **S1's review must answer the swap-layer seam in writing**:
`apply_squad_swap`'s exact signature and its three parameter names as PostgREST sends them; the JSON
shape of `self_swaps`/`squad_swaps` and how an absent key differs from a null; what the app does when the
RPC raises `P0001` (the sheet says so and the layer stays where it is); and **which symbol now reads the
durable row** — a layer with a repository and no reader in `effectiveRoutineExercises` is constraint 12's
cautionary case. **S2's review answers constraint 21's question** — the four frozen log-path symbols,
named, with their bodies unchanged in the diff. Phase B1 shipped a whole round engine with no caller
because that question was asked only in the final review.

---

# STREAM D — the data

Three schema objects, one guard clause, two pgTAP suites. `supabase/**` and `scripts/**` only. Both
migrations are **gates** (constraint 8). Neither is irreversible (constraint 9).

### D1 — the durable swap layer — **M** · Sonnet

**File (new):** `supabase/migrations/20260919000101_session_swap_layer.sql`

Decision 2. Write the header comment first, in the migration's own voice: why the personal layer needs
**no new policy** (quote `20260918000202:71-96`'s reasoning for `todays_scale` and name the two BEFORE
UPDATE triggers it walked — `engine_guard` and `checkin_window_guard` — and why a `self_swaps`-only
UPDATE passes both); why the crew layer **does** need an RPC and a guard clause (the `sessions` UPDATE
policy admits every participant with no column list — the same hole `20260918000203` closed for
`venue_id`, and without the clause one lifter could PATCH the crew's agreed swap alone); why both are
keyed by **routine-exercise row id** and not exercise id (a routine may name one lift twice); and why
neither column has a foreign key (routine rows are deleted when a routine is edited; the layer is a
recorded intent about a session that is over).

```sql
ALTER TABLE public.session_participants
  ADD COLUMN IF NOT EXISTS self_swaps jsonb;

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS squad_swaps jsonb;
```

Shape, in both columns and stated in the `COMMENT ON COLUMN`:
`{"<routine_exercise_id>": "<replacement_exercise_id>", …}`, absent key = no swap for that slot, `NULL` =
no layer at all. Never `{}` written by the app where `NULL` means the same thing — but readers must treat
them identically, and the app-side codec does (S1).

Then `public.apply_squad_swap(p_session_id uuid, p_slot_id uuid, p_replacement_id uuid) RETURNS jsonb`,
SECURITY DEFINER, `SET search_path = public`:
- raise `P0001` when `auth.uid()` is NULL;
- raise `P0001 'not a participant of this session'` when
  `NOT private.is_session_participant(p_session_id, auth.uid())` — the same gate
  `claim_session_venue` uses;
- raise `P0001` when `p_replacement_id` is not a row in `public.exercises`;
- `PERFORM set_config('gymsync.engine', 'on', true)` around the write, `''` after — the engine idiom
  every guard already honours;
- merge the one key into `squad_swaps` (`coalesce(squad_swaps, '{}'::jsonb) || jsonb_build_object(...)`)
  and return the merged object, so the caller never has to guess what landed;
- `REVOKE EXECUTE … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated;`

Finally, one clause added to `private.session_round_guard` — `CREATE OR REPLACE` of the whole function as
it stands at `20260918000203`, with the three existing clauses **verbatim** and one more:

```sql
  IF NEW.squad_swaps IS DISTINCT FROM OLD.squad_swaps THEN
    RAISE EXCEPTION 'squad_swaps is written through apply_squad_swap'
      USING ERRCODE = 'P0001';
  END IF;
```

**Done when:** committed, **not applied**. The commit body names the three objects and says the
controller applies it. The report quotes the two trigger walks. **Stop and hand back.**

### D2 — pgTAP for the swap layer — **M** · Sonnet · **needs D1 applied**

**File (new):** `supabase/tests/session_swap_layer_test.sql`. Fixture block **`17xx`** (constraint 17).

Assertions, and the count in `plan(N)` is whatever the file actually holds:
1. `has_column('session_participants','self_swaps')` and `col_is_null`.
2. `has_column('sessions','squad_swaps')` and `col_is_null`.
3. As lifter A: an own-row `self_swaps` UPDATE **succeeds** — and, in a second statement, the row reads
   back what was written (constraint 17: never assert an effect inside the modifying statement).
4. As lifter B: an UPDATE of A's `self_swaps` **affects zero rows** (RLS, not an exception).
5. As a participant: a direct `UPDATE sessions SET squad_swaps = …` **raises `P0001`**
   (`throws_ok`), naming the guard.
6. As a participant: `apply_squad_swap(...)` **succeeds** and, in a second statement, `squad_swaps` holds
   the merged key.
7. As a non-participant: `apply_squad_swap(...)` **raises `P0001`**.
8. `apply_squad_swap` with an unknown replacement id **raises `P0001`**.
9. **Decision 1's walk, pinned:** insert a `scheduled_for IS NULL`, `style = 'freestyle'`,
   `state = 'in_progress'`, `lifting_started_at IS NULL` session with a `check_in_state = 'ready'`
   participant row, then take a `self_swaps`-only UPDATE on it — **passes** with `engine_guard` and
   `checkin_window_guard` both live. This is the assertion that stops a future guard change breaking the
   ad-hoc path silently.

**Done when:** pushed. Its proof is a green `backend.yml`.

### D3 — a logged set records its routine slot — **S** · Sonnet

**File (new):** `supabase/migrations/20260919000102_set_logs_routine_slot.sql`

Decision 3. Header first: why the column exists (three things it makes honest, named); why there is **no
foreign key** (routine rows are deleted on edit; a logged set is history); why there is **no backfill**
(a pre-column row genuinely does not know its slot, and inventing one would be a fabricated attribution —
the per-id fallback is the honest reading for those rows and it ships in the same window, S2); and that a
freeform workout writes NULL forever, by design.

```sql
ALTER TABLE public.set_logs
  ADD COLUMN IF NOT EXISTS routine_exercise_id uuid;

CREATE INDEX IF NOT EXISTS set_logs_session_slot_idx
  ON public.set_logs(session_id, routine_exercise_id)
  WHERE routine_exercise_id IS NOT NULL;
```

No policy change: the three shipped `set_logs` policies have no column list
(`20260709000007:26-38`), so a lifter writing their own row may already write this column. Say so in the
header rather than adding a fourth policy that grants nothing.

**Done when:** committed, **not applied**. **Stop and hand back.**

### D4 — pgTAP for the slot column — **S** · Sonnet · **needs D3 applied**

**File (new):** `supabase/tests/set_logs_routine_slot_test.sql`. Fixture block **`18xx`**.

1. `has_column`, `col_is_null`, `col_type_is('uuid')`.
2. `has_index('public','set_logs','set_logs_session_slot_idx')`.
3. As the owner: an insert **with** `routine_exercise_id` succeeds; read it back in a second statement.
4. As the owner: an insert **without** it succeeds and reads back NULL — the pre-column shape still
   works, which is what "no backfill" costs.
5. As another lifter: an insert naming someone else's `user_id` is refused by the existing INSERT policy
   — pinned so the new column cannot be read as a new door.
6. **No FK:** `hasnt_fk('public','set_logs')` is too broad (the table has three); assert instead that
   deleting a `routine_exercises` row leaves its `set_logs` rows in place, in a second statement.

**Done when:** pushed. Its proof is a green `backend.yml`.

---

# STREAM S — the app

Six tasks, one worker at a time, in number order (constraint 2).

### S1 — the durable, slot-keyed swap layer — **L** · Opus · **needs D1 applied**

**Files (new):** `Models/SessionSwapLayer.swift`, `GymSyncTests/SessionSwapLayerTests.swift`.
**Files (modified):** `Models/RoutineLayering.swift`, `GymSyncTests/RoutineLayeringTests.swift`,
`Features/Sessions/Live/SessionLiveView.swift`, `Features/Workout/WorkoutSessionView.swift`,
`App/AppState.swift`, `Services/SessionBroadcastService.swift`.

Decision 2, and this task is the **prerequisite** the whole phase hangs off. **Read
`.superpowers/sdd/2026-09-19-group-session-phase-c/debug-swap-state.md` in full before writing a line**;
it is the evidenced root cause with file:line throughout. If `hotfix-report.md` exists beside it, read
that too — the hotfix may already have landed H2's pure cursor function and H6's `RoutineLayering.swapped`
extension, and this task **verifies rather than assumes** which of them is already in the tree.

1. **`SessionSwapLayer`** — a value type over `[slotID: replacementExerciseID]`, i.e. `[UUID: UUID]` keyed
   by **routine-exercise row id**, with a codec that treats `NULL` and `{}` identically, ignores an
   unknown slot id, and round-trips. **The in-memory shapes it backs are not `[UUID: UUID]` and the
   report must not pretend they are**: `selfScales` is `[userID: [exerciseID: SwapTarget]]`
   (`SessionLiveView.swift:344-345`) and `squadSwaps` is `[exerciseID: SwapTarget]` (`:346-347`), where
   `SwapTarget` (`:336`) carries the replacement's **name** for the consent card's wording.
   `effectiveRoutineExercises` (`:620-626`) already maps them down with `.mapValues(\.id)` before calling
   `RoutineLayering.apply`. So S1 re-keys the **inner** dictionary from `exerciseID` to slot id in both,
   keeps `SwapTarget` and keeps `selfScales`' per-user outer key (the crew reads other members' scales on
   the station card), and persists only the mapped-down `[slotID: UUID]` — the name is re-resolved from
   the exercise catalog on load, because a name cached in a row goes stale and a swap's truth is the id.
   Plus
   `SessionSwapRepository`: `loadSelf(sessionID:)` / `saveSelf(sessionID:layer:)` (own-row PATCH on
   `session_participants.self_swaps`) and `applySquad(sessionID:slotID:replacementID:)` (the RPC), each
   mapping `P0001` to a readable error through the shipped `ErrorMapping`.
2. **`RoutineLayering.apply` re-keyed.** `squadSwaps` and `selfScale` become `[slotID: replacementID]`
   and are looked up by `re.id`, not `re.exerciseID` (`RoutineLayering.swift:80-82`). `todaysScale`
   **keeps** its `exerciseID` keying — decision 2's last paragraph, and the function's own header
   (`:14-18`) already explains why. Update every caller:
   `SessionLiveView.effectiveRoutineExercises` (`:620-626`),
   `SessionRunnerView.planRows` (`:249-256`), `SessionLiveView.swapDoorDetails`, and
   `WarmUpReadinessTests`' call.
3. **The durable row becomes the truth.** `SessionLiveView`'s `selfScales` and `squadSwaps` stay as the
   in-memory cache the body renders from, but they are **seeded from the repository in `reload()`** and
   **written through on every change** — the broadcast (`chooseSwap` → `sendSwap`, `:3508-3522`;
   `receiveSwap`, `:3392-3432`) stays exactly as it is and becomes a *nudge*, not the source. Add one
   optional `routineExerciseID` to `SwapEvent` (`SessionBroadcastService.swift:52-60`), decoded if
   present, so an installed build's old-shape event still applies by exercise id (decision 2).
4. **`WorkoutSessionView` points at the same repository** — `soloSwapOverrides` (`:290`) seeded from and
   written to `self_swaps` — and its inline swapped-row rebuild (`:1193-1200`) becomes
   `RoutineLayering.swapped` if the hotfix has not already made it so.
5. **Delete the hotfix stopgap**: the `AppState.LiveSoloSession` swap/rest mirror fields (H1). Name them
   in the report by what is actually in the tree.

**Tests (pure):** the codec round-trip; the empty layer; an unknown slot id ignored; **two slots naming
one exercise id, one swapped — only that slot changes** (the case the old keying got wrong);
`RoutineLayering.apply`'s three-layer order re-asserted against slot ids.

**Constraint 22 applies**: nothing new goes inline into `SessionLiveView.body`.

**Its review answers the seam question in writing** (see Sequencing): the RPC's signature and parameter
names as PostgREST sends them, the JSON shape, the `P0001` behaviour, and **which symbol reads the
durable row**.

**Done when:** pushed, with a report that greps the call site of every new symbol.

### S2 — set attribution by slot — **L** · Opus · **needs D3 applied**

**Files (new):** `GymSyncTests/RoutineSlotProgressTests.swift`.
**Files (modified):** `Models/SetLog.swift`, `Models/RoutineProgression.swift`,
`Models/SessionRepository.swift`, `Features/Sessions/Live/SessionLiveView.swift`,
`Features/Workout/WorkoutSessionView.swift`.

Decision 3.

1. `SetLog` gains `var routineExerciseID: UUID? = nil` and its `CodingKey`
   (`routine_exercise_id`). The trailing default keeps every construction site compiling — the same
   idiom `bodyWeightLbs` used (`SetLog.swift:16-22`).
2. **Both insert paths stamp it**: `SessionLiveView.logSetAndAdvance(...)` (`:4559-4896`) from the slot
   `currentExerciseForSheet` resolved, and `WorkoutSessionView.log(...)` (`:3810-4149`) from
   `currentRoutineExercise?.id`. **Freeform writes NULL.** `SessionRepository.logSet` is unchanged — the
   field rides on the value.
3. **`RoutineProgression` gains a slot-keyed sibling** taking `completedSets: (RoutineExercise) -> Int`
   so the caller can apply decision 3's fallback rule. The `exerciseID` spelling stays, with a doc
   comment naming it the pre-column fallback rather than a duplicate.
4. **Every cursor reader re-pointed**, and the ones deliberately *not* re-pointed named in the report —
   decision 3 lists both sets. `OfflineSetLogQueue`'s enqueued value carries the field too (it encodes a
   `SetLog`); verify its codec and say so.

**Tests (pure), and they must fail on today's logic:** the root-cause report's case —
`[A(3), C(3)]`, slot A swapped to B, logs `3×B + 2×C` → `(index 1, set 3)`, today `(0, 1)`; a no-swap
session byte-identical to today; a swap with no sets yet showing the substitute; **two slots naming one
lift, three sets on the first — the second still shows 0**; an all-NULL (pre-column) session identical to
today.

**Its review answers constraint 21 in writing**: `LogFollowUp.calls(for:)`, `commitInlineLog`,
`prefillLogInputs`, `turnEntryCard` — named, with their bodies unchanged in the diff.

**Done when:** pushed.

### S3 — the ad-hoc start, and the four entry points — **L** · Opus

**Files (modified):** `Models/SessionRepository.swift`, `Features/Home/HomeView.swift`,
`App/RootView.swift`, `Features/Library/RoutinesListView.swift`,
`Features/Library/DiscoverWorkoutDetailView.swift`.

Decision 1 and decision 6.

1. **`startSolo` chooses the style honestly**: `style: .freestyle` on the inserted row (the struct literal
   at `SessionRepository.swift:26-40` gains it). Everything else about the insert is unchanged —
   `state: "in_progress"`, `scheduled_for: nil`, `lifting_started_at` unset, the participant row at
   `check_in_state: "ready"`. The doc comment states decision 1's guard walk so the next reader does not
   re-derive it.
2. **The four production call sites of `WorkoutSessionView` become `SessionEntryView(session:)`**, each
   starting the session first and presenting the entry view with the returned row:
   `HomeView.swift:2208-2217` (the picker's chosen or nil routine — `routine: nil` is the freeform path,
   which still creates a normal row with `routine_id` NULL); `RoutinesListView.swift:339-342`;
   `DiscoverWorkoutDetailView.swift:186-192` (keeping the `attemptOptIn` →
   `PublicWorkoutRepository.startAttempt` call after creation, `:173-184`); `RootView.swift:461-469`
   (resume). **`CatalogHostView.swift:1948-1952` is NOT re-pointed** — `solo-live-set` still photographs
   the old view, which still ships (constraint 7).
3. **The presentation**: `.fullScreenCover` replaces the sheet-plus-push at `HomeView.swift:280-282` /
   `:2207-2218` and at `RootView.swift:461-469`. The MINIMISE control itself is **S4's** — S3 leaves the
   cover dismissible only through it, so the two tasks must not be reordered.
4. **`liveForCurrentUser` stops excluding solo** (`:528-531`), so Home's live pill routes an ad-hoc
   session through `SessionEntryView` like any other.

**No new RPC, no new state, no engine change** (constraint 20). The report states, from reading, that
`SessionRunnerView` needed no edit and why.

**Done when:** pushed. **This is the first commit at which an ad-hoc workout runs in the one body**, and
the report says so plainly.

### S4 — the solo shape of the one body — **M** · Opus

**Files (new):** `Features/Sessions/Live/SoloSessionLayer.swift`,
`GymSyncTests/SoloSessionShapeTests.swift`.
**Files (modified):** `Features/Sessions/Live/SessionLiveView.swift`,
`Features/Sessions/Live/RoundPieces.swift`.

The brief's item 7, answered from the code rather than assumed. **What the one body already hides for a
one-person roster** (context map §5, re-verified): burpee debt, the held-lifter screen and the crew-swap
consent screen each require ≥ 2 participants in their own predicate; `logControlIsMine` is unconditional
for `.freestyle`; `roundWaitPage`/`spotterPage` are `.rounds`-only and unreachable. **What still leaks,
and what this task fixes:**

1. **The rotation strip** (`RoundPieces.TurnStrip`) renders a strip of one for a one-person roster — the
   map flagged this as an untested assumption; S4 verifies it by reading and, if it renders, gates it on
   `rosterCount > 1`.
2. **The voice dock / mic rail** (`turnMicRail`, `joinVoiceIfEligible`, `voiceMixerSheet`, `chatSheet`,
   `:472-529`, `:2849-2916`) is **not solo-gated at all**. An ad-hoc lifter must never see a talk dock.
   Gate on `rosterCount > 1` — and on nothing else, so a scheduled solo session gets the same treatment,
   which is correct.
3. **Presence / roster count** (`:1028`) and any "waiting on" line: hidden for a one-person roster.
4. **`SoloSessionShape.isAdHocSolo(participantCount:roomCode:scheduledFor:)`** — a pure predicate, tested
   on every branch, so the gates above are one law rather than four inline conditions. It reuses
   `SessionShape.isSolo` and adds the ad-hoc discriminator (`scheduledFor == nil`).
5. **`SoloSessionLayer`** carries decision 6's MINIMISE control and every modifier this task adds —
   constraint 22 forbids inlining them in `body`.

**Nothing here touches the heart-rate slot.** The owner's note that HR is "pretty useless" on the logging
screen is design backlog; S4 neither removes it nor builds anything into that corner that would make it
harder to repurpose (the directive's last line).

**Done when:** pushed.

### S5 — the resume path and the live pill — **S** · Sonnet

**Files (modified):** `App/RootView.swift`, `Features/Home/HomeView.swift`, `App/AppState.swift`.

The tail of decision 6, mechanical from S3's shape. The SESSION LIVE pill's copy and its doc comment
(`RootView.swift:431-433`, `:504`) stop describing an orphaned session and describe a minimised one.
`AppState.liveSoloSession` is **not deleted** (the old view still reads it, constraint 9) but is no
longer the resume mechanism; its doc comment says so and names C2.

**Done when:** pushed.

### S6 — three proof frames — **M** · Sonnet

**Files (modified):** `Features/Sessions/Live/LiveFixtures.swift`, `App/CatalogHostView.swift`,
`GymSyncTests/CatalogScreenTests.swift`, `GymSyncUITests/ScreenshotTests.swift`,
`docs/design/frame-map.json`.

The three ids above, **each in one commit across all four places** (constraint 6) — or three commits, one
per id, which is the safer reading of the same rule; do not split an id across commits.

Each arm builds `SessionLiveView(catalog:)` (the existing `#if DEBUG` fixture initializer,
`SessionLiveView.swift:95-127`) over a new one-participant `.freestyle` world in `LiveFixtures`. Every
date is built from components; no repository, no `Date()`, no `.shared` (constraint 11). Verify by
reading that no catalog path reaches `WatchConnectivityBridge.activateIfNeeded()`,
`HeartRateBroadcastService`, the voice room or `LiveSessionTimerStore` — the last is already
`catalogSkipLoad`-guarded at `:2168-2190` and `:3107`.

**Its proof is a green screenshots job, not a green `build-test`** (constraint 19).

**Done when:** pushed, and the controller has re-run the screenshots job.

---

# INTEGRATION

### I1 — the FLOOR, the frame-map and the accepted deviations — **S** · Sonnet

Re-derive the FLOOR literal by counting the exported files in the last green `app-screenshots` artifact
(downloaded into a **fresh** directory) and set `.github/workflows/ios.yml:462` once. Expected `138`
(`135 + 3`); if the count disagrees, the count wins and the report says why. Append this round's entries
to `docs/design/accepted-deviations.json`. Confirm `CatalogScreen` cases == `CatalogScreenTests` ids ==
116 and that `frame-map.json` has no duplicate frame numbers.

### I2 — end-to-end CI, then by eye — **M** · controller

Green `build-test`, `backend.yml` and `screenshots`. Then, into a fresh directory, diff
`app-session-warmup-solo`, `app-session-your-turn`, `app-session-scale-down` and `app-solo-live-set`
against master's latest run **with the status bar masked** — all four must be byte-identical
(constraint 14 and the "best proofs" note). Compose **one** proof card carrying frames 155, 156 and 157.

**And write the owner's manual TestFlight script** — decision 5's three-row table, verbatim, as steps:
swap mid-exercise and swipe down; lock with a rest running; force-quit and reopen. **The script states
the documented limit** (a rest window does not survive a relaunch) so the owner does not report it as a
regression.

### I3 — one PR, with proof cards — **M** · controller

One PR to master from `feat/group-session-phase-c`, body naming: the three decisions that changed the
data model, the FLOOR delta (`135 → 138`), the migrations with their applied timestamps, the two spec
corrections below, and **what C1 deliberately did not do** — nothing is deleted, `solo-live-set` still
ships, and `WorkoutSessionView` is still the view four entry points *used* to open. Merge on green after
review, per the repo's standing permission.

---

## C2 — the outline

C2 is a separate plan on its own branch, written after C1 merges. It moves the remaining capabilities and
**deletes both files**. Its shape, so C1's tasks know what they are handing over:

| # | task | size · model | notes |
|---|---|---|---|
| C2-S1 | **Mid-session routine editing, solo-only** — `SessionRoutineEditor` moves into the one body behind `SoloSessionShape.isAdHocSolo`; the three-way persist (`persistSessionEdits(asNew:)`, `applyCoachRoutineEdit`) comes with it; the freeform ("empty") workout is its degenerate case | L · Opus | decision 7. **Crews keep the consent card** (§3.4) — the editor is never offered to a crew |
| C2-S2 | **`FormClipCapture` moves**, solo-only and unchanged (`canRetainClips`, `pendingClipURL`, `SetLogClip`) | M · Sonnet | decision: **not** offered in crew sessions; a crew's set is not a private form review |
| C2-S3 | **The swap door opens during any rest** (the owner's B3) — the transit-only gate (`WorkoutSessionView.swift:1616`) does not survive the move, because slot attribution (C1 S2) makes a mid-exercise swap countable | S · Sonnet | this is the payoff of C1's D3 |
| C2-S4 | **Coach's solo hooks** — `coachProfile`, `showCoachRecap`, `prefetchCoachContext`, `coachPendingProbe`, `soloCoachDecision` (`BlockProgression`) join the one body's `groupCoachProfile`/`turnCoachDecision`/`openCoachThread`; **solo gains Coach's door**, which it has never had | L · Opus | |
| C2-S5 | **Finish, recap, Pump post, discard** — the two `endSession`/`buildPostSummary` paths converge on the one body's `presentCompletion`; solo gains the explicit `leaveSession()`/`exitToHome()` it never had; HealthKit export stays at its one call site | L · Opus | the recap's volume is already correct after C1 S2 |
| C2-S6 | **The duplicated log path is deleted** — `soloPrefill`, `soloEntryCard`, the solo bar-loader pair, the second `isLoggingSet`, `log(...)` | M · Opus | a deletion, not a rewrite (decision 4) |
| C2-S7 | **Both views are deleted** — `WorkoutSessionView.swift`, `WarmUpPhaseView.swift`, `AppState.LiveSoloSession`, `solo-live-set` (id, case, builder, test id, capture, frame 66) in one commit; `SessionRoutineEditor.swift` and `FormClipCapture.swift` move to `Features/Sessions/` | L · Opus | FLOOR **−1** |

**The capability ledger — every row in the map's inventory, with its verdict.** Nothing disappears
silently.

| capability | verdict |
|---|---|
| Rest timer between own sets | **already there** — `selfRotationRest*` + `LiveSessionTimerStore` (decision 5); solo's `soloRestIsTransit` semantics survive as the store's `restIsTransit` |
| Warm-up phase | **already there** — `WarmUpScreen`, DB-gated; solo's client-only `SoloWarmupStore` timer **retires**, reason: the DB gate is the honest one and the countdown was recomputed from `startedAt` anyway |
| Warm-up **sets** (a per-set flag) | **absent in both** — not a gap, not built |
| Add exercise mid-session (freeform) | **moves** — C2-S1 |
| Reorder / remove, full routine rebuild | **moves, solo-only** — C2-S1 |
| Swap one exercise | **moves and improves** — durable + slot-keyed (C1 S1), searchable (the hotfix), any-rest (C2-S3) |
| Supersets | **already there** — `RoutineLayering` + `RoutineProgression`'s pair handling; solo's `supersetPartnerIndex` **retires** as a duplicate |
| Plate math / bar loader | **already there** — `turnBarCard`/`turnLoaderExpanded`; solo's pair **retires** as a duplicate |
| Notes on a set | **already there, equally absent on both** — neither entry card renders a free-text field; the edit-existing-log sheet is the only door, and it moves with the log path |
| RPE, failed set | **already there** — `RPESwipeTrack`, identical shared component |
| Penalty / burpee-debt sets | **already there, crew-only** — no solo equivalent needed (no crew accountability for a lifter alone) |
| PR detection + `PRFiring` | **already there** — both routed through `PRFiring.shouldCelebrate` by the owner-decisions round; solo's parallel plumbing **retires** |
| Watch + heart rate | **already there and better** — both funnel through the same `WatchSessionStatePayload`; the one body's `isMyTurn` is real where solo hardcoded `true` |
| HealthKit export | **already there** — same bridge, same call site at session end |
| Live Activity / ActivityKit | **absent in both** — not a gap, not built (functional audit §D: cannot determine whether ever wanted) |
| Music / audio | **already there** — `CelebrationSound` only, in both |
| Video form clip | **moves, solo-only** — C2-S2 |
| Voice (PTT) / chat | **crew-only, gated off for solo** — C1 S4 |
| Finish + recap + Pump post | **moves** — C2-S5 |
| Discard / abandon | **solo gains it** — C2-S5 |
| Resume after relaunch | **already there** — C1 S3/S5: the live pill routes through `SessionEntryView` like any other session |
| Metrics sheet | **already there** — both feed the same `WorkoutMetricsSheet` through `PostSummary`/`PumpCheckContext` |
| Coach hooks | **moves, and solo gains Coach's door** — C2-S4 |
| Substitution graph | **already there** — same `ExerciseSubstitutionRepository` call feeds both swap pickers; solo's automatic "stall note" (`soloStallSwapName`) **retires**, reason: it was a solo-only affordance with no crew equivalent and no owner request; if the owner misses it, it returns as its own item |

---

## What this plan does not decide

1. **Whether the crew ever gets a session-local routine editor.** §3.4 makes the consent card the crew's
   mode of exercise change; C2-S1 moves the editor for SOLO sessions only. A crew editor would route
   around unanimity and is not proposed.
2. **Whether `FormClipCapture` is ever offered in a crew session.** Default and decision: solo only,
   unchanged. A crew's set is not a private form review.
3. **The design of the your-turn logging screen, the You page, the Trainer page or the PR celebration.**
   The owner deferred all four to the design pass, and frames 151/152 stay live for it.
4. **Where heart rate belongs on the logging screen.** Design backlog. C1 neither moves it nor builds
   into that corner.
5. **The lock-screen leg of the owner's rest-timer report.** Two candidates, neither proven
   (`debug-swap-state.md` §2). C1 adds no speculative `scenePhase` handler; I2's manual script is what
   separates them.
6. **Repairing sessions already double-logged.** No backfill, no repair migration. Decision 3's
   no-backfill stance is about *new* correctness, not history.
7. **Together's interval editor** (functional audit §A2) — a real gap, a separate item, not Phase C's.
8. **Whether `set_logs` should carry a routine id as well as a slot id.** The slot id is sufficient for
   every reader C1 and C2 have; a routine id would be a second denormalisation with no caller.
9. **The `cue` lever's render site, the Watch's missing notification code, the stale tour copy, the
   fixed-190 HR zone ceiling and the absent privacy manifest** (functional audit §B) — real, docketed,
   none of them Phase C's.

---

## Self-review (run by the planner, 2026-09-18)

**Verified against the code at `d74d95a`, not against the map:** the FLOOR (135, `ios.yml:462`), the
frame counts (92 entries, max 154), the catalog counts (113 cases, 111 real captures), both file sizes
(4,443 / 5,501), `sessions.style`'s default and CHECK, `WarmUpGate.isWarmingUp`'s exact predicate,
`SessionRouter.route`'s ordering, `startSolo`'s full struct literal, the `set_logs` schema and its three
policies, `checkin_window_guard`'s fail-open branch, `session_round_guard`'s three clauses,
`session_venue_insert_guard`, `RoutineLayering.apply`'s keying, `RoutineProgression.currentExercise`'s
counting, `LiveSessionTimerStore`'s memory-only comment and its two call sites, `SwapEvent`'s seven
fields, the `todays_scale` no-new-policy reasoning, the four `WorkoutSessionView` production call sites,
the single `WarmUpPhaseView` call site, and the pgTAP namespaces in use.

**Spec corrections — the map and the root-cause report are each wrong in one place that matters:**

1. **`WarmUpPhaseView` is solo-only in practice.** The context map (§6) flagged the crew caller as
   unverified and asked for confirmation. Confirmed: `grep -rn 'WarmUpPhaseView('` over
   `GymSyncApp/GymSync` returns **exactly one** hit, `WorkoutSessionView.swift:1292`. The crew warm-up
   routes through `WarmUpScreen`. **Consequence:** the brief's "the ad-hoc warm-up adopts the shared
   warm-up screen" is a *deletion plus a route*, not a merge of two callers — and it needs **no new
   catalog frame**, because `session-warmup-solo` already photographs the screen an ad-hoc session will
   use.
2. **The one body's rest window is already durable across a sheet dismissal.**
   `debug-swap-state.md` §6 reports it as "SAME CLASS … `reload()` does not restore them."
   `restoreTimersFromStore()` (`SessionLiveView.swift:3101-3125`), called from `.onAppear` (`:2192-2196`),
   re-seeds it from `LiveSessionTimerStore` **and re-arms the lapse `Task`**, and `.onChange(of:
   selfRotationRestUntil)` (`:2168-2184`) writes it. The store is **memory-only**, so a relaunch still
   loses it. **Consequence:** adopting the one body fixes the fully-evidenced leg of B4-rest by
   construction; C1 needs **no rest-persistence task**, and the relaunch limit is stated honestly in
   decision 5 and in the owner's manual script rather than quietly fixed or quietly claimed.
3. **The data-model seam is narrower than the map called it.** The map (§8) called the
   `lifting_started_at` gate "the sharpest data-model seam in the whole adoption" and offered two
   options: make `startSolo` stamp it, or special-case the gate. **Neither is needed.** An ad-hoc row is
   already `isWarmingUp`, so it already routes to the warm-up screen, and `start_lifting` already moves
   it on. The real seam was the **style default** (`'rounds'`), which the map did not name.

**The riskiest assumptions, named rather than buried:**

- **A1 — `.freestyle` is the right body for a solo lifter.** It is the style with no rotation and no
  round engine, which is why it is chosen; but its rail was designed for a crew going at their own pace,
  and S6's frame 155 is the first time anyone will look at it with a roster of one. If the owner rejects
  the shape, that is a **design-pass** item, not a C1 rework — the data model does not change.
- **A2 — re-keying `RoutineLayering.apply` from exercise id to slot id is behaviour-preserving for every
  routine that names each lift once.** Every routine in the fixtures does. A routine that names one lift
  twice **changes behaviour**, and that change is the fix. S1's test pins both halves.
- **A3 — the crew's `squad_swaps` guard clause does not break an existing write.** `sessions` UPDATEs
  today come from `start_session`, `start_lifting`, `advance_round`, `set_session_stations`,
  `claim_session_venue` (all engine-GUC) and `complete` (which touches `state`/`completed_at` only). The
  clause is `IS DISTINCT FROM`, so an UPDATE that does not name the column passes. D2 pins it; if a
  seventh writer exists, `backend.yml` finds it on the gate.
- **A4 — the hotfix merges before S1.** If it does not, S1 must do H6's `RoutineLayering.swapped`
  extension itself and the stopgap deletion becomes a no-op. S1 **reads the tree** rather than assuming
  either way, and says which in its report.
- **A5 — no reader of `set_logs` outside the ones named in decision 3 needs the slot.** The edge
  functions and the PR trigger (`20260709000009`) read `exercise_id`; D4 does not assert over them. If a
  reader is found later, adding it is additive.
- **A6 — C1 is six app tasks because C2 carries seven.** If a C1 task discovers that a C2 capability
  blocks the adoption (most likely candidate: the freeform path, which S3 touches at
  `HomeView.swift:2208` and C2-S1 owns), the controller promotes that one task into C1 rather than
  letting S3 half-build it.
