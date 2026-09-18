# One session body, a chosen style — Phase B2 — implementation plan

**For agentic workers.** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Every task below is
one subagent, one commit, one review. Do not batch tasks; do not start a Stream S task before the Stream D
gate it names has been applied to the live project. **The intended model is written beside every task** and
in the sequencing table (token addendum, 2026-09-13).

**Goal.** B1 gave the crew session a body that moves — three styles, stations, a server-owned round. B2 is
everything that sits **on** that body without changing how it moves: the crew's routine change becomes a
consent card you can look things up from; the quiet personal scale-down becomes visible where the crew
already looks; the pump-check post is re-composed; the lobby's two deferred lines (the crew's week, the
day's rung) get their real reads; Coach's readiness suggestion returns to the warm-up **with a signal**;
and the last three design-round frames — with the whole `Variations/` folder — retire.

**Architecture.** Four moves, in this order of dependence:

1. **The two change modes get their surfaces** (spec §3.4). Mode 1 — the crew's routine change — is
   `swapVoteBanner` (`SessionLiveView.swift:2294`) and the vote half of `groupSwapSheet` (`:2353`) replaced
   by one **value-in** card, `SwapConsentCard`, over plain values: two tappable exercise rows that open
   `ExerciseDetailView` through the body's own `exerciseDetailSheet` (`:1831`, `:1857`), countable pips, the
   consequence line, Agree / Keep. **The wire is untouched**: `receiveSwap` (`:3010`), `evaluateUnanimity`
   (`:3053`), `castVote` (`:3145`) and the four broadcast kinds (`self` / `propose` / `vote` / `apply`) keep
   their format, so a card change cannot become a protocol change. Mode 2 — the quiet scale-down — is
   already **written** (`selfScales`, `:296`, filled by the sheet's "Just me" path at `:3133` and by the
   `self` broadcast at `:3014`) and already **read** on the station card (`stationLifter`, `:3432`); what is
   missing is the other place the crew looks, the rotation strip, so B2 adds one optional line to
   `TurnStrip.Tile` and nothing else.
2. **The two deferred lobby reads become real.** `crewWeek` (`LobbyView.swift:1100`) returns `nil` in
   production and says so in twenty lines of its own doc comment; `planRungLine` (`:207`) falls back to the
   routine's name, and `SessionRunnerView.swift:129-131` restates the identical deferral for the warm-up's
   `rungHeadline`. The first needs one SECURITY DEFINER RPC (the only cross-member weekly read that exists);
   the second needs no data at all — `BlockGoalRepository.activeGoal()` + `.page(goalID:)` is the read
   `SessionRunnerView.loadBlock()` (`:210-218`) already performs, and `LadderPageModel.rows` carries the
   worded rung this screen wants.
3. **Coach's warm-up suggestion returns with a signal, and Accept applies something real.** `coachLine` is
   passed `nil` (`SessionRunnerView.swift:135`) into plumbing that is wired and inert (`WarmUpScreen.swift:99`,
   `:118-119`; `SessionPlanCardWithSuggestion`, `SessionPieces.swift:441-444`) — Phase A's N7. The signal is
   built from three reads that exist: the block ladder's standing (`LadderPageModel.coachLine`,
   `reachesMilestone`, the current rung's `status`), the last session's RPE and recency
   (`SessionRepository.recentSetLogs(userID:since:)` + `SetLog.rpe`), and an open recovery probe
   (`RecoveryProbeRepository.open()`). **Last night's sleep does not exist in this app** and no task invents
   it. Accept applies a **today-only set reduction** on the named exercise, carried from the warm-up into the
   live body as a value; nothing is persisted, and §4 is satisfied because nothing changes until the athlete
   taps.
4. **The catalog empties `Variations/`.** Frames 118, 119 and 125 are the last three design-round ids. Two
   of them retire behind new production frames; the third — `pump-check-card-v2` — retires behind an id that
   **already exists**: `pump-feed-post` builds the production `PumpPostCard` directly with values
   (`CatalogHostView.swift:1409`), so re-composing the card changes that frame's content rather than adding
   a sixth id. With the three ids go `CardVariations.swift`, `CardVariationsV2.swift`,
   `SessionVariationKit.swift`, `SessionVariationsV2Kit.swift` and the folder itself.

**Tech stack.** Swift 6 / SwiftUI (iOS 17 target), Supabase Postgres + PostgREST + RLS, pgTAP, XCTest +
XCUITest, Deno (edge functions), GitHub Actions (`ios.yml`, `backend.yml`), XcodeGen (`GymSyncApp/project.yml`
— `sources:` is a directory glob, so deleting `Features/Sessions/Variations/` needs **no** project.yml edit).

**Spec (the authority):** `docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md`. **Sections
§2, §3.1, §3.4, §3.6, §4, §5, §6 and §7 bind this plan.** Owner decisions **3, 4, 9, 10, 16, 18, 19, 21**
are the ones B2 builds. Gate documents: the design language
(`docs/superpowers/specs/2026-09-05-design-language.md`), the social-cards spec
(`docs/superpowers/specs/2026-09-11-social-cards-design.md` — the post's seven lines and §9.1's emoji-only
reactions) and the goal-first spec (`docs/superpowers/specs/2026-09-07-goal-first-programming-design.md` —
the rung the plan card prints). Round artefacts, **all of whose line numbers were re-verified against
master `0e1f4e2` on 2026-09-18 and corrected where B1 moved them**: the B1 plan
(`docs/superpowers/plans/2026-09-13-group-session-phase-b-plan.md`, its "Phase B2 — the outline"), the B1
ledger (`.superpowers/sdd/2026-09-13-group-session-phase-b-plan/progress.md`, rulings R-B1…R-B24), its
`preflight.md` and `review-final.md` (findings 1–10 and the fix-round-5 re-review), the B1 context map
(`…/context-map.md`, areas 6–8 and 10 — **stale line numbers, superseded by this plan's**), and the docket's
"Phase B1 closed" entry (`docs/superpowers/plans/2026-09-03-field-report-docket.md`).
Format exemplar (the shape this plan copies): the B1 plan above.

**The reference frames.** Three design-round frames survive on master, all DEBUG-only under
`GymSyncApp/GymSync/Features/Sessions/Variations/`:

| frame | id | file | what production copies |
|---|---|---|---|
| 125 | `swap-consensus-card-v2` | `CardVariationsV2.swift:41` (`SwapConsensusCardV2View`) | the consensus swap: proposer header, two **tappable** exercise rows with kickers NOW / PROPOSED and a `chevron.right` (`SVTappableExerciseRow`, `:148`), four countable pips over the agreed count, the consequence line, Agree / Keep |
| 118 | `swap-consensus-card` | `CardVariations.swift` | round 1 of the same card — superseded by 125, retired with it |
| 119 | `pump-check-card-v2` | `CardVariations.swift:199` (`PumpCheckCardV2View`) | the post: the highlight and the photo on one raised island (`highlightFace`, `:244`), the photo's own caption saying it is a door (`photo`, `:279`), the trajectory + rung chips as a 14 pt `surface` strip (`:294`), the plain-terms line (`:319`), emoji-only reaction chips (`:326`) |

**Production code must not import, reference or `#if DEBUG`-depend on the `Variations/` folder** — and after
S10 the folder does not exist. The production views are built from the shipped primitives the SV\* wrappers
use — `GSInitialsAvatar`, `GSSectionHeader`, `GSDivider`, `GSGoalChip`, `GSTag`, `.gs3DCard(cornerRadius:lipHeight:)`,
`.gs3DCardStyle(...)`, `GSPrimaryButtonStyle`, `GSConsentCard` / `GSConsentCopy`, `Color.gsSuccess`,
`GSMetrics.radiusMd`/`radiusSm`/`pill`, `GSFont` — plus Phase A's and B1's own production components in
`Features/Sessions/SessionPieces.swift` (`SessionPlanCard`, `SessionPlanCardWithSuggestion`, `CrewWeekStrip`,
`BlockLadderStrip`, `CoachDoorRow`) and `Features/Sessions/Live/RoundPieces.swift` (`StationCard`,
`TurnStrip`, `ReactionStrip`, `VoiceNotices`, `HeartRateZoneDisplay`).

---

## Base branch — read this first

**This plan forks from `origin/master` at `0e1f4e2`** (PR #72, the Phase B1 close docket), which is Phase
B1's merge (`800bd79`, PR #71) plus one docs PR. Verified on 2026-09-18 against `origin/master`, never a
local `master` ref:

```
git fetch origin
git log origin/master --oneline -1                                          # 0e1f4e2
grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1                        # FLOOR=130  (line 448)
python -c "import json;d=json.load(open('docs/design/frame-map.json'));print(len(d), max(v['frame'] for v in d.values()))"
                                                                            # 86 141
grep -c '^    case ' GymSyncApp/GymSync/App/CatalogHostView.swift           # 108
grep -c 'captureCatalog("' GymSyncApp/GymSyncUITests/ScreenshotTests.swift  # 106   (see below)
ls GymSyncApp/GymSync/Features/Sessions/Variations/                         # 4 files
```

| | Stream D and Stream S, from `0e1f4e2` |
|---|---|
| base | `origin/master` `0e1f4e2` |
| `FLOOR` in `ios.yml:448` | **130** |
| frames taken | 1-141 (with three pre-existing duplicate numbers, below) |
| next free frame | **142** — and a retired number is never reused, so the gaps below 141 stay gaps |
| `CatalogScreen` cases | 108 |
| `CatalogScreenTests` ids | 108 (set-equal to `allCases`) |
| **real `captureCatalog("…")` calls** | **106** — `grep -c 'captureCatalog('` prints 108 because it also counts the function's own definition (`ScreenshotTests.swift:462`) and one comment (`:465`). B1's final review, finding 9, measured this; the two uncaptured ids (`calendar-scheduling`, `ladder-on-track`) are master's own and are not B2's. |
| `Features/Sessions/Variations/` | 4 files, **3** frame-bearing ids (118, 119, 125) |
| `sessions.style` / `.stations` / `.round` / `.round_started_at` | present (B1 D1, applied `20260913200241`) |
| `advance_round(uuid, integer, boolean)` / `set_session_stations` | present (B1 D3 + fix-forwards `000105`-`000107`) |
| `sessions.state` CHECK | five values (B1 D7, applied `20260913204301`) |
| `soundboard_sounds` / `soundboard_favorites` | **still present, orphaned** — B1's D5/D6 are written and held on `feat/group-session-phase-b-data` (`066d8bf`, `74fbbe9`) waiting on the Supabase connector. **NOT B2's**; do not touch them, do not re-write the drop. |
| `routine_proposals` / `routine_proposal_votes` / `private.proposal_session_id` | present, with **zero** app readers — B2 drops them (D3/D4) |
| `crew_week(...)` | does not exist |

**Duplicate frame numbers on master** (pre-existing, inherited, and B2's to fix per the B1 outline):
`41` → `stattile-loading`, `stattile-error`, `stattile-empty`; `69` → `home-v2-tiles`,
`home-v2-tiles-solo-day`; `70` → `home-v2-strips`, `home-v2-strips-crew-night`.

---

## Global Constraints

These bind **every** task. A task that breaks one says so in its commit body, and why. Constraints 1-21 are
B1's, carried forward verbatim where they are still true, with the four changes marked **[B2]**.

1. **One release branch, `feat/group-session-phase-b2`, and this plan is its first commit.** Fork it from
   `origin/master` (verified above), commit this file, push. Every task below lands on that branch. One PR
   at the end (I3).

2. **Two streams, and only because their files are disjoint by path.**
   - **Stream D** touches `supabase/**` and `scripts/**` and nothing else.
   - **Stream S** touches `GymSyncApp/**`, `docs/design/**` and `.github/workflows/ios.yml` and nothing else.

   **S1-S10 run sequentially, in number order** — S1, S2, S3 and S4 all edit the same 4,939-line
   `SessionLiveView.swift`, and two workers on one file is the gamble this rule exists to forbid. Stream D
   may run beside Stream S throughout, subject to constraint 8's gates. **At most two Opus agents at once**
   (one per stream); dispatch the long pole first.

3. **Swift compiles only in CI.** No macOS toolchain on this machine: no `xcodebuild`, no `swift build`, no
   simulator. Read the code you are changing in full, reason about the types, push.
   `.github/workflows/ios.yml` is the compiler.

4. **Implementers do not wait on CI.** Push and hand the task back with a written report. **The controller
   monitors the run** (one event per run) and opens a fix task if it is red. Fix rounds **resume the same
   implementer**; a fresh agent only after round 3 or a model escalation. Implementers are **retired at push
   points after ≥ 4 tasks**.

5. **One commit per task**, with this trailer, verbatim:
   ```
   Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
   ```
   Use `git commit -F <file>` or a single-quoted heredoc. A `-m` message containing backticked identifiers
   has silently deleted words in this repo before.

6. **The catalog four-part contract, in ONE commit per id.** A new `CatalogScreen` id lands in all four
   places in the *same* commit: the `case` **and** its builder arm in `App/CatalogHostView.swift`; the id
   string in `GymSyncTests/CatalogScreenTests.swift`'s `ids` array; a
   `func testCatalog…() { captureCatalog("<id>") }` in `GymSyncUITests/ScreenshotTests.swift`; an entry in
   `docs/design/frame-map.json`. **And the same contract in reverse for a retirement**: the `case`, the
   builder arm **and the view struct it renders**, the id string, the capture method and the frame-map entry
   all leave in one commit. **A retired frame number is never reused.**

7. **The FLOOR is `±N over master's FLOOR at integration`, never a literal.** **[B2]** This plan's N is
   **+1** (four production captures in, three design-round captures out). I1 re-derives the literal on the
   day by counting the exported files in the last green artifact.

8. **Migrations are gates.** `.github/workflows/backend.yml:24-27` runs `node scripts/run_pgtap.js` against
   the **live** `SUPABASE_DB_URL`; there is no `supabase db push` anywhere in CI. A pgTAP test for an object
   that has not been applied to project `chjkkwqwdlmaxacwglzm` **will fail**. So each migration task ends:
   **commit, stop, hand back.** The controller applies it live (Supabase MCP `apply_migration`), says
   "applied", and only then does the matching pgTAP task — and any Swift task that calls the new RPC —
   start. Each commit body records the timestamp it was applied. **[B2] The Supabase connector must be
   authorized before D1**; it was unauthenticated when B1 closed, which is why B1's own D5/D6 are still
   held. If it is still down when Stream D reaches D1, the controller says so and Stream D stalls — see
   "The data decisions", decision 5, for what B2 ships in that case.

9. **THE IRREVERSIBLE GATE — the archive lands before the removal, and the removal before the drop.**
   **[B2] this phase's irreversible change is the `routine_proposals` drop (D4)**, and it follows D5's
   protocol exactly, no step skipped:
   1. **The controller exports the live rows** — `routine_proposals`, `routine_proposal_votes` — to
      `.superpowers/sdd/2026-09-18-group-session-phase-b2-plan/routine-proposal-rows-<date>.json`, and
      records the two row counts in the ledger. (No git tag is needed: the app code for this flow was
      removed in Phase A and the tables' full definition lives in
      `supabase/migrations/20260712000003_routine_proposals.sql`, which is not deleted.)
   2. **D3** removes every reference that would break — two pgTAP suites, three assertions inside three
      more, the QA script's two proposal commands, the edge function's comment — and is **pushed**.
   3. **D4** — the drop migration — is **written only after the export exists and D3 is pushed**. It is
      applied live by the controller like any other gate, and it cannot be undone.

   No task may reorder these. A drop applied before the assertions are retired reddens `backend.yml` on
   master's next `supabase/` push — the exact failure R-B19 caught for the soundboard drop.

10. **Never request HealthKit or LOCATION authorization outside their one permitted call site, and never
    from a test.** A raised sheet hung `build-test` for 45 minutes once. The permitted sites are
    `LobbyView.initiateCheckIn()`, `SessionRunnerView`'s check-in control (Phase A's N4, recorded) and
    `CheckInService`. **No Phase B2 view may request either.** **[B2] S4 is the task this constraint is
    aimed at**: giving `SessionLiveView` a catalog init means proving that no catalog path reaches
    `WatchConnectivityBridge.activateIfNeeded()`, `HeartRateBroadcastService`, the voice room, or any
    repository.

11. **No live repository, and no `Date.now`, reachable from a catalog builder.** Every `content_*` renders
    from fixture integers, strings and dates built from components. Every new production view in this plan
    is a **value-in view** (no repository of its own) or carries a `catalogFixture*` + `catalogSkipLoad`
    init in the `LobbyView` shape, with every load path returning immediately when the fixture is set.
    Phase A's N3 and B1's final-review finding 5 are the two times this was broken; both were the same
    defect. **[B2] one pre-existing violation is in scope**: `content_pumpFeedPost`
    (`CatalogHostView.swift:1410-1411`) builds its two posts from `Date().addingTimeInterval(-3600)` and
    `-7200`, so that frame's "3 hours ago" line is a clock read at capture time. S5 pins both to dates built
    from components while it is in the file.

12. **Every report claim is verified against `git show <sha> --stat` and the CI artifact, not memory — and
    grep the CALL SITE of every new function before claiming it is live.** Download artifacts **into a fresh
    directory**. A definition is not a feature: `git grep -n "<symbol>("` must show a caller outside the
    symbol's own file and its tests. **[B2] B1's final-review finding 2 is the cautionary case**: the round
    engine shipped with 19 pgTAP assertions, a documented contract and no caller, and only the final review
    caught it.

13. **Design rules, by number** (`2026-09-05-design-language.md`):
    - **1** — two raised surfaces only: `.gs3DCard` to read, `.gs3DCardStyle`/`.gs3D` to press; furniture
      inside a raised box stays flat; strips are `surface` at 14 pt. The two radii are
      `GSMetrics.radiusMd` (cards) and `GSMetrics.radiusSm` (tiles), lips 6 pt on cards and 4-5 on tiles.
    - **2** — **accent is spent once per screen.** **[B2] the consent card spends none** (see decision 2):
      on the live body the accent is already the LOG card, and `GSConsentCard`'s own doc
      (`GSConsentCard.swift:33-41`) states the same departure for the ladder proposal. The warm-up's accent
      stays `START LIFTING`; the lobby's stays Start; the pump card spends none and never has.
      `Color.gsSuccess` means done/present (the pips, the station tick); gold stays streak/check-in; red is
      errors.
    - **4a** — heart-rate zone colours are the one exception, and the zone word accompanies them.
      `HeartRateZoneDisplay` (`RoundPieces.swift:36-55`) is the single source. **No B2 surface adds a
      colour.**
    - **3** — kickers 10-11 pt caps, 0.1-0.13 em tracking, muted; numbers tabular (`.monospacedDigit()`).
    - **9** — sentence case for sentences, caps for kickers; a button says exactly what happens. No
      decorative emoji; SF Symbols for glyphs. The pump card's **reaction chips are content**, the same
      sanctioned exception `RoundCopy.cheerEmoji` carries.

14. **The frozen frames must not move.** **[B2]** Phase A's seven production frames (129-135) and Phase B1's
    six (136-141) are owner-approved compositions, as are the two Home canaries (frames 81, 82). **No task
    in this plan may change what any of the thirteen renders.** This is why Coach's warm-up suggestion gets
    its **own** id (S8) instead of being switched on inside frames 132/133, and why S6's rung line changes
    production only — frames 129-133 render `LobbyWorld.rungLine` / `WarmUpFixtures`, which stay as they
    are. "Unchanged" means 0 % of pixels differ below the status bar and above the home-indicator band.

15. **Do not rename an existing `CatalogScreen` raw value, and do not reuse a retired one.** **[B2]** New
    ids are prefixed by the surface they photograph: `session-` for the three session screens,
    and the pump card reuses the existing `pump-feed-post` id rather than minting a fourth.

16. **Live-DB tests use the `TestSession` teardown factory and far-future rows.**
    `GymSyncTests/TestSession.swift` is the only place a test may create a session; register cleanup with
    `addTeardownBlock` **before** the write. Every date a live-DB test controls is **2099**.

17. **pgTAP conventions.** `BEGIN;` → `CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;` →
    `SELECT plan(N);` → a comment naming the migration under test and declaring the fixture block →
    `auth.users` inserted before `profiles` → role switching with `SET LOCAL role authenticated;
    SET LOCAL request.jwt.claim.sub = '<uuid>';` → **reset the role and claim before inserting the next
    fixture block** (B1's backend run 34782471024 went red for exactly this) → `SELECT * FROM finish();
    ROLLBACK;`.
    **Fixture-block namespaces already taken** inside `00000000-0000-4000-?000-00000000??xx`: `01xx`-`09xx`
    (a known collision at `09xx`), `0axx`-`0exx`, `0fxx`, `10xx`, `11xx`, `12xx`.
    **This plan takes `13xx` (D2) and `14xx` (D5).**

18. **`XCTUnwrap(await …)` does not compile — bind, then unwrap.**

19. **The UI-test target's compile risk, named.** `GymSyncUITests` is built by the **screenshots** job
    (`ios.yml:326-329`), which runs **after** the seed step — `build-test` does **not** build it. So a task
    that edits `ScreenshotTests.swift` (S9, S10) is not proven by a green `build-test`: **its proof is a
    green screenshots job**, and the controller re-runs the job rather than assuming.

20. **Do not change the shipped session-engine contracts.** `start_session`, `advance_turn`, `advance_round`,
    `set_session_stations`, `mark_warmup_ready`, `start_lifting`, `evaluate_lateness`, `mark_no_shows`, the
    `check_in_state` CHECK, the five-state `sessions.state` CHECK and `session_participants`' four policies
    are frozen. **[B2] this plan adds one RPC and drops two dead tables; it changes no shipped contract.**

21. **The swap wire format is frozen.** `SessionBroadcastService.SwapEvent`'s four kinds
    (`self`/`propose`/`vote`/`apply`) and their payload fields are what `receiveSwap` decodes and what every
    installed build sends. S1 redraws the card; it does not touch the wire, the unanimity rule
    (`evaluateUnanimity`: every **present** lifter said yes), or the proposal-expiry arming.

---

## File structure

### Created

| File | Responsibility | Task |
|---|---|---|
| `supabase/migrations/20260918000101_crew_week.sql` | `public.crew_week(p_session_id uuid, p_week_start date)` — SECURITY DEFINER, participants only | D1 |
| `supabase/tests/crew_week_test.sql` | pgTAP: the gate, the window, the goal, the count, the non-participant raise | D2 |
| `supabase/migrations/20260918000102_routine_proposals_drop.sql` | the irreversible drop: two tables, `private.proposal_session_id`, the publication rows | D4 |
| `supabase/tests/routine_proposals_absent_test.sql` | pgTAP: the tables and the helper are gone | D5 |
| `GymSyncApp/GymSync/Features/Sessions/Live/SwapConsentCard.swift` | `SwapConsentCard` + `ExerciseDoorRow` + `SwapConsentCopy`, value-in | S1 |
| `GymSyncApp/GymSyncTests/SwapConsentCopyTests.swift` | every string the card prints, and the pip arithmetic | S1 |
| `GymSyncApp/GymSync/Models/CrewWeekRepository.swift` | `CrewWeekRepository.week(sessionID:weekStart:)` → `[CrewWeekLifter]` | S7 |
| `GymSyncApp/GymSync/Models/SessionRungLine.swift` | `SessionRungLine.resolve(page:routineName:)` — one rung sentence for both screens | S6 |
| `GymSyncApp/GymSyncTests/SessionRungLineTests.swift` | the rung, the fallback, the missing-row case | S6 |
| `GymSyncApp/GymSync/Models/WarmUpReadiness.swift` | `WarmUpReadiness.suggestion(signal:)` — the pure decision and its copy | S8 |
| `GymSyncApp/GymSyncTests/WarmUpReadinessTests.swift` | every branch of the signal, and the no-suggestion case | S8 |
| `GymSyncApp/GymSync/Features/Social/WorkoutMetricsSheet.swift` | what tapping the post's photo opens: the whole workout's metrics, from `post.summary` | S5 |
| `GymSyncApp/GymSyncTests/PumpCardCollapseTests.swift` | the one-line set summary per exercise, and the seven facts' presence | S5 |

### Modified

| File | Change | Task |
|---|---|---|
| `GymSyncApp/GymSync/Features/Sessions/Live/SessionLiveView.swift` | S1 replaces `swapVoteBanner` (`:2294`) and the vote half of `groupSwapSheet` (`:2353`); S2 fills the rotation strip's new line; S3 mounts the error banner; S4 adds the catalog init and its guards | S1-S4 |
| `GymSyncApp/GymSync/Features/Sessions/Live/RoundPieces.swift` | `TurnStrip.Tile.doing` (`:732-742`) — one optional line under the name | S2 |
| `GymSyncApp/GymSync/Features/Sessions/Live/LiveFixtures.swift` | the `swapConsent`, `scaleDown` and `yourTurn` worlds | S1, S2, S4 |
| `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift` | `crewWeek` (`:1100`) reads the RPC; `planRungLine` (`:207`) reads the block; the roster arrives from `SessionEntryView` | S6, S7, S9 |
| `GymSyncApp/GymSync/Features/Sessions/SessionRunnerView.swift` | `rungHeadline` (`:130`) and `rungDetail`; `coachLine` + the two suggestion closures (`:135`); the accepted scale handed to `SessionInProgressView` | S6, S8 |
| `GymSyncApp/GymSync/Features/Sessions/SessionInProgressView.swift` | one value passed through: today's accepted scale | S8 |
| `GymSyncApp/GymSync/Features/Sessions/WarmUpScreen.swift` | the suggestion block is drawn again — solo inside the plan card, crew as the private line (`crewBody`, `:183`) | S8 |
| `GymSyncApp/GymSync/Features/Sessions/SessionPieces.swift` | `SessionPlanCardWithSuggestion` draws `suggestion`/`isPrivate`/`onAccept`/`onDecline` (`:441-444`) instead of documenting why it does not | S8 |
| `GymSyncApp/GymSync/Features/Sessions/SessionEntryView.swift` | the lobby branch is handed the roster it already fetched (`:104`, `:87`) | S9 |
| `GymSyncApp/GymSync/Features/Social/PumpFeedView.swift` | `PumpPostCard` (`:206-280`) re-composed; `summaryBlock` (`:366`) collapses; `photoBlock` (`:347`) becomes the island's door | S5 |
| `GymSyncApp/GymSync/App/CatalogHostView.swift` | three ids in, three out; `content_pumpFeedPost`'s two `Date()` calls pinned | S5, S10 |
| `GymSyncApp/GymSyncTests/CatalogScreenTests.swift` | three ids in, three out | S10 |
| `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` | three capture methods in, three out; the class `setUp()`/`launchApp()` duplication factored (N5) | S9, S10 |
| `docs/design/frame-map.json` | 142-145 in; 118, 119, 125 out; `pump-feed-post` gains frame 146; the three duplicate numbers renumbered to 147-150 | S10 |
| `supabase/tests/rls_proposals_test.sql`, `proposal_session_id_private_schema_test.sql`, `routine_bootstrap_test.sql` | deleted (D3; `routine_bootstrap_test.sql` per R-B2-10 — every assertion depended on the retired tables, no subject left) | D3 |
| `supabase/tests/session_realtime_publication_test.sql`, `drop_undocumented_debug_functions_test.sql` | their proposal assertions retired, `plan(N)` reduced | D3 |
| `scripts/qa_p3a.js` | the two proposal commands (`:69`, `:75`) leave | D3 |
| `supabase/functions/account-deletion-cascade/index.ts` | two comment lines (`:39`, `:89`) stop naming dropped tables | D3 |
| `scripts/seed_qa_fixtures.js` | the QA session is pinned relative to the walk (`:340-341`, `:353`) | D6 |
| `.github/workflows/ios.yml` | the FLOOR, once | I1, and only I1 |
| `docs/design/accepted-deviations.json` | four entries appended (55 today) | I1 |

### Deleted

| File / symbol | Why |
|---|---|
| `GymSyncApp/GymSync/Features/Sessions/Variations/CardVariations.swift`, `CardVariationsV2.swift`, `SessionVariationKit.swift`, `SessionVariationsV2Kit.swift` — and the directory | The last three design-round ids retire behind production frames (S10). The two Kits hold nothing else: after the three views go, `SVFixtures`, `SVFixturesV2`, `SVName`, `SVQuietPill`, `SVTappableExerciseRow`, `SVZoneColor` have no reader. **Grep each before deleting** (constraint 12): B1's final review verified the only outside references are comments in `LiveFixtures.swift:251`, `SessionPieces.swift:10-11,84` and `RoundPieces.swift:312` — those comments are updated, not left dangling. |
| `SessionLiveView.swapVoteBanner` (`:2294-2347`) and the vote half of `groupSwapSheet` (`:2353-2392`) | Replaced by `SwapConsentCard` (S1). The sheet's **option list and its "Just me / Squad vote" picker stay** — that picker is spec §3.4's two modes at the point of choice. |
| `supabase/tests/rls_proposals_test.sql`, `supabase/tests/proposal_session_id_private_schema_test.sql` | They assert the policies and helper D4 drops (D3, 10 and 26 references). |
| `public.routine_proposals`, `public.routine_proposal_votes`, `private.proposal_session_id(uuid)` | Owner decision: the proposal-and-vote flow left the app in Phase A; B1 narrowed the states it was designed for; nothing reads the tables. |

**Not deleted, deliberately:** `soundboard_sounds` / `soundboard_favorites` and B1's D5/D6 (held on
`feat/group-session-phase-b-data` for their own PR — constraint 8); `WorkoutSessionView.swift` and
`WarmUpPhaseView.swift` (the ad-hoc path — Phase C); `sessions.warmup_minutes`;
`ChatView.visibleReactionCounts`' `snd:` filter (`:714`) — the cache defence B1's review said to keep;
`SessionLiveView.errorText` (`:197`) — S3 gives it a reader rather than removing it.

---

## The six data decisions, stated

### 1. `crew_week` takes the week as a parameter — the spec's signature is one argument short

Spec §6 writes `crew_week(session_id)`. Two facts make that signature wrong in practice:

* the strip's own maths is **Monday-first** (`CrewWeek.doneByDay`, "Monday first, seven entries";
  `CrewWeekMath.daysInWeek = 7`), while the client's week start is the **device calendar's**
  (`WeekMath.startOfWeek` uses `calendar.dateInterval(of: .weekOfYear:)`, which is Sunday in a US locale);
* Postgres's `date_trunc('week', …)` is Monday, in the server's timezone.

A server that picked its own week would print counts for a week the athlete's own app does not agree with,
under a kicker that says "this week".

**Ruling:** `public.crew_week(p_session_id uuid, p_week_start date)` — the client passes
`WeekMath.weekStartString()`, the server counts `[p_week_start, p_week_start + 7)`. One definition of "this
week" in the app, and pgTAP can pin it with a literal. Recorded as a deliberate spec correction (I3).

### 2. What `crew_week` returns, and what it does not

Per participant of the session: `user_id`, `username`, `goal` (`profiles.weekly_session_goal` — **not** the
`weekly_goals` table, which is the Home-v3 per-goal store with an entirely different shape), and `done`
(DISTINCT `sessions` with `state = 'completed'` and `completed_at` inside the window, joined through
`session_participants` — attendance, not organization, exactly as `group_consistency_honor` counts).

It returns **no per-day breakdown.** `CrewWeekLifter.doneByDay` is `nil`-able by design and the strip is
already honest about it in its own words ("the actual line then runs straight from Monday 0 to today's
count, which is honest about being a straight line rather than pretending to a shape"). Production therefore
draws the straight line; the catalog fixture on frame 135 keeps its shaped one, and I2 states the
difference so nobody reads the fixture as the product.

**The shape is `group_consistency_honor`'s** (`20260911000001`), deliberately: gate FIRST with
`private.is_session_participant`, `LEFT JOIN LATERAL` per member so two cardinalities cannot multiply,
`REVOKE` then `GRANT`. Two departures from that sibling, both named in the migration header: the window is a
parameter rather than `now() - interval '30 days'`, and **a member with zero sessions is a row, not an
absence** — the honor RPC drops them because a crown decays, but a crew's week must show the lifter who has
not trained yet, or the strip lies about the crew's size.

**A goal is nullable in the value type and NOT NULL in the column.** `profiles.weekly_session_goal` is
`NOT NULL DEFAULT 3` (`20260811000003:7`), so the RPC never returns SQL NULL; `CrewWeekLifter.goal: Int?`
keeps its nil case for the fixture and for a future opt-out. S7 maps the column straight across and does not
invent an "unset" sentinel.

### 3. The consent card spends no accent, which the reference frame does

`SwapConsensusCardV2View` paints Agree with `GSPrimaryButtonStyle` — correct for a frame rendered alone on
its own page. In production the card is an **overlay on a live session page that has already spent its
accent**: the LOG card is the act of every style's page (R-B18 established exactly this for Together's ring).

**Ruling:** the production card uses `GSConsentCard`'s answer pair — two raised faces, `GSConsentCopy`'s
words in the crew's vocabulary (`Agree` / `Keep <exercise>`), no accent anywhere — and `GSConsentCard.swift:33-41`
already argues the case in the app's own voice. The **rest** of frame 125 is copied exactly: proposer
header, two tappable rows with NOW / PROPOSED kickers and chevrons, the pips, the consequence line.

**It is not literally a `GSConsentCard`.** That type takes `kicker`/`sentence`/`detail` strings and has no
slot for two tappable rows or a pip meter. `SwapConsentCard` is its sibling — same padding, same radius, same
lip, same answer pair, built from the same primitives — and `SwapConsentCopy` reuses `GSConsentCopy.accept`'s
discipline (one spelling, asserted by a test). Adding a `@ViewBuilder` content slot to `GSConsentCard`
instead would put a second composition inside a type whose whole doc comment is about having exactly one.

### 4. Coach's readiness signal is three reads that exist, and sleep is not one of them

Spec §2's example — *"you slept five hours and today is 4×5 at 225 — want 3×5?"* — names a signal this app
does not have: **there is no sleep source.** HealthKit is read for heart rate only (`HealthKitBridge`), and
constraint 10 forbids any new authorization request. The honest signals, all already fetched or one cheap
call away:

| signal | read | what it says |
|---|---|---|
| the block's standing | `BlockGoalRepository.activeGoal()` + `.page(goalID:)` → `LadderPageModel.coachLine`, `reachesMilestone`, and the current rung's `status` (`.missed` / `.current` / `.ahead`) | whether the ladder is still reaching |
| last session's effort | `SessionRepository.recentSetLogs(userID:since: now − 14 days)` → the mean `SetLog.rpe` of the most recent day's non-failed, non-penalty logs, and the days since | whether the athlete is coming in hot |
| open soreness | `RecoveryProbeRepository.open()` → an unanswered probe whose `muscle` a plan row trains | whether the last dose is still being paid for |

`WarmUpReadiness.suggestion(signal:)` is a **pure function over those three values plus today's plan rows**,
tested branch by branch, and returns at most one suggestion — the strongest — or `nil`. The rule, pinned in
one place: an open probe on a muscle today trains **and** last session's mean RPE ≥ 8.5 **and** fewer than
two days since → suggest one set fewer on the day's heaviest compound; a `.missed` rung with
`reachesMilestone == false` → suggest nothing (that conversation belongs to the ladder page's own proposal,
spec §4); otherwise `nil`. **`nil` is the normal case, and a warm-up with no suggestion is the shipped
screen** — which is why frames 132/133 do not move (constraint 14).

### 5. Accept applies a today-only set reduction, carried in memory, because no store exists for it

There is no per-session prescription override anywhere: `routine_exercises` is the routine's own row, the
trainer-prescription table (`20260814000008`) is a different subject, and B1's sweep deleted
`targetSetsPerLifter` as callerless.

**Ruling:** Accept sets `TodaysScale(exerciseID:, setsInstead:)` on `SessionRunnerView`, which passes it
through `SessionInProgressView` into `SessionLiveView`, where `effectiveRoutineExercises` (`:513`) layers
it **after** the squad swap and the self scale — the same three-layer order that already exists. Both the
warm-up plan card and the live body's THE SESSION · WHERE WE ARE then print the reduced prescription, because
both build their rows from that one array through `SessionPlanRow.prescription(for:)`.

**Accepted consequence, stated:** a relaunch mid-session loses it. The alternative is a column on
`session_participants` or a new per-session overrides table, which is a data decision nobody has asked for —
recorded in "What this plan does not decide". Nothing is written to the database, so nothing can be wrong in
it; §4 holds either way, because the athlete's tap is the only thing that changes the number.

### 6. The QA seed's wall-clock dependence is Home's one button, and only that

The brief and B1's outline both said the seed pin would also make the arrival track's "late" deterministic.
**Re-verified against master: it would not, because the late lane never reads a clock.**
`SessionArrival.isLate(checkInState:)` (`SessionArrival.swift:77-79`) is `check_in_state == "late" ||
"no_show"` — a column the seed writes and `evaluate_lateness` sets, with no time comparison anywhere on the
render path.

What **is** wall-clock dependent is Home's one button, through two rules that both measure from
`sessions.scheduled_for`, which the seed writes as `now` at seed time (`seed_qa_fixtures.js:341`, `:353`):

* `HomeView.checkInOpensAt` — the window opens at `scheduled_for − 20 min`;
* `HomeView.nextActionableSession` (`:1283-1289`) — a session is **missed and skipped** 30 minutes after
  `scheduled_for`; and `SessionRepository.upcoming()`'s own floor (`:470`) drops it from the query at the
  same age.

So a walk that starts inside 30 minutes of the seed photographs **CHECK IN**, and one that starts later
photographs **START A WORKOUT** — from the same data, for the same account.

**Ruling:** the seed writes `scheduled_for = now + 15 minutes` for the `lobby_open` crew session (the one
with participant rows, and therefore the only one `upcoming()`'s inner join can return). Check-in then opened
five minutes ago and the row stays actionable until 45 minutes after the seed — a **50-minute deterministic
window** instead of a 30-minute one, and CHECK IN on both sides of the boundary that used to flip.
`in_progress` and `completed` rows keep `now`: `liveForCurrentUser`'s floor is six hours and the completed
rows only need to fall inside the honor's 30-day window.

**And the honor's "double credit" is not a defect.** The seed's `states` array carries `completed` twice
(B1's D7 kept six rows by re-spelling the two dead states), and both completed sessions get a genuine
`check_in_state = 'ready'` participant row. `group_consistency_honor` counts attendance at completed
sessions; two attended sessions **is two**. Filtering the RPC by check-in state would change nothing (both
rows are `ready`) and would weaken a shipped contract for a fixture's sake — constraint 20. The honor line
reads `2 SESSIONS` on `app-tab-social`, stably, and I2 records that as the expected content.

---

## New catalog ids, the retirements, and the FLOOR

### In — three production ids, frames 142-145 (four captures)

| id | frame | title | renders | task |
|---|---|---|---|---|
| `session-swap-consent` | 142 | The crew's routine change — both exercises are doors | `SwapConsentCard` over `LiveFixtures.swapConsent`: Dana's proposal, NOW / PROPOSED rows with chevrons and their load lines, four pips with two filled in `gsSuccess`, the consequence line, Agree / Keep — no accent on the page | S10 |
| `session-scale-down` | 143 | A crewmate's quiet scale-down, where the crew already looks | `RoundWaitView` over `LiveFixtures.scaleDown`: the rotation strip with Sam's `doing` line under his name, and the same scale-down on his station-card row — one lifter on a different exercise, nothing announced | S10 |
| `session-warmup-suggestion` | 144 | Solo warm-up — Coach's readiness suggestion, with its signal | `WarmUpScreen` over `WarmUpFixtures.soloWithSuggestion`: the plan card with the rung headline, the rule, Coach's one sentence naming what it read, Accept / Not today as two raised faces | S10 |
| `session-your-turn` | 145 | Rounds, your turn — the live body's own page | `SessionLiveView(catalog: LiveFixtures.yourTurn)`: the header rail, the vitals row, the exercise card and the entry card with the LOG control enabled — spec §7's last missing session frame | S10 |

`session-your-turn` is **one id and one capture** built on S4's fixture init; the other three are value-in
views.

### Frame-map only — an existing capture gets its number

| id | frame | why |
|---|---|---|
| `pump-feed-post` | 146 | The production `PumpPostCard`, re-composed by S5, **is** the twin of `pump-check-card-v2` (119). The id and its capture already exist (`ScreenshotTests.swift:543`; the builder at `CatalogHostView.swift:1409`) and have never carried a frame number, so the retirement would otherwise leave the owner's deck with no pump card at all. No new capture: the FLOOR does not move for this row. |

### Out — three design-round ids

| id | frame | replaced by |
|---|---|---|
| `swap-consensus-card` | 118 | `session-swap-consent` |
| `pump-check-card-v2` | 119 | `pump-feed-post` (frame 146) |
| `swap-consensus-card-v2` | 125 | `session-swap-consent` |

With them go all four files in `Features/Sessions/Variations/` and the directory.

### Renumbered — master's three pre-existing duplicate frame numbers

| id | was | becomes |
|---|---|---|
| `stattile-error` | 41 | 147 |
| `stattile-empty` | 41 | 148 |
| `home-v2-tiles-solo-day` | 69 | 149 |
| `home-v2-strips-crew-night` | 70 | 150 |

The **first** id at each number keeps it (`stattile-loading` 41, `home-v2-tiles` 69, `home-v2-strips` 70);
the later ones take fresh numbers above the maximum, because a retired number is never reused and the gaps
below 141 are retirements. **No capture changes**, so the FLOOR is untouched by this row; the four renumbered
ids keep their `frame-map` entries, their cases and their captures exactly as they are apart from the
`frame` integer, and the entry notes say what happened and why.

### The FLOOR

**`FLOOR` moves by `+1` against master's FLOOR at integration** — four production captures in, three
design-round captures out. Against the base this plan verified (`130`), that is `130 → 131`. **The `+1` is
the invariant; the `131` is arithmetic I1 re-does on the day**, by counting the exported files in the last
green `app-screenshots` artifact.

**Counts after S10:** `CatalogScreen` = **109** cases, `CatalogScreenTests` ids = **109**, real
`captureCatalog("…")` calls = **107** (the two-id gap is master's own — base table),
`frame-map.json` = **88** entries, max frame **150**, **zero** duplicate frame numbers.

**No capture other than these seven moves count.** Five existing captures change *content*, and they are
this plan's best proofs because a fixture cannot fake them: **`app-lobby`** (the live account's real
`LobbyView`) gains THE CREW'S WEEK and the rung line; **`app-home`**'s one button becomes deterministic
(D6); **`app-pump-feed`** and **`app-pump-feed-post`** show the re-composed card; **`app-tab-social`** keeps
its `2 SESSIONS` honor line (decision 6).

---

## Sequencing

```
 origin/master 0e1f4e2  (FLOOR 130, frames 1-141, Variations/ = 4 files)
        │
        ├──► STREAM D · the data  (supabase/**, scripts/**)
        │      D1 crew_week ──[GATE]──► D2 pgTAP
        │      D3 the proposal references retire  ── pushed ──►
        │      D4 routine_proposals DROP ──[GATE]──► D5 pgTAP
        │      D6 the seed pin  (controller re-runs the seed)
        │
        └──► STREAM S · the app (ONE worker at a time, in order)
               S1  the consensus swap card                     Opus
               S2  the quiet scale-down, where the crew looks   Sonnet
               S3  the live body's error line gets a reader     Sonnet
               S4  the live body's catalog init                 Opus
               S5  the pump-check card v2                       Opus
               S6  the rung line, lobby and warm-up             Sonnet
               S7  the crew's week, wired                       Sonnet  ← needs D1 applied
               S8  Coach's readiness suggestion                 Opus
               S9  the roster hand-off, and N5                  Sonnet
               S10 the catalog: four in, three out, Variations  Sonnet
                          │
                          ▼
                   INTEGRATION  (I1 Sonnet · I2 controller · I3 controller)  →  ONE PR, with proof cards
```

**The hard edges.** S1-S4 all edit `SessionLiveView.swift`; they are one worker in number order, and S4 goes
last of the four because its guards must cover whatever S1-S3 added. S7 calls `crew_week` (needs D1
applied). S8 must follow S6 (both rewrite `SessionRunnerView`'s hand-off to `WarmUpScreen`, and S6's rung
resolver is what S8's suggestion sentence quotes). S10 is last in Stream S because it retires the variation
views S1 and S5 were built against — retire them only once production renders — and because it is the one
task whose proof is a green screenshots job (constraint 19). D4 must follow D3's push (constraint 9).
D6 changes what the live walk photographs, so the controller re-runs the seed before I2's eyes-on pass.

**Model ladder, per the 2026-09-13 token addendum.** Opus for the multi-file judgment calls (S1, S4, S5, S8,
and D4 in Stream D). Sonnet 5 for everything mechanical from an exact spec — the strip line, the error
mount, the two lobby reads, the hand-off, the catalog tail, the migrations and their suites, I1. Never
Fable, never `fork`. **Two Opus at once, maximum, one per stream.**

**Seams are reviewed early, not at the end** (the B1 lesson, docketed): **S7's task review must answer the
seam question in writing** — `crew_week`'s exact signature, its return columns and their types, the caller's
gate, and what the app does when it raises `P0001`. B1 shipped a whole round engine with no caller because
that question was asked only in the final review.

---

# STREAM D — the data

Two migrations, two pgTAP suites, one reference-retirement commit, one seed change. `supabase/**` and
`scripts/**` only. Both migrations are **gates** (constraint 8); D4 is additionally bound by the
irreversible-gate rule (constraint 9).

### D1 — `crew_week(p_session_id, p_week_start)` — **M** · Sonnet

**File (new):** `supabase/migrations/20260918000101_crew_week.sql`

Spec §6 and owner decision 21. Write the header comment first: it states decisions 1 and 2 above in the
migration's own voice — why the week is a parameter (the device calendar's week start is not
`date_trunc('week')`'s), why the goal comes from `profiles.weekly_session_goal` and **not** the
`weekly_goals` table (`20260906000001` — a different store with a different shape), why a zero-session member
is a row here and an absence in `group_consistency_honor`, and that the shape is that sibling's.

```sql
CREATE OR REPLACE FUNCTION public.crew_week(p_session_id uuid, p_week_start date)
RETURNS TABLE (user_id uuid, username text, goal int, done int)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT sp.user_id,
         p.username,
         p.weekly_session_goal::int                AS goal,
         COALESCE(agg.session_count, 0)::int       AS done
    FROM public.session_participants sp
    JOIN public.profiles p ON p.id = sp.user_id
    LEFT JOIN LATERAL (
      SELECT count(DISTINCT s.id) AS session_count
        FROM public.sessions s
        JOIN public.session_participants sp2
          ON sp2.session_id = s.id AND sp2.user_id = sp.user_id
       WHERE s.state = 'completed'
         AND s.completed_at >= p_week_start::timestamptz
         AND s.completed_at <  (p_week_start + 7)::timestamptz
    ) agg ON true
   WHERE sp.session_id = p_session_id
   ORDER BY p.username;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.crew_week(uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crew_week(uuid, date) TO authenticated;
```

`COMMENT ON FUNCTION` names spec §6, owner decision 21, and the window's half-open bounds.

**Interfaces** — *consumes:* `session_participants`, `profiles.weekly_session_goal`, `sessions`.
*Produces:* the four columns `CrewWeekRepository` (S7) decodes into `CrewWeekLifter`.

**TDD steps.** 1. Write the migration. 2. **Commit, stop, hand back** — the controller applies it and records
the timestamp. 3. The controller verifies
`SELECT proname, pronargs, prosecdef FROM pg_proc WHERE proname = 'crew_week';` → one row, 2, true.
4. Commit: `feat(session): crew_week — the crew's weekly read, participants only` + the trailer.

**Proves:** the one cross-member weekly read the strip needs exists live, so D2 and S7 can address it.

---

### D2 — pgTAP for `crew_week` — **M** · Sonnet

**File (new):** `supabase/tests/crew_week_test.sql`. **Fixture block `13xx`.** `plan(8)`.
Fixture: one `lobby_open` session, organizer A, participants B and C, non-participant D; `weekly_session_goal`
of 4 for A, 3 for B, default for C; two completed sessions for A inside the window (2099 dates, constraint
16), one for B **outside** it by one day, none for C.

1. `has_function('public','crew_week', ARRAY['uuid','date'])`.
2. As A: the result has **three** rows — C, who has trained zero times this week, is present (decision 2).
3. As A: A's `done` is **2** and A's `goal` is **4**.
4. As A: B's `done` is **0** — the session one day outside the window does not count (the half-open bound).
5. As A: a call with `p_week_start` moved back one week gives B `done = 1` — the parameter is what decides,
   not the server's clock.
6. As B (a participant, not the organizer): the same three rows — every participant may read.
7. As D: `crew_week` **throws** `'not a participant of this session'`.
8. `prosecdef` is true — the function is SECURITY DEFINER, which is what makes the cross-member read legal.

**TDD steps.** Write, run locally if `SUPABASE_DB_URL` is available
(`node scripts/run_pgtap.js supabase/tests/crew_week_test.sql`), else push. Reset role and claim between
fixture blocks (constraint 17). Commit: `test(session): pgTAP for crew_week — the gate, the window, the
zero-session row` + the trailer.

**Proves:** the strip's numbers are the server's, the window is the client's, and a stranger gets nothing.

---

### D3 — the `routine_proposals` references retire — **M** · Sonnet

**Files:** delete `supabase/tests/rls_proposals_test.sql`,
`supabase/tests/proposal_session_id_private_schema_test.sql`, and
`supabase/tests/routine_bootstrap_test.sql` (R-B2-10: every one of its four assertions depended on the
retired tables — 1-2 named them directly, 3-4 asserted on the side effects of the INSERT that 1-2
removed, leaving no subject once they are gone); edit
`supabase/tests/session_realtime_publication_test.sql` (1 reference, `plan(1)`),
`supabase/tests/drop_undocumented_debug_functions_test.sql` (4, `plan(8)`),
`scripts/qa_p3a.js` (`:69`, `:75`), `supabase/functions/account-deletion-cascade/index.ts` (`:39`, `:89`).

This is R-B19's lesson applied before the fact: **a drop applied while a shipped suite still reads the table
reddens `backend.yml` on master.** So every assertion goes first, in its own pushed commit, and each `plan(N)`
is reduced by exactly the number of assertions removed — count them, do not estimate.

The edge function's two comment lines are **comments only** (the function's body never names the tables — it
deletes the auth user and lets the cascade run). They are edited so the inventory stops naming objects that
no longer exist; the function deploys **only from master** (`backend.yml:48`), so the change is inert on the
branch and rides the merge, exactly as B1's `livekit-token` narrowing did. **Note in the commit body that
the `livekit-token` redeploy docketed by B1 rides this same merge** — it is the next edge-function deploy.

**TDD steps.** 1. `git grep -n 'routine_proposal\|proposal_session_id' supabase scripts` and paste the list
into the report. 2. Make the edits. 3. Re-run the grep: the only survivors are
`supabase/migrations/**` (history, never edited), `GymSyncApp/GymSync/Services/LobbyRealtimeService.swift:66`
and `GymSyncApp/GymSyncTests/TestSession.swift:21` (two Swift **comments**, Stream S's paths — leave them;
S10 sweeps them), and `docs/**`. 4. Commit: `chore(proposals): retire the pgTAP suites, the QA commands and
the comments that name routine_proposals` + the trailer.

**Proves:** nothing in `supabase/` or `scripts/` reads the tables, so the drop cannot redden a green suite.

---

### D4 — the `routine_proposals` drop — **M** · Opus · **IRREVERSIBLE**

**File (new):** `supabase/migrations/20260918000102_routine_proposals_drop.sql`

**Do not write this file until the controller has confirmed both of:** the row export exists in the
workspace; D3 is pushed. The task's first step is to state those two facts in the report with the sha and
the two row counts.

The migration, each step commented with what it undoes and where that thing came from
(`20260712000003_routine_proposals.sql`, `20260712000006_session_realtime_publication.sql:6-7`,
`20260726000001_is_session_participant_dual_schema.sql:224-231`,
`20260727000004_proposal_session_id_private_schema.sql`):

```sql
ALTER PUBLICATION supabase_realtime DROP TABLE public.routine_proposal_votes;
ALTER PUBLICATION supabase_realtime DROP TABLE public.routine_proposals;

DROP TABLE IF EXISTS public.routine_proposal_votes;
DROP TABLE IF EXISTS public.routine_proposals;

DROP FUNCTION IF EXISTS private.proposal_session_id(uuid);
```

The publication rows are dropped **explicitly and first** even though `DROP TABLE` would remove them: the
explicit statement is what makes the replication change reviewable, and it fails loudly if the publication
was edited by hand. The policies go with their tables; `private.proposal_session_id` is dropped **after**
them because both tables' policies call it.

**Accepted consequence:** a tester on an older TestFlight build that still subscribes to the two realtime
streams gets an empty stream rather than rows — the app code for that flow left in Phase A, so nothing
renders either way.

**TDD steps.** 1. Confirm the two preconditions in writing. 2. Write the migration. 3. **Commit, stop, hand
back.** The controller applies it. 4. Commit:
`feat(proposals): drop routine_proposals, routine_proposal_votes and proposal_session_id` + the trailer,
with the export path and the two row counts in the body.

**Proves:** the flow the spec deleted from the app is gone from the database, and Phase A's deferred cost is
paid.

---

### D5 — pgTAP for the absence — **S** · Sonnet

**File (new):** `supabase/tests/routine_proposals_absent_test.sql`. **Fixture block `14xx`.** `plan(4)`:
`hasnt_table('public','routine_proposals')`, `hasnt_table('public','routine_proposal_votes')`,
`hasnt_function('private','proposal_session_id')`, and a `SELECT` against
`pg_publication_tables WHERE pubname='supabase_realtime' AND tablename LIKE 'routine_proposal%'` returning
**zero** rows. Commit: `test(proposals): pgTAP proving the tables, the helper and the publication rows are
gone` + the trailer.

---

### D6 — the seed pins the QA session relative to the walk — **S** · Sonnet

**File:** `scripts/seed_qa_fixtures.js` (`:340-341`, `:352-356`).

Decision 6. The `lobby_open` row — the only one `SessionRepository.upcoming()`'s inner join can return, since
it is the only pre-live state with participant rows — gets
`scheduled_for = new Date(Date.now() + 15 * 60_000).toISOString()`, written through a **named constant** with
the arithmetic in its own comment: check-in opened 5 minutes ago (`HomeView.checkInOpensAt`, −20 min), the
row stays actionable for 45 minutes (`HomeView.nextActionableSession`, +30 min), and
`SessionRepository.upcoming()`'s `−30 min` floor never excludes it inside that window. The `scheduled`,
`abandoned`, `in_progress` and both `completed` rows keep `now` — `liveForCurrentUser`'s floor is six hours
and the honor's window is thirty days.

**What this does to the existing live frames**, stated because constraint 14's cousin applies to live
captures too: `app-home`'s one button reads **CHECK IN** deterministically for any walk starting within
50 minutes of the seed, where it previously flipped to START A WORKOUT after 30; `app-lobby` is unchanged
(the lobby renders from the session row's state and its participants, not from `scheduled_for`);
`app-group-sessions` still photographs six state glyphs; `app-tab-social` still reads `2 SESSIONS`.

**TDD steps.** 1. Edit. 2. **Hand back** — the controller re-runs the seed against the QA project and
confirms the `lobby_open` row's `scheduled_for`. 3. Commit: `fix(seed): pin the QA crew session fifteen
minutes ahead so Home's button stops reading the wall clock` + the trailer.

**Proves:** the live Home capture stops depending on how long CI took to get to it.

---

# STREAM S — the app

Ten tasks, in order, one worker at a time (constraint 2).

### S1 — the consensus swap card — **L** · Opus

**Files (new):** `Features/Sessions/Live/SwapConsentCard.swift`, `GymSyncTests/SwapConsentCopyTests.swift`.
**Files (modified):** `Features/Sessions/Live/SessionLiveView.swift`, `Features/Sessions/Live/LiveFixtures.swift`.

Spec §3.4 mode 1, reference frame 125, decision 3.

**The card, value-in.** No repository, no `Date.now`, no environment beyond `gsTheme`:

```swift
struct SwapConsentCard: View {
    struct Model: Equatable {
        let proposerName: String            // "Dana"
        let from: Door                      // kicker "NOW"
        let to: Door                        // kicker "PROPOSED"
        let crewSize: Int                   // the pips
        let agreed: Int                     // filled pips, gsSuccess
        let agreedNames: [String]           // first names, one line, trailing
        let iHaveAnswered: Bool             // hides the answers once I have
    }
    struct Door: Equatable { let exerciseID: UUID; let name: String; let detail: String }
    let model: Model
    var onOpen: (UUID) -> Void = { _ in }
    var onAgree: () -> Void = {}
    var onKeep: () -> Void = {}
}
```

Composition, top to bottom, copied from frame 125 (`CardVariationsV2.swift:41-141`): the proposer row
(`GSInitialsAvatar` 30 pt + `GSSectionHeader("CREW PROPOSAL")` + one sentence); the two `ExerciseDoorRow`s
with an `arrow.down` in a fixed 22 pt slot between them so both rows keep the same edges; the pip row
(10 pt circles, filled `Color.gsSuccess`, then `"\(agreed) of \(crewSize) agree"` tabular, then the names);
the consequence line; the answers. `ExerciseDoorRow` is `SVTappableExerciseRow` in production form — kicker,
name (17 pt bold, `lineLimit(1)`, `minimumScaleFactor(0.8)`), detail, `chevron.right`, the whole row a
`Button` in `.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4)`.

**`SwapConsentCopy`** holds every string once, asserted by `SwapConsentCopyTests`: `kicker = "CREW PROPOSAL"`,
`proposal(by:)` = `"<name> proposes a change for everyone"`, `nowKicker = "NOW"`, `proposedKicker = "PROPOSED"`,
`agreement(agreed:crew:)` = `"<n> of <m> agree"`, `consequence = "It applies to everyone the moment the crew
agrees. Until then your set is unchanged."`, `agree = "Agree"`, `keep(_:)` = `"Keep <exercise lowercased>"`,
`waiting = "Waiting on the crew"` (what the card shows in place of the answers once I have voted — the old
banner showed a bare count and said nothing about what happens next).

**The wiring, and what must not change.** In `SessionLiveView`:
`swapVoteBanner` (`:2294-2347`) is replaced by a computed `swapConsentModel: SwapConsentCard.Model?` built
from `swapProposal`, `participants`, `presentRotation`, `exerciseNames` and `allExercises` — the same five
sources the banner read — and the card is mounted at the same `.overlay(alignment: .top)` (`:1835`) with the
same transition. `onAgree`/`onKeep` call `castVote(true)` / `castVote(false)` **unchanged**; `onOpen` sets
`exerciseDetailSheet = allExercises.first { $0.id == exerciseID }` — the sheet the body already presents at
`:1857`, so tapping a door opens the real exercise page with its own PR and trend reads, and a door whose
exercise is not in the catalog is **not rendered as a button** (a door that opens nothing is worse than a
line). `evaluateUnanimity` (`:3053`), `receiveSwap` (`:3010`), `armProposalExpiry` and the broadcast payloads
are untouched (constraint 21). `groupSwapSheet` keeps its picker and its option list; only its vote-side
copy changes if it names the old banner.

**`LiveFixtures.swapConsent`** — a `SwapConsentCard.Model` with four crewmates, two agreed, Dana proposing
back squat → goblet squat, both doors carrying a load line. Values only, UUIDs from literals.

**TDD steps.** 1. `SwapConsentCopyTests` (pure: every string, and `agreement(agreed:crew:)` at 0/2/4).
2. The card and the door row. 3. The model builder and the mount. 4. `git grep -n 'swapVoteBanner'` → zero.
Commit: `feat(session): the crew's routine change as a consent card, with both exercises as doors` + the
trailer.

**Proves:** a crewmate can look up what they are being asked to agree to, and the wire that carries the
agreement did not move.

---

### S2 — the quiet scale-down, where the crew already looks — **M** · Sonnet

**Files (modified):** `Features/Sessions/Live/RoundPieces.swift`, `Features/Sessions/Live/SessionLiveView.swift`,
`Features/Sessions/Live/LiveFixtures.swift`.

Spec §3.4 mode 2, owner decision 9. **Most of this is already built** — say so in the commit body rather
than re-deriving it: `selfScales` (`SessionLiveView.swift:296`) is written by the sheet's "Just me" path
(`chooseSwap`, `:3116-3143`) and by the inbound `self` broadcast (`receiveSwap`, `:3010-3016`); it is layered
into `effectiveRoutineExercises` for the viewer only (`:511-520`); and the station card already prints it
(`stationLifter`, `:3432`, `scaleDown:`). **What is missing is the rotation strip** — "who's up next" — which
shows a name and nothing else.

1. `TurnStrip.Tile` gains `var doing: String? = nil` (`RoundPieces.swift:732-742`), drawn under the name at
   11 pt in `neutral500`, `lineLimit(1)`, `minimumScaleFactor(0.8)`, and **only when non-nil** — a tile with
   no scale-down keeps its current two-line height, so the strip's baselines do not move on the frozen
   frames 137-139. Defaulted, so every existing call site compiles unchanged.
2. `rotationTiles` in `SessionLiveView` fills `doing` from `selfScales[userID]?[currentExerciseID]?.name`,
   for **every** lifter including the viewer — the same lookup `stationLifter` makes.
3. `LiveFixtures.scaleDown` — the `roundWait` world with Sam on a goblet squat: his tile carries `doing`, his
   station row carries `scaleDown`, nobody else's does, and no banner or badge appears anywhere.

**Never broadcast as a proposal:** the `self` kind is what `chooseSwap` already sends and `receiveSwap`
already stores; no new broadcast kind is added and `evaluateUnanimity` is not reached from this path.

**TDD steps.** 1. Extend `RoundWaitCopyTests` (or add `TurnStripTests`) with a tile that has `doing` and one
that does not. 2. The property. 3. The fixture. Commit:
`feat(session): a crewmate's scale-down shows in who's up next, and nowhere else` + the trailer.

**Proves:** spec §3.4's second mode is visible where the crew already looks, without anything being pushed
at anyone.

---

### S3 — the live body's error line gets a reader — **S** · Sonnet

**File (modified):** `Features/Sessions/Live/SessionLiveView.swift`.

Docket, Phase B1 close: *"`errorText` in `SessionLiveView` is write-only since S4 deleted
`legacyBottomChrome`."* Verified on master: twelve assignments (`:3568`, `:3967`, `:4504`, `:4582`, `:4597`,
`:4621`, `:4631`, `:4639` and their `localizedDescription` twins), **zero** readers. The writers are the
session's own verbs — ending the session, leaving, the burpee ledger, the skip, the re-mix — so today a
failed "End for everyone" tells the lifter nothing at all.

**Ruling: keep the state, give it one reader.** A `GSInlineErrorBanner`-style line mounted **once** on the
body root as a top overlay, beside the swap card's own mount (`:1835`) rather than per page, so all five
pages are covered by one mount; it clears on tap and on the next successful attempt (`errorText = nil` is
already written at `:4631`). It is **not** the entry card's inline line: `logSetErrorText` means "nothing was
saved, try again" and is read at `:1628`; this one means "the verb you pressed did not happen", and the two
must not merge (the file's own comment at `:213` says exactly that).

Two lines of copy, in `SessionCopy`: the banner's title (`"That didn't go through"`) and its dismissal.
No accent, no red fill — red is errors, so the **text** is red and the surface is not (rule 2).

**TDD steps.** 1. The mount. 2. `git grep -n 'errorText'` shows a reader outside its own declaration
(constraint 12). Commit: `fix(session): the live body's error line is shown, not only written` + the trailer.

**Proves:** a failed end/leave/skip says so.

---

### S4 — the live body's catalog init — **M** · Opus

**Files (modified):** `Features/Sessions/Live/SessionLiveView.swift`, `Features/Sessions/Live/LiveFixtures.swift`.

Spec §7 asks for a "your turn" production frame; B1 costed it as B2's because the my-turn page lives inside
the live body and nothing can photograph the live body. This task makes that possible **without extracting
the log path** — the one part of this file that three fix rounds stabilised (R-B21, R-B22) and that no
frame is worth destabilising.

**The shape is `LobbyView`'s** (`LobbyView.swift:26-31`), which is constraint 11's sanctioned form:

```swift
#if DEBUG
private let catalog: LiveWorld?
init(catalog: LiveWorld) { … seed every @State the page reads from the world … }
#endif
private var catalogSkipLoad: Bool { #if DEBUG catalog != nil #else false #endif }
```

**Every load path gets the guard, and the report names each one with its line number.** On master they are:
`.task(id: currentExerciseForSheet?.id)` (`:959`), `.task` (`:970`), `.task { await openAndSubscribe() }`
(`:1935` — realtime, voice and the broadcast channel), `.onAppear { restoreTimersFromStore() }` (`:1989`),
`.onChange(of: scenePhase)` (`:2019`), `.onAppear` (`:2035` — the presence push and
`WatchConnectivityBridge.activateIfNeeded()`), `.task(id: liveSession.state)` (`:2230`),
`.task(id: currentRoutineExercise?.position)` (`:2251` — the station re-mix, which calls
`set_session_stations`), and the swap sheet's `.task { await loadGroupSwapOptions() }` (`:2389`). Plus every
`LiveSessionTimerStore.shared` / `RestNotifier` write. **Constraint 10 is the hard one**: no catalog path may
reach `WatchConnectivityBridge`, `HeartRateBroadcastService`, `HealthKitBridge`, `CheckInService` or the
voice room — the guard on `:1935` and `:2035` is what prevents it, and the reviewer greps all five symbols
from the catalog builder outwards.

**`LiveFixtures.yourTurn`** seeds the world the page reads: the session (`in_progress`, `style: .rounds`,
round 2, a fixed `startedAt` built from components), the roster, `currentTurnUserID == selfID`, the routine
row and its prescription, a heart rate with its zone, the exercise catalog entry the card names, and
`logControlIsMine` true through the existing `LogControlGate`. **No `Date()` anywhere** (constraint 11).

**TDD steps.** 1. Read the whole file's load paths and list them in the report before editing. 2. The init
and the guards. 3. The fixture world. 4. Prove the guards: for each of the nine entry points, the report
quotes the guarded line. The catalog **arm** for the id lands in S10, not here — this task ships the init and
the world, and `git grep 'LiveWorld'` showing only the fixture and the init is the expected intermediate
state, declared in the commit body. Commit: `feat(session): a catalog init for the live body, so your turn
can be photographed` + the trailer.

**Proves:** the live body can render a frame without touching a repository, a socket, a timer or an
authorization prompt.

---

### S5 — the pump-check card v2 — **L** · Opus

**Files (modified):** `Features/Social/PumpFeedView.swift`, `App/CatalogHostView.swift`.
**Files (new):** `Features/Social/WorkoutMetricsSheet.swift`, `GymSyncTests/PumpCardCollapseTests.swift`.

Spec §5, reference frame 119 (`CardVariations.swift:199-370`). The **same seven facts**, about half the
height. `PumpPostCard` (`PumpFeedView.swift:206`) is re-composed in place — same initializer, same call
sites, same `WorkoutPost` input:

1. **The author row** stays as it is (`:281-305`): avatar, name, relative time, the retake and lateness tags.
2. **The highlight island** replaces the split between `summaryBlock`'s first line and `photoBlock`:
   one `.gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)` holding `GSSectionHeader("THE ONE THING")`,
   `HighlightText.line(highlight, unit:)` at 17 pt bold, the detail line, and **the photo beside it** at
   88 × 88 with its caption underneath saying it is a door. The 300 pt `photoBlock` is gone.
3. **The photo is a button** → `WorkoutMetricsSheet(post:)`: the full-bleed photo, then every exercise with
   every set exactly as `exerciseRow` (`:406-437`) draws them today, the bar-loader minis, the PR and FAIL
   tags, the duration/volume/HR line. **It is built entirely from `post.summary` and `post.photoPath`** —
   no new repository read, no session fetch (another lifter's `sessions` row is not readable, which is why
   this is a sheet over the post and not a link to `CompletedSessionView`).
4. **The trajectory strip** (`:321-345`) keeps its content and becomes a 14 pt `surface` strip carrying the
   trajectory sentence and the `GSGoalChip` rungs — the one block the frame deliberately did not change.
5. **The set rows collapse to one line per exercise**: `"<name> · <n> × <top weight>"` with the PR tag when
   any set is a PR, from a pure `PumpCardCollapse.line(for:unit:)` so the wording is testable and identical
   everywhere. The full rows live in the sheet.
6. **The plain-terms line** (`:383-400`) stays exactly as it is — routine, minutes, volume, and the HR pair
   when present.
7. **The reactions row** is already emoji-only (B1's S12 removed the `snd:` pills); it keeps
   `GroupRecapView.kudosEmoji` and its counts.

**While in the file** (constraint 11, the pre-existing violation): `content_pumpFeedPost`
(`CatalogHostView.swift:1409-1411`) builds its two posts from `Date().addingTimeInterval(…)`. Replace both
with dates built from `DateComponents` so the frame's "3 hours ago" is a fixture rather than a clock read at
capture time.

**TDD steps.** 1. `PumpCardCollapseTests` (pure: one exercise with three sets, a PR set, a failed set, a
cardio entry with no weight). 2. The collapse helper. 3. The composition. 4. The sheet. 5. The fixture dates.
Commit: `feat(social): the pump-check card re-composed — the highlight leads, the photo is a door` + the
trailer.

**Proves:** the same seven facts, half the height, and nothing about the post's data changed.

---

### S6 — the rung line, in the lobby and on the warm-up — **M** · Sonnet

**Files (new):** `Models/SessionRungLine.swift`, `GymSyncTests/SessionRungLineTests.swift`.
**Files (modified):** `Features/Sessions/LobbyView.swift`, `Features/Sessions/SessionRunnerView.swift`.

Phase A hand-off, spec §3.1 ("today's rung line on top") and §2 ("today's rung on top"). Both screens carry
the identical deferral in their own comments: `LobbyView.planRungLine` (`:205-212`, "The routine's own name
until the block's rung reaches this screen — Phase B's") and `SessionRunnerView` (`:126-130`, "The routine's
own name until the BLOCK's rung reaches this screen — Phase B's, exactly as the lobby's `planRungLine` says
of itself").

**The read already exists.** `SessionRunnerView.loadBlock()` (`:210-218`) calls
`blockGoalRepository.activeGoal()` then `.page(goalID:)` and keeps `weekNumber`, `weekCount` and `headline`
for `BlockLadderStrip`. `LadderPageModel.rows` (`Ladder.swift:60`) carries the **worded** rung —
`LadderRow.targetText` ("3 × 5 at 190") and `implication` ("≈ 214 e1RM") — for each `weekNumber`.

`SessionRungLine.resolve(page:routineName:)` is pure:

- the row whose `weekNumber == page.weekNumber` → `"Week \(weekNumber) · \(targetText)"` as the line, with
  `implication` as the detail;
- no such row, or no page → `routineName`, with an empty detail — today's behaviour, unchanged;
- an empty routine name and no page → `""`, which both cards already render as no line.

**Whose rung.** The viewer's own, on both screens. A crewmate's block goal is not readable
(`block_goals` is owner-scoped) and the spec's line is "today's rung" on the card the viewer is reading — not
a per-lifter column. Stated in the commit body so the next reader does not go looking for the crew's rungs.

`LobbyView` gains the same two-call load in its existing lifecycle (`.task`, behind the `catalog != nil`
guard every other read in that file carries — `:1300`, `:1332`, `:1371`, `:1588`, `:1651`, `:1664`), keeps
`routineInfo?.name` as the fallback, and feeds `SessionPlanCard(rungLine:)` (`:404`).
`SessionRunnerView` feeds `rungHeadline` / `rungDetail` (`:130-131`) from the same resolver and its
**already-loaded** page — no second fetch — and drops the `isSolo` restriction on `loadBlock()` only if the
crew warm-up is to carry it too (it is: the rung is a personal fact, and each lifter sees their own).

**Honest fixtures:** `LobbyWorld.rungLine` and `WarmUpFixtures`' rung strings stay exactly as they are, so
frames 129-133 do not move (constraint 14).

**TDD steps.** 1. `SessionRungLineTests` (the rung, the implication, the missing row, the no-page fallback,
the empty case). 2. The resolver. 3. The two screens. Commit:
`feat(session): the day's rung reaches the lobby's plan card and the warm-up` + the trailer.

**Proves:** the two deferred lines print the block's own number, and fall back to the routine's name exactly
as they did when there is no block.

---

### S7 — the crew's week, wired — **M** · Sonnet · **needs D1 applied**

**Files (new):** `Models/CrewWeekRepository.swift`.
**Files (modified):** `Features/Sessions/LobbyView.swift`.

Owner decision 21. `CrewWeekStrip` (`SessionPieces.swift:878`… the strip itself), `CrewWeek` / `CrewWeekMath`
(`Models/CrewWeek.swift`) and `CrewWeekMathTests` all exist and are correct; `LobbyView.crewWeek` (`:1100`)
returns `nil` in production and explains why in twenty lines. **This task is the read and nothing else** —
the strip's composition does not change, and frame 135 keeps its fixture.

```swift
enum CrewWeekRepository {
    /// The crew's week. Best-effort, like every other read the lobby makes:
    /// a failure leaves the lobby without the strip, never with an error.
    static func week(sessionID: UUID, weekStart: String) async throws -> [CrewWeekRow]
}
```
— `GroupRepository.consistencyHonor`'s idiom verbatim (`CrewHonor.swift:69-80`): `client.rpc("crew_week",
params: ["p_session_id": …, "p_week_start": …])`, `ErrorMapping.map` on the catch. `CrewWeekRow` decodes
`user_id`, `username`, `goal`, `done`.

In `LobbyView`: one `@State private var crewWeekRows: [CrewWeekRow] = []`, loaded in the existing lifecycle
behind the `catalog != nil` guard, with `WeekMath.weekStartString()` as the parameter; `crewWeek` becomes
`catalog?.crewWeek ?? CrewWeek(lifters: rows.map { … }, todayIndex: WeekMath.todayIndex())` and returns
**nil while the rows are empty**, so the strip and its space appear together or not at all — which is what
`crewWeek`'s own doc already promises. `doneByDay` is `nil` (decision 2); `todayIndex` is a computed value at
render time in production and a **fixed integer** in the fixture (constraint 11).

Delete the twenty-line "wiring it is a Phase B item" comment and replace it with what the read does, naming
the RPC and its window parameter.

**THE SEAM QUESTION, answered in this task's review** (the B1 lesson): the signature and its two parameter
names as PostgREST sends them; the four return columns and their Swift types; the caller's gate
(participants only, so a non-participant sees no strip rather than an error); and the behaviour on `P0001`
(logged, strip absent).

**TDD steps.** 1. The repository. 2. The wiring. 3. `git grep -n 'crew_week'` shows the call site outside the
repository's own file. Commit: `feat(session): THE CREW'S WEEK reads the server, in production` + the
trailer.

**Proves:** owner decision 21's strip shows real people's real weeks on `app-lobby`.

---

### S8 — Coach's readiness suggestion on the warm-up — **L** · Opus

**Files (new):** `Models/WarmUpReadiness.swift`, `GymSyncTests/WarmUpReadinessTests.swift`.
**Files (modified):** `Features/Sessions/SessionRunnerView.swift`, `Features/Sessions/WarmUpScreen.swift`,
`Features/Sessions/SessionPieces.swift`, `Features/Sessions/SessionInProgressView.swift`,
`Features/Sessions/Live/SessionLiveView.swift`, `Features/Sessions/WarmUpFixtures.swift`.

Spec §2 and §4, decisions 4 and 5 above, Phase A's N7 (and N2 — this task gives `SessionCopy.accept` /
`.decline` their first production caller, which `SessionPiecesCopyTests` has been asserting into the void).

**1. The signal, pure.** `WarmUpReadiness.Signal` = `(rungStatus: RungStatus?, reachesMilestone: Bool,
lastSessionMeanRPE: Double?, daysSinceLastSession: Int?, openProbeMuscles: Set<String>, planRows:
[(exerciseID: UUID, name: String, muscle: String?, targetSets: Int?)])`.
`WarmUpReadiness.suggestion(signal:) -> Suggestion?` implements decision 4's rule and nothing more.
`Suggestion` carries `exerciseID`, `setsInstead`, and the two sentences: what was read
(*"Your last session averaged RPE 9 and your chest is still sore from Tuesday."*) and what is proposed
(*"Today is 4 × 5 on bench — want 3 × 5?"*). **The signal is named in the sentence**; a suggestion that does
not say what it read is the thing Phase A deleted.

**2. The reads.** In `SessionRunnerView`, beside the existing `loadBlock()`: the mean RPE of the most recent
logged day from `SessionRepository.recentSetLogs(userID:since: now − 14 days)` (non-failed, non-penalty —
the repository already filters both) and the day gap from the same rows; `RecoveryProbeRepository.open()`
for the muscles. All three are best-effort: any failure yields `nil` for its own term, never an error, and a
signal with every term nil produces no suggestion.

**3. The card.** `SessionPlanCardWithSuggestion` (`SessionPieces.swift:431-464`) draws what it has been
carrying inertly: under a `GSDivider()`, the two sentences and then `SessionCopy.accept` /
`SessionCopy.decline` as **two raised faces** (`.gs3DCardStyle`, radiusSm, lip 4) — `GSConsentCard`'s pair,
so a suggestion answers the same way everywhere (rule 2: the warm-up's accent is START LIFTING).
`isPrivate` draws a small "only you see this" line — spec §3.2's "the Coach line for each lifter privately"
— and `crewBody` (`WarmUpScreen.swift:183-191`) switches from `SessionPlanCard` to
`SessionPlanCardWithSuggestion` with `isPrivate: true` **only when there is a suggestion**, so the crew
frame with none renders byte-identically to frame 133 (constraint 14).

**4. Accept applies something.** Decision 5: Accept sets `TodaysScale(exerciseID:setsInstead:)` on
`SessionRunnerView`; `SessionInProgressView` passes it to `SessionLiveView`, whose
`effectiveRoutineExercises` (`:513`) layers it last; the warm-up's own plan rows re-render with the new
prescription immediately. Decline clears the suggestion for the session and records nothing. **Nothing is
written to the database by either.**

**TDD steps.** 1. `WarmUpReadinessTests` — every branch: the probe-and-RPE case suggests; a missed rung that
cannot reach suggests **nothing**; two quiet days suggests nothing; no probe suggests nothing; an empty plan
suggests nothing; the sentence names the signal. 2. The type. 3. The three reads. 4. The card. 5. The
apply path, with a test that the layered prescription is what `SessionPlanRow.prescription(for:)` prints.
Commit: `feat(session): Coach's readiness suggestion returns to the warm-up, with the signal it read` + the
trailer.

**Proves:** §4's rule holds on the one screen the spec built for it — Coach proposes, the athlete accepts,
and the number changes only then.

---

### S9 — the roster hand-off, and N5 — **S** · Sonnet

**Files (modified):** `Features/Sessions/SessionEntryView.swift`, `Features/Sessions/LobbyView.swift`,
`GymSyncUITests/ScreenshotTests.swift`.

**(a) The hand-off.** `SessionEntryView`'s own doc comment (`:64-67`) says it "hands the fetched rows down to
whichever destination it picks, so that screen does not refetch on first paint". True for
`SessionRunnerView` (`:114`), **false for the lobby**: both `LobbyView(session:)` call sites (`:85` the
fetch-failure fallback, `:109` the `.lobby` route) pass no roster, so the lobby's own `reload()` fetches the
same rows again before its arrival track can paint. Give `LobbyView` an `initialParticipants:` parameter
defaulted to `[]` (so no other call site changes), seed `@State participants` (`:41`) from it, and keep
`reload()` exactly as it is — the poll is what keeps the track live; this only removes the blank first
frame. The fallback branch keeps passing nothing, which is correct: there are no rows to hand over.

**(b) N5** (docket `:367`). `ScreenshotTests`' class-level `setUp()` (`:75-101`) repeats `launchApp()`'s
three launch-argument pairs (`:126`, `:137`, `:150`). Factor **only the arguments and the environment
forwarding** into one `private static func applyLaunchDefaults(to app: XCUIApplication)`; call it from both.
`setUp()`'s deliberate differences stay: no `XCTFail` on missing credentials, its own 120 s budget, its own
tolerant poll — the comment at `:64-70` explains why, and that comment is updated rather than deleted.
**The 19 `launchApp()` call sites are untouched** and no test's behaviour changes.

**TDD steps.** 1. The parameter and its default; `git grep -n 'LobbyView(session:'` shows both call sites.
2. The extraction. 3. Note constraint 19: this edits `ScreenshotTests.swift`, so its proof is the screenshots
job, not `build-test`. Commit: `fix(session): the lobby is handed the roster the entry view already fetched;
one launch-defaults helper` + the trailer.

**Proves:** one round trip instead of two on the lobby's first paint, and one spelling of the launch
arguments.

---

### S10 — the catalog: four in, three out, and the Variations folder goes — **M** · Sonnet

**Files (modified):** `App/CatalogHostView.swift`, `GymSyncTests/CatalogScreenTests.swift`,
`GymSyncUITests/ScreenshotTests.swift`, `docs/design/frame-map.json`.
**Files (deleted):** all four files in `Features/Sessions/Variations/`, and the directory.

Constraint 6, in both directions, **in one commit** (B1's `2faa3ba` shipped a non-compiling intermediate by
splitting exactly this; do not repeat it).

**In** — `sessionSwapConsent` (142), `sessionScaleDown` (143), `sessionWarmupSuggestion` (144),
`sessionYourTurn` (145): a `case`, a builder arm, an id string, a capture method and a frame-map entry each.
Every builder is a value-in view over a fixture world — `SwapConsentCard(model: LiveFixtures.swapConsent)`,
`RoundWaitView(...)` over `LiveFixtures.scaleDown`, `WarmUpScreen(...)` over
`WarmUpFixtures.soloWithSuggestion`, and `SessionLiveView(catalog: LiveFixtures.yourTurn)` — with no
`Date()`, no `await`, no `Task`, no `.shared` and no repository in any of the four arms (constraint 11).

**Out** — `swap-consensus-card` (118), `pump-check-card-v2` (119), `swap-consensus-card-v2` (125): the cases,
the builder arms, the id strings, the capture methods, the frame-map entries, **and the view structs**
(`SwapConsensusCardView`, `PumpCheckCardV2View`, `SwapConsensusCardV2View`) with the files that hold nothing
else — which, after those three, is all four files in `Variations/`. **Grep before each deletion**
(constraint 12): `git grep -n 'SVFixtures\|SVFixturesV2\|SVName\|SVQuietPill\|SVTappableExerciseRow\|SVZoneColor\|PumpComposerFixtures'`
must show no reader outside the directory. `PumpComposerFixtures` is the one to check hardest —
`content_pumpComposerHighlight` (`CatalogHostView.swift:1364`) and S5's card both reference a photo fixture;
if it lives in a Kit, **move it** to the composer's own file rather than deleting it.

**`pump-feed-post` gains frame 146** — a frame-map entry only; its case and capture already exist.

**The three duplicate numbers are fixed**: `stattile-error` → 147, `stattile-empty` → 148,
`home-v2-tiles-solo-day` → 149, `home-v2-strips-crew-night` → 150, each entry's `note` recording that it was
a duplicate of 41/69/70 and that the first id at each number kept it.

**Mechanical cleanup, while here:** the two Swift comments that still name dropped tables —
`Services/LobbyRealtimeService.swift:66` and `GymSyncTests/TestSession.swift:21` (D3 left them because they
are Stream S's paths) — and the four `Variations/` references in comments that B1's review enumerated
(`Live/LiveFixtures.swift:251`, `SessionPieces.swift:10-11,84`, `Live/RoundPieces.swift:312`).

**Counts after this task:** `CatalogScreen` 109, `CatalogScreenTests` ids 109, real `captureCatalog("…")`
calls **107** (`grep -c 'captureCatalog('` prints 109 — the definition and the comment; report the measured
number, not the grep), `frame-map.json` 88 entries, max frame 150, no duplicate frame numbers.

**TDD steps.** Constraint 19: a green `build-test` does **not** prove `ScreenshotTests.swift` compiles. This
task's proof is a green **screenshots** job; if the seed fails, the controller re-runs it.
Commit: `feat(catalog): four production ids in, three design-round ids out, Variations retired` + the
trailer.

**Proves:** the design round is over — every frame in the deck is a screen that ships.

---

# INTEGRATION

### I1 — the FLOOR, the frame-map and the accepted deviations — **S** · Sonnet

- `.github/workflows/ios.yml` — **the FLOOR moves by `+1` against master's FLOOR at integration**. Re-derive
  the literal on the day:

  ```
  git fetch origin
  grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1
  grep -c 'captureCatalog("' GymSyncApp/GymSyncUITests/ScreenshotTests.swift
  gh run download <last green run> -n app-screenshots -D ./fresh-artifact && ls ./fresh-artifact | wc -l
  ```

  Against the verified base that is `FLOOR=130` → `FLOOR=131`. Extend the comment block above the line in
  the style Phase A and B1 established: the four ids in with their frame numbers, the three out with theirs,
  the renumbering (no count change), and "the +1 is the invariant, not the literal 131".
- `docs/design/frame-map.json` — 142-146 present, 118/119/125 absent, the four renumbered entries at
  147-150, **zero duplicate frame numbers** (a one-line script in the report proves it), everything else
  untouched.
- `docs/design/accepted-deviations.json` — append **four** entries (55 today), one per new id, each naming
  the retired frame it was built to and the spec section that is its authority. The `session-swap-consent`
  entry records decision 3 (frame 125 paints Agree in accent; production spends none, because the live page
  has already spent it). The `session-warmup-suggestion` entry records that it is a **new** id rather than a
  change to frames 132/133, per constraint 14. The `session-your-turn` entry records that it renders the
  production body through a catalog init rather than a value-in presentation, and why.

Commit: `chore(session): FLOOR 130 -> 131, four frames in, three out, the duplicates renumbered` + the
trailer.

### I2 — end-to-end CI, then by eye — **M** · controller

Push and read the run. **Download the artifact into a fresh directory** (constraint 12).

**iOS workflow** — build green; `GymSyncTests` green with the new files (`SwapConsentCopyTests`,
`SessionRungLineTests`, `WarmUpReadinessTests`, `PumpCardCollapseTests`); the screenshots job exports
**≥ the new FLOOR** and "Verify capture count" passes.

**Backend workflow** — pgTAP green for `crew_week_test.sql` (8) and `routine_proposals_absent_test.sql` (4),
each of which requires its migration to have been **applied** (constraint 8); a red with a "does not exist"
error means a gate was skipped, not that the SQL is broken. The two deleted suites are gone from the run's
output; the three reduced suites report their new plan counts.

**Then read the artifact, by eye, in this order:**

1. The thirteen frozen frames — Phase A's 129-135, B1's 136-141, and the two Home canaries (81, 82) —
   **unchanged** (constraint 14). Frames 132/133 in particular: no suggestion block appears on either.
2. `app-session-swap-consent` — two raised door rows with chevrons, four pips with two filled in
   `gsSuccess`, the consequence line, Agree and Keep as two neutral faces, and **no accent anywhere on the
   page**.
3. `app-session-scale-down` — exactly one lifter carries a `doing` line in the rotation strip and the same
   name on their station row; no banner, no badge, nobody else marked.
4. `app-session-warmup-suggestion` — the rung headline, the rule, two sentences (what was read, what is
   proposed), Accept / Not today as two raised faces; START LIFTING is still the page's one accent.
5. `app-session-your-turn` — the header rail, the vitals row, the exercise card, the entry card with LOG
   enabled; the fixture's numbers, not a clock's.
6. `app-pump-feed-post` — the highlight island with the 88 pt photo beside it and its caption, the
   trajectory strip, one line per exercise, the plain-terms line, emoji chips; about half the height of
   master's capture, side by side.
7. **`app-lobby`** — the live account's real lobby with THE CREW'S WEEK drawn from the RPC (a straight actual
   line, per decision 2) and the rung line above the plan. The one capture a fixture cannot stand in for.
8. **`app-home`** — CHECK IN, and the controller confirms the seed ran within the window D6 pins.
9. `app-tab-social` — still `2 SESSIONS` on the honor line (decision 6); `app-group-sessions` — still six
   state glyphs.

Fix-forward any red; each fix is its own commit.

### I3 — one PR, with proof cards — **M** · controller

`feat/group-session-phase-b2` → `master`. The body carries:

1. **What shipped**, in the spec's vocabulary: a crew change is a card you can look things up from; a quiet
   scale-down is visible where the crew already looks; the post leads with the one thing; the lobby's two
   deferred lines print real numbers; Coach suggests and the athlete decides; the design round is over.
2. **The four new ids, the three retirements, the renumbering, the FLOOR (+1)**, as this plan's tables.
3. **The two migrations**, each with the timestamp it was applied to `chjkkwqwdlmaxacwglzm`, and **the row
   export path and counts** for the irreversible one.
4. **The deliberate deviations**, each with its reason: `crew_week` takes a week parameter the spec's
   signature does not name; the consent card spends no accent where frame 125 does; the pump card reuses
   `pump-feed-post` rather than minting an id; Coach's signal is the block ladder, RPE and recovery probes
   because sleep does not exist in this app; Accept's set reduction is session-local because no per-session
   prescription store exists; the seed pin fixes Home's button only — the arrival track's late lane never
   read a clock; `WorkoutSessionView` still lives (Phase C); B1's D5/D6 are still held on the data branch and
   are not in this PR.
5. **Proof cards**, each a run URL plus its evidence: the data (two pgTAP suites, with the window and the
   participant gate named); the two change modes (frames 142, 143 beside the retired 118/125); the post
   (`app-pump-feed-post` before and after, with the height measured); the lobby (`app-lobby` live, with the
   strip and the rung); the warm-up (frame 144 beside frame 132's unchanged capture); your turn (frame 145);
   the retirement (`git grep Variations` empty, `ls Features/Sessions/Variations` absent).
6. The trailer per constraint 5, plus `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## What this plan does not decide

1. **Whether a per-session prescription override should be stored.** Decision 5. Today's accepted suggestion
   is a value in memory; a relaunch mid-session loses it. The alternative is a column or a table and an owner
   question about whether an accepted scale-down should follow the athlete to the recap and the post.
2. **Whether the crew should see a scale-down that was Coach's idea rather than the athlete's.** S8's Accept
   changes sets, which is not the `selfScales` exercise swap S2 renders, so the crew sees nothing. Whether
   "Sam is doing 3 × 5 today" belongs in who's-up-next is a product question nobody has been asked.
3. **`crew_week` across timezones.** The window is the caller's week. Two crewmates in different locales can
   read the same strip and mean two different weeks by it. One session's crew training together makes this
   rare; a remote crew makes it real.
4. **Whether the pump card's metrics sheet should be reachable from anywhere but the photo.** Spec §5 names
   the photo as the door. A post with no photo therefore has no door, and the collapsed set rows are all its
   reader gets.
5. **Whether `stattile-loading`/`error`/`empty` should be three frames at all** — they were one number
   because they are one screen in three states; the renumbering makes them countable, not necessarily right.
6. **When `WorkoutSessionView` adopts the one session body.** Phase C, unchanged from B1.
7. **B1's D5/D6.** The soundboard drop is written, reviewed and held on `feat/group-session-phase-b-data`
   until the Supabase connector returns. It ships as its own PR and is not this plan's to re-write.

---

## Self-review (run by the planner, 2026-09-18)

**1. Spec coverage — every Phase B2 sentence maps to a task.**

| spec | requirement | task |
|---|---|---|
| §3.4 mode 1 / decision 9 | the routine change as a consent card, both exercises tappable, pips, consequence, Agree / Keep | S1 |
| §3.4 mode 2 / decision 9 | the personal scale-down, never broadcast as a proposal, visible in who's up next | S2 (the rotation strip; the station card and the write path shipped in B1) |
| §5 | the shipped pump-check card is replaced by the v2 composition — same seven facts, about half the height | S5 |
| §5 | the photo opens the whole workout's metrics | S5 (`WorkoutMetricsSheet`) |
| §5 / §9.1 of the social spec | emoji reactions only | **already true** — B1's S12; verified on master, no task needed |
| §6 / decision 21 | `crew_week(session_id)`, participants only, sessions done this week and the weekly session goal | D1, D2 (the RPC), S7 (the wiring) |
| §2 / §3.1 | today's rung line on the plan card, on the lobby and the warm-up | S6 |
| §2 / §4 / decision 4 | Coach's one suggestion as the card's second line, Accept / Not today | S8 |
| §3.2 | the Coach line for each lifter privately, on the crew warm-up | S8 (`isPrivate`) |
| §7 | a production frame for the consensus swap card | S10 — frame 142 |
| §7 | a personal scale-down visible in "who's up next" | S10 — frame 143 |
| §7 | the "your turn" frame | S4 (the init) + S10 — frame 145 |
| §7 | the variation ids retire as each production frame lands | S10 — three out, the folder with them |
| Phase A hand-off | `SessionEntryView` hands the lobby its roster | S9 |
| docket N5 | `ScreenshotTests`' duplicated launch arguments | S9 |
| docket, B1 close | the `routine_proposals` drop and its edge-function reference | D3, D4, D5 |
| docket, B1 close | the stale `errorText` in `SessionLiveView` | S3 |
| docket, B1 close | the seed pins the QA session relative to the walk | D6 |
| B1 outline | the frame-map's duplicate numbers 41 / 69 / 70 | S10, I1 |
| decisions 15, 22 | live encouragement stays verbal; `pro_until` stays readable | **nothing to build** — verified: no task adds an encouragement feature or touches the profiles policy |

**Five spec corrections, made deliberately.** (a) §6's `crew_week(session_id)` gains a `p_week_start date`
parameter, because the device's week start is not `date_trunc('week')`'s (decision 1). (b) Frame 125 paints
Agree in accent; the production card spends none, following `GSConsentCard`'s own documented departure
(decision 3). (c) §5's pump card gets **no new id** — `pump-feed-post` already builds the production card,
so the retirement is a content change plus a frame number. (d) §2's suggestion example is about sleep and
about sets; the signal is the block ladder, RPE and recovery probes, and Accept's set reduction is
session-local (decisions 4 and 5). (e) B1's own B2-8 said the seed pin would also make the arrival track's
"late" deterministic — re-verified against master and **false**: `SessionArrival.isLate` reads
`check_in_state` only, so the pin fixes Home's one button and nothing else (decision 6).

**2. Placeholder scan.** Grepped the finished document for `TBD`, `TODO`, `FIXME`, `XXX`, `add validation`,
`similar to`, `same as above`, `<fill`, `and so on`, `etc.`: **zero hits outside this sentence**. Every task
names its files, its exact values, its tests, its commit message and its `Proves:` capture.

**Six things this review changed, rather than noted.**

1. **The first draft gave the pump card a new catalog id.** Read `ScreenshotTests.swift:543` and
   `CatalogHostView.swift:1409`: `pump-feed-post` already builds the production `PumpPostCard` with values.
   A fifth id would have photographed the same view twice. The FLOOR delta fell from +2 to **+1** and the
   retirement became a content proof, which is the stronger evidence.
2. **The first draft planned B2-2 as a build.** Read `SessionLiveView.swift:296`, `:3014`, `:3116-3143` and
   `:3432`: the write path, the broadcast and the station-card line all shipped in B1. Only the rotation
   strip was missing, so the task fell from M-with-a-picker to one optional field on `TurnStrip.Tile` — and
   the plan says so rather than letting an implementer rebuild what exists.
3. **The first draft made Accept write to the database.** There is no per-session prescription store:
   `routine_exercises` is the routine's own row and B1's sweep deleted `targetSetsPerLifter` as callerless.
   Decision 5 states the session-local ruling and its accepted consequence instead of inventing a table in a
   phase that is supposed to sit **on** the body.
4. **The first draft filtered `group_consistency_honor` by check-in state** to fix the seed's "double
   credit". Read `seed_qa_fixtures.js:370-375`: both completed sessions write `check_in_state = 'ready'`, so
   the filter would change nothing — and it would narrow a shipped contract (constraint 20) for a fixture.
   Decision 6 says the count of two is correct.
5. **The first draft extracted the my-turn page into a value-in view** so it could be photographed. That is
   the log path R-B21 and R-B22 stabilised across two fix rounds. S4 gives the body a catalog init instead —
   the `LobbyView` shape constraint 11 already sanctions — and enumerates the nine load paths that must be
   guarded rather than leaving "add the guards" as an instruction.
6. **The first draft dropped `routine_proposals` before retiring its pgTAP suites.** R-B19 caught exactly
   this for the soundboard: `rls_proposals_test.sql` (10 references) and
   `proposal_session_id_private_schema_test.sql` (26) plus three assertions in three more suites read the
   tables. D3 now precedes D4 and is pushed first.

**3. Cross-task symbol consistency.** Every cross-task symbol was grepped across this document for a single
spelling. The near-miss spellings a second author would reach for — `SwapConsensusCard`, `ConsentSwapCard`,
`CrewWeekService`, `RungLineResolver`, `ReadinessSignal`, `PumpCardV2`, `TodayScale` — appear nowhere in this
document except in this sentence.

- `SwapConsentCard` / `SwapConsentCard.Model` / `SwapConsentCard.Door` / `ExerciseDoorRow` /
  `SwapConsentCopy` — declared S1, rendered by S1's mount and S10's builder, nothing else.
- `TurnStrip.Tile.doing` — one field, filled in one place (`rotationTiles`), drawn in one place.
- `CrewWeekRepository.week(sessionID:weekStart:)` and `CrewWeekRow` — declared S7, one caller
  (`LobbyView.crewWeek`'s loader), decoding `public.crew_week`'s four columns character for character.
- `SessionRungLine.resolve(page:routineName:)` — one signature, two callers (S6's two screens), one test file.
- `WarmUpReadiness.Signal` / `.Suggestion` / `.suggestion(signal:)` and `TodaysScale` — declared S8, read by
  `SessionRunnerView`, `WarmUpScreen`, `SessionInProgressView` and `effectiveRoutineExercises`.
- `PumpCardCollapse.line(for:unit:)` and `WorkoutMetricsSheet(post:)` — declared S5, one caller each.
- `public.crew_week(uuid, date)` — one signature in D1, asserted in D2, wrapped once in S7.
- The four production ids appear identically in five places each: this plan's two tables, the enum case, the
  `ids` array, the capture method and the frame-map key.

**Gaps I could not close, named rather than papered over:**

- **The three riskiest assumptions, in order.** (1) **S4's catalog init can be made hermetic** across nine
  load paths in a 4,939-line file without disturbing the log path — if the reviewer finds a tenth,
  `session-your-turn` is dropped and the frame stays spec §7's open item. (2) **Coach's readiness suggestion
  has no persisted store** (decision 5), so its Accept is honest but forgettable. (3) **`crew_week`'s week
  window is the caller's** (decision 1) — correct for one device, undefined for a crew split across
  timezones.
- **Stream D cannot start without the Supabase connector.** It was unauthenticated when B1 closed; if it is
  still down, D1's gate cannot be applied, S7 cannot be proven, and B2 ships its eight app-only tasks with
  the strip still hidden — exactly the shape B1 used for D5/D6, and the controller decides it the same way.
- **Nothing here proves the consent card with two real devices.** Unanimity is evaluated on the proposer's
  client (`evaluateUnanimity`); S1 does not change that, and a genuine two-phone vote is a manual check
  listed in I3 rather than claimed by a test.
- **`GymSyncUITests` compiles only in the screenshots job** (constraint 19), so S9 and S10 are the two tasks
  whose proof depends on a seed — which D6 changes in the same branch.
- **The renumbering touches ids this plan otherwise never reads** (`stattile-*`, `home-v2-*`). If any tool
  outside `frame-map.json` keys off those frame numbers, I1's duplicate-count script will not see it;
  `git grep -n '"frame": 41'` is the check, and it is in S10's steps.
