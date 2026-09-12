# The crew lobby and the shared warm-up — Phase A — implementation plan

**For agentic workers.** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Every task below is
one subagent, one commit, one review. Do not batch tasks; do not start a Stream S task before the Stream D
gate it names has been applied to the live project.

**Goal.** De-furnish the crew lobby into the composition the owner approved — an arrival track that IS the
readiness signal, one Coach door, the whole session plan, how the crew feels, the dock, Start — and give
solo and crew **one warm-up screen** instead of a minutes stepper in the lobby and a vote page buried in
`GroupSessionLiveView`. Ship, with it, the one shipped behaviour the suggestion principle forbids: the
block ladder stops re-laddering itself on the first Home load of a week and asks.

**Architecture.** Three moves, in this order of dependence:

1. **The lobby becomes a crew screen.** Today one `LobbyView` (2,098 lines) serves scheduled solo and crew
   alike, so a lifter training alone reads WHO'S HERE and a talk dock. Phase A splits the entry: a thin
   `SessionEntryView` decides, from the session's **shape** (participant count + room code — never
   `group_id`, which `.friends` and `.code` sessions also leave nil, `ScheduleSessionView.swift:778-786`),
   whether the next screen is the lobby or the warm-up screen.
2. **Warm-up becomes one screen with two frames.** `mark_warmup_ready` / `start_lifting`
   (`20260803000004_session_warmup_phase.sql:44,105`) already model the hand-off exactly and are untouched;
   what changes is where the screen lives. A new `SessionRunnerView` renders the warm-up screen while
   `state == 'in_progress' AND lifting_started_at IS NULL`, then the live view — so `GroupSessionLiveView`
   loses its `isInWarmUp` branch and gains nothing.
3. **The crew's energy and the crew's Coach thread are the two new facts**, and they need opposite amounts
   of backend. `session_participants` already lets a participant write their own row and every crewmate
   read it (`20260712000001_sessions_phase3_columns.sql:22-25`, `20260726000001…:182-187`), so energy is one
   column and **no new policy**. The Coach thread is the reverse: `coach_chat_threads` is single-owner
   (`20260824000005_coach_chat_threads.sql:19-23`) with no subject key at all, so a session thread needs a
   column, two read policies and a **server-evaluated** Pro gate — a client-side "is anyone Pro" cannot see
   another athlete's `pro_until` (`20260730000004_pro_entitlement.sql:21-22`).

**Tech stack.** Swift 6 / SwiftUI (iOS 18 target), Supabase Postgres + PostgREST + RLS, pgTAP, XCTest +
XCUITest, GitHub Actions (`ios.yml`, `backend.yml`), XcodeGen (`project.yml`).

**Spec (the authority):** `docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md`. **Sections
§1, §2, §3.1, §3.2, §3.6, §4, §4a, §5, §6, §7 and §8 items 2 and 4 bind this plan**; §3.3, §3.4, §3.5 and
§9a are Phase B and are quoted here only where Phase A must not foreclose them. All twenty owner decisions
bind; decisions **3, 5, 12, 16, 18, 19, 20** are the ones this plan builds, decision **4** is the one it
fixes. Gate documents: the design language (`docs/superpowers/specs/2026-09-05-design-language.md`) and the
goal-first programming spec (`docs/superpowers/specs/2026-09-07-goal-first-programming-design.md` — the plan
card and the ladder read its objects). Round artefacts with file:line facts:
`.superpowers/sdd/2026-09-12-lobby-round/context-map.md` (405 lines) and `report-design-round.md`.
Format exemplars (the shape this plan copies): `docs/superpowers/plans/2026-09-11-social-cards-plan.md` and
`docs/superpowers/plans/2026-09-06-design-congruence-plan.md`.

**The reference frames.** The production lobby and warm-up are built to four catalog frames from the design
round, on branch `feat/session-variations` (worktree `G:/Projects/GymSync-wt/wt-session-variations`, folder
`GymSyncApp/GymSync/Features/Sessions/Variations/`):

| frame | id | file | what production copies |
|---|---|---|---|
| 120 | `lobby-crew-waiting-v2` | `LobbyVariationsV2.swift` | the waiting lobby: track, plan, energy, Coach, dock, Start |
| 127 | `lobby-crew-ready-v3` | `SessionVariationsV3.swift` | the all-ready lobby: the track IS the primary |
| 122 | `warmup-solo-v2` | `WarmupVariationsV2.swift` | the solo warm-up: plan + suggestion, ladder, clock, Start lifting |
| 111 | `warmup-crew` | `WarmupVariations.swift` | the crew warm-up: readiness row, private Coach line, dock, leader's note |

**Production code must not import, reference or `#if DEBUG`-depend on the `Variations/` folder.** Every SV\*
type there is a DEBUG-only catalog fixture. Task S4 builds the production components from the same shipped
primitives the SV\* wrappers use — `GSInitialsAvatar` (`SocialTabView.swift:711`, and it already takes
`fill:`/`ink:`), `GSSectionHeader`, `GSDivider`, `GSTag`, `.gs3DCard(cornerRadius:lipHeight:)`,
`.gs3DCardStyle(cornerRadius:lipHeight:face:)` (`GS3DButton.swift:215-221`), `GSPrimaryButtonStyle`,
`PTTDockRow`, `Color.gsSuccess`, `GSMetrics.radiusMd`/`radiusSm`, `GSFont` — so the SV\* file is the
drawing, never the dependency.

---

## Base branch — read this first

**This plan forks from `origin/master` AFTER `feat/session-variations` has merged.** That branch is the
design round's proof deck (23 catalog ids, frames 106-128, `FLOOR=137`) and at the time of writing it is
**not merged**: `git branch --merged master --list "*variation*"` returns only `feat/home-v3-variations`, and
`git rev-list --left-right --count master...feat/session-variations` reads `2  6`. The precedent it follows
is `feat/home-v3-variations`, which merged (`e06b709`) and whose ten variation ids were later retired by the
production work that replaced them.

**Verify before the first commit**, against `origin/master`, never a local `master` ref — the Home v3 plan
lost a day to exactly that:

```
git fetch origin
git log origin/master --oneline | grep -i session-variations   # must print the merge commit
grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1           # expect FLOOR=137
python -c "import json;d=json.load(open('docs/design/frame-map.json'));print(len(d), max(v['frame'] for v in d.values()))"
                                                               # expect 93 128
```

| | Stream D and Stream S, from the merge |
|---|---|
| base | `origin/master`, with `feat/session-variations` in |
| `FLOOR` in `ios.yml` | **137** |
| frames taken | 1-128 |
| next free frame | **129** |
| `CatalogScreen` cases | 115 (92 + the round's 23) |
| `Features/Sessions/Variations/` | present, DEBUG-only, 14 files |
| `session_participants.energy` | absent until D1 is applied |
| `coach_chat_threads.session_id` | absent until D3 is applied |

**If the controller decides `feat/session-variations` will NOT merge**, this plan still runs: task S11's
retirement half becomes a no-op (there is nothing to retire), and the FLOOR delta changes from **−4** to
**+6**. Nothing else in any task body changes. **I1 computes the delta from what is actually on the
integration base**, which is why the FLOOR is written as an invariant everywhere and as a literal nowhere.

---

## Global Constraints

These bind **every** task. A task that breaks one says so in its commit body, and why.

1. **One release branch, `feat/group-session-phase-a`, and this plan is its first commit.** Fork it from
   `origin/master` (verified above), commit this file, push. Every task below lands on that branch. One PR
   at the end (I3).

2. **Two streams, and only because their files are disjoint by path.**
   - **Stream D** touches `supabase/migrations/**` and `supabase/tests/**` and nothing else.
   - **Stream S** touches `GymSyncApp/**`, `docs/design/**` and `.github/workflows/ios.yml` and nothing else.

   There is **no third stream.** The re-ladder work (S1, S2) would be a natural parallel stream — it touches
   no session file — except that it edits `GymSyncApp/GymSync/Features/Home/HomeView.swift`, which task S10
   also edits (`:353`, the lobby destination). Two workers on one file is the gamble this rule exists to
   forbid, so **S1-S11 run sequentially, in number order, by one worker.** Stream D may run beside them
   throughout, subject to constraint 8's gates.

3. **Swift compiles only in CI.** No macOS toolchain on this machine: no `xcodebuild`, no `swift build`, no
   simulator. Read the code you are changing in full, reason about the types, push.
   `.github/workflows/ios.yml` is the compiler.

4. **Implementers do not wait on CI.** Push and hand the task back. **The controller monitors the run** and
   opens a fix task if it is red. An implementer sitting on a run is an implementer not writing the next
   task.

5. **One commit per task**, with this trailer, verbatim:
   ```
   Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
   ```
   Use `git commit -F <file>` or a single-quoted heredoc. A `-m` message containing backticked identifiers
   has silently deleted words in this repo before.

6. **The catalog four-part contract, in ONE commit per id.** A new `CatalogScreen` id lands in all four
   places in the *same* commit:
   - the `case` in `App/CatalogHostView.swift`'s `enum CatalogScreen` (`:16-136` on master, wider after the
     variations merge) **and** its builder arm in the same file's `switch` (`:144-237`);
   - the id string in `GymSyncTests/CatalogScreenTests.swift`'s `ids` array — `:112` asserts
     `CatalogScreen.allCases.count == ids.count`, so a case without a list entry fails the build, and `:117`
     asserts the raw values are unique;
   - a `func testCatalog…() { captureCatalog("<id>") }` in `GymSyncUITests/ScreenshotTests.swift` (helper at
     `:403-436`);
   - an entry in `docs/design/frame-map.json` (`"<id>": {"frame": <n>, "title": "<title>"}`).

   **And the same contract in reverse for a retirement**: the `case`, the builder arm **and the view struct
   it renders**, the id string, the capture method, and the frame-map entry all leave in one commit. A
   retired frame number is **never reused** — the next production id takes the next free number.

7. **The FLOOR is `+N over master's FLOOR at integration`, never a literal.** It is a minimum
   (`ios.yml:405` — `if [ "$COUNT" -lt "$FLOOR" ]`), so a branch that adds captures stays green against the
   old floor and only I1 moves it. **This plan's N is negative** (six production captures in, ten
   design-round captures out), which is the one case where the floor must move or CI stops noticing a
   degraded suite: a floor left at 137 against 133 real captures fails every run. **I1 computes N from the
   integration base** and writes the arithmetic into the comment block above the line.

8. **Migrations are gates.** `.github/workflows/backend.yml:24-27` runs `node scripts/run_pgtap.js` against
   the **live** `SUPABASE_DB_URL`. There is no `supabase db push` anywhere in CI — grep-verified. A pgTAP
   test for an object that has not been applied to project `chjkkwqwdlmaxacwglzm` **will fail**. So each
   migration task ends: **commit, stop, hand back.** The controller (or the Supabase MCP `apply_migration`)
   applies it live, and only then does the matching pgTAP task — and any Swift task that decodes the new
   column — start. Each commit body records the timestamp it was applied.

9. **`XCTUnwrap(await …)` does not compile — bind, then unwrap.** `try XCTUnwrap` on an `await` expression
   is a compile error in this target's Swift mode: write `let value = await …` first, then
   `let unwrapped = try XCTUnwrap(value)`.

10. **Never request HealthKit authorization outside `save(_:)` or from a unit test** — a raised sheet hung
    `build-test` for 45 minutes once. **This plan adds a second permission to the same rule: never request
    LOCATION authorization outside `LobbyView.initiateCheckIn()`, and never from a test.**
    `CheckInService.requestLocation()` (`CheckInService.swift:68`) drives `LocationOneShotHelper`, which
    calls `manager.requestWhenInUseAuthorization()` when the status is `.notDetermined`
    (`CheckInService.swift:101-104`). Task S3 adds a **promptless** sibling that returns `nil` unless
    authorization is *already* granted, and the arrival track is its only caller. A location prompt inside
    `testLobby()` would hang that walk exactly the way the HealthKit sheet hung `build-test`.

11. **No live repository, and no `Date.now`, reachable from a catalog builder.** Every `content_*` renders
    from fixture integers, strings and dates built from components (`HomeV2Fixtures.swift`,
    `CrewsTabFixtures.swift`, `LadderFixtures`). Every new production view in this plan therefore carries a
    `catalogFixture*` + `catalogSkipLoad` init in the `VenueHubView` / `SocialTabView` shape
    (`SocialTabView.swift`'s DEBUG init, the social-cards S1.6 precedent), and its `refresh()` returns
    immediately when `catalogSkipLoad` is set.

12. **Every report claim is verified against `git show <sha> --stat` and the CI artifact, not memory — and
    grep the CALL SITE of every new function before claiming it is live.** A task report that says a file
    changed names the sha it read; a task report that says a capture landed names the run it downloaded it
    from, **into a fresh directory** (a stale `app-screenshots/` from a previous run is how a plan "proves"
    a frame it never rendered). A definition is not a feature: `git grep -n "<symbol>("` must show a caller
    outside the symbol's own file and its tests. This project has shipped complete logic with no call site
    often enough that the grep IS the claim, not the confidence.

13. **Design rules, by number** (`2026-09-05-design-language.md`). The ones this plan leans on:
    - **1** — two raised surfaces only: `.gs3DCard` to read, `.gs3DCardStyle`/`.gs3D` to press; furniture
      (rows, chips, inputs) inside a raised box stays flat; strips are `surface` at 14 pt.
      **The two radii this plan uses are `GSMetrics.radiusMd` (cards) and `GSMetrics.radiusSm` (tiles and
      pill-height controls)** — what the reference frames draw, lips 6 pt on cards and 4-5 on tiles.
    - **2** — **accent is spent on the one primary action per screen, an invitation line, and the current
      item. A page never has two accent buttons.** **Gold has exactly two jobs: the week-streak number and
      "the window is open, act now"** — so the lobby's Check In button keeps its gold face
      (`LobbyView.swift:1247-1248`, `checkInGold` / `checkInGoldInk`) and nothing else in this plan is gold.
      **Green is `Color.gsSuccess` and means done or present** — a readiness tick, and nothing else. Red is
      errors. **The heart-rate zone exception (spec §4a) applies nowhere in Phase A**: no Phase A screen
      shows a heart rate, so no Phase A view may introduce a zone ramp. No decorative emoji; SF Symbols for
      glyphs.
    - **3** — kickers 10-11 pt caps, 0.1-0.13 em tracking, muted; numbers tabular (`.monospacedDigit()`).
    - **4** — one primary per screen; **same body, different frame** for solo and group — crew presence
      *adds* (the readiness row, the dock, the leader's note) and never rearranges.
    - **9** — sentence case for sentences, caps for kickers; a button says exactly what happens.

14. **The frozen frames must not move.** `app-home-v3-08a-targets-above-calendar` (frame 81) and
    `app-home-v3-08b-targets-above-join` (frame 82) are the owner-approved Home compositions. They render
    `HomeV3TargetsAboveCalendarView` / `HomeV3TargetsAboveJoinView` (`HomeV3Variations.swift:425,466`) over
    `HomeV2Fixtures.crewNight` + `HomeV2Fixtures.coachTargetsProgress` — **a world with no pending ladder
    proposal, because `WeeklyGoalProgress` has no proposal member at all**
    (`WeeklyGoalRepository.swift:61-75`). Tasks S1 and S2 therefore must not touch `HomeV3Variations.swift`
    or `HomeWeeklyGoalStrip.swift`, and those two captures are the canary checked in I2. "Unchanged" means
    **0 % of pixels differ below the status bar and above the home-indicator band** — `compare_frames.py`'s
    definition, not "byte-identical"; a re-encoded PNG is never byte-identical.

15. **Do not rename an existing `CatalogScreen` raw value, and do not reuse a retired one.**
    `ScreenshotTests` and `CatalogScreenTests` key off the exact strings, and a production id that reused a
    retired variation id would make two different compositions share one name across the artifact's
    history. **Every production id in this plan is prefixed `session-`** for exactly that reason (S11).

16. **Live-DB tests use the `TestSession` teardown factory and far-future rows.**
    `GymSyncTests/TestSession.swift` is the only place a test may create a session; register cleanup with
    `addTeardownBlock` **before** the write (XCTest awaits teardown; `defer { Task { … } }` loses the race
    with process exit). Every date a live-DB test *controls* is **2099** — these run as the shared CI
    account and a current-week row would fight `scripts/seed_qa_fixtures.js`.

17. **pgTAP conventions.** `BEGIN;` → `CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;` →
    `SELECT plan(N);` → a comment naming the migration under test and **declaring the fixture block** →
    `auth.users` inserted before `profiles` → role switching with `SET LOCAL role authenticated;
    SET LOCAL request.jwt.claim.sub = '<uuid>';` → close with `SELECT * FROM finish(); ROLLBACK;`.
    **Fixture-block namespaces already taken** inside `00000000-0000-4000-?000-00000000??xx`: `01xx`-`09xx`,
    `0bxx`, `0cxx`, `0dxx` — with a **known collision at `09xx`** (`rotation_presence_test.sql` and
    `crew_consistency_honor_test.sql` both use it; do not add a third). **This plan takes `0axx` (D2) and
    `0exx` (D4).**

18. **Do not change the shipped session-engine contracts.** `start_session`, `advance_turn`,
    `mark_warmup_ready`, `start_lifting`, `evaluate_lateness`, `mark_no_shows`, the `check_in_state` CHECK
    and `session_participants`' four policies are frozen. This plan **adds** one column and one thread key
    and **reads** everything else. In particular `warmup_minutes` is not dropped, its CHECK is not changed,
    and `SessionRepository.setWarmupMinutes` is not deleted — the column simply loses its last writer (S7)
    and its last reader (S9), which is what spec §6's "becomes unused" means.

---

## File structure

### Created

| File | Responsibility | Task |
|---|---|---|
| `supabase/migrations/20260912000101_session_participant_energy.sql` | `session_participants.energy smallint` + its CHECK | D1 |
| `supabase/tests/session_participant_energy_test.sql` | pgTAP: the column, the CHECK, self-write, crew-read, no cross-write | D2 |
| `supabase/migrations/20260912000102_session_coach_thread.sql` | `coach_chat_threads.session_id`, the two read policies, `private.session_has_pro`, `public.session_coach_thread` | D3 |
| `supabase/tests/session_coach_thread_test.sql` | pgTAP: the gate, the participant read, the non-participant refusal, one thread per session | D4 |
| `GymSyncApp/GymSync/Models/LadderProposal.swift` | `LadderProposal`, `LadderProposalMath.sentence(_:)` — the frozen value the card renders | S1 |
| `GymSyncApp/GymSyncTests/LadderProposalTests.swift` | the diff, the empty case, the sentence | S1 |
| `GymSyncApp/GymSync/DesignSystem/GSConsentCard.swift` | the consent card: kicker, sentence, Accept / Not today | S2 |
| `GymSyncApp/GymSyncTests/GSConsentCardCopyTests.swift` | the two button labels and the kicker, as strings | S2 |
| `GymSyncApp/GymSync/Models/SessionArrival.swift` | `ArrivalStage`, `ArrivalRow`, `SessionShape`, `CrewEnergy` — the frozen interface | S3 |
| `GymSyncApp/GymSyncTests/SessionArrivalTests.swift` | the stage law, the solo law, the energy clamp, the caption | S3 |
| `GymSyncApp/GymSync/Features/Sessions/SessionPieces.swift` | the production components the lobby and warm-up share | S4 |
| `GymSyncApp/GymSyncTests/SessionPiecesCopyTests.swift` | every string these components print | S4 |
| `GymSyncApp/GymSync/Models/SessionCoachThread.swift` | `SessionCoachThread`, `SessionCoachThreadRepository.open(sessionID:)`, the gate read | S6 |
| `GymSyncApp/GymSyncTests/SessionCoachThreadLiveTests.swift` | the RPC decodes and is gated, against the live project | S6 |
| `GymSyncApp/GymSync/Features/Sessions/LobbyFixtures.swift` | the hermetic world the three lobby ids render | S7 |
| `GymSyncApp/GymSync/Features/Sessions/WarmUpScreen.swift` | the shared warm-up screen, both frames | S9 |
| `GymSyncApp/GymSync/Features/Sessions/WarmUpFixtures.swift` | the hermetic world the two warm-up ids render | S9 |
| `GymSyncApp/GymSyncTests/WarmUpScreenGateTests.swift` | `WarmUpGate.isWarmingUp(...)`, the pure predicate | S9 |
| `GymSyncApp/GymSync/Features/Sessions/SessionEntryView.swift` | the router: lobby, warm-up, or the live view | S10 |
| `GymSyncApp/GymSyncTests/SessionEntryRouteTests.swift` | the route law, as a pure function | S10 |

### Modified

| File | Change | Task |
|---|---|---|
| `GymSyncApp/GymSync/Models/BlockGoalLiveRepository.swift` | `detectGoalIfMissing`'s branch 1 stops re-laddering (`:1071-1080`); `reLadderProposal(goalID:)` added | S1 |
| `GymSyncApp/GymSync/Models/BlockGoalRepository.swift` | the protocol gains `reLadderProposal`; `StubBlockGoalRepository` gains a fixture proposal | S1 |
| `GymSyncApp/GymSync/Features/Home/HomeView.swift` | the ladder proposal on the fetch tuple + the card (S2); `SessionEntryView` at `:353` (S10) | S2, S10 |
| `GymSyncApp/GymSync/Features/Coach/LadderPageView.swift` | the proposal card above the rungs; `LET COACH RE-LADDER` unchanged | S2 |
| `GymSyncApp/GymSync/Models/Session.swift` | `SessionParticipant.energy` | S5 |
| `GymSyncApp/GymSync/Models/SessionRepository.swift` | `setEnergy(sessionID:value:)` | S5 |
| `GymSyncApp/GymSync/Services/CheckInService.swift` | `locationIfAlreadyAuthorized()` — promptless | S3 |
| `GymSyncApp/GymSync/Services/LobbyRealtimeService.swift` | the presence payload carries the stage; the three proposal subscriptions go | S3, S8 |
| `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift` | the whole scroll body and action bar (S7); the sheet becomes `SessionRunnerView` (S9); the proposal state and sheets go (S8) | S7, S8, S9 |
| `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift` | **the `isInWarmUp` branch and its three helpers, and nothing else** | S9 |
| `GymSyncApp/GymSync/Features/Home/TrainingCalendarWidget.swift` | `SessionEntryView` at `:189` | S10 |
| `GymSyncApp/GymSync/Features/Calendar/CalendarSchedulingView.swift` | `SessionEntryView` at `:242` | S10 |
| `GymSyncApp/GymSync/Features/Social/GroupView.swift` | `SessionEntryView` at `:455` | S10 |
| `GymSyncApp/GymSync/Models/PublicWorkout.swift` | one doc comment, re-pointed off the deleted `RoutineProposal.swift` | S8 |
| `GymSyncApp/GymSync/Models/SessionKudos.swift` | one doc comment, re-pointed | S8 |
| `GymSyncApp/GymSyncTests/SessionKudosTests.swift` | one doc comment, re-pointed | S8 |
| `GymSyncApp/GymSync/App/CatalogHostView.swift` | one doc comment re-pointed (S8); six production ids in, ten variation ids out (S11) | S8, S11 |
| `GymSyncApp/GymSyncTests/CatalogScreenTests.swift` | six ids in, ten out | S11 |
| `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` | six capture methods in, ten out | S11 |
| `docs/design/frame-map.json` | frames 129-134 in, frames 106-111 / 120-122 / 127 out | S11 |
| `.github/workflows/ios.yml` | the FLOOR, once | I1, and only I1 |
| `docs/design/accepted-deviations.json` | six entries appended | I1 |

### Deleted

| File / symbol | Why |
|---|---|
| `GymSyncApp/GymSync/Models/RoutineProposal.swift` (212 lines) | Spec §5: the proposal-and-vote flow leaves the app. `RoutineProposal`, `ProposalVote`, `ProposalRepository` and the four payload builders have no caller left once S7 rewrites the lobby. |
| `GymSyncApp/GymSync/Features/Sessions/ProposalCardView.swift` (208 lines) | Its only call site is `LobbyView.proposalsSection` (`:865`), which S7 deletes. |
| `LobbyView.ProposalComposerView` (`LobbyView.swift:1897-2098`) | Same: the composer sheet's only presenter is the lobby's own `showProposalComposer`. |
| `GymSyncApp/GymSyncTests/ProposalRepositoryTests.swift` | Tests a repository that no longer exists. |
| the three `routine_proposals` / `routine_proposal_votes` subscriptions in `LobbyRealtimeService.swift:124-143` | Spec §3.1 names them by count. Nothing else subscribes to those tables. |
| the ten design-round lobby/warm-up variation views + their four-part registrations | S11, and the reverse contract in constraint 6. |

**Not deleted, deliberately:** the `routine_proposals` / `routine_proposal_votes` **tables**, their four RLS
policies, `private.proposal_session_id`, the two SECURITY DEFINER triggers and
`supabase/tests/rls_proposals_test.sql`. Spec §5 puts the *flow* out of the app; the soundboard precedent
(owner decision 14) drops tables in a **later** migration, after the code is gone. Phase B owns it.

---

## The two data decisions, stated

### `session_participants.energy` needs no policy

`"participant updates own check-in"` (`20260712000001_sessions_phase3_columns.sql:22-25`) is
`USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid())` with **no column list**, and
`"participants readable by other participants"` (`20260726000001…:182-187`) is row-level with no column
restriction. So spec §6's *"written by the lifter from the lobby; read by the crew with the existing
participant policy"* is already true the moment the column exists. What is **not** free is the three
`BEFORE UPDATE` triggers on that table — `engine_guard` (`20260714000001:69-71`), `checkin_window_guard`
(`20260715000003:47-49`) and `late_joiner_to_rotation_end` (`20260802000001:140-142`). D2 asserts that an
energy-only self-update passes all three; if one of them rejects it, that is a finding for the controller,
not a reason to widen a policy.

### The three dead states are NOT dropped in Phase A — here is the grep

Spec §5 lists `editing`, `voting`, `locked` as leaving, and the brief says "only if nothing references
them". **Things reference them.** Every hit in the tree, checked on master:

| Kind | Where |
|---|---|
| the CHECK itself | `20260709000006_create_sessions.sql:5-7` |
| **a server trigger's deny-list** | `20260803000002_set_logs_reject_prelive.sql:19` |
| **an edge function's allow-list** | `supabase/functions/livekit-token/index.ts:88` (`VOICE_ELIGIBLE_STATES`), asserted by `test.ts:451` |
| **a fixture that WRITES `'editing'`** | `supabase/tests/rls_proposals_test.sql:19` |
| **a QA seed that WRITES `'voting'` and `'locked'`** | `scripts/seed_qa_fixtures.js:306` (and the `PRELIVE_STATES` list at `:70`) |
| read-side bucketing, Swift | `SessionRepository.swift:477`, `LobbyView.swift:120,431`, `GroupSessionLiveView.swift:347`, `CrewRoomView.swift:621`, `GroupView.swift:407`, `SocialTabView.swift:645`, `SentryContext.swift:45` |
| test assertions over those sets | `SentryContextTests.swift:102-104`, `EventKitBridgeTests.swift:81`, `WatchDisplayFormattingTests.swift:86` |

No production code **writes** any of the three — that part of the spec is right. But dropping them from the
CHECK would break the QA seed (which is what `app-lobby`, `app-group-sessions` and `app-session-recap` all
walk), the edge function's contract test, and a pgTAP fixture. **Ruling: Phase A does not touch the CHECK.**
It removes the *flow* the states were designed for, which is the part that was actually dead. Phase B, which
already carries a migration for the soundboard tables, carries this one too — and its cost is now written
down rather than discovered.

---

## New catalog ids, the retirements, and the FLOOR

### In — six production ids, frames 129-134

| id | frame | title | renders | task |
|---|---|---|---|---|
| `session-lobby-waiting` | 129 | Crew lobby, waiting — the arrival track, the plan, the crew's energy | the production `LobbyView` over `LobbyFixtures.waiting`: two checked in, one at the gym, one on the way; Start disabled, captioned `2 of 4 checked in` | S11 |
| `session-lobby-ready` | 130 | Crew lobby — everyone's here, the track is the button | the production `LobbyView` over `LobbyFixtures.ready`: the accent arrival card reading `Everyone's here. Let's work.`, the leader's caption, FIRST UP, the neutral secondary Start | S11 |
| `session-lobby-late` | 131 | Crew lobby — one lifter late, the leader's Start anyway | `LobbyFixtures.late`: three checked in, one `late`; Start live and captioned, the confirmation's copy reachable | S11 |
| `session-warmup-solo` | 132 | Solo warm-up — the whole day, Coach's line, the block ladder | `WarmUpScreen` in its solo frame over `WarmUpFixtures.solo` | S11 |
| `session-warmup-crew` | 133 | Shared warm-up, crew frame — who's warm, the private Coach line | `WarmUpScreen` in its crew frame over `WarmUpFixtures.crew` | S11 |
| `ladder-reladder-proposal` | 134 | Ladder page — Coach proposes a new ladder | `LadderPageView` over `StubBlockGoalRepository.fixturePage` **plus** `StubBlockGoalRepository.fixtureProposal` | S11 |

### Out — ten design-round ids the production frames replace

Every lobby and warm-up id from the round, including the losing compositions: once production is built to
the chosen one, a catalog full of the alternatives is a deck nobody can read. The Phase B families
(`round-*`, `freestyle-rail`, `together-clock*`, `swap-consensus-card*`, `pump-check-card-v2`) **stay** and
are Phase B's to retire.

| id | frame | replaced by |
|---|---|---|
| `lobby-crew-waiting-a` | 106 | `session-lobby-waiting` |
| `lobby-crew-waiting-b` | 107 | `session-lobby-waiting` |
| `lobby-crew-ready` | 108 | `session-lobby-ready` |
| `warmup-solo-a` | 109 | `session-warmup-solo` |
| `warmup-solo-b` | 110 | `session-warmup-solo` |
| `warmup-crew` | 111 | `session-warmup-crew` |
| `lobby-crew-waiting-v2` | 120 | `session-lobby-waiting` |
| `lobby-crew-ready-v2` | 121 | `session-lobby-ready` |
| `warmup-solo-v2` | 122 | `session-warmup-solo` |
| `lobby-crew-ready-v3` | 127 | `session-lobby-ready` |

### The FLOOR

**`FLOOR` moves by `−4` against master's FLOOR at integration** — six production captures in, ten
design-round captures out. Against the base this plan assumes (`137`), that is `137 → 133`. **The `−4` is
the invariant; the `133` is arithmetic I1 re-does on the day.** If `feat/session-variations` never merged,
the retirement half is a no-op and the invariant is `+6`.

**No capture other than these sixteen moves count.** Three existing captures change *content* and not
count, and they are the plan's best proofs because a fixture cannot fake them:

- **`app-lobby.png`** (`testLobby()`, `ScreenshotTests.swift:830`, frame-map key `lobby` → frame 5) — the
  live account walks Crews → Push Crew → Manage → Sessions → the "Lobby Open" row into the **real**
  `LobbyView`. After S7 it shows the de-furnished lobby against real data.
- **`app-group-sessions.png`** — unchanged; the sessions list is not touched, and the dead states stay in
  the CHECK so the seed still writes six rows.
- **`app-tab-home.png`** — unchanged, and that is the point: S1 removes a silent write, and S2's card only
  appears when a proposal exists, which the CI account's Home does not have.

---

## Sequencing

```
 origin/master  (feat/session-variations merged; FLOOR 137)
        │
        ├──► STREAM D · the data                       D1 → [GATE] → D2
        │      supabase/** only                        D3 → [GATE] → D4
        │
        └──► STREAM S · the app (ONE worker, in order)
               S1  the re-ladder stops applying itself         ─┐ no session file
               S2  the consent card on Home and the ladder page ─┘  touched
               S3  THE INTERFACE: arrival, shape, energy, the promptless read
               S4  the session pieces (production components)
               S5  the energy write and read            ← needs D1 applied
               S6  this session's Coach thread           ← needs D3 applied
               S7  the lobby, de-furnished
               S8  the proposal-and-vote flow leaves
               S9  the shared warm-up screen and the runner
               S10 solo never enters the lobby
               S11 the catalog: six in, ten out
                          │
                          ▼
                   INTEGRATION  (I1 … I3)  →  ONE PR, with proof cards
```

**The only hard cross-stream edges are the two gates.** S5 decodes `session_participants.energy`; S6 calls
`public.session_coach_thread`. Both fail against a project the migration has not reached, so D1 and D3 are
applied before them. Everything else in Stream S is ordered by type dependence: S3 declares the values S4,
S7, S9 and S10 type against; S4 declares the components S7 and S9 render; S7 must land before S8 (deleting
`ProposalRepository` while the lobby still calls it does not compile) and before S9 (which edits the same
file's sheet content).

---

# STREAM D — the data

Two migrations, two pgTAP suites. `supabase/**` only, so this stream may run beside Stream S from the first
day. Both migrations are **gates** (constraint 8).

### D1 — `session_participants.energy`, how the crew feels — **S**

**File (new):** `supabase/migrations/20260912000101_session_participant_energy.sql`

Spec §6 and owner decision 18: *"`session_participants.energy smallint` (1-5, null until reported) written
by the lifter from the lobby; read by the crew with the existing participant policy."* One column. **No
policy**, for the reason set out in "The two data decisions" above — adding one would be a second permissive
policy ORed with the one that already grants this, i.e. noise that looks like security.

Write exactly this:

```sql
-- 20260912000101_session_participant_energy.sql
--
-- Spec: docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md §6
-- and owner decision 18 — the lobby carries the crew's self-reported energy
-- (1-5) as a group. Plan: docs/superpowers/plans/2026-09-12-group-session
-- -phase-a-plan.md, task D1.
--
-- NO NEW POLICY, ON PURPOSE. "participant updates own check-in"
-- (20260712000001_sessions_phase3_columns.sql:22-25) is
-- USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid()) with no
-- column list, so a lifter can already write their own row; "participants
-- readable by other participants" (20260726000001_is_session_participant
-- _dual_schema.sql:182-187) is row-level, so the crew can already read it.
-- A third policy here would be permissive-ORed with those and would grant
-- nothing while looking like it granted something.
--
-- NULL IS AN ABSENCE, NEVER A ZERO. The widget draws five empty pips and the
-- words "not yet" for NULL (the pump card's lateness-tag rule), so 0 must be
-- unreachable — hence the CHECK's lower bound of 1 rather than a DEFAULT.
--
-- smallint, not integer: a 1-5 scale, and this table is read on every lobby
-- render for every participant.
ALTER TABLE public.session_participants
  ADD COLUMN IF NOT EXISTS energy smallint
    CHECK (energy IS NULL OR energy BETWEEN 1 AND 5);

COMMENT ON COLUMN public.session_participants.energy IS
  'Self-reported energy for this session, 1-5. NULL until the lifter answers. Written by the lifter from the lobby (SessionRepository.setEnergy), read by the whole crew through the existing participant SELECT policy. Spec 2026-09-12-group-session-and-lobby-design.md section 6.';
```

**Interfaces** — *consumes:* `public.session_participants`. *Produces:* the column, decoded by S5's
`SessionParticipant.energy`.

**TDD steps.**

1. Write the migration exactly as above.
2. **Commit, stop, hand back.** The controller applies it to `chjkkwqwdlmaxacwglzm` (constraint 8) and
   records the timestamp in the commit body via an amend or a follow-up note. Do not start D2 or S5 first.
3. The controller verifies by hand:
   `SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = 'session_participants' AND column_name = 'energy';` → one row, `smallint`, `YES`.
4. Commit: `feat(lobby): session_participants.energy — how the crew feels, 1 to 5` + the trailer.

**Proves:** the column exists on the live project and D2 can address it.

---

### D2 — pgTAP for energy — **M**

**File (new):** `supabase/tests/session_participant_energy_test.sql`

**Fixture block `0axx`** — free, and chosen to avoid the known `09xx` collision (constraint 17).
`plan(8)`. The fixture: one session, three participants (A the organizer, B a crewmate, C a crewmate) and
D, a non-participant.

The eight assertions, in this order:

1. `has_column('session_participants', 'energy')`.
2. `col_type_is('session_participants', 'energy', 'smallint')`.
3. `col_is_null('session_participants', 'energy')` — the column is nullable, so "not reported" is
   representable.
4. As A: `UPDATE session_participants SET energy = 4 WHERE session_id = <s> AND user_id = <A>` **succeeds**
   and the row reads 4. *This is the assertion that proves the three BEFORE UPDATE triggers do not reject an
   energy-only self-update* — name that in a comment, because it is the one thing about this column that
   could have been wrong.
5. As A: the same UPDATE with `energy = 0` **throws** (`throws_ok`, the CHECK).
6. As A: `energy = 6` **throws**.
7. As B: `UPDATE … WHERE user_id = <A>` **updates zero rows** (RLS gives B no row to write, so this is
   `is((SELECT count(*) …), 0::bigint)` on the result of the update, not a `throws_ok`).
8. As B: `SELECT energy FROM session_participants WHERE session_id = <s> AND user_id = <A>` returns **4** —
   the crew reads each other's energy, which is the whole widget.

Then, outside the plan count, a `SET LOCAL role authenticated; SET LOCAL request.jwt.claim.sub = <D>;`
sanity read returning zero rows is *not* asserted — the existing
`is_session_participant_dual_schema_test.sql` already owns that policy's proof and this suite must not
re-prove someone else's invariant.

**TDD steps.** 1. Write the suite. 2. Run it locally if `SUPABASE_DB_URL` is available
(`node scripts/run_pgtap.js supabase/tests/session_participant_energy_test.sql`); otherwise push and let
`backend.yml` run it. 3. Commit: `test(lobby): pgTAP for session_participants.energy — the CHECK, the self-write, the crew read` + the trailer.

**Proves:** energy is writable by its owner, unwritable by anyone else, readable by the crew, and bounded
1-5 — and that no session-engine trigger blocks the write.

---

### D3 — the session's Coach thread, and the any-member-Pro gate — **L**

**File (new):** `supabase/migrations/20260912000102_session_coach_thread.sql`

Spec §3.6 and owner decision 19: *"Every crew session has one Coach thread shared by the whole crew …
unlocked for everyone while at least one participant is Pro."* Spec §6 calls it *"the existing coach-chat
thread model keyed by `session_id`"*. **The existing model has no subject key and is single-owner**
(`coach_chat_threads`, `20260824000005_coach_chat_threads.sql:6-23`: `user_id` and a free-text `title`, one
`FOR ALL` policy `USING (user_id = auth.uid())`). So "keyed by session_id" is a column this migration adds,
and the sharing is two new SELECT/INSERT policies beside the owner policy — never a replacement for it,
because every personal thread in the app depends on it.

Write exactly this:

```sql
-- 20260912000102_session_coach_thread.sql
--
-- Spec: docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md
-- §3.6 and §6, owner decision 19 — one Coach thread per crew session, shared
-- by the whole crew, unlocked while ANY participant is Pro. Plan:
-- docs/superpowers/plans/2026-09-12-group-session-phase-a-plan.md, task D3.
--
-- WHY A COLUMN AND NOT A TITLE. CoachThreadLauncher already fakes subjects by
-- writing them into `title` (ProgramScheduleView.swift:1106). A title is not a
-- key: it cannot be unique, cannot be joined, and cannot be the subject of an
-- RLS predicate. A crew-readable thread needs all three.
--
-- WHY THE PRO GATE IS SERVER-SIDE. profiles.pro_until is not readable across
-- users (20260730000004_pro_entitlement.sql), so a client asking "is anyone in
-- this session Pro" would be asking about rows it cannot see and would answer
-- "no" for everyone but itself. SECURITY DEFINER is what makes the answer
-- true. The shape is CrewCoachEngine.crewHasCoach's ("one Pro member lights
-- @Coach for the whole crew", CrewCoachEngine.swift:22-25), moved to the
-- server and scoped to session participants instead of group members.

-- 1. The key.
ALTER TABLE public.coach_chat_threads
  ADD COLUMN IF NOT EXISTS session_id uuid REFERENCES public.sessions(id) ON DELETE CASCADE;

-- ONE thread per session. A partial unique index rather than a table
-- constraint, because every personal thread has session_id NULL and NULLs
-- must not collide.
CREATE UNIQUE INDEX IF NOT EXISTS coach_chat_threads_session_key
  ON public.coach_chat_threads(session_id)
  WHERE session_id IS NOT NULL;

COMMENT ON COLUMN public.coach_chat_threads.session_id IS
  'The session this thread belongs to, or NULL for a personal thread. One thread per session (coach_chat_threads_session_key). Readable by every participant of that session. Spec 2026-09-12-group-session-and-lobby-design.md section 3.6.';

-- 2. The Pro gate, in the private schema like every other predicate helper
-- (private.is_session_participant, private.is_group_member).
CREATE OR REPLACE FUNCTION private.session_has_pro(p_session_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.session_participants sp
      JOIN public.profiles p ON p.id = sp.user_id
     WHERE sp.session_id = p_session_id
       AND p.pro_until IS NOT NULL
       AND p.pro_until > now()
  );
$$;

REVOKE EXECUTE ON FUNCTION private.session_has_pro(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.session_has_pro(uuid) TO authenticated;

-- 3. The thread's own subject, hoisted out of the messages policy so the
-- policy does not have to read coach_chat_threads under RLS (the
-- private.proposal_session_id precedent, 20260727000004).
CREATE OR REPLACE FUNCTION private.coach_thread_session_id(p_thread_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT session_id FROM public.coach_chat_threads WHERE id = p_thread_id;
$$;

REVOKE EXECUTE ON FUNCTION private.coach_thread_session_id(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.coach_thread_session_id(uuid) TO authenticated;

-- 4. The crew's read. ADDITIVE: "own threads" (20260824000005:20-23) stays
-- exactly as it is, and Postgres ORs permissive policies of the same command,
-- so a personal thread is unaffected.
CREATE POLICY "session threads readable by participants"
  ON public.coach_chat_threads FOR SELECT TO authenticated
  USING (
    session_id IS NOT NULL
    AND private.is_session_participant(session_id, auth.uid())
  );

CREATE POLICY "session threads insertable by participants"
  ON public.coach_chat_threads FOR INSERT TO authenticated
  WITH CHECK (
    session_id IS NOT NULL
    AND user_id = auth.uid()
    AND private.is_session_participant(session_id, auth.uid())
  );

CREATE POLICY "session thread messages readable by participants"
  ON public.coach_chat_messages FOR SELECT TO authenticated
  USING (
    thread_id IS NOT NULL
    AND private.is_session_participant(
          private.coach_thread_session_id(thread_id), auth.uid())
  );

CREATE POLICY "session thread messages postable by participants"
  ON public.coach_chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    thread_id IS NOT NULL
    AND user_id = auth.uid()
    AND private.is_session_participant(
          private.coach_thread_session_id(thread_id), auth.uid())
  );

-- 5. The one client-callable entry point: find-or-create this session's
-- thread, and say whether it is unlocked. Find-or-create because two lifters
-- tapping "Talk to Coach" at the same moment must land in ONE room — the
-- unique index makes that a race the ON CONFLICT resolves rather than an
-- error one of them sees.
CREATE OR REPLACE FUNCTION public.session_coach_thread(p_session_id uuid)
RETURNS TABLE (thread_id uuid, unlocked boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_thread_id uuid;
BEGIN
  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  SELECT id INTO v_thread_id
    FROM public.coach_chat_threads
   WHERE session_id = p_session_id;

  IF v_thread_id IS NULL THEN
    INSERT INTO public.coach_chat_threads (user_id, session_id, title)
    VALUES (auth.uid(), p_session_id, 'This session')
    ON CONFLICT (session_id) WHERE session_id IS NOT NULL DO NOTHING
    RETURNING id INTO v_thread_id;

    IF v_thread_id IS NULL THEN
      SELECT id INTO v_thread_id
        FROM public.coach_chat_threads
       WHERE session_id = p_session_id;
    END IF;
  END IF;

  RETURN QUERY SELECT v_thread_id, private.session_has_pro(p_session_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.session_coach_thread(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.session_coach_thread(uuid) TO authenticated;
```

**Interfaces** — *consumes:* `private.is_session_participant(uuid, uuid)`
(`20260726000001…:148-155`), `coach_chat_threads`, `coach_chat_messages`, `session_participants`,
`profiles.pro_until`. *Produces:* `coach_chat_threads.session_id`, `private.session_has_pro(uuid)`,
`private.coach_thread_session_id(uuid)`, `public.session_coach_thread(uuid)` — decoded by S6.

**TDD steps.**

1. Write the migration exactly as above.
2. **Commit, stop, hand back** (constraint 8). The controller applies it and records the timestamp.
3. The controller verifies:
   `SELECT prosecdef FROM pg_proc WHERE proname IN ('session_has_pro','session_coach_thread','coach_thread_session_id');` → three `t`.
4. Commit: `feat(coach): this session's Coach thread — the key, the crew read, the any-member-Pro gate` + the trailer.

**Proves:** the thread can be keyed, read by the crew and gated on the server, and D4 can address all three.

---

### D4 — pgTAP for the session Coach thread — **M**

**File (new):** `supabase/tests/session_coach_thread_test.sql`

**Fixture block `0exx`** (constraint 17). `plan(10)`. The fixture: session **e10** with participants A
(organizer, not Pro), B (not Pro) and C (**`pro_until = now() + interval '30 days'`**); session **e11** with
participants A and B only, nobody Pro; D, a non-participant of either.

1. `has_column('coach_chat_threads', 'session_id')`.
2. `col_type_is('coach_chat_threads', 'session_id', 'uuid')`.
3. `private.session_has_pro('…e10')` is **true** — one Pro member lights it for the crew (decision 19).
4. `private.session_has_pro('…e11')` is **false** — no Pro member, no unlock.
5. A Pro membership that has **lapsed** (`pro_until = now() - interval '1 day'`, set on B in e11 inside the
   test) leaves `session_has_pro('…e11')` **false** — the gate reads the clock, not the column's presence.
6. As A: `SELECT * FROM public.session_coach_thread('…e10')` returns one row with a non-null `thread_id`
   and `unlocked = true`.
7. As B: the same call returns **the same `thread_id`** — one room, not two. (Capture A's id into a temp
   table before switching role.)
8. As D: the same call **throws** `P0001` (`throws_ok`, the participant gate).
9. As B: `SELECT count(*) FROM coach_chat_threads WHERE session_id = '…e10'` is **1** — the crew reads a
   thread it does not own, which the pre-existing `"own threads"` policy alone would have hidden.
10. As D: the same count is **0** — a non-participant cannot see the room exists.

**TDD steps.** 1. Write the suite. 2. Run it (or push and read `backend.yml`). 3. Commit:
`test(coach): pgTAP for the session Coach thread — the gate, the shared room, the outsider` + the trailer.

**Proves:** spec §3.6's rule is enforced by the database rather than by the client — including the lapse,
which is the case a boolean column would have got wrong.

---

# STREAM S — the app

Eleven tasks, one worker, in number order (constraint 2).

### S1 — the re-ladder stops applying itself — **L**

**Files:** `GymSyncApp/GymSync/Models/BlockGoalLiveRepository.swift`,
`GymSyncApp/GymSync/Models/BlockGoalRepository.swift`,
`GymSyncApp/GymSync/Models/LadderProposal.swift` (new),
`GymSyncApp/GymSyncTests/LadderProposalTests.swift` (new).

Spec §4, owner decision 4: *"every change to weight, volume or sets — in a workout or outside it — is a
suggestion the athlete accepts, never an unprompted change"*, and the one shipped violation it names.

**What happens today**, verbatim (`BlockGoalLiveRepository.swift:1071-1080`):

```swift
        if let existing = await goal(enrollmentID: enrollment.id) {
            // The re-laddered ladder is handed straight to materialisation
            // rather than being dropped and re-read (finding F5).
            guard let fresh = await reLadder(goalID: existing.id) else {
                return DetectedBlockWeek(goal: existing, week: nil)
            }
            let week = await materialiseRung(goal: existing, ladder: fresh,
                                             weekStart: currentWeek)
            return DetectedBlockWeek(goal: existing, week: week)
        }
```

`reLadder(goalID:)` (`:495-530`) ends in `upsertRungs(changed, goalID:derivedAt:)` (`:528`) — a write to
`block_goal_rungs`. The path runs from `ladderWeek(weekStart:)` (`:1029-1034`) ← `WeeklyGoalLiveRepository`
`:434` (the Home read) and `:379` (the booking write) ← `HomeView.fetchWeeklyGoal`'s `detectIfMissing`
(`HomeView.swift:1799`). So the first Home load of a new week silently rewrites the athlete's ladder.

**Change 1 — the detect path reads the ladder it has, and writes nothing new.** Replace the block above
with:

```swift
        if let existing = await goal(enrollmentID: enrollment.id) {
            // SPEC §4 / owner decision 4: this path used to call
            // `reLadder(goalID:)`, which ends in `upsertRungs` — so the first
            // Home load of a new week rewrote the athlete's ladder with no
            // consent anywhere on screen. It now materialises this week's rung
            // from the ladder AS IT STANDS; the re-laddered ladder is offered
            // instead, by `reLadderProposal(goalID:)`, and applied only when
            // the athlete accepts (plan task S2). `LET COACH RE-LADDER`
            // (LadderPageView.swift:380) is unchanged and still applies
            // immediately, because there the athlete asked.
            guard let standing = await ladder(goalID: existing.id) else {
                return DetectedBlockWeek(goal: existing, week: nil)
            }
            let week = await materialiseRung(goal: existing, ladder: standing,
                                             weekStart: currentWeek)
            return DetectedBlockWeek(goal: existing, week: week)
        }
```

`materialiseRung(goal:ladder:weekStart:)` (`:577-603`) still writes `weekly_goals` — and must, because a
week with no rung row is a Home with no target. It is gated by
`WeeklyGoalWriteRule.shouldOverwrite(existing:detected:)` (`:593`), which already refuses to overwrite the
athlete's own row. **Materialising a rung the standing ladder already contains is not a change to a plan; it
is the plan.** Say so in the comment, because a reviewer will ask.

**Change 2 — the proposal, computed and not written.** Add to `BlockGoalLiveRepository`:

```swift
    /// The re-ladder Coach WOULD apply, as a proposal — the same computation
    /// `reLadder(goalID:)` performs, stopping one line short of `upsertRungs`.
    ///
    /// Returns nil when there is nothing to propose: no goal, no ladder, no
    /// enrollment template, or a re-ladder that changes no rung. "No changed
    /// rung" is the common case and it must be an ABSENCE — a card reading
    /// "Coach proposes: nothing" is worse than no card.
    func reLadderProposal(goalID: UUID) async -> LadderProposal?
```

Its body is `reLadder`'s (`:495-527`) up to and including the diff, then
`LadderProposal(goalID:current:proposed:changed:derivedAt:)` instead of the write. **Extract the shared
computation into one private method rather than copying it** — two copies of the re-ladder maths is exactly
the drift this repo has been bitten by; `reLadder` becomes `compute` + `upsertRungs`, and
`reLadderProposal` becomes `compute` + wrap.

**Change 3 — the protocol and the stub.** `BlockGoalRepository` (`BlockGoalRepository.swift:16-80`) gains

```swift
    /// The re-ladder as a proposal (spec §4). Default nil, so a conforming
    /// stub that has no opinion is not forced to invent one.
    func reLadderProposal(goalID: UUID) async -> LadderProposal?
```

with a `nil` default in the protocol extension beside `saveDerivedLadder`'s (`:97-102`).
`StubBlockGoalRepository` (`:152-283`) gains `static let fixtureProposal: LadderProposal` and returns it —
that is what S11's `ladder-reladder-proposal` renders. Its `reLadder(goalID:)` still returns
`fixtureLadder` and still writes nothing (`:280`).

**The value** — `Models/LadderProposal.swift`:

```swift
import Foundation

/// Coach's proposed re-ladder, before the athlete has said yes.
///
/// Spec §4 (docs/superpowers/specs/2026-09-12-group-session-and-lobby
/// -design.md): every change to weight, volume or sets is a suggestion. This
/// is the value that carries one, from `BlockGoalRepository.reLadderProposal`
/// to the consent card on Home and on the ladder page (plan task S2).
///
/// It is a VALUE, not a row. Spec §6: "the suggestion principle needs no new
/// table: proposals render from the values Coach would have written." It is
/// recomputed on every read and discarded when the athlete says Not today.
struct LadderProposal: Equatable, Sendable {
    let goalID: UUID
    /// The ladder as it stands — what "Not today" keeps.
    let current: Ladder
    /// The ladder Coach would write — what "Accept" applies.
    let proposed: Ladder
    /// Only the rungs whose target actually moved, ordered by `weekIndex`.
    /// Never empty: `reLadderProposal` returns nil rather than an empty
    /// proposal.
    let changed: [LadderRung]
    let derivedAt: Date
}

enum LadderProposalMath {
    /// The card's one sentence, in Coach's first person (design rule 7).
    ///
    /// One changed rung reads as the change; more than one reads as a count
    /// plus the nearest change, because a card that lists six weeks is a
    /// table and the ladder page is where a table belongs.
    static func sentence(_ proposal: LadderProposal, unit: WeightUnit) -> String
}
```

`sentence` is the only formatting in this task and it is pure. Copy, exactly:

- one rung: `"Week 4 becomes 3 × 5 at 215 lbs."`
- more than one: `"Weeks 4 to 8 move — the next is 3 × 5 at 215 lbs."`

with the target rendered by the app's own spelling (`lbs`, not `lb` — the social-cards fix-round ruling) and
the week numbers being `weekIndex + 1` if and only if `LadderRow.weekNumber` already does that; **read
`LadderMath`'s existing row builder and match it rather than assuming.**

**Tests** — `LadderProposalTests.swift`, pure, no DB:

1. a proposal whose diff is empty is expressed as `nil` by the repository contract (assert against the stub
   protocol default, not the live repository);
2. `changed` is ordered by `weekIndex` and contains only rungs whose `target` differs;
3. `sentence` for one changed rung;
4. `sentence` for three changed rungs names the count and the nearest one;
5. `sentence` in kilos renders kilos (the Units doctrine — a frozen "215 lbs" shown to a kilo athlete is the
   bug this test exists for).

**Grep the call site** (constraint 12): after this task, `git grep -n "reLadder(goalID:" ` must show exactly
two callers — `LadderPageView.swift:659` and the new `compute`-sharing internals — and **zero** inside
`detectGoalIfMissing`.

**TDD steps.** 1. Write `LadderProposal.swift` and the failing tests. 2. Extract `compute`, add
`reLadderProposal`, change the detect path. 3. Protocol + stub. 4. Push. 5. Commit:
`fix(coach): the block re-ladder becomes a proposal — nothing rewrites a ladder unasked` + the trailer.

**Proves:** the silent write is gone (grep), the proposal is a tested value, and `LET COACH RE-LADDER` is
untouched — before any card renders it.

---

### S2 — the consent card, on Home and on the ladder page — **M**

**Files:** `GymSyncApp/GymSync/DesignSystem/GSConsentCard.swift` (new),
`GymSyncApp/GymSyncTests/GSConsentCardCopyTests.swift` (new),
`GymSyncApp/GymSync/Features/Home/HomeView.swift`,
`GymSyncApp/GymSync/Features/Coach/LadderPageView.swift`.

Spec §4: *"It becomes a proposal card — 'Coach proposes a new ladder: …' — on Home and the ladder page,
applied on accept."* And: *"the consent-card pattern is the one Coach chat already uses for swaps and
rules."*

**Reuse that pattern, do not invent one.** The two shipped consent cards are
`ConsultCloseView.ruleCard(_:)` (`ConsultCloseView.swift:97`, with `accept(_:)` `:155` / `reject(_:)` `:174`)
and `CoachHomeView.threadRuleCard(_:)` (`:973`, kicker `"COACH HEARD A RULE"`). Read both before writing a
line. `GSConsentCard` is their composition lifted into the design system so this plan's third instance is
the same object rather than a third drawing:

```swift
/// A consent card: Coach proposes, the athlete decides, nothing happens until
/// they do. The composition of ConsultCloseView.ruleCard and
/// CoachHomeView.threadRuleCard, lifted so the ladder proposal (plan task S2)
/// is the same object rather than a third drawing of it.
///
/// ACCENT: none. Rule 2 spends accent on the screen's one primary action, and
/// a proposal is not the primary act of Home or of the ladder page. Accept and
/// Not today are both raised faces (`.gs3DCardStyle`, radiusSm, lip 4) — the
/// same pair the warm-up screen's suggestion uses, so a suggestion answers the
/// same way everywhere in the app.
struct GSConsentCard: View {
    let kicker: String        // caps, 10 pt, tracking 1.2, muted (rule 3)
    let sentence: String      // one sentence, sentence case (rule 9)
    var detail: String?       // the consequence line, neutral500, optional
    let acceptTitle: String   // "Accept"
    let declineTitle: String  // "Not today"
    let onAccept: () -> Void
    let onDecline: () -> Void
}
```

Card body: `.gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)`, 14 pt padding, the kicker, the
sentence at `GSFont.bodyMedium(13.5, relativeTo: .subheadline)` in `theme.text`, the optional detail at
`GSFont.body(12, relativeTo: .caption)` in `theme.neutral500`, then the two pills in an `HStack(spacing: 8)`
with a trailing `Spacer(minLength: 0)`.

**On the ladder page.** `LadderPageView` gains `var proposal: LadderProposal? = nil` beside its existing
`world:` seam and renders the card **above the rungs and below the coach line** — the rungs are what the
proposal is about, so the question sits above its own subject (rule 4, questions above the fold). Accept
calls `repository.reLadder(goalID:)` then `repository.materialiseRung(goalID:weekStart:)` — **the exact pair
`reLadder()` at `:655-663` already calls**, so Accept and `LET COACH RE-LADDER` are one code path and cannot
drift — then re-reads `page(goalID:)` and clears the card. Not today clears the card only; the next Home
load recomputes it, which is correct: the proposal is a fact about the ladder, not a dismissible notice.
**`LET COACH RE-LADDER` stays exactly where it is, worded as it is** (`:380-383`).

**On Home.** `fetchWeeklyGoal(userID:)` (`HomeView.swift:1790-1818`) already returns a five-member tuple
including `ladder: LadderPageModel?`. Add a sixth member, `ladderProposal: LadderProposal?`, filled by
`await blockGoalRepository.reLadderProposal(goalID: block)` inside the existing `if let block` branch — the
one place that already knows the block goal id, so no second read is introduced. The card renders in the
Home body directly beneath the goal strip, `nil` meaning no card and no space. Accept does what the ladder
page's Accept does, then re-runs the Home fetch.

**Constraint 14 is the hazard in this task.** Do not touch `HomeWeeklyGoalStrip.swift` and do not touch
`HomeV3Variations.swift`. `app-home-v3-08a/08b` render those two variation views over a fixture world that
has no proposal member to set; if either capture moves, the card was put in the wrong file.

**Tests** — `GSConsentCardCopyTests.swift`: the kicker is `"COACH PROPOSES A NEW LADDER"`, the accept label
is `"Accept"`, the decline label is `"Not today"` — the same two words the warm-up suggestion uses, asserted
as strings so a later edit to one surface cannot silently diverge from the other.

**Grep the call site** (constraint 12): `git grep -n "GSConsentCard("` must show `HomeView.swift` and
`LadderPageView.swift`, and `git grep -n "reLadderProposal("` must show `HomeView.swift` plus the repository
and its tests.

**TDD steps.** 1. `GSConsentCard` + its copy test. 2. The ladder page (the smaller of the two call sites, and
the one S11 photographs). 3. Home. 4. Push. 5. Commit:
`feat(coach): Coach proposes a new ladder — a consent card on Home and the ladder page` + the trailer.

**Proves:** spec §4's card exists on both surfaces and applies through the same code path as the explicit
lever; the two frozen Home frames do not move (checked in I2).

---

### S3 — THE INTERFACE: arrival, shape, energy, and one promptless read — **M**

**Files:** `GymSyncApp/GymSync/Models/SessionArrival.swift` (new),
`GymSyncApp/GymSyncTests/SessionArrivalTests.swift` (new),
`GymSyncApp/GymSync/Services/CheckInService.swift`,
`GymSyncApp/GymSync/Services/LobbyRealtimeService.swift`.

**Everything from S4 to S11 types against this file.** It is pure values and pure functions; no view, no
repository, no clock beyond an injected `Date`.

```swift
import Foundation

/// Spec §1: a lifter with the lobby open outside the gym's geofence is *on the
/// way*; inside it, *at the gym*; *checked in* once they tap (or the geofence
/// confirms). Owner decision 12 pins the first one.
enum ArrivalStage: String, CaseIterable, Sendable {
    case onTheWay, atTheGym, checkedIn

    var caps: String { … }   // "ON THE WAY" / "AT THE GYM" / "CHECKED IN"
    var glyph: String { … }  // "figure.walk" / "mappin.and.ellipse" / "checkmark.circle.fill"
}

/// One lifter in the lobby, as the track draws them.
struct ArrivalRow: Identifiable, Equatable, Sendable {
    let id: UUID              // user id
    let name: String
    let avatarURL: URL?
    let stage: ArrivalStage
    /// Self-reported energy, 1-5. nil = has not answered (never 0).
    let energy: Int?
    let isYou: Bool
    let isLate: Bool          // check_in_state == "late" || "no_show"
}

enum ArrivalLaw {
    /// CHECKED IN is a DB fact; the other two are a presence fact.
    ///
    /// `check_in_state == "ready"` is checked in, full stop — spec §3.1's
    /// "checked in is ready; there is no separate roster and no separate ready
    /// tick" (owner decision 16's reversal of round 1's two signals).
    ///
    /// AT THE GYM requires knowing where somebody standing in the room is, and
    /// no column stores that: the geofence is evaluated on each device
    /// (CheckInService.distanceCheck). So it comes from the lobby's own
    /// presence payload, which each device publishes for ITSELF. A lifter
    /// whose device has published nothing reads ON THE WAY, which is the
    /// honest default — see this plan's "What this plan does not decide" 1.
    static func stage(checkInState: String?, publishedStage: String?) -> ArrivalStage
}

enum SessionShape {
    /// Spec §2 / owner decision 3: a scheduled SOLO session has no lobby.
    ///
    /// NOT `group_id == nil`. `ScheduleSessionView`'s `.friends` and `.code`
    /// modes also leave group_id nil (ScheduleSessionView.swift:778-786), and
    /// the code's own comment already calls that condition "solo" — the F10
    /// heal reads it that way and the crash report's H4 is the consequence
    /// (context-map §6). A solo session is one participant and no room code.
    static func isSolo(participantCount: Int, roomCode: String?) -> Bool {
        participantCount <= 1 && roomCode == nil
    }
}

enum LobbyCopy {
    /// "2 of 4 checked in" — Start's caption, counting the CHECKED IN column
    /// and nothing else (spec §3.1).
    static func checkedInCaption(checkedIn: Int, total: Int) -> String

    /// "Everyone's here. Let's work." — owner decision 20, verbatim.
    static let everyoneHere = "Everyone's here. Let's work."

    /// The leader's caption on the accent widget.
    static let readyLeaderCaption = "Yours to start — or it starts on its own."

    /// Everyone else's, in the same slot on the same widget.
    static func readyCrewmateCaption(leaderFirstName: String) -> String
        // "Waiting for Alex — or it starts on its own"

    /// Under the foot's neutral secondary, which is the same act.
    static let secondaryStartNote = "Same action, in the thumb zone"

    /// "3 OF 4 REPORTED" — the energy card's right-hand read.
    static func energyReported(reported: Int, total: Int) -> String
}
```

**The promptless location read** — `CheckInService.swift`:

```swift
    /// The device's location ONLY if location authorization has already been
    /// granted. Returns nil — never a prompt — when the status is
    /// `.notDetermined`, `.denied` or `.restricted`.
    ///
    /// Global constraint 10: `requestLocation()` (:68) drives
    /// `LocationOneShotHelper`, which calls `requestWhenInUseAuthorization()`
    /// on `.notDetermined` (:101-104). A prompt raised from the lobby's own
    /// `.task` would hang `testLobby()` the way the HealthKit sheet hung
    /// `build-test`. The arrival track is this function's ONLY caller.
    static func locationIfAlreadyAuthorized() async -> CLLocation?
```

Implement it by checking `CLLocationManager().authorizationStatus` against
`.authorizedWhenInUse` / `.authorizedAlways` **before** touching `LocationOneShotHelper`, and returning
`nil` otherwise. Do not change `requestLocation()`.

**The presence payload** — `LobbyRealtimeService.swift`. `track(state:)` already publishes a
`"check_in_state"` key that is **always the empty string** (`:73`). Replace it with a real
`"stage"` key carrying `ArrivalStage.rawValue`, and add a `publishStage(_:)` the lobby calls when its own
stage changes. Take the `onPresence` callback from `Set<UUID>` to
`[UUID: String]` (user id → published stage) so the track can read it; the lobby's `presenceSet` becomes
`presenceStages` and `presenceSet.contains(id)` becomes `presenceStages[id] != nil` at its one remaining
call site (`LobbyView.swift:952`, the presence dot — which S7 deletes anyway).

**Tests** — `SessionArrivalTests.swift`, pure:

1. `"ready"` is `.checkedIn` whatever the presence says (the DB fact wins);
2. `nil`/`"invited"`/`"online"`/`"late"` with no published stage is `.onTheWay`;
3. `"online"` with `publishedStage == "atTheGym"` is `.atTheGym`;
4. `"ready"` with `publishedStage == "onTheWay"` is still `.checkedIn` — the case a naive `if presence`
   ordering gets wrong;
5. `isSolo(participantCount: 1, roomCode: nil)` is true;
6. `isSolo(participantCount: 2, roomCode: nil)` is **false** — the `.friends` session that `group_id == nil`
   would have called solo;
7. `isSolo(participantCount: 1, roomCode: "ABCD")` is **false** — a room code is an invitation, so somebody
   is expected;
8. `checkedInCaption(2, 4)` is `"2 of 4 checked in"`;
9. `energyReported(3, 4)` is `"3 OF 4 REPORTED"`;
10. `readyCrewmateCaption(leaderFirstName: "Alex")` is `"Waiting for Alex — or it starts on its own"`.

**TDD steps.** 1. Write the tests. 2. Write the file. 3. `CheckInService`. 4.
`LobbyRealtimeService` and its one call-site edit. 5. Push. 6. Commit:
`feat(lobby): the arrival stage, the session's shape, and a location read that cannot prompt` + the trailer.

**Proves:** the lobby's two hardest facts — who is where, and what counts as solo — are pure, tested, and
named in one place before a pixel depends on them.

---

### S4 — the session pieces — **L**

**Files:** `GymSyncApp/GymSync/Features/Sessions/SessionPieces.swift` (new),
`GymSyncApp/GymSyncTests/SessionPiecesCopyTests.swift` (new).

The production components the lobby (S7) and the warm-up screen (S9) share. **Build each one to the
reference frame named beside it, reading that frame's source in the variations worktree.** They are the
same compositions with production types (`SessionParticipant`, `Profile`, `RoutineExercise`, `LadderRow`)
in place of `SVLifter` / `SVPlanRow`, and no `#if DEBUG`.

| production type | reference | notes that are not obvious from the drawing |
|---|---|---|
| `SessionArrivalTrack(rows:)` | `SVArrivalRail`, `SessionVariationKit.swift:774-844` | three fixed columns, 6 pt gaps, a chevron between; an empty stage keeps its column and draws a dashed 30 pt tile at `30 * 0.28` radius so it reads as a missing person; avatars overlap at `-8`; count under each column, `—` when empty. `theme.surface`, 14 pt radius: **a strip, not a card** (rule 1). |
| `SessionPlanCard(kicker:rungLine:rows:showsSwap:)` | `SVPlanListCard`, `SessionVariationsV2Kit.swift:251-334` | the whole routine, one row per exercise, **fixed 28 pt row height** so four rows make four straight edges; a 3 pt gutter reserved whether or not a row is current; the prescription right-aligned and `.monospacedDigit()`; `Swap` is a **flat capsule chip** on the raised card (rule 1), shown only when `showsSwap`. |
| `SessionPlanCardWithSuggestion(…)` | `SVPlanListCardWithSuggestion`, `WarmupVariationsV2.swift` | the same rows, plus a divider and the suggestion **inside** the card. A separate type, not a boolean on the one above: the suggestion's place under a rule inside the card is `warmup-solo-b`'s whole argument, and a flag would let a later edit quietly move it back out. |
| `CoachSuggestionBlock(line:accept:decline:isPrivate:)` | `SVSuggestionBody`, `SessionVariationKit.swift:440-489` | Coach's 30 pt `CO` tile, the first-person line, `Only you see this.` when private (spec §3.2 — a crew screen that shows a Coach line without saying so reads as a broadcast), then the two raised pills. **Accept / Not today**, the same two words `GSConsentCard` uses (S2). |
| `CrewEnergyCard(rows:reported:askTitle:onAsk:)` | `SVCrewEnergyCard`, `SessionVariationsV2Kit.swift:346-410` | kicker `HOW THE CREW FEELS`, right-hand `n OF m REPORTED`; fixed 70 pt columns so avatars and meters share baselines; the ask control is a **raised face, never accent** — the screen's accent is Start. |
| `EnergyMeter(value:onAccent:)` | `SVEnergyMeter`, `:413-447` | five 6×8 pips at 3 pt spacing, `text` filled / `neutral300` empty; `nil` draws the words `not yet`, never a zero. `onAccent` inverts to `theme.bg` ink for the ready card. |
| `CoachDoorRow(title:detail:note:onTap:)` | `SVCoachEntryRow`, `:457-505` | one strip, one tap. **Not accent** — a door that shouts on every screen is a banner. |
| `EveryoneHereCard(rows:caption:isTappable:onTap:)` | `SVLockedInAccentCard`, `SessionVariationsV3.swift` | the accent face, `.gs3DCardStyle(… face: theme.accent)` so it sinks like every pressable; the headline in `theme.bg`; avatars inverted (`fill: theme.bg, ink: theme.accent`); the caption + chevron; **no green tick** — on an accent slab a second colour is a second idea. Column geometry identical to the neutral card's (44 pt avatar, 13 pt name row, 12 pt meter, 80 pt column). |
| `FirstUpCard(headline:then:)` | `SVFirstUpCard`, `LobbyVariationsV2.swift` | kicker `FIRST UP`, the day's first exercise at 21 pt bold, a divider, and the rest of the day **named** in one `neutral500` line — never silently dropped. |
| `SecondaryStartButton(title:note:onTap:)` | `SVSecondaryStart`, `SessionVariationsV3.swift` | full-width raised neutral face, ink `theme.text` (**not** the inert `neutral700` of a gated control — this one is live), the note centred beneath. |
| `SessionReadinessRow(rows:kicker:count:)` | `SVReadinessRow`, `SessionVariationKit.swift:845-880` | the crew warm-up's readiness; a `Color.gsSuccess` tick on a lifter who has marked warm and nothing on one who has not. |
| `BlockLadderStrip(week:weeks:milestone:)` | `SVProgramLadder`, `SessionVariationsV2Kit.swift:654-692` | `WHERE YOU ARE` + `WEEK n OF m`; done rungs `text`, the current one taller, the rest `neutral300`; a neutral `flag.checkered`. **No colour** — a block you are 3/8 through is neither an invitation nor an achievement. |
| `WarmUpClockStrip(elapsed:)` | `SVWarmupClock`, `WarmupVariations.swift` | a **strip at 22 pt**, not a hero: the largest thing on the warm-up screen is what you are about to lift. Trailing line `No target. Go when you're ready.` |

**One primary per screen** (rule 4) is enforced by composition, not by hope: none of these components
renders `GSPrimaryButtonStyle`. The lobby and the warm-up screen each place their own single primary in the
foot.

**Tests** — `SessionPiecesCopyTests.swift` asserts every literal these components print, as strings:
`ON THE WAY`, `AT THE GYM`, `CHECKED IN`, `THE SESSION`, `HOW THE CREW FEELS`, `How are you feeling?`,
`not yet`, `FIRST UP`, `WHERE YOU ARE`, `WARMING UP`, `No target. Go when you're ready.`, `WHO'S WARM`,
`Only you see this.`, `Accept`, `Not today`, `Talk to Coach`,
`This session's focus · form questions · demo videos`. Copy that lives in a view body is copy nobody can
review; hoist each into a `SessionCopy` enum in this file and assert it there.

**TDD steps.** 1. Hoist the copy + write its test. 2. Build the components, one at a time, reading the
reference file for each. 3. Push. 4. Commit:
`feat(sessions): the production session pieces — the arrival track, the plan, the energy, Coach's door` +
the trailer.

**Proves:** the approved compositions exist as production types with no dependency on `Variations/`
(`git grep -n "SV[A-Z]" GymSyncApp/GymSync/Features/Sessions/SessionPieces.swift` returns nothing).

---

### S5 — the energy write and read — **M** · **needs D1 applied**

**Files:** `GymSyncApp/GymSync/Models/Session.swift`,
`GymSyncApp/GymSync/Models/SessionRepository.swift`,
`GymSyncApp/GymSyncTests/SessionEnergyLiveTests.swift` (new).

`SessionParticipant` (`Session.swift:127-169`) gains

```swift
    /// Self-reported energy for this session, 1-5 (20260912000101). NULL until
    /// the lifter answers — decoded with the same safe-decode guard
    /// `warmupReady` uses (:167), because a projected select or a client
    /// running ahead of the migration must not fail the whole row.
    let energy: Int?
```

with `case energy` in `CodingKeys` and
`energy = try? c.decodeIfPresent(Int.self, forKey: .energy) ?? nil` in the custom `init(from:)`.

`SessionRepository` gains, beside `checkIn` (`:595-613`) and in its idiom:

```swift
    /// Write my own energy for this session (spec §6, owner decision 18).
    /// A direct UPDATE, not an RPC: "participant updates own check-in"
    /// (20260712000001:22-25) already scopes the write to my own row, and the
    /// column's CHECK (1-5) is the backstop — the same reasoning
    /// `setWarmupMinutes` (:742) records for the organizer's own column.
    static func setEnergy(sessionID: UUID, value: Int) async throws
```

It clamps to `1...5` client-side before the write (a UI that can only send 1-5 still should not be the only
guard) and `.eq("session_id", …).eq("user_id", …)` on the caller's own id.

**Tests** — `SessionEnergyLiveTests.swift`, against the live project, through `TestSession` with a **2099**
scheduled date and `addTeardownBlock` registered before the write (constraint 16):

1. `setEnergy(sessionID:value: 4)` then `participants(sessionID:)` reads back `energy == 4`;
2. `setEnergy(value: 9)` clamps and the row reads `5` — the clamp is proved, not assumed;
3. a fresh participant row reads `energy == nil`.

**TDD steps.** 1. Confirm D1 is applied (ask the controller; do not guess). 2. Model + repository. 3. The
live test. 4. Push. 5. Commit: `feat(lobby): a lifter writes their own energy, the crew reads it` + the
trailer.

**Proves:** the column round-trips through the client against the live table, so the lobby's widget has a
value behind it before it has a pixel.

---

### S6 — this session's Coach thread, and its door — **L** · **needs D3 applied**

**Files:** `GymSyncApp/GymSync/Models/SessionCoachThread.swift` (new),
`GymSyncApp/GymSyncTests/SessionCoachThreadLiveTests.swift` (new).

Spec §3.6. One value, one repository call, one gate.

```swift
/// This session's Coach thread — one room for the whole crew (spec §3.6,
/// owner decision 19).
struct SessionCoachThread: Equatable, Sendable {
    let threadID: UUID
    /// Server-evaluated: at least one participant of this session is Pro
    /// (private.session_has_pro, 20260912000102). Never computed on the
    /// client — profiles.pro_until is not readable across users, so a
    /// client-side answer would be "no" for everybody but me.
    let unlocked: Bool
}

enum SessionCoachThreadRepository {
    /// Find-or-create, through `public.session_coach_thread(uuid)`. Two
    /// lifters tapping at once land in ONE room; the unique index resolves
    /// the race server-side.
    static func open(sessionID: UUID) async throws -> SessionCoachThread
}
```

**The client's reading of "unlocked".** Mirror `CrewCoachEngine.crewHasCoach`'s convention exactly
(`CrewCoachEngine.swift:22-25`): while `Monetization.paywallEnabled` is `false` — which it is today
(`Monetization.swift:25`) — the row is unlocked for everyone regardless of the server's answer, because
every other gate in the app behaves that way and a Coach door that is the app's only live paywall would be
a product change this plan is not entitled to make. Write that as a one-line pure function next to the
value:

```swift
    /// `guard Monetization.paywallEnabled else { return true }` first — the
    /// house convention (CrewCoachEngine.swift:22-25). The server's answer is
    /// authoritative only once the paywall is on.
    static func isReachable(_ thread: SessionCoachThread) -> Bool
```

**The door.** `CoachDoorRow` (S4) is placed by S7 (the lobby) with
`title: "Talk to Coach"`, `detail: "This session's focus · form questions · demo videos"`, and — when
`isReachable` is false — `note: "Nobody in the crew has Pro yet — see plans"` and a tap that presents
`PaywallView` instead of the thread. When reachable, the tap opens `ChatView`'s Coach surface on
`threadID`. **Read `CoachHomeView`'s own thread presentation before choosing how** (`:563-681`); reuse it
rather than building a second Coach reader.

**Tests** — `SessionCoachThreadLiveTests.swift`, live, `TestSession`, 2099:

1. `open(sessionID:)` on a session the CI account participates in returns a non-nil `threadID`;
2. calling it twice returns **the same** `threadID` (the find-or-create, from the client's side);
3. `unlocked` decodes as a `Bool` (its *value* depends on whether the CI account is Pro, so assert the
   decode, not the verdict — D4 owns the verdict);
4. `isReachable` returns `true` while `Monetization.paywallEnabled` is false, whatever `unlocked` says.

**Grep the call site** (constraint 12): after S7, `git grep -n "SessionCoachThreadRepository.open("` must
show `LobbyView.swift`.

**TDD steps.** 1. Confirm D3 is applied. 2. The value + repository. 3. The live test. 4. Push. 5. Commit:
`feat(coach): one Coach thread per session, unlocked while any member is Pro` + the trailer.

**Proves:** the crew's thread is reachable from the client and the gate's answer comes from the server.

---

### S7 — the lobby, de-furnished — **L**

**File:** `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift`, and
`GymSyncApp/GymSync/Features/Sessions/LobbyFixtures.swift` (new).

Spec §3.1 and owner decisions 16, 18, 20. The reference frames are `lobby-crew-waiting-v2` (120) and
`lobby-crew-ready-v3` (127). **Read `LobbyView.swift` in full before editing** — it is 2,098 lines and its
three-layer body split (`lobbyScroll` / `lobbyWithLifecycle` / `body`, `:196`, `:355`, `:466`) exists because
the RELEASE type-checker timed out twice on this file. **Keep the three layers.**

**What the scroll body becomes**, top to bottom, replacing `lobbyScroll`'s content
(`:198-274`):

1. `roomCodeBanner` — **kept**, unchanged. It is how a `.code` session is joined and no owner decision
   touched it.
2. `SessionArrivalTrack(rows:)` — the arrival track, and the lobby's **only** presence signal. It replaces
   `checkInStatusCard` (`:816-855`) and `participantsSection` (`:876-903`) **and** `participantRow`
   (`:906-1021`) **and** `checkInBadge` (`:1024-1046`) **and** `checkInSubtitle` (`:1048-1055`). Rows come
   from `participants` mapped through `ArrivalLaw.stage(checkInState:publishedStage:)` (S3).
3. `CoachDoorRow` — `Talk to Coach` (S6).
4. `SessionPlanCard(kicker: "THE SESSION", rungLine:, rows:, showsSwap: isOrganizer)` — the **whole** plan,
   built from `routineInfo!.exercises` through `exerciseName(for:)` / `exerciseEquipment(for:)` (`:1155`,
   `:1159`), with `Swap` per row for the leader. The swap control **presents the existing routine picker**
   (`showRoutinePicker`, `LobbyRoutinePickerSheet`) scoped to that row — spec §3.4 mode 1 is what a swap
   becomes *after* Start and is Phase B; before Start the leader is simply choosing the session's routine,
   which is what the picker already does. Do not build a swap sheet.
5. `CrewEnergyCard(rows:reported:askTitle:onAsk:)` — `onAsk` presents a 1-5 picker writing
   `SessionRepository.setEnergy` (S5) and reloading. `askTitle` is `nil` once **I** have answered; the card
   never nags about somebody else.
6. the error line — kept.

**The all-ready state** (`lobby-crew-ready-v3`). When `allReady` (the existing computed property, `:100`,
already `participants.allSatisfy { $0.participant.checkInState == "ready" }` — *checked in is ready, in the
shipped code as well as the spec*), the body renders instead:

- `EveryoneHereCard(rows:caption:isTappable:onTap:)` — accent, `LobbyCopy.everyoneHere`, the four avatars
  with their energy, `readyLeaderCaption` and a live tap for the organizer;
  `readyCrewmateCaption(leaderFirstName:)` and **no tap** for everyone else;
- `FirstUpCard(headline:then:)` — the first exercise large, the rest named;
- **and nothing else.** The energy card, the Swap controls and the Coach row are gone from this state on
  purpose: they are decisions, and the decisions are made.

**The foot** (`actionBar`, `:1252-1362`):

- the gold **Check In** button — kept exactly as it is, including `canCheckIn`, `checkInOpensAtText`, the
  `.task(id: checkInOpensAt)` one-shot wake-up and `initiateCheckIn()`'s travel dialog. Gold's second job is
  this button (rule 2).
- `PTTDockRow` — kept, in place, above the primary (rule 6).
- **Start.** Waiting: the accent `GSPrimaryButtonStyle` primary, **disabled**, captioned
  `LobbyCopy.checkedInCaption(checkedIn:total:)` beneath. All-ready: the accent has moved to the arrival
  widget, so the foot's Start becomes `SecondaryStartButton(title: "Start", note: LobbyCopy.secondaryStartNote)`
  — same action, one accent on the page.
- **Start anyway.** The existing `showStartDialog` confirmation (`:521-533`) stays for the leader when
  somebody has not checked in, with its copy unchanged. Its title already counts correctly
  (`notReadyDialogTitle`, `:186`).
- the crewmate's `Waiting for organizer to start…` row — **replaced** by the widget's own crewmate caption.
  Delete it.

**Consensus Start.** Spec §3.1: *"Start is the leader's tap, or fires when everyone is checked in."* The
server has no consensus rule and this plan does not add one (constraint 18 — `start_session` is frozen and
organizer-gated). So consensus is **the organizer's client firing the tap it would have fired**: in the
`.onChange(of:)` that already watches the roster, when `allReady` turns true and `isOrganizer`, schedule a
single 3-second `Task.sleep` and then `startSession()` unless it has been cancelled by the leader tapping
first or by the roster changing. One shot, cancellable, never a timer — the `checkInWindowRefreshTick`
idiom (`:1355-1361`). **Everyone else's copy says exactly what will happen** (`or it starts on its own`),
which is why the caption is not decoration.

**What leaves this file, in this task:** `warmupSection` (`:1172-1204`), `warmupStepButton` (`:1206-1220`),
`adjustWarmup` (`:1224-1244`) and the `warmup_minutes` branch in `lobbyScroll` (`:243-251`) — spec §3.1,
warm-up is a phase, not a number. `SessionRepository.setWarmupMinutes` itself stays (constraint 18); it
simply has no caller, and S9's commit body says so.

**The catalog seam** (constraint 11). `LobbyView` gains the `catalogFixture*` + `catalogSkipLoad` DEBUG init
in `SocialTabView`'s shape, seeding `participants`, `currentSession`, `routineInfo`, `groupName` and
`presenceStages`, and `reload()` / `openAndLoad()` return immediately when it is set — so no repository, no
realtime, no `CheckInService` and no clock is reachable from a frame. `LobbyFixtures.swift` carries three
worlds — `.waiting`, `.ready`, `.late` — with **fixed UUIDs** (avatar tint keys off the id) and a fixed
`scheduledFor` built from components at noon UTC (the `CrewsTabFixtures.utcDate` idiom), never `Date()`.

**Grep, before claiming done:** `git grep -n "WHO'S HERE\|Who's here\|Lock in & Start\|warmupSection" GymSyncApp/GymSync/Features/Sessions/LobbyView.swift` returns nothing.

**TDD steps.** 1. `LobbyFixtures.swift`. 2. The seam. 3. The scroll body. 4. The all-ready state. 5. The
foot and consensus. 6. Delete the warm-up section. 7. Push. 8. Commit:
`feat(lobby): the crew lobby de-furnished — the arrival track is the roster and the button` + the trailer.

**Proves:** `app-lobby` (the live walk, unchanged test) renders the new composition against real data — the
proof a fixture cannot give.

---

### S8 — the proposal-and-vote flow leaves the app — **M**

**Files:** delete `GymSyncApp/GymSync/Models/RoutineProposal.swift`,
`GymSyncApp/GymSync/Features/Sessions/ProposalCardView.swift`,
`GymSyncApp/GymSyncTests/ProposalRepositoryTests.swift`; edit
`GymSyncApp/GymSync/Services/LobbyRealtimeService.swift` and
`GymSyncApp/GymSync/Features/Sessions/LobbyView.swift`.

Spec §5. S7 removed the flow's UI; this task removes the flow.

- `LobbyView`: delete `@State proposals` (`:17`), `proposalVotes` (`:18`), `proposerUsernames` (`:19`),
  `showProposalComposer` (`:41`), `proposalsSection` (`:859-873`), `proposalComposerSheet` (`:1363-1370`),
  its `.sheet` (`:478-480`), `castVote(proposalID:approve:)` (`:1661-1670`), the `ProposalRepository.open` /
  `.votes` reads inside `reload()` (`:1402-1418`), and the whole `ProposalComposerView` (`:1897-2098`).
- `LobbyRealtimeService`: delete `proposalInserts` (`:125-130`), `proposalUpdates` (`:131-136`) and
  `voteInserts` (`:139-143`) plus their three `group.addTask` arms. **Three subscriptions, exactly as spec
  §3.1 counts them.** The `sessions` and `session_participants` subscriptions stay.
- delete the two source files and the test file.

**What must NOT be deleted**, and the commit body says why: the `routine_proposals` /
`routine_proposal_votes` tables, their policies, `private.proposal_session_id`, the two triggers, and
`supabase/tests/rls_proposals_test.sql` (which also writes the `'editing'` state — see "The three dead
states"). Tables outlive their code here by the same rule the soundboard follows (owner decision 14).

**Four doc comments cite the deleted files as precedents and must be re-pointed in the same commit**, or the
grep below is not clean and the next reader is taught a law about a file that does not exist:

| file:line | what it says today |
|---|---|
| `GymSyncApp/GymSync/Models/PublicWorkout.swift:467` | cites `RoutineProposal.swift:68-72`'s vocabulary for `p_opt_in` |
| `GymSyncApp/GymSync/Models/SessionKudos.swift:61` | cites `RoutineProposal.vote` as the one-row-Encodable idiom |
| `GymSyncApp/GymSync/App/CatalogHostView.swift:1699` | cites a leak class "just closed in ProposalRepositoryTests" |
| `GymSyncApp/GymSyncTests/SessionKudosTests.swift:16` | cites `ProposalRepositoryTests.testDuplicateAffectsExerciseThrowsValidation` |

Re-point each at this plan and the commit that removed the flow — never delete the *reasoning*, only the
dangling citation. These four are comment-only edits and change no behaviour.

**Grep, before claiming done:** `git grep -n "RoutineProposal\|ProposalRepository\|ProposalCardView\|ProposalVote" GymSyncApp/`
returns **nothing**.

**TDD steps.** 1. The grep, first, and read every one of the seven hits on master. 2. Delete the lobby's
members. 3. Delete the subscriptions. 4. Delete the three files. 5. Re-point the four comments. 6. Push.
7. Commit:
`refactor(lobby): the routine proposal-and-vote flow leaves — 620 lines and three subscriptions` + the
trailer.

**Proves:** the flow is gone from the app and the grep is clean; `app-lobby` is unchanged from S7 (a
deletion that moves a frame deleted something the frame needed).

---

### S9 — the shared warm-up screen, and the runner — **L**

**Files:** `GymSyncApp/GymSync/Features/Sessions/WarmUpScreen.swift` (new),
`GymSyncApp/GymSync/Features/Sessions/WarmUpFixtures.swift` (new),
`GymSyncApp/GymSyncTests/WarmUpScreenGateTests.swift` (new),
`GymSyncApp/GymSync/Features/Sessions/LobbyView.swift`,
`GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift`.

Spec §2 and §3.2, owner decisions 3 and 5. Reference frames: `warmup-solo-v2` (122) and `warmup-crew` (111).

**The gate, pure and tested first:**

```swift
enum WarmUpGate {
    /// The warm-up screen renders while the session is live and lifting has
    /// not begun. `warmup_minutes` is deliberately NOT read: spec §6 retires
    /// it ("warm-up is a phase, not a number"), and the clock that used to
    /// end the phase is now a readout.
    ///
    /// THE ONE EDGE, named rather than discovered: a session that was already
    /// `in_progress` with `lifting_started_at IS NULL` when this build shipped
    /// re-enters the warm-up screen once. Every such session's next
    /// "Start lifting" writes `lifting_started_at`, so the state is
    /// self-healing and bounded by one tap.
    static func isWarmingUp(state: String, liftingStartedAt: Date?) -> Bool {
        state == "in_progress" && liftingStartedAt == nil
    }
}
```

**The screen.** One `WarmUpScreen(session:participants:isSolo:…)` with two frames — same body, different
frame (rule 4). Both carry, in this order: the plan card, the clock, and `START LIFTING` as the one accent
primary in the foot.

*Solo frame* (`warmup-solo-v2`):
`SessionPlanCardWithSuggestion` (the whole day, today's rung on top, Coach's line as the card's second line
with Accept / Not today) → `BlockLadderStrip(week:weeks:milestone:)` → `WarmUpClockStrip(elapsed:)` → foot:
`START LIFTING`.

**Check-in lives here for solo** (spec §2's path is *check-in → warm-up*). When the session is `scheduled` /
`lobby_open` and I am not checked in, the foot carries the lobby's own gold **Check In** control above
`START LIFTING` — the same `initiateCheckIn()`, the same travel dialog, the same
`canCheckIn` / `checkInOpensAt` computation, lifted into a small `SessionCheckInControl` in `SessionPieces`
so both screens press the same button. Gold's second job, once (rule 2). **`session-warmup-solo` renders the
checked-in state**, matching the reference frame, and the pre-check-in state is proven by the gate's unit
test rather than a second capture — named as a deviation in I1.

*Crew frame* (`warmup-crew`), after Start:
`SessionReadinessRow(rows:kicker: "WHO'S WARM", count:)` → `SessionPlanCard` → `CoachSuggestionBlock(…,
isPrivate: true)` → `WarmUpClockStrip` → foot: `PTTDockRow` → `START LIFTING` with the leader's note
(`You're the leader · <name> is still warming up`) beneath. The primary stays **live** for the leader while
someone is still warming up — spec §3.2 lets the leader move on, and the note is where that costs something
rather than a second control.

**The RPCs, unchanged.** `START LIFTING` in the crew frame calls
`SessionRepository.markWarmupReady(sessionID:)`; when it returns `true` the screen hands off. The leader's
note row calls `SessionRepository.startLifting(sessionID:)`. Both wrappers
(`SessionRepository.swift:755-787`) and both RPCs are untouched. In the **solo** frame `START LIFTING`
calls `markWarmupReady` too — a party of one satisfies unanimity in one call
(`mark_warmup_ready`'s `EXISTS … AND NOT warmup_ready` finds nobody) — and, when the session is not yet
`in_progress`, `SessionRepository.start(sessionID:)` first.

**The runner.** A thin router beside `SessionInProgressView` (18 lines, the precedent):

```swift
/// While `WarmUpGate.isWarmingUp`, the warm-up screen; then the live view.
/// The whole reason `GroupSessionLiveView` no longer needs an `isInWarmUp`
/// branch (plan task S9).
struct SessionRunnerView: View {
    let session: WorkoutSession
    let participants: [(participant: SessionParticipant, profile: Profile)]
}
```

It owns the poll the warm-up phase used to ride on: a 5-second `.task(id:)` re-reading
`SessionRepository.session(id:)` and `participants(sessionID:)` while warming up — the lobby's own pre-live
poll idiom (`LobbyView.swift:429-441`), never a `Timer` — so another client's `start_lifting` reaches this
one. Realtime stays the fast path via the live view's own channels once it mounts.

`LobbyView.liveSessionSheetContent` (`:592-598`) becomes
`SessionRunnerView(session: effectiveSession, participants: participants).id(effectiveSession.id)`. **The
`.id` pin and the comment above it stay** — that pin is a field-bug fix, not decoration.

**The one change to `GroupSessionLiveView`, and nothing else** (the brief's own bound). Delete:
`warmupRefreshTick` (`:748`), `warmupEndsAt` (`:752-756`), `isInWarmUp` (`:764-777`), the `if isInWarmUp`
arm of `arenaBase`'s page switch (`:2864-2865`), the `if isInWarmUp` arm of `bottomChrome` (`:2968-2970`),
`warmUpPage` (`:2327-2352`), `voteWarmupReady()` (`:2358-2370`), `forceStartLifting()` (`:2376-2386`), the
`.task(id: warmupEndsAt)` wake-up (`:2960-2965`), the `if isInWarmUp { await reloadParticipants() }` line
inside the 10-second poll (`:2948`), and the two `warmup`-column comparisons in that poll's freshness check
(`:2939`, `fresh.liftingStartedAt` / `fresh.warmupMinutes`) — **keep `fresh.liftingStartedAt`**, because the
live view still needs to notice the flip, and drop only `fresh.warmupMinutes`. The page switch goes from
four ways back to three, which is the first line `arenaBase` has lost since the split.

**`WarmUpPhaseView.swift` is NOT deleted.** `WorkoutSessionView.swift:1275` still renders it for the
**ad-hoc solo** path (Home's start control → `SoloWarmupStore`), which this plan does not touch. That leaves
two solo warm-up surfaces for one release: the new screen for a *scheduled* solo session, the old page for
an ad-hoc one. **This is a deliberate deviation, named in I1 and in "What this plan does not decide" 4** —
Phase B owns "one session body" and is where `WorkoutSessionView` adopts the shared screen.

**Tests** — `WarmUpScreenGateTests.swift`: `isWarmingUp` for `in_progress` + nil is true; for
`in_progress` + a date is false; for `lobby_open` + nil is false; for `completed` + nil is false.

**Grep the call site:** `git grep -n "SessionRunnerView("` shows `LobbyView.swift`;
`git grep -n "isInWarmUp"` returns **nothing**.

**TDD steps.** 1. The gate + its test. 2. `WarmUpFixtures`. 3. `WarmUpScreen`, solo frame. 4. Crew frame.
5. `SessionRunnerView`. 6. The lobby's sheet. 7. The eleven deletions in `GroupSessionLiveView`. 8. Push.
9. Commit: `feat(warmup): one warm-up screen for solo and crew; the live view loses its fourth page` + the
trailer.

**Proves:** `session-warmup-solo` and `session-warmup-crew` (S11) render the approved frames, and
`GroupSessionLiveView`'s page switch is three-way again.

---

### S10 — solo never enters the lobby — **M**

**Files:** `GymSyncApp/GymSync/Features/Sessions/SessionEntryView.swift` (new),
`GymSyncApp/GymSyncTests/SessionEntryRouteTests.swift` (new),
`GymSyncApp/GymSync/Features/Home/HomeView.swift`,
`GymSyncApp/GymSync/Features/Home/TrainingCalendarWidget.swift`,
`GymSyncApp/GymSync/Features/Calendar/CalendarSchedulingView.swift`,
`GymSyncApp/GymSync/Features/Social/GroupView.swift`.

Spec §2, owner decision 3. `LobbyView` is documented as *"the app's single entry point for a session
regardless of its current state"* (`HomeView.swift:369`). That sentence stops being true here, and the
router is what keeps it true of **one** type instead of scattering the branch across four call sites.

**The law, pure and tested first:**

```swift
enum SessionRoute: Equatable {
    case lobby        // a crew, before Start
    case warmUp       // a solo session before Start, or anyone during warm-up
    case live         // lifting has begun
}

enum SessionRouter {
    /// `participantCount` and `roomCode` decide solo (SessionShape.isSolo,
    /// task S3) — never `group_id`.
    static func route(state: String,
                      liftingStartedAt: Date?,
                      participantCount: Int,
                      roomCode: String?) -> SessionRoute
}
```

- `state == "completed"` / `"abandoned"` → `.live` (the live view already self-presents the recap; this
  router adds no new terminal screen).
- `WarmUpGate.isWarmingUp(state:liftingStartedAt:)` → `.warmUp`.
- `SessionShape.isSolo(participantCount:roomCode:)` → `.warmUp`.
- otherwise → `.lobby`.

**The view.** `SessionEntryView(session:)` fetches `SessionRepository.participants(sessionID:)` **once** —
the count is what decides, and no cheaper signal is honest — renders a quiet centred `ProgressView` while it
resolves, then routes, handing the fetched participants down so the destination does not refetch on first
paint. On a failed fetch it falls through to `.lobby`, the shipped behaviour, and shows the error line the
lobby already renders.

**The four call sites** — one line each, keeping the `.id(session.id)` pin and its comment at every one:

| file:line | from | to |
|---|---|---|
| `HomeView.swift:353` | `LobbyView(session: session)` | `SessionEntryView(session: session)` |
| `TrainingCalendarWidget.swift:189` | same | same |
| `CalendarSchedulingView.swift:242` | same | same |
| `GroupView.swift:455` | same | same |

Update `HomeView.swift:369`'s doc comment, which names `LobbyView(session:)` as the single entry point, to
name `SessionEntryView` and say what it decides. A stale comment that contradicts the code is how the next
reader learns the wrong law.

**Tests** — `SessionEntryRouteTests.swift`, pure, eight cases: scheduled solo → warmUp; scheduled crew →
lobby; scheduled two-person `.friends` (count 2, no room code) → **lobby**; scheduled `.code` (count 1, room
code) → **lobby**; in_progress + nil lifting → warmUp (solo and crew alike); in_progress + a lifting date →
live; completed → live; abandoned → live.

**Grep the call site:** `git grep -n "LobbyView(session:"` shows **only** `SessionEntryView.swift`.

**TDD steps.** 1. The tests. 2. `SessionRouter`. 3. `SessionEntryView`. 4. The four call sites and the doc
comment. 5. Push. 6. Commit:
`feat(sessions): a scheduled solo session goes to warm-up, never to a crew lobby` + the trailer.

**Proves:** `testLobby()` still reaches the lobby (the seeded session is a crew session, so the route is
unchanged for it) — and the two-person `.friends` case, which `group_id == nil` would have mis-routed, is
pinned by a test rather than by a comment.

---

### S11 — the catalog: six production ids in, ten variation ids out — **M**

**Files:** `GymSyncApp/GymSync/App/CatalogHostView.swift`,
`GymSyncApp/GymSyncTests/CatalogScreenTests.swift`,
`GymSyncApp/GymSyncUITests/ScreenshotTests.swift`, `docs/design/frame-map.json`, and the deletion of four
files in `GymSyncApp/GymSync/Features/Sessions/Variations/`.

**One commit.** Constraint 6 in both directions, which is the only way the FLOOR arithmetic is legible.

**In** — six cases, six builders, six id strings, six `testCatalog…()` methods, six frame-map entries, as
tabled in "New catalog ids". The builders:

```swift
    /// `session-lobby-waiting`: the production LobbyView over a fixture crew —
    /// two checked in, one at the gym, one on the way. Built to the design
    /// round's `lobby-crew-waiting-v2` (frame 120), which this id retires.
    private var content_sessionLobbyWaiting: some View {
        NavigationStack { LobbyView(catalog: LobbyFixtures.waiting) }
    }
```

— wrapped in a `NavigationStack` because `LobbyView` sets `.navigationTitle` and carries toolbar items, both
no-ops without one (the `content_ladderOnTrack` precedent, `CatalogHostView.swift:2078-2081,2193-2198`). The
warm-up ids are **not** wrapped: `WarmUpScreen` is a `VStack` on `theme.bg` with no navigation chrome.
`ladder-reladder-proposal` is wrapped and passes both `world:` and `proposal:`:

```swift
    private var content_ladderReladderProposal: some View {
        NavigationStack {
            LadderPageView(goalID: StubBlockGoalRepository.fixtureGoalID,
                           world: StubBlockGoalRepository.fixturePage,
                           proposal: StubBlockGoalRepository.fixtureProposal)
        }
    }
```

Frame-map entries take frames **129-134** in the table's order, and the first one carries the round's
`note` idiom naming this plan and why these six have no numbered canvas frame:

```json
  "session-lobby-waiting": {
    "frame": 129,
    "title": "Crew lobby, waiting - the arrival track, the plan, the crew's energy",
    "note": "Phase A of the group-session round (docs/superpowers/plans/2026-09-12-group-session-phase-a-plan.md, task S11). Frames 129-134 are the PRODUCTION screens built to the design round's approved compositions; the round's own ids (frames 106-111, 120-122, 127) are retired in the same commit, so these six replace ten. No proof frame in docs/design/mockups/ - the authority is the spec and the retired frames, which is the Home v3 -> production precedent. parity_diff.js logs 'skip session-lobby-waiting: no proof frame'."
  },
```

**Out** — ten ids, the reverse contract, plus the view code they rendered:

- delete `LobbyVariations.swift` (holds `lobby-crew-waiting-a`, `-b`, `lobby-crew-ready` — all three
  retired);
- delete `LobbyVariationsV2.swift` (`lobby-crew-waiting-v2`, `lobby-crew-ready-v2`, and `SVLockedInCard` /
  `SVFirstUpCard`, whose only other user is the retired `lobby-crew-ready-v3`);
- delete `WarmupVariations.swift` (`warmup-solo-a`, `-b`, `warmup-crew`, and `SVWarmupClock`);
- delete `WarmupVariationsV2.swift` (`warmup-solo-v2`, `SVPlanListCardWithSuggestion`);
- edit `SessionVariationsV3.swift`: remove `LobbyCrewReadyV3View`, `SVLockedInAccentCard`,
  `SVSecondaryStart` and the whole `SVFixturesV3` enum (all four of its strings are lobby strings); **keep
  `RoundSpotterV3View`**, which is Phase B's.

Then delete the symbols in the two kits that the deletions orphan, **checked by grep and not by memory** —
on the pre-deletion tree these are used only by retired frames: `SVArrivalRail`, `SVRosterCard`,
`SVRosterRow`, `SVCrewEnergyCard`, `SVEnergyMeter`, `SVProgramLadder`, `SVPlanCard`, `SVSuggestionBody`
(check `StyleVariations.swift` first — `SVSuggestionStrip` survives there), `SVReadinessRow`, and
`SVFixtures`' warm-up/lobby members. **Run `grep -o` per symbol across the folder before deleting each
one**; a Phase B frame that loses a component is a red build and a wasted CI cycle.

**Do not bump `FLOOR`** — I1 does it once (constraint 7).

**TDD steps.** 1. Add the six ids, all four parts each. 2. Retire the ten, all four parts each, plus the
view code. 3. The per-symbol grep. 4. `python -c` over `frame-map.json` to assert 89 entries, max frame 134,
and no duplicate frame numbers. 5. Push. 6. Commit:
`feat(catalog): six production session frames in, ten design-round frames out` + the trailer.

**Proves the stage:** six new `app-session-*` / `app-ladder-reladder-proposal` captures in the artifact,
ten gone, `CatalogScreenTests` green (its count guard is the test), and `app-lobby` still exported.

---

# INTEGRATION

Three tasks on `feat/group-session-phase-a`.

### I1 — the FLOOR, the frame-map and the accepted deviations — **S**

- `.github/workflows/ios.yml` — **the FLOOR moves by `−4` against master's FLOOR at integration**, which is
  the invariant. Re-derive the literal on the day:

  ```
  git fetch origin
  grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1
  grep -c 'captureCatalog(' GymSyncApp/GymSyncUITests/ScreenshotTests.swift
  grep -c 'func test' GymSyncApp/GymSyncUITests/ScreenshotTests.swift
  ```

  Against the assumed base that is `FLOOR=137` → `FLOOR=133`. Extend the comment block above the line in the
  style the social-cards I1 established:

  ```
  # group session Phase A (I1, 2026-09-12-group-session-phase-a-plan.md):
  # 137 -> 133. SIX production captures in (session-lobby-waiting 129,
  # session-lobby-ready 130, session-lobby-late 131, session-warmup-solo 132,
  # session-warmup-crew 133, ladder-reladder-proposal 134) and TEN design-round
  # captures out (frames 106-111, 120-122, 127 — the lobby and warm-up
  # variation families, replaced by the production frames above). The -4 is the
  # invariant, not the literal 133. app-lobby is RE-RENDERED by the de-furnished
  # LobbyView (task S7), not added, so it moves no count.
  ```

  **A falling FLOOR is the one case where the literal must be right**, because a floor above the real count
  fails every run. Count the exported files in the last green artifact before writing it.

- `docs/design/frame-map.json` — verify 129-134 present, 106-111 / 120-122 / 127 absent, 1-105 and the
  surviving 112-119 / 123-126 / 128 unrenumbered, and no duplicate frame numbers.

- `docs/design/accepted-deviations.json` — append **six** entries, one per new id, each naming the retired
  frame it was built to and the spec section that is its authority. The `session-warmup-solo` entry
  additionally records the two deviations that frame shows:

  ```json
  {
    "screenId": "session-warmup-solo",
    "reason": "Group session Phase A, integration task I1. Frame 132 (task S9) has no numbered canvas frame - the authority is spec section 2 of 2026-09-12-group-session-and-lobby-design.md and the design round's warmup-solo-v2 (frame 122), which this id retires in the same commit. TWO deviations are visible in it. (1) The frame renders the CHECKED-IN state: spec section 2's path is check-in then warm-up, so the screen carries the lobby's own gold Check In control when a scheduled session is not yet checked in, but the approved composition has no check-in row and the production frame matches the composition; the pre-check-in state is pinned by WarmUpScreenGateTests instead of a second capture. (2) WarmUpPhaseView still serves the AD-HOC solo path from WorkoutSessionView:1275, so for one release a scheduled solo session and an ad-hoc one warm up on different screens; Phase B's 'one session body' is where that closes."
  }
  ```

Commit: `chore(sessions): FLOOR 137 -> 133, frames 129-134 in and ten out, accepted deviations` + the
trailer.

### I2 — end-to-end CI, then by eye — **M**

Push and read the run. **Download the artifact into a fresh directory** (constraint 12).

**iOS workflow**
- build green;
- `GymSyncTests` green — **ten new test files**: `LadderProposalTests`, `GSConsentCardCopyTests`,
  `SessionArrivalTests`, `SessionPiecesCopyTests`, `SessionEnergyLiveTests`, `SessionCoachThreadLiveTests`,
  `WarmUpScreenGateTests`, `SessionEntryRouteTests` — plus `CatalogScreenTests`' count guard, which now
  carries six more ids and ten fewer, and `ProposalRepositoryTests` **absent**;
- the screenshot job exports **≥ the new FLOOR** and "Verify capture count" passes.

**Backend workflow**
- pgTAP green for `session_participant_energy_test.sql` (new, 8) and `session_coach_thread_test.sql` (new,
  10) — which requires D1's and D3's migrations to have been **applied to the project** (constraint 8). A
  red with a "does not exist" error means the gate was skipped, not the SQL broken.

**Then read the artifact, by eye, in this order:**

1. `app-home-v3-08a-targets-above-calendar` and `-08b-targets-above-join` — **unchanged** (0 % of pixels
   differ in the compared band). The canary for S1/S2; if either moved, the ladder card was put in a shared
   file and S2 must be fixed rather than the frame re-approved.
2. `app-tab-home` — **unchanged**. The CI account has no pending proposal, so the card must not appear.
3. `app-ladder-reladder-proposal` — the card above the rungs: `COACH PROPOSES A NEW LADDER`, one sentence,
   `Accept` and `Not today` as **raised** faces, `LET COACH RE-LADDER` still present below, and **no second
   accent** anywhere on the page.
4. `app-session-lobby-waiting` — the three-column track with two avatars in CHECKED IN, one in AT THE GYM,
   one in ON THE WAY; `Talk to Coach`; four plan rows with aligned prescriptions and a Swap chip on each;
   the energy card with three meters and one `not yet` plus `How are you feeling?`; the dock; a **disabled**
   accent Start captioned `2 of 4 checked in`. No roster, no proposals, no warm-up stepper, no soundboard.
5. `app-session-lobby-ready` — the **accent** arrival card reading `Everyone's here. Let's work.` with four
   inverted avatars and their energy, the leader's caption and a chevron; FIRST UP with the rest of the day
   named; and a **neutral** Start in the foot under `Same action, in the thumb zone`. Exactly one accent
   object on the page.
6. `app-session-lobby-late` — three in CHECKED IN, one late in ON THE WAY, Start live and captioned.
7. `app-session-warmup-solo` — the plan card holding four exercises with Coach's line under a rule inside
   it, `Accept` / `Not today`, the eight-rung ladder with the milestone flag, the clock as a 22 pt strip,
   `START LIFTING` the one accent.
8. `app-session-warmup-crew` — `WHO'S WARM · 3 OF 4` with green ticks on three, the plan, the private
   Coach line carrying `Only you see this.`, the dock, `START LIFTING` with the leader's note.
9. **`app-lobby`** — the **live** account's real `LobbyView`, showing the de-furnished composition against
   seeded data. This is the one capture a fixture cannot stand in for: an empty or old-looking lobby here is
   a defect in the seam, the fetch or the route, not in the fixture.
10. `app-group-sessions` and `app-session-recap` — **unchanged**; the seed still writes six session states
    because the CHECK was not touched.

Fix-forward any red; each fix is its own commit on the integration branch.

### I3 — one PR, with proof cards — **M**

`feat/group-session-phase-a` → `master`. The body carries:

1. **What shipped**, in the spec's own vocabulary: the lobby is where a crew waits, and checked in is ready;
   warm-up is one screen both frames of the app share; a ladder is never re-laddered unasked.
2. **The six new catalog ids, the ten retirements, and the FLOOR change** (−4), as this plan's table.
3. **The two migrations**, and how and when each was applied to `chjkkwqwdlmaxacwglzm`.
4. **The deliberate deviations**, each with its reason:
   - **`session_participants.energy` ships with no new RLS policy** — the two shipped policies already grant
     exactly what spec §6 asks for, and a third would be permissive-ORed noise. (D1, D2.)
   - **the Coach thread needed a column, two policies and two helper functions** the spec did not list —
     spec §6 calls it "the existing coach-chat thread model keyed by `session_id`" and that model has no
     subject key and is single-owner. (D3.)
   - **the `editing` / `voting` / `locked` states are NOT dropped from the CHECK.** Nothing writes them in
     production, but `scripts/seed_qa_fixtures.js:306`, `supabase/tests/rls_proposals_test.sql:19`, the
     `livekit-token` edge function and its Deno test all reference them. The grep is in the plan; Phase B
     carries the migration.
   - **the proposal tables stay while their code goes** — the soundboard precedent (owner decision 14).
   - **consensus Start is a client-side one-shot on the leader's device**, not a server rule —
     `start_session` is organizer-gated and frozen, and the crewmate's caption says exactly what will
     happen.
   - **AT THE GYM is presence-published and can only be reached by a device that already has location
     permission** — no column stores where anyone is, and a prompt from the lobby's `.task` would hang
     `testLobby()`.
   - **solo is `participantCount <= 1 && roomCode == nil`, never `group_id == nil`** — the condition the
     shipped code's own comment mislabels "solo", and the crash report's H4.
   - **`WarmUpPhaseView` survives for the ad-hoc solo path**, so one release has two solo warm-up surfaces;
     Phase B closes it.
   - **`session-warmup-solo` renders the checked-in state**, matching the approved composition; the
     check-in state is pinned by a unit test.
   - **the FLOOR falls.** Six frames replace ten, so this is a plan whose N is negative — the arithmetic is
     in `ios.yml`'s comment block.
5. **Proof cards**, each a CI run URL plus its specific evidence:
   - **The data** — Backend green: `session_participant_energy_test.sql` 8/8 (including the assertion that
     no session-engine trigger blocks an energy-only self-update) and `session_coach_thread_test.sql` 10/10
     (including the lapsed-Pro case).
   - **The suggestion principle** — `git grep -n "reLadder(goalID:"` showing no caller inside
     `detectGoalIfMissing`; `app-ladder-reladder-proposal`; and `app-home-v3-08a/08b` unchanged.
   - **The lobby** — `app-session-lobby-waiting`, `-ready` and `-late` side by side with the retired
     `lobby-crew-waiting-v2` and `lobby-crew-ready-v3` from the design round's own run (name that run),
     **and `app-lobby`**: the same composition through the production path against seeded data.
   - **The warm-up** — `app-session-warmup-solo` and `app-session-warmup-crew`; plus
     `git grep -n "isInWarmUp"` returning nothing and `GroupSessionLiveView`'s page switch back to three
     ways.
   - **The removals** — `git grep -n "RoutineProposal\|ProposalRepository"` clean; the three realtime
     subscriptions gone; `app-group-sessions` unchanged.
6. The trailer per constraint 5, plus `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## What this plan does not decide

1. **How a lifter reads as AT THE GYM before they check in.** The stage is presence-published (S3) and the
   publishing device needs location authorization it may not have, so in practice the middle column fills
   only for lifters who have already granted location. A background geofence, or a `session_participants`
   column the client writes on entering the fence, would make the column mean what the spec's picture shows.
   Phase A ships the honest version and the empty column keeps its place, which is what the track's design
   already required.
2. **Whether the consensus Start should be a server rule.** S7 fires it from the leader's device after a
   3-second cancellable delay. If the leader's phone is asleep, nothing fires and the crew waits — which is
   the shipped behaviour and no worse. A server-side "last check-in starts the session" would need
   `start_session` to lose its organizer gate, and constraint 18 forbids that in Phase A.
3. **What "Swap" does before Start beyond choosing the session's routine.** S7 wires the per-row Swap to
   the shipped routine picker. Spec §3.4 mode 1 (the consensus card) is Phase B and is what a swap becomes
   *after* Start; a per-exercise pre-Start substitution is a third thing nobody has asked for.
4. **When `WorkoutSessionView` adopts the shared warm-up screen.** Named as a deviation above; Phase B's
   "one session body" is the round that closes it, and until then `SoloWarmupStore` and `WarmUpPhaseView`
   are live for the ad-hoc path.
5. **What the crew's Coach thread says when it opens.** S6 opens the room; the thread's seeding — this
   session's focus, the pointed form question, the demo video that spec §3.1 promises in the row's own
   subtitle — is Coach's engine work and belongs with the round-wait and spotter entries (Phase B), which
   share the same door.
6. **Whether energy should decay or expire.** The column is per-session and written once; nothing re-asks a
   lifter who reported 2 an hour before a session that started late. Spec §6 asks for a value, not a
   lifecycle.
7. **Whether the lobby should show a crewmate's energy before they check in.** It does — the card is "how
   the crew feels", not "how the crew who arrived feels" — but nobody ruled on it.

---

## Self-review (run by the planner, 2026-09-12)

**1. Spec coverage — every Phase A sentence maps to a task.**

| spec | requirement | task |
|---|---|---|
| §1 | *lobby* = crew only; *on the way / at the gym / checked in*; checked in is ready | S3 (`ArrivalStage`, `ArrivalLaw`), S7 |
| §1 / decision 12 | "on the way" = lobby open, outside the geofence circle | S3 — and gap 1: the geofence half is presence-published |
| §2 / decision 3 | solo has no lobby; check-in → warm-up | S10 (the route), S9 (the check-in control on the warm-up screen) |
| §2 | the plan card carries the whole day, with a swap control | S4 (`SessionPlanCardWithSuggestion`), S9 |
| §2 | Coach's one suggestion as the card's second line, Accept / Not today | S4 (`CoachSuggestionBlock`), S9 |
| §2 | the where-you-are line — the block's rungs with the milestone flagged | S4 (`BlockLadderStrip`), S9 |
| §2 | `warmup-solo-v2` is the reference frame | S9, S11 (frame 132 replaces frame 122) |
| §3.1 | the arrival track, and no separate roster or ready tick | S7 |
| §3.1 | Talk to Coach as one entry row | S4, S6, S7 |
| §3.1 | the whole session plan, a Swap per row for the leader | S4, S7 |
| §3.1 / decision 18 | how the crew feels — energy 1-5, own control until answered | D1, D2, S5, S7 |
| §3.1 | the talk dock stays, as shipped in `PTTDockRow` | S7 (kept, untouched) |
| §3.1 | Start, captioned with the count; the leader's tap or consensus | S3 (`checkedInCaption`), S7 |
| §3.1 | "Start anyway" stays for the leader | S7 (the shipped dialog, unchanged) |
| §3.1 / decision 20 | the all-ready track turns accent, reads the sentence, starts the session; the bottom Start is a neutral secondary | S4 (`EveryoneHereCard`, `SecondaryStartButton`), S7 |
| §3.1 | gone: the proposal-and-vote flow and its three realtime subscriptions | S8 |
| §3.1 | gone: the warm-up minutes stepper | S7 |
| §3.1 | gone: every soundboard reference | **nothing to build** — `grep -in "sound\|plate" LobbyView.swift` returns one hit, a *comment* at `:309` describing how the live view stacks its dock; S7 deletes the surrounding block anyway. The lobby and the warm-up screen have no soundboard code. Recorded so the absence is verified rather than assumed. |
| §3.2 / decision 5 | Start opens the shared warm-up screen; the style phase begins when everyone is warm or the leader moves on | S9 |
| §3.2 | Coach's line is private to each lifter in the crew frame | S4 (`isPrivate`), S9 |
| §3.2 | `mark_warmup_ready` / `start_lifting` stay | S9 — called, not changed (constraint 18) |
| §3.6 / decision 19 | one Coach thread per session, shared, unlocked while any member is Pro, server-evaluated; the paywall for whoever taps when nobody is | D3, D4, S6, S7 |
| §4 / decision 4 | every weight, volume or set change is a suggestion | S1 (the write removed), S2 (the card), S4 (Accept / Not today everywhere) |
| §4 | `BlockGoalLiveRepository:1074` stops applying the re-ladder inside the detect path | S1 |
| §4 | the card is on Home **and** the ladder page, applied on accept | S2 |
| §4 | `LET COACH RE-LADDER` remains | S2 — untouched at `LadderPageView.swift:380-383` |
| §4 | weekly-goal proposals already comply; build-time titration is untouched | **nothing to build** — verified: `HomeView.coachProposal` (`:1823`) already gates on `WeeklyGoalProposalRule.isMeaningful` and renders through the editor sheet's Accept |
| §4a | heart-rate zones keep their colours | **nothing to build in Phase A** — no Phase A screen shows a heart rate; constraint 13 forbids introducing one |
| §5 | the dead states and the proposal-vote flow leave | S8 for the flow; the states are **ruled not droppable** — see "The three dead states", with the grep |
| §5 | the soundboard, the spectate subtree, the pump-check card | Phase B, out of scope |
| §6 | `session_participants.energy smallint`, null until reported, existing policy | D1, D2, S5 |
| §6 | the Coach thread keyed by `session_id`, participant read policy, server-side Pro gate | D3, D4, S6 |
| §6 | `warmup_minutes` becomes unused | S7 (last writer), S9 (last reader) — the column and its setter stay (constraint 18) |
| §6 | the suggestion principle needs no new table | S1 — `LadderProposal` is a value, recomputed per read |
| §6 | RLS unchanged in shape | D1 adds none; D3 adds four **additive** policies beside the owner policy |
| §7 | production frames for the lobby (waiting, everyone ready, a late arrival), the crew warm-up, the solo warm-up | S11 — frames 129-133 |
| §7 | the variation ids are retired as each production frame replaces them | S11 — ten out |
| §7 | proof cards before merge; FLOOR moves by the count of new captures | I1, I3 — and the count is **negative**, which the spec did not anticipate |
| §8 item 2 | Phase A = the lobby and the shared warm-up screen | the whole of Stream S, S3-S11 |
| §8 item 4 | the re-ladder proposal card ships with Phase A | S1, S2 |
| decisions 1, 2, 6, 7, 9, 11, 13, 15, 17 | styles, stations, turn order, spotter, the two change modes, the hold threshold, HR sharing, encouragement, the colour exception | Phase B — none is foreclosed: no Phase A file touches `sessions.style`, `stations`, `round`, or any heart-rate surface |

**One spec correction, made deliberately.** §5 lists the three dead states as leaving the app. They cannot
in Phase A: two of them are written by `scripts/seed_qa_fixtures.js:306`, which is the fixture every session
walk in `ScreenshotTests` depends on, and a third by a pgTAP fixture. The plan removes the flow they were
designed for and hands the CHECK to Phase B with the grep attached. §7's *"FLOOR moves by the count of new
captures"* is also corrected: six new captures retire ten, so the FLOOR **falls** by four — the arithmetic
that matters is the artifact's.

**2. Placeholder scan.** Grepped the finished document for `TBD`, `TODO`, `FIXME`, `XXX`, `add validation`,
`similar to`, `same as above`, `<fill`, `and so on`, `etc.`: **zero hits outside this sentence**. Every task names its files, its
exact code or exact behaviour, its tests, its commit message and its `Proves:` capture. The three "Phase B"
markers are scope statements the spec itself makes, each listed in "What this plan does not decide" or in
the coverage table.

**Four things this review changed, rather than noted.**

1. **The first draft made "solo" `group_id == nil`**, straight from `LobbyView.swift:1434-1443`'s own
   comment. Checked against `ScheduleSessionView.swift:778-786`: `.friends` and `.code` both leave
   `group_id` nil. A two-person ad-hoc session would have been routed to a solo warm-up screen with no
   lobby, no dock and no Start for the other lifter — and every catalog frame would have looked right,
   because a fixture has one participant. `SessionShape.isSolo` and its three tests come from that check.
2. **The first draft added an RLS policy for `energy`.** Read `20260712000001:22-25`: the self-UPDATE policy
   has no column list, and permissive policies OR. The new policy would have granted nothing while reading
   as though it had. What the read *did* surface is the real risk — three `BEFORE UPDATE` triggers on that
   table — so D2 asserts the write passes them.
3. **The first draft said "key the Coach thread by `session_id`", as spec §6 does.** Read
   `20260824000005_coach_chat_threads.sql`: no subject column exists, the only policy is `user_id =
   auth.uid()`, and `CoachThreadLauncher` fakes subjects in the `title` string. A thread "keyed by session"
   would have been invisible to every crewmate. D3's column, unique index, four policies and two helpers all
   come from that read.
4. **The first draft gated the warm-up screen on `warmup_minutes > 0`**, copying `isInWarmUp`
   (`GroupSessionLiveView.swift:764-777`). But spec §6 retires that column, so every session would have
   skipped warm-up entirely the moment the stepper was deleted. `WarmUpGate.isWarmingUp` reads
   `lifting_started_at` instead — which surfaced the migration edge (a session already in flight at deploy)
   now named in the gate's own doc comment.

**3. Cross-task symbol consistency.** Every cross-task symbol was grepped across this document for a single
spelling. The near-miss spellings a second author would plausibly reach for — `ArrivalState`,
`SessionArrivalRail`, `LadderReProposal`, `SessionChatRepository`, `WarmUpView`, `SessionRouterView`,
`setEnergyLevel` — appear nowhere in this document except in this sentence. (`CoachThreadRepository` is
deliberately *not* on that list: it is a substring of the real `SessionCoachThreadRepository`, so a grep for
it can never be clean and would give a false alarm every time.)

- `ArrivalStage` — three cases, declared S3; read by `ArrivalLaw.stage` (S3), `SessionArrivalTrack` (S4),
  `LobbyView` (S7), `LobbyFixtures` (S7), and published as `rawValue` by `LobbyRealtimeService` (S3). One
  spelling, one case order.
- `ArrivalRow` — seven fields (`id`, `name`, `avatarURL`, `stage`, `energy`, `isYou`, `isLate`); built in
  S7 from `(SessionParticipant, Profile)` and in `LobbyFixtures`; consumed by `SessionArrivalTrack`,
  `CrewEnergyCard` and `EveryoneHereCard` with the same field names at every site.
- `SessionShape.isSolo(participantCount:roomCode:)` — one signature, two callers (`SessionRouter.route` in
  S10, and its tests). Never inlined.
- `WarmUpGate.isWarmingUp(state:liftingStartedAt:)` — one signature, two callers (`SessionRunnerView` and
  `SessionRouter.route`), so the router and the runner cannot disagree about what warm-up is.
- `LobbyCopy` — six members (`checkedInCaption`, `everyoneHere`, `readyLeaderCaption`,
  `readyCrewmateCaption`, `secondaryStartNote`, `energyReported`); asserted in `SessionArrivalTests`,
  rendered in S7. The two owner-verbatim strings (`Everyone's here. Let's work.`,
  `Waiting for … — or it starts on its own`) appear in exactly one place each.
- `LadderProposal` — five fields (`goalID`, `current`, `proposed`, `changed`, `derivedAt`); produced by
  `BlockGoalRepository.reLadderProposal(goalID:)` (S1) and `StubBlockGoalRepository.fixtureProposal`;
  rendered through `LadderProposalMath.sentence(_:unit:)` into `GSConsentCard` at both call sites (S2).
- `GSConsentCard` — seven parameters (`kicker`, `sentence`, `detail`, `acceptTitle`, `declineTitle`,
  `onAccept`, `onDecline`); called by `HomeView` and `LadderPageView` with the same labels.
- `SessionCoachThread` — two fields (`threadID`, `unlocked`); produced by
  `SessionCoachThreadRepository.open(sessionID:)`, read through `isReachable(_:)`, rendered by
  `CoachDoorRow` (S4) at its one call site in `LobbyView` (S7).
- `SessionRepository.setEnergy(sessionID:value:)` — one signature; called from `LobbyView`'s energy control
  and from `SessionEnergyLiveTests`, with the same labels in the same order.
- `SessionRunnerView(session:participants:)` — one initializer, one call site
  (`LobbyView.liveSessionSheetContent`), and it is the only thing that renders `WarmUpScreen` in production.
- The six production catalog ids appear identically in five places each: the plan's two tables, the enum
  case, the `ids` array, the capture method and the frame-map key. All six carry the `session-` /
  `ladder-` prefix and none collides with a retired id (constraint 15).

**Gaps I could not close, named rather than papered over:**

- **The middle column of the arrival track is, in practice, reachable only for a device that already has
  location permission.** Written up as gap 1 and as a PR deviation. The alternative — asking for location
  from the lobby's `.task` — is forbidden by constraint 10 for a reason this repo has already paid for once.
- **Consensus Start has no server rule**, so a leader whose phone sleeps leaves the crew waiting. Gap 2. It
  is not a regression (today nothing fires at all) and the crewmate's caption is honest about it, but it is
  weaker than spec §3.1's "fires when everyone is checked in" reads.
- **Two solo warm-up surfaces ship for one release.** Gap 4 / a PR deviation. Closing it inside Phase A
  would mean editing `WorkoutSessionView` (4,000+ lines) and its `soloWarmupPage`, which the brief scopes to
  Phase B and which would put a second large session file in this branch's blast radius.
- **`app-lobby` is the only production capture of the new lobby against real data, and its seeded crew has
  one participant checked in.** The three fixture frames carry the compositions; the live walk carries the
  path. If the seed's crew grew a second checked-in participant, the live walk would also exercise the
  all-ready state — that is a `seed_qa_fixtures.js` change this plan deliberately does not make, because
  the seed is shared with four other walks and changing it to flatter one frame is how a fixture starts
  lying.
- **Nothing in Phase A proves the crew Coach thread end to end with two accounts.** D4 proves the policies
  with two roles inside one transaction; `SessionCoachThreadLiveTests` proves one account's round trip. A
  genuine two-device read is a manual check, and it is listed as such in I3's proof cards rather than
  claimed by a test.
