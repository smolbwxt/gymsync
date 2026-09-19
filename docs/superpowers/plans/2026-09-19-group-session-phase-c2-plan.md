# The old solo screen is emptied and deleted — Phase C2 — implementation plan

**For agentic workers.** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Every task below is
one subagent, one commit, one review. Do not batch tasks. **The intended model is written beside every
task** and in the sequencing table.

**Milestone served: M1 · One session body** (`docs/superpowers/plans/2026-09-19-v0-roadmap.md`). M1's exit
criterion, quoted:

> **Exit:** exactly one warm-up screen and one logging screen exist. Every capability the old solo screen
> had is moved, or retired with a written reason in the capability ledger.

C2 is the second and last half of M1. C1 (PR #79, TestFlight 1053) made an ad-hoc solo workout **run** in
the one session body. C2 empties the old body and deletes it: `Features/Workout/WorkoutSessionView.swift`
(4,929 lines) and `Features/Sessions/WarmUpPhaseView.swift` (416 lines) leave the tree, every row of the
C1 capability ledger gets a verdict backed by a merged task, and a workout the lifter walks away from is
**abandoned on the server** instead of standing open.

**Architecture.** Five moves, in order of dependence:

1. **The routine editor moves, and it meets slot-keyed state.** C1 keyed swaps (`self_swaps` /
   `squad_swaps`), progress (`SlotProgress`) and set rows (`set_logs.routine_exercise_id`) by routine
   SLOT. `SessionRoutineEditor` rebuilds the slot list mid-session. This is the phase's highest-risk seam
   and it is decided in full in decision 2 and asked at the FIRST app task's review, not at the end.
2. **ABANDON gets its user-initiated door.** The server side already exists — `'abandoned'` has been a
   legal `sessions.state` since the table's first migration and a 6-hour reaper already flips idle rows
   (decision 1). What is missing is a verb the lifter can reach: Discard on the live body, END on the
   warm-up, and a lazy sweep of the lifter's own stale rows at the next start.
3. **The remaining solo-only capabilities move behind the predicate that exists.** `FormClipCapture`,
   Coach's five solo hooks, and — a correction — the swap door, which in the one body is already
   ungated.
4. **Finish, recap, Pump post and discard converge on `presentCompletion`.**
5. **Both files are deleted, in one commit, with the four-part catalog contract run in reverse.**

**Tech stack.** Swift 6 / SwiftUI (iOS 17 target), Supabase Postgres + PostgREST + RLS, pgTAP, XCTest +
XCUITest, GitHub Actions (`ios.yml`, `backend.yml`), XcodeGen (`GymSyncApp/project.yml` — `sources:` is a
directory glob, so **no `project.yml` edit is needed for a file added, moved or deleted** under
`Features/`).

**Spec (the authority):** `docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md`, §2, §3.4,
§4, §8. Round artefacts: the C1 plan
(`docs/superpowers/plans/2026-09-19-group-session-phase-c-plan.md` — "C2 — the outline", the 24-row
capability ledger, decision 7, Global Constraints), the C1 ledger
(`.superpowers/sdd/2026-09-19-group-session-phase-c/progress.md`), the C2 context map
(`.superpowers/sdd/2026-09-19-group-session-phase-c2/context-map.md` — a map, not an authority; the
corrections it earned are in "Self-review").

**Owner directive (2026-09-18/19), binding.** **Function before design.** No design rounds, no variation
frames, no owner-pick gates. Moved capabilities keep the UI they have today. Every surface **newly
reachable** in the one body gets **one** hermetic proof frame. Open owner decision #6 (the style selector
moves to the warm-up) **defaults to M4 and is not planned here.** **No task may build into the logging
screen's top-left slot** — heart rate leaves it in M4.

---

## Base branch — read this first

**This plan is committed on `feat/group-session-phase-c2`, cut from `origin/master` at `8e9112e`**, in a
new worktree `G:/Projects/GymSync-wt/wt-phase-c2-release`. The main checkout (`G:/Projects/GymSync`) and
every other worktree stay where they are. Verified in that worktree at `8e9112e` on 2026-09-19, by
running the commands, not by copying the map:

```
git log --oneline -1                                                     # 8e9112e (PR #81, the roadmap)
grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1                     # FLOOR=140   (line 471)
python -c "import json;d=json.load(open('docs/design/frame-map.json'));print(len(d), max(v['frame'] for v in d.values()))"
                                                                         # 97 159
grep -c '^    case ' GymSyncApp/GymSync/App/CatalogHostView.swift        # 118
grep -c 'captureCatalog(' GymSyncApp/GymSyncUITests/ScreenshotTests.swift # 119 → 116 real (see below)
wc -l …/WorkoutSessionView.swift …/SessionLiveView.swift                 # 4929 / 6185
```

| | at `8e9112e` |
|---|---|
| base | `feat/group-session-phase-c2` @ `8e9112e` (= `origin/master`) |
| `FLOOR` (`ios.yml:471`) | **140** — its comment block already anticipates this phase: "solo-live-set (frame 66) retires with WorkoutSessionView in C2 (-1)" |
| frames taken | 1-159, zero duplicates; **next free: 160, 161** |
| `CatalogScreen` cases / test ids | **118** each |
| real `captureCatalog("…")` calls | **116** — `grep -c` prints 119 because it also counts the function's own definition and two comments |
| `WorkoutSessionView(` call sites | **exactly one**, `App/CatalogHostView.swift:1979` (the catalog builder). Two other mentions (`DiscoverWorkoutDetailView.swift:65`, `HomeView.swift:2246`) are comments explaining why they no longer call it |
| `WarmUpPhaseView(` call sites | **exactly one**, `WorkoutSessionView.swift:1531` — it dies with the file |
| `sessions.state` CHECK | `('scheduled','lobby_open','in_progress','completed','abandoned')` — `'abandoned'` is **already legal**; C2 adds no state |
| a writer of `'abandoned'` in the app | **none** — every `"abandoned"` literal in `GymSyncApp` is a reader; the two `ProgramRepository` writes are a different table's `reason` column |
| `SoloSessionShape.isAdHocSolo` | **does not exist** — C1 replaced it with `isSoloByConstruction(groupID:roomCode:scheduledFor:)` (`SoloSessionLayer.swift:142-146`). The C1 plan's C2-S1 row is stale on this |
| pgTAP fixture namespaces taken | `01xx`-`13xx`, `15xx`-`18xx`. **This plan takes `19xx` (D1).** |
| migrations this plan adds | **none.** See decision 1 |
| in flight beside this plan | nothing |

---

## Global Constraints

These bind **every** task. A task that breaks one says so in its commit body, and why. Constraints 1-22
are C1's, carried forward where still true, with the changes marked **[C2]**.

1. **One release branch, `feat/group-session-phase-c2`, and this plan is its first commit** (with the
   roadmap's one-line correction, per decision 1). Every task lands on that branch. One PR at the end.

2. **[C2] ONE STREAM AT A TIME ON THE APP.** S1-S9 run sequentially, in number order: S1, S2, S5, S6 and
   S7 all edit the 6,185-line `SessionLiveView.swift`, and two workers on one file is the gamble this
   rule forbids. **Stream D is one task and touches `supabase/tests/**` only**; it may run beside Stream
   S throughout. **At most two Opus agents at once.**

3. **Swift compiles only in CI.** No macOS toolchain here: no `xcodebuild`, no `swift build`, no
   simulator. Read the code you are changing in full, reason about the types, push. `ios.yml` is the
   compiler. **And the Release configuration compiles only in `deploy-testflight` on master** — a
   DEBUG-only member read from outside `#if DEBUG` is green on every PR and red on the deploy job.

4. **Implementers do not wait on CI.** Push and hand back a written report file
   (`<workspace>/<stream>-pushN.md`, ≤ 25 lines returned). The controller monitors the run (**one event
   per run**) and opens a fix task if it is red. **Reviewers write their own review file**
   (`<workspace>/review-<stream>-pushN.md`) and return ≤ 15 lines.

5. **One commit per task**, with this trailer, verbatim:
   ```
   Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
   ```
   **Use `git commit -F <file>` or a single-quoted heredoc.** A `-m` message containing backticked
   identifiers has silently deleted words in this repo before.

6. **The catalog four-part contract, in ONE commit per id — and in reverse for a retirement.** A new id
   lands in all four places in the same commit: the `case` **and** its builder arm in
   `App/CatalogHostView.swift`; the id string in `GymSyncTests/CatalogScreenTests.swift`; a
   `func testCatalog…() { captureCatalog("<id>") }` in `GymSyncUITests/ScreenshotTests.swift`; an entry in
   `docs/design/frame-map.json`. A retirement removes the `case`, the builder arm **and the view struct it
   renders**, the id string, the capture method and the frame-map entry in one commit. **A retired frame
   number is never reused.**

7. **The FLOOR is `±N over master's FLOOR at integration`, never a literal.** **[C2] this plan's N is
   `+1`** — two production captures in (160, 161), one out (`solo-live-set`, frame 66). Against the
   verified base (`140`) that is `140 → 141`. I1 re-derives the literal on the day by counting the
   exported files in the last green `app-screenshots` artifact. **Frames 151/152 stay — M4 retires them.**

8. **Migrations are gates — and [C2] this plan has no migration.** `backend.yml` runs
   `node scripts/run_pgtap.js` against the **live** database; there is no `supabase db push` in CI. D1 is
   a pgTAP suite over objects that already exist, so it is **not** a gate and needs no controller apply
   step. **If any task discovers it needs DDL, it STOPS and hands back** — the migration becomes a
   controller gate, and its test retirement merges in the same window (the live-DB rule). **Subagents
   never run DDL or DML against the live project, not even inside a rolled-back transaction.**

9. **[C2] THE IRREVERSIBLE STEP IS THE DELETION, AND IT IS LAST.** S8 removes 5,345 lines of shipped
   product. It lands only after **every row of the capability ledger has a verdict backed by a merged
   task** (the ledger at the end of this plan is the checklist; S8's report walks it row by row). The
   abandon write (S2) is the other one-way step in spirit: from that commit on, a lifter can put a
   session into a terminal state the app never wrote before. It is reversible per row (`state` can be
   set back) and fires nothing (decision 1).

10. **Never request HealthKit, LOCATION or CAMERA authorization outside their one permitted call site, and
    never from a test or a catalog builder.** A raised sheet hung `build-test` for 45 minutes once.
    **[C2] this constraint is aimed at S3**: `FormClipCapture` is a camera surface. It moves unchanged, it
    keeps its one call site behind a user tap, and **it gets no catalog frame** (decision 3).
    `HealthKitBridge.exportWorkout` stays at exactly one call site (`presentCompletion`).

11. **No live repository, and no `Date.now`, reachable from a catalog builder.** Every `content_*` renders
    from fixture integers, strings and dates built from components. S9's frames use `SessionLiveView`'s
    existing `#if DEBUG` fixture initializer and `SoloSessionCover.catalogContent`, both already proved
    hermetic in C1.

12. **Every report claim is verified against `git show <sha> --stat` and the CI artifact, not memory — and
    grep the CALL SITE of every new function before claiming it is live.** A definition is not a feature:
    `git grep -n "<symbol>("` must show a caller outside the symbol's own file and its tests. **[C2] the
    cautionary case for this plan is `SessionRepository.abandon`** — a repository function with a pgTAP
    suite and no button would look complete and change nothing.

13. **Design rules, by number** (`2026-09-05-design-language.md`) — the floor a moved capability must not
    fall below, **not an invitation to restyle**.
    - **1** — two raised surfaces only: `.gs3DCard` to read, `.gs3DCardStyle`/`.gs3D` to press; furniture
      inside a raised box stays flat; strips are `surface` at 14 pt. Radii `GSMetrics.radiusMd` (24) and
      `radiusSm` (16). **Never `theme.surface`/`theme.bg` as a face.**
    - **2** — **accent is spent once per screen.** On the live body the accent is the LOG card; nothing
      C2 adds spends a second. `Color.gsSuccess` = done/present; gold = streak and check-in ONLY; red =
      errors **and the discard verb**.
    - **3** — kickers 10-11 pt caps, 0.1-0.13 em tracking, muted; numbers tabular.
    - **9** — sentence case for sentences, caps for kickers; **a button says exactly what happens** (this
      one binds decision 1's copy). No decorative emoji; SF Symbols for glyphs.

14. **The frozen frames must not move.** Phase A's seven (129-135), B1's six (136-141), B2's five
    (142-146), the owner-decisions round's (147-154) and C1's five (155-159), plus the two Home canaries
    (81, 82). "Unchanged" means 0 % of pixels differ below the status bar and above the home-indicator
    band. **[C2] frame 159 (`session-solo-warmup-cover`) is the one that WILL change** — S2 mounts END on
    the warm-up cover. That is an **accepted deviation**, recorded by I1 and shown to the owner on a proof
    card, not a new id.

15. **Do not rename an existing `CatalogScreen` raw value, and do not reuse a retired one.** **[C2] the
    two new ids are `session-solo-editor` and `session-solo-coach`** — `session-` prefixed like every
    other one-body frame. `solo-live-set` retires; **66 is never reused.**

16. **Live-DB tests use the `TestSession` teardown factory and far-future rows.**
    `GymSyncTests/TestSession.swift` is the only place a test may create a session; register cleanup with
    `addTeardownBlock` **before** the write. Every date a live-DB test controls is **2099**.

17. **pgTAP conventions.** `BEGIN;` → `CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;` →
    `SELECT plan(N);` → a comment naming what is under test and declaring the fixture block →
    `auth.users` before `profiles` → role switching with `SET LOCAL role authenticated;
    SET LOCAL request.jwt.claim.sub = '<uuid>';` → **reset the role and claim before the next fixture
    block** → `SELECT * FROM finish(); ROLLBACK;`. **An emptied suite is deleted, never left at
    `plan(0)`** — pgTAP aborts the whole run with "No tests run!". **Assert a delete's effect in a second
    statement, never inside a data-modifying CTE.** **Namespace: `19xx`.**

18. **`XCTUnwrap(await …)` does not compile — bind, then unwrap.**

19. **The UI-test target's compile risk, named.** `GymSyncUITests` is built by the **screenshots** job,
    which runs after the seed step — `build-test` does **not** build it. A task that edits
    `ScreenshotTests.swift` (S8, S9) is not proven by a green `build-test`: **its proof is a green
    screenshots job.**

20. **Do not change the shipped session-engine contracts.** `start_session`, `advance_turn`,
    `advance_round`, `set_session_stations`, `mark_warmup_ready`, `start_lifting`, `evaluate_lateness`,
    `mark_no_shows`, `claim_session_venue`, `apply_squad_swap`, the `check_in_state` CHECK, the five-state
    `sessions.state` CHECK and `session_participants`' four policies are frozen. **[C2] this plan changes
    no contract, adds no RPC and drops nothing.**

21. **THE LOG PATH IS FROZEN.** `LogFollowUp.calls(for:)`, `commitInlineLog()`, `prefillLogInputs()` and
    `turnEntryCard` have stayed character-identical through every round (digests `c1d2b3b35ad7` /
    `89398786e075` / `36f76cbdb951` / `fbf068daacc1`). **[C2] the intended answer is that NO task in this
    plan touches any of the four** — S7 deletes the OLD view's *duplicates* (`soloPrefill`,
    `soloEntryCard`, the solo bar-loader pair, the second `isLoggingSet`, `log(reps:…)`), which are
    different symbols in a different file. **Every app task's report states, per symbol, whether it
    touched it, and every app review re-extracts and re-digests all four.** A task that believes it must
    change one of them STOPS and hands back.

22. **ViewBuilder hygiene, because the one body's type-checker budget is spent.** No local `func`
    declarations and no explicit `return` inside a `ViewBuilder` closure; ten children maximum per
    container. `SessionLiveView.body` is at its budget — **every new modifier or subview goes into an
    extracted layer** (a `private var` returning `some View`, or a new file), never inline in `body`.

23. **[C2] Token economy II (2026-09-19).** Opus legs of **at most two tasks / ~250k**, retired at every
    push. **Fix rounds from file:line findings and scoped re-reviews go to a FRESH Sonnet with a `-U3`
    package** — "warm cache" is not a reason to resume a large agent. Mechanical tails go down a tier.
    Dispatch prompts stay under ~40 lines; requirements live in a brief file. A **final whole-branch Opus
    review is warranted here** (this is a phase, and it deletes 5,345 lines), and **it walks every path
    START→RECAP including the OFFLINE leg** (C1's final review found three defects only on that leg).

24. **[C2] C1's process lessons, as rules.** Defaulted fixture fields are `var`, never `let x = default`
    (the memberwise init omits them — one red release run). A small late commit gets a **type self-check
    before push**: optionals passed into non-optional params, and every caller of a changed signature
    including tests (three CI-only compile slips in C1 and Phase C1's PR #79). Proof renders go on their
    own `proof/<what>-<sha>` ref; one integrated render on the release branch.

25. **[C2] The owner's manual TestFlight script is part of acceptance** and I2 runs it:
    START SOLO → edit the routine mid-workout (add, remove, reorder) → swap mid-exercise → minimise →
    airplane mode → walk away from a second workout and Discard it → the recap counts every set exactly
    once, and friends never see the abandoned one as live.

---

## The decisions, stated

### 1. ABANDON — the data side, and it needs no migration

**The premise the C1 hand-over got wrong.** C1's ledger says a stale ad-hoc row "reads as live forever",
and `AdHocSessionAdoption.swift:32-34` says in its own header "true: there is no reaper". **Both are
wrong, and the comment is corrected by S2.** A reaper exists and runs:

```sql
-- 20260716000004_reminder_window_fix.sql:107-122, inside enqueue_scheduled_pushes()
PERFORM set_config('gymsync.engine', 'on', true);
UPDATE public.sessions
   SET state = 'abandoned', completed_at = COALESCE(last_activity_at, started_at)
 WHERE state = 'in_progress'
   AND COALESCE(last_activity_at, started_at) < now() - interval '6 hours';
```

`20260716000004` is the **live** definition (`20260716000003` is superseded; no later migration redefines
the function), it is the per-minute `push-enqueue` cron, and the controller verified it live on
2026-09-19: **0** `in_progress` rows older than 6 h, 36 rows already `abandoned`. `last_activity_at` is
bumped by a `set_logs` INSERT trigger (`20260716000003_push_cron.sql:55-60`) with no `scheduled_for`
filter, and a session with no sets COALESCEs to `started_at`. **So the residual is six hours, not
forever**, and this plan's own commit corrects the roadmap's "which has no age bound today" sentence to
say what is true: `friends_live()` itself carries no bound, but the row is reaped at six hours.

**(a) The write. A client UPDATE, shaped exactly like `complete()`. No new RPC, no migration.**

```swift
// Models/SessionRepository.swift, directly beneath complete(sessionID:) at :188-200
static func abandon(sessionID: UUID, at when: Date = Date()) async throws -> WorkoutSession
// .update(["state": "abandoned", "completed_at": iso8601(when)])
```

Walked, and clear:
- **Policy.** `"organizer or participant can update session"`
  (`20260726000001_is_session_participant_dual_schema.sql:172-178`) is `USING (organizer_id = auth.uid()
  OR private.is_session_participant(sessions.id, auth.uid()))` with **no `WITH CHECK` on values** — the
  same policy `complete()` already relies on.
- **Triggers.** The one `BEFORE UPDATE ON public.sessions` is `private.session_round_guard`
  (`20260913000102:96-132`, amended by `20260918000203` and `20260919000101`). It restricts `round`,
  `round_started_at`, `stations`, `venue_id`, `squad_swaps` and `style` — **never `state`**, and its own
  header says it "is not an authorization layer".
- **So who may call it is a CLIENT-SIDE scope, and this plan says so honestly.** The server cannot
  distinguish "abandon my own ad-hoc row" from "abandon the crew's session" today, and neither can it for
  `complete()` — identical exposure, unchanged by this plan. **Every call site added here is gated on
  `crewShape == .solo`** (decision 2's predicate). Widening the guard would mean adding a `state` clause
  to a trigger that explicitly refuses to be an authorization layer; that is **docketed**, not built. A
  crew member leaving already has its own verb (`check_in_state = 'left'` via `SessionRepository.leave`)
  and C2 does not touch it.

**(b) What the transition fires — verified function by function, and what it must NOT fire.**

| must NOT fire | proof |
|---|---|
| leaderboard recompute + `leaderboard_entries` INSERT | `leaderboard_recompute_on_session_completion()`, `20260723000001:245-303`, guards `NEW.state IS NOT DISTINCT FROM OLD.state OR NEW.state <> 'completed'` → returns |
| the `leaderboard_passed` push **to another user** | `leaderboard_social_effects_on_completion()`, `20260723000002:211-297` (re-declared `20260723000003:218-254`), **read this session**: same guard, `IF NEW.state … OR NEW.state <> 'completed' THEN RETURN NEW` |
| campaign credit + the `system_campaign` chat row in every group | `campaign_progress_on_session_completion()`, `20260728000002:191-…`, trigger :345, same guard shape |
| a streak BUMP | `streak_on_session_state_change()`, latest definition `20260803000005:30-125`: the `'completed'` arm is the only one that calls `streak_bump_user` |

Two triggers **do** react to `'abandoned'`, and both are walked:

- **`announce_session_lifecycle()`** — latest definition `20260713000002_series_announcements.sql:1-44`.
  It would post `🌫️ … abandoned` into a group chat, **but its first statement is
  `IF NEW.group_id IS NULL THEN RETURN NEW;`**. An ad-hoc solo row has no group. **Confirmed no-op.**
- **The streak trigger's `ELSIF NEW.state = 'abandoned'` branch** (`20260803000005:101-121`, which breaks
  the streak of every participant with `check_in_at IS NULL`). **Unreachable for an unscheduled row**:
  lines 49-51 are `IF v_unscheduled AND NEW.state <> 'completed' THEN RETURN NEW;`, and
  `v_unscheduled := NEW.scheduled_for IS NULL`. The migration's own header says so: "Unscheduled +
  abandoned: still returns early. Bailing out of an ad-hoc workout must not BREAK a streak."

**The two lifters, answered.** A lifter who logged 12 sets and taps **Discard** gets: no streak day, no
week credit (`WeeklyGoalLiveRepository.weekSessions:791-798` sources `history` (completed) + `upcoming`
(pre-workout) — an abandoned row is in neither bucket), and **their 12 sets stay in `set_logs`**. A lifter
who logged none and taps Discard gets the same, minus the sets. A lifter who logged 12 sets and taps
**Finish** gets a streak day — `20260803000005:69-84` bumps an unscheduled session's individual streak
**when that user logged at least one non-penalty set**. **That is honest**, and it is the only honest
reading of a button that says "Discard".

> **CORRECTION TO THE C1 RECORD.** C1's commit `f3ea990` recorded "solo Finish does NOT credit the streak
> — the trigger early-returns on `scheduled_for NULL`". That was the pre-`20260803000005` behaviour. As of
> the live definition, an unscheduled **completed** session **with logged work does** credit the
> individual streak. The C1 ledger entry at 03:35 UTC is wrong on this point; this plan is the correction,
> and S2's review re-reads `20260803000005:40-99` rather than trusting either statement.

**(c) The stale row nobody taps — three layers, none of them new schema.**

1. **The explicit door** (S2): Discard on the live body, END on the warm-up.
2. **A lazy sweep at the next start** (S2). `AdHocSessionAdoption.decide` today has **two outcomes only**,
   and the third was withdrawn in C1 (fix round 2 / B3) **because the only verb available was
   `complete()`**, which is not a quiet write. That objection dies with `abandon`. The decision gains:
   ```swift
   enum Decision: Equatable {
       case adopt(UUID, abandoning: [UUID])
       case startFresh(abandoning: [UUID])
   }
   ```
   where `abandoning` is exactly the rows the existing filter already computes and discards: **mine**
   (`organizerID == me`), **ad-hoc** (triple nil), **older than `staleAfter` (6 h)** — i.e. `mine` minus
   `fresh`, at `AdHocSessionAdoption.swift:112-136`. It stays a **pure function**; `startOrAdoptSolo`
   performs the writes, best-effort, never blocking the start (the file's own "A FAILED READ SIMPLY
   STARTS ONE" stance). **`completed_at` for a lazy abandon is the row's own `startedAt`**, not `now` —
   the client's equivalent of the cron's `COALESCE(last_activity_at, started_at)`, because the lifter
   walked away hours ago. `last_activity_at` is not on the `WorkoutSession` model and is not added.
3. **The 6-hour reaper**, already live, as the backstop for a lifter who never comes back.

**(c′) `friends_live()`: NO new bound, and the reason is written down.** `20260906000002_friends_live.sql`
joins on `s.state = 'in_progress'` with no `started_at` floor (verified: the whole function body, :32-105,
`ORDER BY s.started_at DESC … LIMIT 5`). A bound was considered and **rejected**:
- the reaper already caps staleness at ~6 h + one cron minute, so a **6-hour** bound is a no-op;
- anything **tighter** than 6 h is a product definition of "in the gym right now", not a defect fix, and
  it would hide a genuinely live friend through a long rest or a warm-up — a new wrong answer on the one
  surface whose job is presence;
- solo rows are already gated behind `profiles.show_solo_workouts`, **default false**
  (`20260906000002:88-104`);
- it would cost a migration gate and a pgTAP amendment in a phase that otherwise needs neither.
**Docketed** as a product question for M4 ("what does live mean"), with the evidence above. If the owner
later wants one, `COALESCE(last_activity_at, started_at)` is the convention to reuse and
`supabase/tests/friends_live_test.sql` passes unmodified for any bound ≥ 30 minutes (its five fixture
sessions are `now() - interval '5'…'25 minutes'`, `last_activity_at` unset — checked at :47-65).

**(d) The "Not now" leave-behind, and the trap in it.** `DiscoverWorkoutDetailView.swift:201` —
`Button("Not now", role: .cancel) { attemptAwaitingAcknowledgement = nil }` on the "Couldn't join the
leaderboard" dialog — leaves a session standing that the lifter declined to enter. **It is abandoned in
S2 — but only if this call STARTED it.** `beginSoloAttempt(optIn:)` (`:431-454`) calls
`SessionRepository.startOrAdoptSolo`, which may have **adopted a workout already in progress**;
abandoning that would kill a live session from a dialog about a leaderboard. So `startOrAdoptSolo`'s
return widens to carry the outcome:
```swift
struct Start { let session: WorkoutSession; let adopted: Bool }
static func startOrAdoptSolo(routineID: UUID?) async throws -> Start
```
Three call sites (`HomeView.swift:2438`, `DiscoverWorkoutDetailView.swift:437`,
`RoutinesListView.swift:495`); two read `.session` and ignore `.adopted`. **"Not now" abandons only when
`adopted == false`.** The attempt row is not a concern here: this dialog is the branch where
`PublicWorkoutRepository.startAttempt` **threw**, so there is no `workout_attempts` row to strand — and
`'abandoned'` would not fire the attempt-completion trigger even if there were.

**(e) Sets logged under an abandoned session stay, and every reader is sane.** `set_logs` is never
filtered by `sessions.state` anywhere in the app — the readers are keyed by user/session/exercise
(`SessionRepository.swift:238/287/303/321/372/402/423/1398`, `WeeklyGoalLiveRepository.swift:773`,
`BlockGoalLiveRepository.swift:1020/1050`). So PR basis, volume, block goals and the recap's own read all
count them: **history is history**. The one asymmetry, stated rather than fixed:
`SessionRepository.history` (`:270-283`) selects `state = 'completed'`, so an abandoned session does not
appear in the workout history list while its sets still count toward PRs and volume. That is the same
asymmetry a never-ended session has on master today, and closing it would be a product decision about
what the history list means. **Docketed, not built.**

**(f) Gate ordering.** There is **no gate** — no DDL, no new function. The pgTAP suites that assert on
this trigger surface are a **regression net C2 gets for free** and must keep passing **unmodified**:
`streaks_test.sql` (extensive `'abandoned'`-transition coverage at :253-338, :530-653),
`push_cron_test.sql`, `mark_no_shows_test.sql`, `session_states_narrow_test.sql`, `friends_live_test.sql`.
**No retirement is needed in this window.** D1 adds one new suite (`19xx`) and is the proof that the
client-initiated write behaves exactly like the cron's.

### 2. The routine editor meets slot-keyed state — THE HIGHEST-RISK SEAM

**Where it mounts, and behind which predicate.** `SessionRoutineEditor`
(`Features/Workout/SessionRoutineEditor.swift`) is presented from `WorkoutSessionView.swift:1186-1195`
with `soloEditedList` (`@State`, decl `:345`) as its channel. **`SoloSessionShape.isAdHocSolo` does not
exist** — C1 replaced it (`SoloSessionLayer.swift:119-146`). The editor mounts behind
**`crewShape == .solo`** (`SessionLiveView.swift:505-513`, the same derivation the five crew-furniture
gates read), **not** `isSoloByConstruction`:
- `isSoloByConstruction` is triple-nil = **ad-hoc only**; a SCHEDULED solo session answers `false` by
  design (its header, :136-141: at the row a scheduled solo and a scheduled `.friends` session are
  byte-identical — only the roster separates them);
- `crew(…)` returns `.solo` for both an ad-hoc row and a scheduled row whose roster has loaded and holds
  one, and returns **`.unknown` → crew behaviour** while the roster is in flight. So a crew is never
  offered the editor (§3.4: the consent card is the crew's mode of exercise change), and a scheduled solo
  lifter gains it. **A capability the old screen never had for scheduled solo is a gain, not a scope
  creep** — and the alternative (gating on `isSoloByConstruction`) would ship a screen where the same
  lifter has an editor on Tuesday's ad-hoc workout and not on Wednesday's booked one.

**The layering order is unchanged and is stated again because C2 is where it becomes real.** Edit first,
layer second: `effectiveRoutineExercises` (`SessionLiveView.swift:724-731`) becomes
`RoutineLayering.apply(soloEditedList ?? routineExercises, …)` — **one expression changes**, and it is the
only place the overlay is applied (that property's header already claims to be "the one place"). A slot
that was removed has no layer to apply; a slot that was added has no swap yet.

**Where the edited list LIVES — and this is the correctness requirement, not a nicety.** It may **not** be
`@State` on `SessionLiveView`. C1 made the solo session a cover, and **MINIMISE destroys the view**; an
edit lost on minimise is a live-session data loss with a user-visible symptom (the lifter's added exercise
vanishes). So the overlay lives in an **app-level, session-keyed, in-memory store** copying
`SessionSwapPendingStore`'s shape exactly (`Models/SessionSwapLayer.swift:86-129`,
`private var bySession: [UUID: …]`, `@MainActor final class … static let shared`), seeded on `reload()`
and cleared at completion/exit alongside the swap outbox (`SessionLiveView.swift:5680`). **Disk is M2 —
see decision 7.**

**What happens to logged sets, pending swaps and the cursor, per action.** The rule the whole table
obeys: **a surviving slot keeps its id; an edit is in place; a removal is a removal, never a re-key**
(ruling R-C-5 from C1's D review, generalised). `RoutineRepository.save` deletes and re-inserts rows
**with their client-side ids**, so this is achievable and is already what `applyCoachRoutineEdit` does
(`WorkoutSessionView.swift:3648-3664`, with the R-C-5 comment in place).

| action mid-session | logged sets (`set_logs.routine_exercise_id`) | pending / durable swaps | the cursor (`SlotProgress` + `RoutineProgression.currentSlot`) |
|---|---|---|---|
| **reorder** | untouched — ids are stable, only `position` moves | untouched (keyed by slot id) | recomputes in the new position order; a lifter can be moved to a different "current" slot mid-session. **Acceptance: the counts do not change, only the order** |
| **add** | the new slot carries a **client-minted UUID**, stable for the rest of the session; sets stamp it. That id is **not yet in `routine_exercises`** — there is no FK on `set_logs.routine_exercise_id` (D3's stance), so the insert succeeds | a `self_swaps` entry keyed to it is accepted (a plain jsonb client write, no slot validation). `apply_squad_swap` **would** raise `slot is not part of this session's routine` — unreachable, because crews never get the editor | the new slot appears in position order with 0 done |
| **remove** | its rows **stay in `set_logs`** with a now-dangling slot id. They still count for volume, PR and block goals (decision 1(e)); they leave `SlotProgress` because the slot is gone from the list. **This is the one place the recap total and the on-screen "sets done" can diverge, and it is correct in both** | the pending/durable entry for that slot becomes inert; it is **not** cleaned up (a harmless orphan key, same class as a swap on a slot the routine later loses) | recomputes over the shorter list |

**And per persist branch, at session end** (`persistSessionEdits(asNew:)`,
`WorkoutSessionView.swift:3576-3604`, raised by the "Keep your mid-session edits?" dialog at :631-650):

- **"Update this routine" (`asNew: false`)** — `RoutineRepository.save(routine, exercises: rows)` where
  `rows` is `edited` with `position` renumbered and **ids preserved** (`var r = re`). Surviving slots keep
  their ids; **added slots are inserted with the very id the session already logged against**, so those
  set rows become valid retroactively. Removed slots are deleted; their set rows keep a dangling id and
  fall back to the per-`exerciseID` path (`RoutineProgression.completedRows(forSlot:in:)`, C1 S2).
- **"Save as a new routine" (`asNew: true`)** — clones into a **new** routine id via
  `RoutineLayering.copied(_:intoRoutine:position:)`, which mints fresh ids. **The live session's
  `routine_id` still points at the ORIGINAL routine**, whose rows are untouched, so nothing the session
  logged is re-keyed. Added slots' ids never reach the database at all; their set rows keep the
  exerciseID fallback. **This branch must not touch the original routine — S1's review re-reads
  `RoutineLayering.copied` and `RoutineRepository.save` to confirm the clone writes only the new id.**
- **"Discard" (cancel)** — nothing is written. Identical to "save as new" from the session's point of
  view: added slots' ids were never persisted, and the sets keep the fallback.
- **`applyCoachRoutineEdit`** (the Apply card, `:3611-3694`) — edits **in place**, preserves `old.id`
  explicitly (:3649, with R-C-5's comment), guards `routine.prescribedBy == nil` so a trainer's
  prescription is never rewritten, and writes the overlay at :3690. **It moves unchanged**, and S1's
  review verifies the id is still preserved after the move.

**THE FREEFORM ("empty") WORKOUT — the degenerate case, walked.** `isFreeform` is
`routineExercises.isEmpty` (`WorkoutSessionView.swift:303`). Every exercise arrives through the editor's
own picker, nothing is ever persisted to `routine_exercises`, and **every set writes
`routine_exercise_id = NULL`** (:1123 and :4275, both `isFreeform ? nil : …`). In the one body, the
equivalent site is `SessionLiveView.swift:3470` (`routineExerciseID: currentRoutineExercise?.id`), which
**already yields nil when the routine is empty** — no `isFreeform` flag is added. `SlotProgress` places
NULL-slot rows rather than dropping them (C1 fix F2/R-F2-1, greedy in-order up-to-target), so a freeform
session counts correctly today. **S1's acceptance includes a pure test over a freeform session: add three
exercises, log two sets against the second, remove the first, and assert the cursor and the counts.**

**S1's review answers this seam IN WRITING** — the table above, re-derived from the diff, plus: which
symbol reads the overlay (exactly one: `effectiveRoutineExercises`), which store holds it, and that the
four frozen log-path symbols are untouched. **Not the final review's question.**

### 3. `FormClipCapture` moves solo-only and unchanged

`FormClipCapture` (`Features/Workout/FormClipCapture.swift`) is presented from
`WorkoutSessionView.swift:1203-1211` as a `.fullScreenCover`, with `canRetainClips` (`:334`, decided at
:2590-2596 — Pro or has-coach), `pendingClipURL` (`:333`) consumed at `:4371-4381` via
`SetLogClipRepository.attach`. It moves behind `crewShape == .solo` (decision 2's predicate) — **a crew's
set is not a private form review** (C1 "does not decide" #2, unchanged).

**The rest lapse, walked against the C1 hotfix's F1 precedent.** F1 was: the OLD view cancelled its rest
lapse `Task` in `.onDisappear` and never re-armed it, so a `fullScreenCover` mid-rest (exactly this clip
capture) stranded the rest — no chime, no `captureRestDrop`, the rest page never left. The fix was
`.task(id: restEndAt)`. **The one body does not have that bug, and the reason is different:** its lapse is
a bare inline `Task { sleep }` created at the point the window is set
(`SessionLiveView.swift:3328-3336`) and re-armed by `restoreTimersFromStore()` (`:3357-3374`) on
`.onAppear`. **Nothing cancels it** — there is no `.onDisappear` cancel anywhere in the file — and a
`fullScreenCover` presented *from* the body does not remove the body from the hierarchy. The guard
`if selfRotationRestUntil == until` makes a double-arm idempotent, and `restoreTimersFromStore`'s own
`guard selfRotationRestUntil == nil` prevents one. **S3 verifies this by reading and states it in its
report; it does NOT convert the inline `Task` to `.task(id:)`** — that would be a change to the one body's
rest mechanism, outside C2's scope and outside the proof this phase can run.

**`scenePhase`.** `SessionLiveView` reads it at `:131` and reloads on `→ .active` (`:2427-2431`). The clip
cover's dismissal does not change `scenePhase`; the camera going foreground/background may. The reload is
idempotent and already survives a cover (C1 proved it for the swap sheet). **No new `scenePhase` handler
is added** — C1's "does not decide" #5 (the lock-screen leg, two unproven candidates) stands.

**No catalog frame** (constraint 10). A capture that renders `FormClipCapture` would raise the camera
permission alert inside `screenshots`, which is the class of failure that hung `build-test` for 45
minutes. Its proof is the manual script.

### 4. The swap door opens during any rest — and it is already open

**A correction to the C1 outline.** C2-S3 says "the transit-only gate (`WorkoutSessionView.swift:1616`)
does not survive the move". Two things are wrong with that line. The gate is at **`:1882-1883`**
(`private var transitSwapButton` … `if soloRestIsTransit, currentExercise != nil`) — `:1616` today is
`if soloIsBarbell { soloBarCard }`, an unrelated line; the number drifted before C1 even started. And
more importantly: **the one body has no such gate to remove.** Its swap button
(`SessionLiveView.swift:1577-1588`, `showGroupSwapSheet = true`) sits in the exercise-header row with no
`if` around it, and the sheet is presented unconditionally at `:2189`. The transit-only restriction is a
property of the OLD view, and it dies with the file in S8.

**So S4 is not a removal — it is the PROOF that the payoff of C1's D3 is real**, and it is the cheapest
task in the phase: a pure test that a **mid-exercise** swap counts once. Given a routine slot with
`targetSets = 3`, two sets logged against it, then a swap to a different exercise, then a third set:
`SlotProgress` must report **3 of 3 for that one slot** and must not split the count across the old and
new `exercise_id`, and `RoutineProgression.currentSlot` must advance exactly once. This is the assertion
that `set_logs.routine_exercise_id` was added for; without it, C1's D3 has a column and no consumer test.
Size **S**.

### 5. Coach's solo hooks join the one body's Coach door

Five symbols move from `WorkoutSessionView` to `SessionLiveView`, each onto an existing twin:

| moves | from | onto |
|---|---|---|
| `coachProfile` (`:103`) | `@State TrainingProfile` | `groupCoachProfile` (`:337`) — **one property, renamed in place is out of scope; the solo hook READS the existing one** |
| `showCoachRecap` (`:104`), the recap sheet (`:606-620`) | solo sheet | the body's coach sheet (`:2194-2195`) |
| `prefetchCoachContext()` (`:3716-3869`, ~154 lines, persists `lastProbeAt` at `:3743`) | solo | the body's own context builder (`:5607`, `:5627`) — **the larger of the two; the move is a merge, not a copy** |
| `coachPendingProbe` (`:108`) | solo | the body has no twin — it arrives |
| `soloCoachDecision` (`:82`, `BlockProgression.Decision?`) | solo | `turnCoachDecision` (computed, `:983`, read at `:1013`, `:1440`, `:1825`) |

**Solo gains Coach's door**, which it has never had: `openCoachThread()` (`:4527`, `@MainActor`, whose
doc-comment at `:4518-4525` explains it deliberately mirrors `LobbyView.openCoachThread()` rather than
sharing it, because the two views hold different session values). It is mounted for solo behind
`crewShape == .solo` only insofar as the copy differs; **the door itself is not crew furniture and is not
gated**. This is the surface that earns proof frame 161 (`session-solo-coach`).

**`prefetchCoachContext` writes.** It persists `coachProfile.lastProbeAt` through
`TrainingProfileRepository.save` (`:3742-3743`). After the move there must be **exactly one** caller — a
second one would double-advance the probe clock. S5's report greps the call sites.

**Ride-along candidate: Coach's `cue` lever — DOCKETED, not built.** `TrainingRules.swift:48-52` declares
`case cue`; `RuleClassifier.swift:192-200` produces it; `TrainingRules.swift:111` and
`TrainingProfile.swift:547` both group it with the generator-unbuildable levers. Its own doc-comment says
why: "`RoutineExercise.notes` is carried through every constructor and **rendered nowhere**". Rendering it
means choosing a site on the logging screen — and **the logging screen's top-left slot is design backlog
and off limits** (owner directive). It is not "one S task at a site this work already touches". Docket.

### 6. Finish, recap, Pump post and discard converge on `presentCompletion`

`presentCompletion(_:)` (`SessionLiveView.swift:5848-5870`) is the landing site, and it already does more
than the C1 outline credits it with: the merged read through `PendingSetLogMerge.merged` (C1's NEW-2, at
`:5859-5862` — **this must keep reading through it**), the **one** `HealthKitBridge.exportWorkout` call
site, `liveService.unsubscribe()`, `buildGroupRecapPayload`, `buildPumpCheckContext` (`:6056-6115`, which
already builds a `PostSummary` and already calls `HealthKitBridge.heartRateStats`), `assembleGroupDebrief`
and `recapData`. **So `buildPostSummary()` (`WorkoutSessionView.swift:4897-4928`) does not move — it is
already there, at `:6076-6111`.** S6's job is the remainder, and only the remainder:

| what is missing in the one body | the old site |
|---|---|
| **recovery probes** — open one per muscle trained, then load the oldest OPEN one that is not from today | `syncRecoveryProbes(sessionID:logs:)`, `:4838-4852`, plus `answerRecoveryProbe` `:4854-4858` |
| **`LiveSessionTimerStore.shared.clear(sessionID:)`** — the old view is the **only** caller in the app; the group body writes anchors and never clears them (flagged pre-existing in the C1 hotfix report) | `:4776` |
| **the mid-session-edit persist dialog** — "Keep your mid-session edits?" / Update this routine / Save as a new routine / Discard | `:631-650`, fired from `.task(id: completed)` |
| **`AppState.liveSoloSession = nil`** | `:4765-4766` — **retires** with the field in S8, not moved |
| **DISCARD, the workout verb — solo GAINS it** | **nowhere.** The old view's only "Discard" (`:647`) discards routine EDITS, not the session. The ledger row is right that solo *gains* this |

**DISCARD's shape.** The end confirmation (`showEndConfirmation`, `:213`, presented `:2286`) gains a
second, **destructive** button, mounted **only when `crewShape == .solo`** — a crew member ends a crew
session for everyone or leaves; they do not discard it. Copy per design rule 9 (a button says exactly
what happens) and rule 2 (red is the discard verb):

> **Discard this workout** — "Your sets stay in your history, but this workout won't count toward your
> week or your streak."

That sentence is **true**, and decision 1(b)/(e) is what makes it true. It calls
`SessionRepository.abandon(sessionID:)`, then the same teardown `endSession()` does minus the recap:
clear the swap outbox, clear the timer store, `exitToHome()`. **It does not call `presentCompletion`** —
there is no recap for a discarded workout.

**The warm-up's END** (S2, not S6, because it is part of the abandon door). `SessionEndAffordance.Page`
has five cases and all five are live-body pages (`SessionEndAffordance.swift:56-110`); the warm-up is a
different screen (`WarmUpScreen.swift`, 279 lines) and is **not** a new `Page` case. C1's N12 named it:
"the WARM-UP is the one screen with no END". Today the only control on the solo warm-up cover is
MINIMISE (`SoloMinimiseControl`, `SoloSessionLayer.swift:265-291`, mounted at `:198` via
`.soloMinimiseOverlay`). S2 mounts END beside it, for `crewShape == .solo` only, calling
`abandon(sessionID:)` — a lifter who warmed up and left the gym has logged nothing, so abandoning is the
only honest verb. **`WarmUpGate.showsWarmUp` (`WarmUpScreen.swift:44-46`) already returns `false` for
`state == "abandoned"`** — dead code today, live after S2, and that is the clean exit. **This changes
frame 159; it is an accepted deviation (constraint 14), not a new id.**

### 7. Disk persistence — the M1/M2 seam, decided: **M2**

The roadmap asks this plan to decide. **Decision: the three stores stay in memory in C2; disk persistence
opens M2 as its first task.** The reasons, sized honestly against the map's section 4:

- **What C2 actually needs is survival of a VIEW's destruction, not of the PROCESS.** The editor overlay
  must survive MINIMISE (decision 2), and the in-memory, session-keyed, app-level store that C1 already
  established twice (`SessionSwapPendingStore`, `SessionRoutineCache`) gives exactly that, for a handful
  of lines. **That much lands in C2, inside S1**, because without it the editor move is a data-loss bug.
- **Surviving a process death is a different mechanism, not a bigger one of the same.** The idiom to copy
  is `OfflineSetLogQueue` (`Services/OfflineSetLogQueue.swift:141-536`): a SwiftData `@Model`, the app's
  single `ModelContainer`, a `configure(modelContext:)` entry point called from `RootView`, per-item
  clearing and an age-based prune. Doing that for three stores with three different key shapes
  (`LiveSessionTimerStore` by session, `SessionSwapPendingStore` by session, `SessionRoutineCache` by
  **routine**) plus the new edit overlay is **two L tasks and four new model types**, with round-trip and
  "fresh always wins" tests for each.
- **C2 is already at nine app tasks** (S1-S9). Adding two more L tasks would push a phase that deletes
  5,345 lines past its leg budget and past the two-tasks-per-Opus-leg rule.
- **The ranking rule is satisfied.** M1's exit does not depend on persistence; M2's does, and M2's exit
  criterion ("killed and relaunched mid-rest, every set counted exactly once") is *precisely* this work —
  it belongs where it is measured.

Recorded under "What this plan does not decide" as **M2's first task**, with the three stores' exact
locations and the `OfflineSetLogQueue` idiom named, so M2's planner starts from evidence.
`SessionRoutineCache.swift:18-21` — "A cold launch with no network … needs the plan on disk — and that is
deliberately not attempted here (docketed to C2)" — **is answered in the negative here, in writing, which
is what the docket was owed.**

### 8. Deletion — last, and only against a complete ledger

**Order.** The duplicated log path and the two view files leave in **one** commit, not two. This is a
**correction to the C1 outline**, which made C2-S6 (delete `soloPrefill`, `soloEntryCard`, the solo
bar-loader pair, the second `isLoggingSet`, `log(reps:…)`) a separate M · Opus task ahead of C2-S7
(delete the files). Emptying a 4,929-line file in one commit and deleting it in the next is work with no
consumer: nothing ships between them, no review question is answered twice, and the intermediate state
compiles only by accident. **S7 is the whole deletion.**

**The acceptance list, built from the map's sections 5 and 7 and re-verified at `8e9112e`:**

| coordinate | verified at |
|---|---|
| `WorkoutSessionView.swift` (4,929 lines) | file |
| `WarmUpPhaseView.swift` (416 lines) + `enum SoloWarmupStore` declared in it (`:32`) | file; consumers `WorkoutSessionView.swift:199/1600/3969` die with it |
| the one construction site | `App/CatalogHostView.swift:1979` |
| `AppState.LiveSoloSession` (struct `App/AppState.swift:178`) + `AppState.liveSoloSession` (`:186`) | writers: `CatalogHostView.swift:1972`, `WorkoutSessionView.swift:3955`; reads/clear `:3936`, `:4765-4766`. **No other live reader** — the five other mentions (`HomeView.swift:1398`, `RootView.swift:438`, `SessionRepository.swift:139`, `SessionSwapLayer.swift:99`, `LivePillDecisionTests.swift:71`) are doc-comments |
| `Models/SoloResumeCursor.swift` **and** `SoloResumeCursorTests.swift` | referenced only by `WorkoutSessionView.swift`, `CatalogHostView.swift`, `WarmUpPhaseView.swift` and its own test — **not** by `SessionLiveView.swift`. See the open question below |
| `supersetPartnerIndex(of:)` (`:4618`, one internal caller `:4533`) | **retires** — duplicate of `RoutineProgression`'s pair handling |
| `soloStallSwapName` (`:99`, written `:482/:487`, read `:2653`) | **retires** — solo-only, no crew equivalent, no owner request |
| `refreshSoloWatchState()` (`:1075`) / `pushSoloWatchState(session:active:)` (`:1087`) | **retire** — they hardcode `groupID: nil` and `isMyTurn: true` (`:1094`, `:1099`); the one body's payload is real |
| the four-part catalog contract in reverse for `solo-live-set` | `CatalogHostView.swift:79` (case), `:302` (dispatch), `:1970-1985` (builder), `GymSyncTests/CatalogScreenTests.swift:59` (id), `GymSyncUITests/ScreenshotTests.swift:649` (capture), `docs/design/frame-map.json` (frame 66) |
| `FLOOR` | `.github/workflows/ios.yml:471`, `140 → 141` at I1 (net of S9's two in) |
| **moves, not deletions** | `Features/Workout/SessionRoutineEditor.swift` and `Features/Workout/FormClipCapture.swift` → `Features/Sessions/`. `git mv` only; no `project.yml` edit (the glob) |
| **absences, checked and clear** | no Sentry breadcrumb or analytic names the old view (`SentryContext.SessionPhase` keys on `sessions.state` strings); **no test constructs either view** |

**`SoloResumeCursor` — the one capability with no named landing site, and it is answered before S7, not
during it.** The map flagged it: C1's ledger row "Resume after relaunch — already there (C1 S3/S5)" may
subsume it, or it may be a second, undecided resume mechanism. **S1 answers it** (the first app task
touching this area reads `SoloResumeCursor.swift` and `RoutineProgression`/`SlotProgress` side by side and
states which), because a deletion task is the wrong place to discover a capability. Its verdict —
subsumed, or moved — goes into the ledger before S7 starts. **S7 does not delete anything whose ledger row
lacks a verdict backed by a merged task** (constraint 9).

### 9. Small ride-alongs

Each is **one S · Sonnet task**, each lands in its own commit, and **none of them gates deletion**.

- **R1 — HR zones from birth year.** `Services/HeartRateZone.swift:50` is `static let defaultMaxBPM = 190`
  with a doc-comment (:26-46) claiming "`Profile` has NO birth-date/age field — checked before writing
  this". **That claim is stale**: `Profile.swift:35` declares `let birthYear: Int?` (decoded :55/:81) and
  `Profile.updateDemographics(sex:birthYear:)` (:264-270) writes it. Wire `220 − age` **and keep 190 as
  the fallback** — **`birthYear` can be nil today** (it is optional, and nothing forces it at onboarding),
  so the nil path is the common path and must be the tested one. Correct the doc-comment in the same
  commit.
- **R2 — the stale tour copy.** `Services/GuidanceTips.swift:139` still says Coach is "coming soon"; Coach
  ships (`CoachHomeView`, `openCoachThread()`, `prefetchCoachContext()`). One string, plus a grep for
  other call sites of that tip.
- **Docketed, not ridden along:** the `cue` lever (decision 5), a `friends_live()` age bound
  (decision 1(c′)), the history-list asymmetry (decision 1(e)), a server-side narrowing of who may write
  `sessions.state` (decision 1(a)).

---

## New catalog ids, and the FLOOR

### In — two production ids, frames 160-161 (S9)

Per the owner directive: every surface **newly reachable** in the one body gets **one** hermetic proof
frame, built from the production views with fixture values. No variations, no compositions to choose
between.

| id | frame | what it proves |
|---|---|---|
| `session-solo-editor` | **160** | `SessionRoutineEditor` mounted on a solo session in the one body — the add/reorder/remove list over a fixture routine. The capability the owner uses most and the one this phase risks most |
| `session-solo-coach` | **161** | Coach's door on a solo session — the surface solo has **never** had (decision 5) |

**No frame for the discard door**: it is a `confirmationDialog`, a system presentation that a catalog
capture cannot render hermetically or reliably. Its proof is a pure test over
`SessionEndAffordance`-shaped copy plus the manual script. **No frame for `FormClipCapture`**: the camera
permission alert (constraint 10). **No new warm-up frame**: S2's END lands on the existing
`session-solo-warmup-cover` (159), which **changes** — an accepted deviation on a proof card, not a new
id (constraint 14).

### Out — one, `solo-live-set` (frame 66)

Retires in S7's commit, in the same commit as the view it photographs, via the four-part contract in
reverse. **66 is never reused.** Frames 151/152 stay — M4's to retire.

### The FLOOR

**`FLOOR` moves by `+1` against master's FLOOR at integration** — two captures in, one out. Against the
verified base (`140`) that is **`140 → 141`**. I1 re-derives the literal on the day by counting the
exported files in the last green `app-screenshots` artifact, and updates the comment block at
`ios.yml:468-470` so the next planner reads the truth (that block currently says the C2 delta is `−1`; it
was written before this plan's two frames existed).

**Counts after S9:** `CatalogScreen` cases **119**, `CatalogScreenTests` ids **119**, real
`captureCatalog("…")` calls **117**, `frame-map.json` **98** entries, max frame **161**, zero duplicates.

**Captures that change CONTENT rather than count, and are therefore this plan's best proofs:**
`app-session-solo-live` (155), `app-session-solo-rest` (156), `app-session-solo-swap` (157) must be
**byte-identical** after S1-S6 — moving the editor, the clip door and the Coach hooks behind a solo gate
is behaviour-preserving for a fixture session that opens none of them, or it is a bug. `app-session-warmup-solo`
must be byte-identical too (S2 touches the **cover**, frame 159, not the screen).

---

## Sequencing

```
 feat/group-session-phase-c2  8e9112e   (FLOOR 140, frames 1-159)
        │
        ├──► STREAM D · the data  (supabase/tests/** only — NO migration, NOT a gate)
        │      D1  pgTAP 19xx: the abandon transition fires nothing        M · Sonnet
        │
        └──► STREAM S · the app  (ONE worker at a time, in number order)
               S1  the routine editor, solo-only + the slot seam           L · Opus  ─┐ leg 1
               S2  the abandon door: Discard, warm-up END, lazy sweep      L · Opus  ─┘ (retire)
               S3  FormClipCapture moves, solo-only                        S · Sonnet
               S4  the any-rest swap, proved (pure test only)              S · Sonnet
               S5  Coach's solo hooks + solo gains Coach's door            L · Opus  ─┐ leg 2
               S6  finish / recap / Pump post / discard → presentCompletion L · Opus ─┘ (retire)
               S7  BOTH VIEWS DELETED (+ the duplicated log path)          L · Opus
               S8  R1 HR zones from birth year · R2 stale tour copy        S · Sonnet ×2
               S9  two proof frames (160, 161)                             M · Sonnet
                          │
                          ▼
                   INTEGRATION  (I1 Sonnet · I2 controller · I3 controller)  →  ONE PR, proof cards
```

**The hard edges.**
- **S1 first, and its review answers the slot seam** (decision 2) — not the final review's question.
  C1 shipped a whole round engine with no caller because a seam question was asked only at the end.
- **S2 needs nothing from D1** (D1 proves the server behaviour C2 relies on; it does not gate a Swift
  task, because no object is being created). Dispatch D1 **first anyway** — if it finds the premise wrong,
  S2's design changes and everything after it is cheaper to redirect.
- **S3 and S4 may not start before S1 is pushed** (S3 edits `SessionLiveView`; S4 is pure but its test
  reads the slot progress S1 may have touched).
- **S7 is last of the app work** and lands only against a complete ledger (constraint 9).
- **S9 is after S7** because its two frames render views that S1 and S5 create, and because its proof is
  a green **screenshots** job (constraint 19), not a green `build-test`.
- **S8's two ride-alongs may run any time after S1** on a Sonnet beside an Opus leg (constraint 2's
  two-Opus ceiling is never reached — Stream D is Sonnet and S8 is Sonnet).

**Model ladder.** Opus for multi-file judgment (S1, S2, S5, S6, S7). Sonnet 5 for everything mechanical
from an exact spec (D1, S3, S4, S8, S9, I1). **Never Fable, never `fork`.** **Two Opus at once maximum**;
**legs of at most two tasks / ~250k, retired at every push**; fix rounds and scoped re-reviews go to a
**fresh Sonnet** with a `-U3` package (constraint 23).

---

# STREAM D — the data

No migration. One pgTAP suite, `19xx`, over objects that already exist.

### D1 — pgTAP: the abandon transition fires nothing — **M · Sonnet**

**File:** `supabase/tests/session_abandon_test.sql`. **Fixture block: `19xx` UUIDs** (constraint 17;
`01xx`-`13xx`, `15xx`-`18xx` are taken).

**What it pins** — the premise the whole of decision 1 rests on, asserted against the **live** database
where `backend.yml` runs it:

1. `'abandoned'` is in the `sessions.state` CHECK (a cheap regression on
   `20260913000103_session_states_narrow.sql`).
2. **An authenticated organizer of an ad-hoc (`group_id`/`room_code`/`scheduled_for` all NULL) session
   CAN UPDATE `state` to `'abandoned'`** under the shipped policy — the write S2 makes, with no engine GUC
   and no RPC.
3. After that write: **no `leaderboard_entries` row** exists for the session; **no `push_queue` row** of
   kind `'leaderboard_passed'` exists; **no `chat_messages` row** exists (the group-less no-op of
   `announce_session_lifecycle`); `workout_attempts` for the session is unchanged.
4. **The streak is untouched**: the user's streak row is byte-identical before and after (the unscheduled
   early return, `20260803000005:49-51`).
5. **The contrast case, so the suite proves a difference rather than an absence:** the SAME fixture with
   `state = 'completed'` and one non-penalty `set_logs` row **does** bump the individual streak
   (`20260803000005:69-84`). This is the assertion that would have caught C1's stale streak claim.
6. A session **with** a `group_id` abandoned by its organizer **does** get the `🌫️` `system_session` chat
   row — proving the no-op in (3) is the `group_id IS NULL` branch and not a broken trigger.

**Conventions.** Constraint 17 verbatim: `BEGIN;` → extension → `plan(N)` → a header comment naming what
is under test and declaring the fixture block → `auth.users` before `profiles` → `SET LOCAL role` /
`request.jwt.claim.sub` per actor, **reset between fixture blocks** → `finish()` → `ROLLBACK;`. Assert a
write's effect in a **second statement**, never inside a data-modifying CTE. **Never `plan(0)`.**

**Acceptance.** `backend.yml` green, this suite's assertions all passing, and **the five existing suites
that assert on this trigger surface pass UNMODIFIED**: `streaks_test.sql`, `push_cron_test.sql`,
`mark_no_shows_test.sql`, `session_states_narrow_test.sql`, `friends_live_test.sql`. If any of them needs
a change, that is a finding and the task **stops and hands back** — it would mean the premise in decision
1 is wrong.

**Report.** The `plan(N)`; each numbered assertion above with the file:line of the function it pins; the
five untouched suites named; confirmation that **no migration file was added**.

---

# STREAM S — the app

`GymSyncApp/**`, `docs/design/**` and `.github/workflows/ios.yml` only. One worker at a time, in number
order. **Every task's report states, per frozen symbol (`LogFollowUp.calls(for:)`, `commitInlineLog`,
`prefillLogInputs`, `turnEntryCard`), whether it touched it — the answer must be "no" for all four in
every task — and every review re-extracts and re-digests them** (`c1d2b3b35ad7` / `89398786e075` /
`36f76cbdb951` / `fbf068daacc1`).

### S1 — the routine editor moves, solo-only, and the slot seam is answered — **L · Opus**

Decision 2 is the specification; implement it as written.

**Do.** Mount `SessionRoutineEditor` in `SessionLiveView` behind `crewShape == .solo`; carry
`persistSessionEdits(asNew:)` and `applyCoachRoutineEdit(_:)` with it, **ids preserved on every surviving
slot**; put the edited list in a new app-level, session-keyed, in-memory store shaped like
`SessionSwapPendingStore` (`Models/SessionSwapLayer.swift:86-129`), seeded in `reload()` and cleared where
the swap outbox is cleared (`SessionLiveView.swift:5680`); apply it in **exactly one** place —
`effectiveRoutineExercises` (`:724-731`), edit first, layer second. Carry the "Keep your mid-session
edits?" dialog's *writer* half only; the dialog itself is S6's (it fires at completion).
**`git mv Features/Workout/SessionRoutineEditor.swift Features/Sessions/`** — no `project.yml` edit.
**Answer `SoloResumeCursor`'s verdict in the report** (decision 8) by reading it beside
`RoutineProgression`/`SlotProgress`.

**Constraint 22 applies hard here:** the editor's sheet modifier goes in an extracted layer, never inline
in `body`.

**Pure tests (no live DB, no network):** the four rows of decision 2's action table; both persist branches
(`asNew` true/false) asserting which ids survive; the **freeform** walk (add three, log two against the
second, remove the first, assert cursor and counts); and a test that a removed slot's logged rows still
appear in the session's set list while leaving `SlotProgress`.

**Review must answer, in writing:** decision 2's table re-derived from the diff; the one reader of the
overlay; the store's lifecycle (seed / clear) walked including the **MINIMISE** path; that
`applyCoachRoutineEdit` still preserves `old.id`; that `asNew: true` writes only the clone; the four
frozen digests; and the `SoloResumeCursor` verdict.

### S2 — the abandon door: Discard, the warm-up's END, the lazy sweep — **L · Opus**

Decision 1 is the specification.

**Do.** `SessionRepository.abandon(sessionID:at:)` beside `complete` (`:188-200`), same shape. Widen
`startOrAdoptSolo` to return `Start { session, adopted }` and update its **three** call sites
(`HomeView.swift:2438`, `DiscoverWorkoutDetailView.swift:437`, `RoutinesListView.swift:495`). Add the
third outcome to `AdHocSessionAdoption.Decision` (`abandoning: [UUID]`, computed from `mine` minus
`fresh`, still pure) and perform those writes in `startOrAdoptSolo`, best-effort, **`completed_at` = the
row's own `startedAt`**. Mount **Discard** on the end confirmation for `crewShape == .solo`
(`SessionLiveView.swift:2286`) with decision 6's copy. Mount **END** on the solo warm-up cover beside
`SoloMinimiseControl` (`SoloSessionLayer.swift:198`, `:265-291`) for `crewShape == .solo`, calling
`abandon` with `completed_at = now`. Make `DiscoverWorkoutDetailView`'s **"Not now"** (`:201`) abandon —
**only when `adopted == false`**. **Correct `AdHocSessionAdoption.swift:29-64`**: the header's "there is
no reaper" paragraph and the withdrawn-ruling paragraph are both rewritten to say what is true (the
6-hour reaper at `20260716000004:107-122`; the ruling is un-withdrawn because `abandon` is the quiet verb
it lacked).

**Pure tests:** `decide(…)` returns the right `abandoning` set for — no stale rows; one stale row; a stale
row that is somebody else's; a stale row that is a crew session of mine; a row with `startedAt == nil`
(never abandoned, it is a data anomaly); and adopt-plus-abandon together. Plus a test that the Discard
button is absent for `.crew` and for `.unknown`.

**Review must answer:** every call site of `abandon` and its gate; that no call site can reach a crew
session; that `startOrAdoptSolo` still starts when the read fails; that the lazy sweep never blocks the
start; and the copy against design rule 9.

*(Leg boundary — retire the Opus implementer after S2.)*

### S3 — `FormClipCapture` moves, solo-only and unchanged — **S · Sonnet**

Decision 3. Move the `.fullScreenCover` (`WorkoutSessionView.swift:1203-1211`), `canRetainClips`
(`:334`, gate `:2590-2596`), `pendingClipURL` (`:333`) and the attach at `:4371-4381`, behind
`crewShape == .solo`. `git mv Features/Workout/FormClipCapture.swift Features/Sessions/`. **No catalog
frame, no new `scenePhase` handler, and do not touch the rest-lapse `Task`** — **read**
`SessionLiveView.swift:3328-3336` and `:3357-3374` and state in the report why the F1 failure mode cannot
occur here (nothing cancels the lapse; the body is not removed by a cover presented from it).

### S4 — the any-rest swap, proved — **S · Sonnet**

Decision 4. **No production change is expected** — the one body's swap button (`:1577-1588`) and sheet
(`:2189`) are already ungated. Add the pure test that a **mid-exercise** swap counts once: three target
sets, two logged, swap, one logged → `SlotProgress` reports 3 of 3 on that one slot, split across no
second `exercise_id`, and `RoutineProgression.currentSlot` advances exactly once. **If a gate is found,
STOP and hand back** — that would contradict this plan and the finding is worth more than the edit.

### S5 — Coach's solo hooks, and solo gains Coach's door — **L · Opus**

Decision 5's table. Merge `prefetchCoachContext` onto the body's context builder rather than copying it,
and **grep that exactly one caller remains** — `TrainingProfileRepository.save(… lastProbeAt …)`
(`WorkoutSessionView.swift:3742-3743`) must not run twice. Mount `openCoachThread()` (`:4527`) for solo.
`coachPendingProbe` arrives with no twin; `soloCoachDecision` folds into `turnCoachDecision` (`:983`).
Constraint 22: every new modifier goes in an extracted layer. **The `cue` lever is NOT in scope.**

### S6 — finish, recap, Pump post and discard converge on `presentCompletion` — **L · Opus**

Decision 6's table, and only that table. **`presentCompletion` keeps reading through
`PendingSetLogMerge.merged` (`:5859-5862`) — C1's NEW-2, and a review finding if it moves.**
`HealthKitBridge.exportWorkout` stays at **one** call site. Carry `syncRecoveryProbes` +
`answerRecoveryProbe`, `LiveSessionTimerStore.shared.clear(sessionID:)`, and the "Keep your mid-session
edits?" dialog (its writer half arrived in S1). **`buildPostSummary` does NOT move — it is already there**
(`:6076-6111`); a task that "moves" it has duplicated the recap.

*(Leg boundary — retire the Opus implementer after S6.)*

### S7 — both views are deleted — **L · Opus**

Decision 8's acceptance table, in **one** commit, including the duplicated log path (`soloPrefill`
`:1231-1343`, `soloEntryCard` `:2526-2788`, `soloLoaderExpanded` `:2257` + `barLoaderCard(re:)` `:3193`,
the second `isLoggingSet` `:73`, `log(reps:weight:rpe:isFailed:note:)` `:4247-4603`) — which dies with the
file rather than being deleted ahead of it.

**Before the first deletion, the report walks the capability ledger row by row and names, per row, the
merged task that gives it its verdict.** A row without one stops the task (constraint 9).

**Then:** both files; `SoloWarmupStore` and its three consumers; `AppState.LiveSoloSession` + the
property; `SoloResumeCursor.swift` + its test **per S1's verdict**; `supersetPartnerIndex`;
`soloStallSwapName`; `refreshSoloWatchState`/`pushSoloWatchState`; the six `solo-live-set` coordinates;
the frame-map entry. **Type self-check before push** (constraint 24) — this commit changes more call sites
than any other in the phase.

### S8 — two ride-alongs — **S · Sonnet ×2, one commit each**

R1 (HR zones from `Profile.birthYear`, **nil is the common path and the tested one**, 190 stays as the
fallback, the stale doc-comment corrected) and R2 (the "Coach — coming soon" string at
`GuidanceTips.swift:139`). Neither gates S7.

### S9 — two proof frames — **M · Sonnet**

`session-solo-editor` (160) and `session-solo-coach` (161), each through the four-part contract in **one**
commit per id (constraint 6), built on `SessionLiveView`'s existing `#if DEBUG` fixture initializer and
the `SoloSessionCover.catalogContent` seam C1 established. Constraint 11: no repository, no `Date()`, no
`.shared`, no reachable `WatchConnectivityBridge` / `HeartRateBroadcastService` / voice room.
**New fixture fields are `var`, never `let x = default`** (constraint 24 — this exact slip reddened C1's
release run). Proof is a green **screenshots** job, not `build-test` (constraint 19).

---

# INTEGRATION

### I1 — the FLOOR, the frame-map and the accepted deviations — **S · Sonnet**

Re-derive `FLOOR` by counting `app-*` files in the last green `app-screenshots` artifact (downloaded into
a **fresh** directory), set `ios.yml:471` to that literal, and **rewrite the comment block at
`:468-470`**, which currently predicts a C2 delta of `−1`: the delta is **`+1`** (160, 161 in; 66 out).
Record the accepted deviation for **frame 159** (`session-solo-warmup-cover` now shows END). Re-count:
119 cases, 119 ids, 117 real captures, 98 frame-map entries, max 161, zero duplicates.

### I2 — end-to-end CI, then by eye — **M · controller**

One integrated render on the release branch; proof renders on their own `proof/<what>-<sha>` ref.
Then the owner's manual TestFlight script (constraint 25), walked in order, **including the OFFLINE leg**:
START SOLO → edit the routine mid-workout → swap mid-exercise → minimise → airplane mode → walk away from
a second workout and Discard it → the recap counts every set exactly once → friends never see the
abandoned one as live.

### I3 — one PR, with proof cards — **M · controller**

Cards: the editor (160), Coach's door (161), the changed warm-up cover (159, as an accepted deviation),
and a **before/after of the deletion** (line count, the six retired `solo-live-set` coordinates, FLOOR
140 → 141). **A final whole-branch Opus review** (constraint 23) that walks START→RECAP on every path
including offline, and re-digests the four frozen symbols one last time.

---

## The capability ledger — every row, with its C2 verdict

C1's 24 rows, carried forward with the task that closes each. **S7 may not start until every row's task
has merged.**

| capability | verdict | closed by |
|---|---|---|
| Rest timer between own sets | already there — `selfRotationRest*` + `LiveSessionTimerStore`; `soloRestIsTransit` survives as the store's `restIsTransit` | C1 |
| Warm-up phase | already there — `WarmUpScreen`, DB-gated; `SoloWarmupStore` **retires** (the DB gate is the honest one) | C1 + S7 |
| Warm-up **sets** (a per-set flag) | absent in both — not a gap, not built | — |
| Add exercise mid-session (freeform) | **moves** | S1 |
| Reorder / remove, full routine rebuild | **moves, solo-only** (`crewShape == .solo`) | S1 |
| Swap one exercise | **moves and improves** — durable + slot-keyed (C1), searchable (the hotfix), **already any-rest in the one body** | C1 + S4 |
| Supersets | already there — `RoutineLayering` + `RoutineProgression`; `supersetPartnerIndex` **retires** as a duplicate | S7 |
| Plate math / bar loader | already there — `turnBarCard`/`turnLoaderExpanded`; the solo pair **retires** | S7 |
| Notes on a set | already there, equally absent on both — the edit-existing-log sheet is the only door and it moves with the log path | S7 |
| RPE, failed set | already there — `RPESwipeTrack`, identical shared component | C1 |
| Penalty / burpee-debt sets | already there, crew-only — no solo equivalent needed | — |
| PR detection + `PRFiring` | already there — both through `PRFiring.shouldCelebrate`; solo's parallel plumbing **retires** | S7 |
| Watch + heart rate | already there and better — one `WatchSessionStatePayload`; the solo pair hardcoded `groupID: nil` / `isMyTurn: true` and **retires** | S7 |
| HealthKit export | already there — one bridge, **one** call site in `presentCompletion` | S6 |
| Live Activity / ActivityKit | absent in both — not a gap, not built (cut from v0 pending an owner decision) | — |
| Music / audio | already there — `CelebrationSound` only, in both | — |
| Video form clip | **moves, solo-only** | S3 |
| Voice (PTT) / chat | crew-only, gated off for solo | C1 |
| Finish + recap + Pump post | **moves** — the remainder only; `buildPostSummary` was already there | S6 |
| Discard / abandon | **solo GAINS it** — and it is `abandon`, not `complete` | S2 + S6 |
| Resume after relaunch | already there — the live pill routes through `SessionEntryView`. **`SoloResumeCursor`'s verdict is S1's to write** | C1 + S1 |
| Metrics sheet | already there — both feed `WorkoutMetricsSheet` through `PostSummary`/`PumpCheckContext` | C1 |
| Coach hooks | **moves, and solo gains Coach's door** | S5 |
| Substitution graph | already there — one `ExerciseSubstitutionRepository` feeds both pickers; `soloStallSwapName` **retires** (solo-only, no crew equivalent, no owner request; if the owner misses it, it returns as its own item) | S7 |
| **Recovery probes** *(new row — the map found it outside C1's inventory)* | **moves** — `syncRecoveryProbes` / `answerRecoveryProbe` have no twin in the one body | S6 |

---

## What this plan does not decide

1. **Disk persistence for the rest window, the swap outbox, the routine cache and the edit overlay.**
   Decided in decision 7: **M2's first task.** The idiom is `OfflineSetLogQueue`
   (`Services/OfflineSetLogQueue.swift:141-536`) — a SwiftData `@Model` on the app's single
   `ModelContainer`, `configure(modelContext:)` from `RootView`, per-item clear plus an age prune. The
   three stores are `Services/LiveSessionTimerStore.swift:16-48` (by session),
   `Models/SessionSwapLayer.swift:86-129` (by session) and `Models/SessionRoutineCache.swift:38-58` (by
   **routine**), plus S1's new overlay store (by session). C2 lands only the in-memory survival the editor
   move requires.
2. **An age bound on `friends_live()`.** Decision 1(c′): none, with reasons. A product question for M4.
3. **A server-side narrowing of who may write `sessions.state`.** Identical exposure to `complete()`
   today; adding a `state` clause to `session_round_guard` would make a guard that disclaims authority
   into an authorization layer. Docketed.
4. **Whether the crew ever gets a session-local routine editor.** §3.4 makes the consent card the crew's
   mode of exercise change. Not proposed.
5. **Whether `FormClipCapture` is ever offered in a crew session.** Solo only, unchanged.
6. **The `cue` lever's render site.** It needs a home on the logging screen, and that screen's slots are
   M4's. Docketed with its evidence (decision 5).
7. **The history-list asymmetry** — an abandoned session's sets count toward PRs and volume but the
   session does not appear in `SessionRepository.history`. Pre-existing for any never-ended session.
   Docketed.
8. **Where the style selector and the rack ask live** (open owner decision #6). **Defaults to M4** per the
   dispatch; no task here moves them.
9. **The design of the your-turn logging screen, the You page, the Trainer page or the PR celebration**,
   and **where heart rate belongs**. M4. **No task here builds into the top-left slot.**
10. **Repairing sessions already double-logged.** M2, and it needs the owner's word after a read-only
    count.
11. **The lock-screen leg of the owner's rest-timer report.** Two candidates, neither proven; C2 adds no
    speculative `scenePhase` handler (decision 3).
12. **Together's interval editor.** An open owner decision, not M1's.

---

## Self-review (run by the planner, 2026-09-19)

**Verified against the code at `8e9112e`, by running the command or reading the lines — not against the
map and not against the C1 plan:** the FLOOR (140, `ios.yml:471`) and its comment block; the frame counts
(97 entries, max 159); the catalog counts (118 cases, 116 real captures); both file sizes (4,929 /
6,185); the one `WorkoutSessionView(` site and the one `WarmUpPhaseView(` site; every symbol coordinate in
decisions 2, 3, 5, 6 and 8; `SoloSessionShape`'s three predicates and `isSoloByConstruction`'s full
doc-comment; `SessionEndAffordance.Page`'s five cases; `presentCompletion`'s body; the one body's rest
lapse and `restoreTimersFromStore`; `SessionRepository.complete`, `startOrAdoptSolo`, `liveForCurrentUser`
and `history`; `AdHocSessionAdoption.decide` in full; `WeeklyGoalLiveRepository.weekSessions`; the
`sessions` UPDATE policy and the single `BEFORE UPDATE` trigger; the three completion triggers' guards;
`announce_session_lifecycle`'s `group_id IS NULL` return; `streak_on_session_state_change`'s live
definition; the reaper's SQL; `friends_live`'s body and its test's fixture ages; the pgTAP namespaces.

**Corrections this plan makes to what it was handed:**

1. **A reaper exists.** `AdHocSessionAdoption.swift:32-34` ("there is no reaper") and C1's ledger ("reads
   as live forever") are wrong; the residual is **six hours**, not forever. S2 corrects the comment; this
   plan's own commit corrects the roadmap's `friends_live()` sentence. **Consequence:** decision 1 shrinks
   to the user-initiated door and needs **no migration at all**.
2. **`SoloSessionShape.isAdHocSolo` does not exist.** The C1 outline's C2-S1 row names a symbol C1 itself
   retired. The gate is `crewShape == .solo`, and decision 2 argues why that, and not
   `isSoloByConstruction`.
3. **The swap door is already ungated in the one body.** C2-S3's "the transit-only gate does not survive
   the move" describes the OLD view (and cites `:1616`, which drifted — the gate is `:1882-1883`). The
   task becomes a pure test, size **S**.
4. **`buildPostSummary` is already in the one body** (`SessionLiveView.swift:6076-6111`, inside
   `buildPumpCheckContext`). C2-S5's "the two `endSession`/`buildPostSummary` paths converge" over-states
   the work; decision 6 lists the actual remainder, and **recovery probes** — absent from C1's 24-row
   ledger entirely — are added as a 25th row.
5. **C2-S6 and C2-S7 merge.** Emptying a file in one commit and deleting it in the next is work with no
   consumer. One L · Opus task instead of M · Opus + L · Opus.
6. **C1's streak correction (`f3ea990`) is itself wrong.** An unscheduled **completed** session with
   logged work **does** credit the individual streak as of `20260803000005:69-84`. D1's assertion 5 pins
   it so the record cannot drift again.
7. **The FLOOR delta is `+1`, not `−1`.** `ios.yml:468-470` predicts `−1` because it was written before
   this plan's two frames existed. I1 rewrites it.

**The riskiest assumptions, named rather than buried:**

- **A1 — a client-side scope is enough for `abandon`.** The policy lets any participant abandon any
  session they are in, exactly as it lets them complete one. This plan gates every call site on
  `crewShape == .solo` and docket the server-side narrowing. If the owner ever offers a crew-facing
  abandon, that docket becomes a blocker first.
- **A2 — an editor-added slot's client-minted id is safe to stamp on `set_logs` before the row exists.**
  There is no FK (C1 D3's deliberate stance) so the insert succeeds, and `RoutineProgression`'s
  per-`exerciseID` fallback covers the case where the id never reaches the database. S1's tests pin both
  halves. **If a FK is ever added, this is the first thing it breaks.**
- **A3 — `crewShape == .solo` is the right gate for four different capabilities** (editor, clip capture,
  Discard, warm-up END). It is `.unknown`-safe by construction (unknown keeps crew behaviour), and it is
  the gate C1 already ships for five crew-furniture decisions. The one behaviour change it carries is
  deliberate: a **scheduled** solo session gains the editor, which the old screen never offered.
- **A4 — the one body's rest lapse cannot be stranded by a `fullScreenCover`.** Argued from absence
  (nothing cancels the `Task`) rather than from a test, because there is no simulator here. S3 states it
  from reading, and the manual script (constraint 25) is what would find it.
- **A5 — `SoloResumeCursor` is subsumed by C1's resume path.** Not verified by this planner; it is **S1's
  question to answer**, deliberately, because a deletion task is the wrong place to discover a capability.
  If the answer is "not subsumed", S7's scope grows by one move and the ledger row changes before
  deletion, not after.
- **A6 — nine app tasks is the budget.** If a task discovers that a decision here blocks it (most likely
  candidate: S1's store, if the overlay turns out to need the routine itself on disk to be meaningful
  offline), the controller promotes **decision 7's M2 task** into C2 rather than letting S1 half-build
  it — and says so in the ledger.
