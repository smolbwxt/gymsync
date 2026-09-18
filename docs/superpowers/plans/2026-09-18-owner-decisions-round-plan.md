# Three owner decisions — the round of 2026-09-18 — implementation plan

**For agentic workers.** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Every task below is
one subagent, one commit, one review. Do not batch tasks; do not start a Stream S task before the Stream D
gate it names has been applied to the live project. **The intended model is written beside every task** and
in the sequencing table (token addendum, 2026-09-13).

**Goal.** Three questions the owner answered on 2026-09-18, and nothing else:

1. **PR celebration** — *"keep the sound effect, implement the new screen. I don't think what's live is what
   we designed."*
2. **Rack counts per gym** — *"make an informed decision that makes sense."*
3. **An accepted warm-up scale-down surviving a relaunch** — *"Yes."*

Decision 1 is a small design round inside this plan: two catalog-only compositions of the celebration on the
design language, the owner picks one, and the production overlay is rebuilt to the pick. It also carries the
logic the owner may mean by *"not what we designed"* — docket row 7's PR-firing rule, which is **not
implemented on master** — and the rescued sound, returned as a bundled resource. Decision 2 is the
controller's binding ruling, below. Decision 3 is one nullable column and one extraction.

**Architecture.** Four moves, in this order of dependence:

1. **The PR fires on the right event, or it celebrates nothing.** Docket row 7 (`2026-09-03-field-report
   -docket.md:10`, P1) asks for two rules: *the first-ever log of an exercise is a baseline, not a PR*, and
   *the PR fires only after all sets of that exercise are complete*. Verified against master: **neither is
   implemented, in either body.** `SessionLiveView.logSetAndAdvance` (`:4516-4536`) sets
   `isPR = weight > prior` where `prior` is `priorMax(...)`'s **zero** when the lifter has no history, so the
   first set of a lift a lifter has never logged always celebrates; and the check runs on every set. The solo
   twin (`WorkoutSessionView.swift:3816-3838`) goes through `PersonalRecordMath.isPR(weight:reps:basis:)` and
   has the same two properties (`bestWeight` returns `0` for an empty basis; `isPR` is called per set). The
   rule becomes pure code in `PersonalRecordMath`, tested, and both call sites adopt it.
2. **The celebration is redesigned on the design language, and the owner picks the composition.** What is
   live is canvas frame 29 lifted verbatim in July (`2026-07-16-pr-takeover-design.md`), with **one** design
   rule applied since — rule 8's headline-first order, by the design-congruence plan's T6.1
   (`2026-09-06-design-congruence-plan.md:1036`). Everything else on the screen predates
   `2026-09-05-design-language.md`. Two catalog-only variations differ in **composition**, the production
   rebuild follows the pick, and the two variation ids retire with it.
3. **The sound comes back as one bundled file.** `lightweight-baby.mp3` (60,857 bytes), rescued from the
   public bucket, becomes an app resource; a ~40-line `CelebrationSound` plays it at the two call sites
   `SoundboardPlayer` used to own — `SessionLiveView.showPROverlay` (`:4918-4922`) and
   `WorkoutSessionView.showPROverlay` (`:4151-4155`), both of which today carry a comment saying the sound
   left and nothing else.
4. **Two nullable columns and an extraction.** `venues.rack_counts` + one RPC give the station split a real
   cap; `sessions.venue_id` tells a session which building it is in; `session_participants.todays_scale`
   makes an accepted warm-up scale-down survive a relaunch. All three are additive, all three need **no new
   policy**, and the layering the third one feeds is extracted from its three hand-copies while here.

**Tech stack.** Swift 6 / SwiftUI (iOS 17 target), Supabase Postgres + PostgREST + RLS, pgTAP, XCTest +
XCUITest, Deno (edge functions), GitHub Actions (`ios.yml`, `backend.yml`), XcodeGen (`GymSyncApp/project.yml`
— `sources:` is a directory glob, but **`resources:` is an explicit list** and the bundled sound needs an
entry there; see S2).

**Spec (the authority).** `docs/superpowers/specs/2026-09-05-design-language.md` — §1 (surfaces), §2
(colour), §3 (type), §8 (celebration and milestones: *"the headline first, big, in accent ('New personal
record.'), a line sweeps under it, then the lift and the number land with the ring. No kudos row on the
splash."*), §9 (copy). Secondary: `2026-07-16-pr-takeover-design.md` (what the overlay was built to),
`2026-06-28-gymsync-design.md:1086` (*"…PR celebration audio must mix with — never interrupt, pause, or duck
— the user's music. Non-negotiable."*) and `2026-09-12-group-session-and-lobby-design.md` §3.1 / §3.4 (the
lobby's cards; the quiet scale-down). Round artefacts, **all of whose file:line references were re-verified
against `origin/master` `67f3f15` on 2026-09-18**: the docket (`2026-09-03-field-report-docket.md`, row 7 at
`:10`, the "Phase B2 closed" entry's leftovers), the Phase B2 plan
(`docs/superpowers/plans/2026-09-18-group-session-phase-b2-plan.md` — the shape this plan copies and the
source of Global Constraints 1-21), and the planner brief
(`.superpowers/sdd/2026-09-18-owner-decisions-round/brief-plan.md`) with today's live render
(`pr-celebration-live-2026-09-18.png`) and the sound file beside it.

---

## Base branch — read this first

**This plan forks from `origin/master` at `67f3f15`** (PR #74, the Phase B2 close docket), which is Phase
B2's merge (`6f73b26`, PR #73) plus one docs PR. Verified on 2026-09-18 against `origin/master`, never a
local `master` ref:

```
git fetch origin
git log origin/master --oneline -1                                          # 67f3f15
grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1                        # FLOOR=131  (line 453)
python -c "import json;d=json.load(open('docs/design/frame-map.json'));print(len(d), max(v['frame'] for v in d.values()))"
                                                                            # 88 150
grep -c '^    case ' GymSyncApp/GymSync/App/CatalogHostView.swift           # 109
grep -c 'captureCatalog(' GymSyncApp/GymSyncUITests/ScreenshotTests.swift   # 109  (real: 107 — see below)
ls GymSyncApp/GymSync/Features/Sessions/Variations/                         # absent (B2 S10)
```

| | Stream D and Stream S, from `67f3f15` |
|---|---|
| base | `origin/master` `67f3f15` |
| `FLOOR` in `ios.yml:453` | **131** |
| frames taken | 1-150, **zero duplicates** (B2 renumbered 41/69/70 to 147-150) |
| next free frames | **151, 152** — a retired number is never reused, so the gaps below 150 stay gaps |
| `CatalogScreen` cases | 109 |
| `CatalogScreenTests` ids | 109 (set-equal to `allCases`) |
| **real `captureCatalog("…")` calls** | **107** — `grep -c 'captureCatalog('` prints 109 because it also counts the function's own definition and one comment. Master's own two uncaptured ids (`calendar-scheduling`, `ladder-on-track`) are not this plan's. |
| `pr-celebration` | id **and** capture exist (`CatalogHostView.swift:17`, `:194`, `:323-333`; `ScreenshotTests.swift:516`; `CatalogScreenTests.swift:11`), frame **29** in `frame-map.json` |
| `PRCelebrationOverlay.swift` | 215 lines, two consumers (`SessionLiveView.swift:1953`, `WorkoutSessionView.swift:611`) plus the catalog arm |
| `venues.equipment text[]` | present (`20260814000010`), default `{barbell,dumbbell,machine,cable,bodyweight}` |
| `venues.rack_counts` | **does not exist** |
| `sessions.venue_id` | **does not exist** |
| `session_participants.todays_scale` | **does not exist** |
| `venue_checkins` (venue_id, user_id, created_at) | present (`20260729000002:79-84`), RLS-enabled with **no policies** — service/DEFINER reads only |
| `check_in_to_venue(uuid, double, double)` | present — the app's only **server-verified** geofence |
| `StationSplit.count(crew:equipmentCap:)` | present (`SessionStations.swift:65`), called once with `equipmentCap: nil` (`SessionLiveView.swift:4437`) |
| `TodaysScale(exerciseID:setsInstead:)` | present (`WarmUpReadiness.swift:165-171`), in memory on `SessionRunnerView.swift:79` |
| `AudioSessionManager.ensureMixablePlayback()` | present (`:101-106`), **callerless since B1 S11**, kept on purpose for a returning overlay sound |
| held on the data worktree | B2 D1/D2 (`crew_week`, `30c9406`), B2 D4/D5 (the `routine_proposals` drop), B1 D5/D6 (the soundboard drop, `066d8bf`/`74fbbe9`). **NOT this plan's**; do not touch them, do not re-write them. They claim pgTAP fixture blocks **13xx** and **14xx**. |

---

## Global Constraints

These bind **every** task. A task that breaks one says so in its commit body, and why. Constraints 1-21 are
Phase B2's, carried forward verbatim where they are still true, with the changes marked **[C]**.

1. **One release branch, `feat/owner-decisions-2026-09-18`, and this plan is its first commit.** Fork it from
   `origin/master` (verified above), commit this file, push. Every task below lands on that branch. One PR
   at the end (I3).

2. **Two streams, and only because their files are disjoint by path.**
   - **Stream D** touches `supabase/**` and `scripts/**` and nothing else.
   - **Stream S** touches `GymSyncApp/**`, `docs/design/**` and `.github/workflows/ios.yml` and nothing else.

   **[C] S1-S4 run sequentially, in number order** — they all touch the celebration path, and S4 cannot be
   written before the owner has picked. **S5-S8 also run in number order**: S5, S6 and S7 all edit
   `SessionLiveView.swift` (4,900+ lines) and two workers on one file is the gamble this rule exists to
   forbid. Stream D may run beside Stream S throughout, subject to constraint 8's gates. **At most two Opus
   agents at once** (one per stream); dispatch the long pole first.

3. **Swift compiles only in CI.** No macOS toolchain on this machine: no `xcodebuild`, no `swift build`, no
   simulator. Read the code you are changing in full, reason about the types, push.
   `.github/workflows/ios.yml` is the compiler.

4. **Implementers do not wait on CI.** Push and hand the task back with a **written report file**
   (`<workspace>/<stream>-pushN.md`, ≤ 25 lines returned). **The controller monitors the run** (one event per
   run) and opens a fix task if it is red. Fix rounds **resume the same implementer**; a fresh agent only
   after round 3 or a model escalation. Implementers are **retired at push points after ≥ 4 tasks**.

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
   all leave in one commit. **A retired frame number is never reused.** B2's `2faa3ba` shipped a
   non-compiling intermediate by splitting exactly this; do not repeat it.

7. **The FLOOR is `±N over master's FLOOR at integration`, never a literal.** **[C]** This plan's N is
   **0** — two variation captures in at S3, the same two out at S4, and `pr-celebration` keeps its existing
   capture through the rebuild. **The contingency is stated, not assumed:** if the owner's pick has not
   arrived when Stream S reaches integration, S4 does not run, the two variation ids stay live, N is **+2**,
   and the retirement becomes its own follow-up PR. I1 re-derives the literal on the day.

8. **Migrations are gates.** `.github/workflows/backend.yml:24-27` runs `node scripts/run_pgtap.js` against
   the **live** `SUPABASE_DB_URL`; there is no `supabase db push` anywhere in CI. A pgTAP test for an object
   that has not been applied to project `chjkkwqwdlmaxacwglzm` **will fail**. So each migration task ends:
   **commit, stop, hand back.** The controller applies it live (Supabase MCP `apply_migration`), says
   "applied", and only then does the matching pgTAP task — and any Swift task that reads the new column —
   start. Each commit body records the timestamp it was applied. **[C] The Supabase connector is authorized
   again** (brief, 2026-09-18), so Stream D runs rather than stalls. **The held migrations are not this
   plan's**: B2 D1/D2, B2 D4/D5 and B1 D5/D6 ship as their own data PR, and nothing here waits on them.

9. **THE IRREVERSIBLE GATE.** **[C] this plan has no irreversible change.** All three migrations are
   **additive nullable columns and one new function**; nothing is dropped, nothing is narrowed, and every
   one of them is reversible by a later `DROP COLUMN`. The **one-way step in this plan is the owner's pick**
   (S3 → S4), and it is gated the same way a migration is: the controller renders the two variations, sends
   the proof card, and **S4 does not start until the pick is recorded in the ledger**, by name, with the
   reason the owner gave. A rebuild begun on a guess is the failure this gate exists to prevent.

10. **Never request HealthKit or LOCATION authorization outside their one permitted call site, and never
    from a test.** A raised sheet hung `build-test` for 45 minutes once. The permitted sites are
    `LobbyView.initiateCheckIn()`, `SessionRunnerView`'s check-in control and `CheckInService`. **[C] S6 is
    the task this constraint is aimed at**: the venue link is written **after** the existing check-in
    succeeds, from data the server already holds — it adds **no** location read, no new `CLLocationManager`,
    and no new call to `CheckInService.requestLocation()`.

11. **No live repository, and no `Date.now`, reachable from a catalog builder.** Every `content_*` renders
    from fixture integers, strings and dates built from components. **[C] the two variation arms and the
    rebuilt `pr-celebration` arm are value-in views** — `PRCelebrationOverlay` takes six values and a
    closure and reads no repository today; keep it that way. **`CelebrationSound` must not be reachable from
    a catalog builder either**: the overlay does not play the sound, its two *callers* do (S2), so a catalog
    capture stays silent by construction. S3's variations are pure views over literals.

12. **Every report claim is verified against `git show <sha> --stat` and the CI artifact, not memory — and
    grep the CALL SITE of every new function before claiming it is live.** Download artifacts **into a fresh
    directory**. A definition is not a feature: `git grep -n "<symbol>("` must show a caller outside the
    symbol's own file and its tests. **[C] the cautionary case for this plan is
    `AudioSessionManager.ensureMixablePlayback()`** — written, documented, tested, and callerless for a
    whole phase. S2 gives it a caller; the report proves it.

13. **Design rules, by number** (`2026-09-05-design-language.md`):
    - **1** — two raised surfaces only: `.gs3DCard` to read, `.gs3DCardStyle`/`.gs3D` to press; furniture
      inside a raised box stays flat; strips are `surface` at 14 pt. **Never `theme.surface` or `theme.bg`
      as a face.** The two radii are `GSMetrics.radiusMd` (24, cards) and `GSMetrics.radiusSm` (16, tiles),
      lips 6-7 pt on cards and 4-5 on tiles.
    - **2** — **accent is spent once per screen.** The PR splash's accent is the headline and `KEEP LIFTING`
      — which is already two spends on a single page, and the variations must resolve that rather than
      inherit it. `Color.gsSuccess` (`GSAccent.swift:77`) means done/present; **gold is streak and check-in
      ONLY** and has no job on this screen; red is errors.
    - **3** — kickers 10-11 pt caps, 0.1-0.13 em tracking, muted; numbers tabular (`.monospacedDigit()`);
      the hero number is the largest thing on its page with one small unit beside it.
    - **8** — the PR splash's own rule, quoted in full under "Spec" above. **No kudos row.**
    - **9** — sentence case for sentences, caps for kickers; a button says exactly what happens. **No
      decorative emoji; SF Symbols for glyphs** — which the live `▲` at `PRCelebrationOverlay.swift:122-123`
      is not.

14. **The frozen frames must not move.** **[C]** Phase A's seven production frames (129-135), Phase B1's six
    (136-141), Phase B2's five (142-146) and the two Home canaries (81, 82) are owner-approved compositions.
    **No task in this plan may change what any of the twenty renders.** "Unchanged" means 0 % of pixels
    differ below the status bar and above the home-indicator band. **Frame 29 (`pr-celebration`) is the one
    frame this plan deliberately changes**, and only at S4, after the owner has picked.

15. **Do not rename an existing `CatalogScreen` raw value, and do not reuse a retired one.** **[C]** The two
    new ids are `pr-celebration-a` and `pr-celebration-b`, and they are **retired at S4** — `pr-celebration`
    itself is never renamed and never retired, because the production screen it photographs still ships.

16. **Live-DB tests use the `TestSession` teardown factory and far-future rows.**
    `GymSyncTests/TestSession.swift` is the only place a test may create a session; register cleanup with
    `addTeardownBlock` **before** the write. Every date a live-DB test controls is **2099**.

17. **pgTAP conventions.** `BEGIN;` → `CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;` →
    `SELECT plan(N);` → a comment naming the migration under test and declaring the fixture block →
    `auth.users` inserted before `profiles` → role switching with `SET LOCAL role authenticated;
    SET LOCAL request.jwt.claim.sub = '<uuid>';` → **reset the role and claim before inserting the next
    fixture block** → `SELECT * FROM finish(); ROLLBACK;`. **An emptied suite is deleted, never left at
    `plan(0)`** (R-B2-10: pgTAP aborts the whole run with "No tests run!").
    **Fixture-block namespaces already taken** inside `00000000-0000-4000-?000-00000000??xx`: `01xx`-`12xx`
    on master, **`13xx` and `14xx` claimed by the held B2 data branch**.
    **[C] This plan takes `15xx` (D2) and `16xx` (D4)**, so a later merge of the held branch cannot collide.

18. **`XCTUnwrap(await …)` does not compile — bind, then unwrap.**

19. **The UI-test target's compile risk, named.** `GymSyncUITests` is built by the **screenshots** job
    (`ios.yml:326-329`), which runs **after** the seed step — `build-test` does **not** build it. So a task
    that edits `ScreenshotTests.swift` (S3, S4, S8) is not proven by a green `build-test`: **its proof is a
    green screenshots job**, and the controller re-runs the job rather than assuming.

20. **Do not change the shipped session-engine contracts.** `start_session`, `advance_turn`, `advance_round`,
    `set_session_stations`, `mark_warmup_ready`, `start_lifting`, `evaluate_lateness`, `mark_no_shows`,
    `check_in_to_venue`, the `check_in_state` CHECK, the five-state `sessions.state` CHECK and
    `session_participants`' four policies are frozen. **[C] this plan adds three nullable columns and one
    RPC; it changes no shipped contract and drops nothing.**

21. **[C] The audio session belongs to the whole app, and this plan does not touch it.** The AUDIO SACRED
    RULE (`ChatView.swift:9`, `VoiceBubblePlayer`): a player **never** sets the `AVAudioSession` category.
    `CelebrationSound` calls `AudioSessionManager.shared.ensureMixablePlayback()` and then plays. It must not
    call `configure()`, `setCategory`, `setActive`, `enterVoiceMode` or `exitVoiceMode`, and it must not
    play while `AudioSessionManager.shared.isInVoiceMode` — see data decision 4.

---

## File structure

### Created

| File | Responsibility | Task |
|---|---|---|
| `supabase/migrations/20260918000201_venue_rack_counts.sql` | `venues.rack_counts jsonb NOT NULL DEFAULT '{}'`, `rack_counts_updated_by/at`, and `public.set_venue_rack_count(uuid, text, int)` — SECURITY DEFINER, gated on a venue check-in inside 12 hours | D1 |
| `supabase/tests/venue_rack_counts_test.sql` | pgTAP: the gate, the class whitelist, the clamp, last-write-wins, the stranger's raise | D2 |
| `supabase/migrations/20260918000202_session_venue_and_todays_scale.sql` | `sessions.venue_id uuid NULL REFERENCES venues(id)`, `session_participants.todays_scale jsonb NULL` — both additive, **no new policy** | D3 |
| `supabase/tests/session_venue_todays_scale_test.sql` | pgTAP: the columns, the FK, the own-row write, the other-row rejection, both BEFORE UPDATE triggers passing the write through | D4 |
| `GymSyncApp/GymSync/Models/PRFiring.swift` | `PRFiring.shouldCelebrate(...)` — docket row 7's two rules, pure | S1 |
| `GymSyncApp/GymSyncTests/PRFiringTests.swift` | the baseline case, the mid-exercise case, the complete case, the rep-PR twin | S1 |
| `GymSyncApp/GymSync/Services/CelebrationSound.swift` | `CelebrationSound.playPR()` — one `AVAudioPlayer`, no category write | S2 |
| `GymSyncApp/GymSync/Resources/Sounds/lightweight-baby.mp3` | the bundled resource (60,857 bytes, from the brief folder) | S2 |
| `GymSyncApp/GymSyncTests/CelebrationSoundTests.swift` | the bundle lookup resolves; the player is nil-safe when it does not | S2 |
| `GymSyncApp/GymSync/Features/Sessions/PRCelebrationVariations.swift` | `#if DEBUG` — `PRCelebrationVariationA` / `…B` and their shared fixture | S3 (deleted S4) |
| `GymSyncApp/GymSync/Models/VenueRackRepository.swift` | `VenueRackRepository.counts(venueID:)` and `.set(venueID:equipmentClass:count:)` | S6 |
| `GymSyncApp/GymSync/Models/RoutineLayering.swift` | `RoutineLayering.apply(_:squadSwaps:selfScale:todaysScale:)` — the one layering | S7 |
| `GymSyncApp/GymSyncTests/RoutineLayeringTests.swift` | the three layers and their order, once | S7 |

### Modified

| File | Change | Task |
|---|---|---|
| `GymSyncApp/GymSync/Models/PersonalRecordMath.swift` | `isPR` gains the empty-basis guard; the doc records docket row 7 | S1 |
| `GymSyncApp/GymSync/Features/Sessions/Live/SessionLiveView.swift` | S1 routes the PR check through `PRFiring`; S2 calls `CelebrationSound.playPR()` at `:4918`; S6 passes the cap at `:4437`; S7 replaces `effectiveRoutineExercises`' body (`:621-637`) with `RoutineLayering.apply` | S1, S2, S6, S7 |
| `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift` | S1 routes the solo PR check the same way (`:3816-3838`); S2 calls `CelebrationSound.playPR()` at `:4151` | S1, S2 |
| `GymSyncApp/GymSync/Features/Sessions/PRCelebrationOverlay.swift` | rebuilt to the picked composition; the stale "behavior-preserving extraction" header (docket `:320`) goes with it | S4 |
| `GymSyncApp/project.yml` | one entry under the `GymSync` target's `resources:` list (`:95-96`) | S2 |
| `GymSyncApp/GymSync/App/CatalogHostView.swift` | two ids in (S3), two out and `content_prCelebration` re-pointed at the rebuilt overlay (S4) | S3, S4 |
| `GymSyncApp/GymSyncTests/CatalogScreenTests.swift` | two ids in, two out | S3, S4 |
| `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` | two capture methods in, two out; **[S8]** the first catalog test's launch retried once | S3, S4, S8 |
| `docs/design/frame-map.json` | 151, 152 in (S3); both out (S4); frame 29's note records the rebuild | S3, S4, I1 |
| `GymSyncApp/GymSync/Models/SessionRepository.swift` | `checkIn` gains the best-effort venue claim | S5 |
| `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift` | the style card's one stepper line (`styleCard`, `:1227-1248`) | S6 |
| `GymSyncApp/GymSync/Features/Sessions/Live/RoundPieces.swift` | the station card's header gains the edit affordance | S6 |
| `GymSyncApp/GymSync/Features/Sessions/SessionRunnerView.swift` | `todaysScale` (`:79`) is seeded from and written to the participant row; `planRows` (`:249-256`) reads `RoutineLayering` | S7 |
| `GymSyncApp/GymSyncTests/WarmUpReadinessTests.swift` | the hand-copied layering at `:151-155` becomes a `RoutineLayering.apply` call | S7 |
| `GymSyncApp/GymSync/Features/Sessions/WarmUpFixtures.swift` | `suggestionForCrew.exerciseID` (`:176`) corrected | S8 |
| `GymSyncApp/GymSync/Features/Social/PumpFeedView.swift` | the literal radius 14 (`:453`) becomes `GSMetrics.radiusSm` | S8 |
| `.github/workflows/ios.yml` | the FLOOR, once | I1, and only I1 |
| `docs/design/accepted-deviations.json` | entries appended (55 today) | I1 |

### Deleted

| File / symbol | Why |
|---|---|
| `GymSyncApp/GymSync/Features/Sessions/PRCelebrationVariations.swift` and both ids | The design round ends when the owner picks; the production frame is the proof (S4). Same discipline that emptied `Variations/` in B2. |
| The three hand-copies of the `TodaysScale` layering (`SessionLiveView.swift:631-633`, `SessionRunnerView.swift:251-253`, `WarmUpReadinessTests.swift:152-155`) | Docket, B2 leftovers: *"`TodaysScale` layering is hand-copied in three places incl. its test (extract one `RoutineLayering.apply`)"*. |

**Not deleted, deliberately:** the held migrations on `feat/group-session-phase-b-data` and
`feat/group-session-phase-b2-data` (their own PR, constraint 8); `WorkoutSessionView.swift` (the ad-hoc path
— Phase C); `AudioSessionManager.ensureMixablePlayback()` (S2 gives it its caller back);
`PersonalRecordMath.oneRepMax` (a different subject, untouched by S1); the `ShareLink` on the celebration —
§8 forbids a **kudos row**, not sharing, and the owner has never asked for Share to go.

---

## The four decisions, stated

### 1. Rack counts live on the venue, and the people standing in it maintain them

R-B3 (docket, twice) asked the owner *"who maintains rack counts — the venue's owner profile, the crew, or a
one-time picker at scheduling?"*. The owner answered *"make an informed decision that makes sense."* Here it
is, and it is binding for this plan.

**The number belongs to the building, not to a session.** `venues.rack_counts jsonb NOT NULL DEFAULT '{}'`,
keyed by the equipment classes `venues.equipment` already lists (`Venue.equipmentClasses` =
`["barbell","dumbbell","machine","cable","bodyweight"]`, `Models/Venue.swift:35`), e.g.
`{"barbell": 3, "bench": 2}` → in this app's vocabulary `{"barbell": 3, "machine": 2}`. A venue that hosts
four squat racks hosts them for every crew that trains there, on every day.

**Any lifter checked in there may set or correct it.** `public.set_venue_rack_count(p_venue_id uuid,
p_equipment_class text, p_count int)`, SECURITY DEFINER, gated on a row in `venue_checkins` for
`auth.uid()` at `p_venue_id` within the last **12 hours**. Last write wins; `rack_counts_updated_by` and
`rack_counts_updated_at` record who and when, so a wrong number has an author.

**Why not the three alternatives the docket named.**

* *The venue owner's profile.* A creator role does exist — `venues.created_by` with a creator-edit policy
  for unverified venues, and `relinquish_venue` hands it to the community
  (`20260814000002_venue_owner_controls.sql`). **But it is nullable by design**: a community-owned hub has
  no owner at all, and the owner of a hub is not necessarily ever in the building. A rack count maintained
  by an absent creator decays silently, and a community hub could never get one.
* *A one-time picker at scheduling.* It asks the one person who is **not at the gym yet**, about a room they
  will walk into in four hours, and writes the answer onto a single session so the next crew starts from
  zero.
* *The crew, per session.* Same number, re-asked every session, by people who have no way to know whether
  the answer they give is the one the last crew gave.

**The gate is `venue_checkins`, not `venue_users`, on purpose.** `venue_users` records membership — a lifter
who joined a hub in March is still a member today. `venue_checkins` records a **server-verified geofenced
presence** (`check_in_to_venue` is the app's only server-side geofence, and its own header says so), which
is exactly the claim "I can see the racks from here". The table is RLS-enabled with **no policies at all**,
so only a SECURITY DEFINER function can read it — which is why the gate must live inside the RPC.

**The write is validated, not trusted.** `p_equipment_class` must be one of the five classes (a hard
whitelist in the function, matching `Venue.equipmentClasses`); `p_count` is clamped to `1...99`; a count of
0 is rejected rather than stored, because "no racks here" is `venues.equipment` not listing the class, and
an unknown count is the key being **absent**, never zero. `jsonb_set` on a single key, so two lifters
correcting two different classes cannot clobber each other.

**Where it is asked: once, quietly, in the lobby's style card.** `LobbyView.styleCard` (`:1227-1248`) draws
the three style rows before Start. When the style is `.rounds` **and** the session's venue is known **and**
that venue has no count for the first exercise's equipment class, one stepper line appears under the rows —
`How many racks here?  −  2  +` — with a SKIP affordance, matching design rule §4's *"Questions come as one
block with a SKIP in its header"*. It **never blocks Start**, it never appears twice, and it is editable
later from the station card's header (`RoundPieces.swift`, `StationCard`). No new screen, no new sheet.

**The cap.** `StationSplit.count(crew:equipmentCap:)` (`SessionStations.swift:65`) already implements
`max(1, min(ceil(crew / 3), equipmentCap ?? .max))` and is called once with `equipmentCap: nil`
(`SessionLiveView.swift:4437`). S6 passes the venue's count for the **current exercise's** equipment class
and `nil` when unknown. The re-mix at exercise changes (`.task(id: currentRoutineExercise?.position)`)
re-reads it, so a barbell block and a dumbbell block can split differently in the same session.

**The exercise-to-class mapping needs a normalizer, and the plan says so rather than assuming one.**
`exercises.equipment` carries values outside the five venue classes — `ez-bar` and `smith` at least
(`Units.swift:161-170`, `ProgramGenerator.swift:1730`). S6 adds `Venue.equipmentClass(for:)` mapping
`ez-bar`/`smith` → `barbell` and anything unrecognised → `nil` (which means "unknown", which means no cap).
Tested against the five classes and the two aliases.

### 2. The session's venue comes from the **venue** check-in, not the session check-in — the brief's premise is corrected

The brief said `sessions.venue_id` is *"set by the first check-in's matched gym (`CheckInService.primaryGym()`
/ the geofence match) through the existing check-in write path"*. **Read against master, that path cannot
produce a venue id.**

* `CheckInService.primaryGym()` (`CheckInService.swift:35-51`) reads the **`gyms`** table — a private,
  per-user geofence row (`user_id`, `latitude`, `longitude`, `radius_meters`, `is_primary`;
  `20260709000004_create_gyms.sql`). A `gyms.id` is **not** a `venues.id`; there is no column, join or
  function anywhere in the repo that relates the two.
* `SessionRepository.checkIn(sessionID:method:)` (`SessionRepository.swift:598-616`) writes **only**
  `check_in_state`, `check_in_at` and `check_in_method` on `session_participants`. It never touches
  `sessions` and never names a venue.
* The venue flow is separate and already correct: `VenueRepository.checkIn(venueID:coordinate:)`
  (`Venue.swift:366`) → `check_in_to_venue` → a `venue_checkins` row, driven from the venue hub screen
  (`VenueHubViews.swift:768`).

**Ruling:** `sessions.venue_id` is claimed from the **caller's most recent `venue_checkins` row within the
last 12 hours**, written best-effort **after** the existing session check-in succeeds, and **only while
`venue_id IS NULL`** — first check-in wins, exactly the property the owner's phrasing asked for.

**No new policy, and no new RPC for the write.** `sessions`' UPDATE policy is *"organizer or participant can
update session"* (`20260709000006_create_sessions.sql:61-67`) — a participant may already write the row —
and `private.session_round_guard` (B1 D3) guards only the three engine columns, so `venue_id` passes. The
client writes it with a `.is("venue_id", value: nil)` predicate, which makes first-write-wins a **database**
property rather than a client race. **The read of `venue_checkins` does need DEFINER** (no policies on that
table), so the claim goes through one small function, `public.claim_session_venue(p_session_id uuid)`,
shipped in D1 beside the rack RPC because it shares the same 12-hour presence rule.

**Accepted consequence, stated:** a crew that never checks into a venue hub has `venue_id IS NULL`, no cap,
and `ceil(n/3)` stations — exactly today's behaviour. The feature degrades to the shipped default rather
than guessing a building from a private geofence row that means something else.

### 3. `todays_scale` is one nullable column and needs no policy, and the triggers were checked

`session_participants.todays_scale jsonb NULL`, shaped `{"exercise_id": "<uuid>", "sets_instead": <int>}`.

**Phase A's energy-column reasoning applies verbatim** and the migration header says so in its own voice:
*"participant updates own check-in"* (`20260712000001:22-25`) is `USING (user_id = auth.uid()) WITH CHECK
(user_id = auth.uid())` **with no column list**, so a lifter can already write their own row; *"participants
readable by other participants"* is row-level, so the crew can already read it. A third policy would be
permissive-ORed with those and would grant nothing while looking like it granted something.

**Both BEFORE UPDATE triggers were read, not assumed:**

* `engine_guard` (`20260714000001:45-70`) raises only when `late_minutes`, `burpees_owed` or `turn_order`
  change. A `todays_scale` write changes none of them. **Passes.**
* `checkin_window_guard` (`20260715000003:13-46`) returns early when `NEW.check_in_state IS DISTINCT FROM
  'ready'` — which is **not** an early return for our write, because the row is already `'ready'` by warm-up
  time and `NEW.check_in_state` is still `'ready'` on an UPDATE that does not touch it. It then compares
  `now() < scheduled_for - interval '20 minutes'`. A warm-up Accept happens **after** check-in opened, so
  the comparison is false and the trigger returns `NEW`. **Passes.** (Identical to what `energy` already
  does in production; D4 pins it with an assertion so a future guard change cannot break it silently.)

**Read with the rows the runner already loads.** `SessionRunnerView` fetches the participant rows for the
warmth track; `todays_scale` rides along, so a relaunch mid-session re-seeds `todaysScale` (`:79`) with no
extra round trip. **Written on Accept** (`SessionRunnerView.swift:384-385`), best-effort: a failed write
leaves the in-memory value in place and the session behaves exactly as B2 shipped it. **Cleared by nothing**
— the session ends and the row stops being read.

**The layering is extracted while here** (docket, B2 leftovers). `RoutineLayering.apply(_:squadSwaps:
selfScale:todaysScale:)` holds the three-layer order **unchanged**: squad swaps first (everyone), then my
quiet self-scale (my own choice for my body beats the squad's), then today's accepted set reduction last,
keyed on the routine's own exercise. `SessionLiveView.effectiveRoutineExercises` (`:621-637`),
`SessionRunnerView.planRows` (`:249-256`) and `WarmUpReadinessTests` (`:151-155`) all call it, and
`RoutineLayeringTests` is the one place the order is asserted.

**Crew visibility is unchanged.** The crew still does not see a Coach-suggested set reduction — S7 persists
a value B2 already displayed only to its owner, and adds no surface. Recorded under "does not decide".

### 4. The sound plays through `.playback`, not `.ambient` — the brief's second premise is corrected

The brief asked for `AVAudioPlayer` with **`.ambient` + `.mixWithOthers`**, citing spec 2026-06-28
§*"must mix with… never interrupt"*. The spec does say `.ambient` (`2026-06-28-gymsync-design.md:1096-1111`).
**The owner overruled that on 2026-08-14 and the code records it**, in `AudioSessionManager.configure()`
(`:24-35`):

> *".playback, NOT .ambient (owner 2026-08-14 …): 'it should not go silent when the phone is silenced —
> Spotify plays through silent mode'. .ambient obeys the ringer switch by definition; .playback ignores it.
> .mixWithOthers keeps the sacred half of the old behavior — we layer OVER the lifter's music, never
> replace it."*

**Ruling:** `CelebrationSound` sets **no category at all** — the AUDIO SACRED RULE (`ChatView.swift:9`,
`VoiceBubblePlayer`: *"NEVER touches AVAudioSession category"*). It calls
`AudioSessionManager.shared.ensureMixablePlayback()` (`:101-106`), which restores the documented
`.playback + .mixWithOthers` baseline **only when `mixWithOthers` is missing** and **never while a voice room
holds the session** — the helper written for field report #39 (*"the PR sound pauses Spotify"*) and left
callerless since B1's S11 precisely *"because the invariant it restores belongs to the whole app's audio
session … and a future overlay sound (or a returning one) would need it again."* This is that sound.

**And it does not play during push-to-talk.** `CelebrationSound.playPR()` returns immediately when
`AudioSessionManager.shared.isInVoiceMode` is true — a crewmate mid-sentence is not interrupted by someone
else's PR. Recorded as this plan's one deliberate departure from spec 2026-06-28's literal text, and as a
correction to the brief.

---

## New catalog ids, the retirement, and the FLOOR

### In — two design-round ids, frames 151-152 (S3)

| id | frame | title | what it argues |
|---|---|---|---|
| `pr-celebration-a` | 151 | The number leads | The record itself is the hero: the tabular number at maximum size with one small unit beside it (rule 3), `New personal record.` as a **kicker** above it rather than a 34 pt accent headline, the lift and `▲ 5 LBS OVER YOUR BEST` folded into one sentence under it as a `surface` strip, the monthly count as a `gsSuccess` tick on that strip rather than a bordered `theme.surface` chip. **Accent is spent once, on `KEEP LIFTING`.** Share is a quiet raised face beneath it. |
| `pr-celebration-b` | 152 | The lift's place on your ladder leads | The record is read as **progress**, not as a number: a `.gs3DCard(radiusMd, lip 6)` island carrying the lift's name, the new number and the old one beside it as a before/after pair, and — where the rings are today — the athlete's block-ladder rung worded from the values the caller already holds. `nth PR this month` becomes the card's kicker. Share sits **in the card's header** as a small glyph door, so the page's foot is one button. **Accent is spent once, on the new number.** |

**What both must fix, and what both must keep.** Both are built from shipped primitives (`GSFont`,
`GSMetrics.radiusMd`/`radiusSm`, `.gs3DCard`, `.gs3DCardStyle`, `GSSectionHeader`, `GSTag`, `Color.gsSuccess`)
and both must: spend accent **once** (today's screen spends it on the headline, the sweep capsule, two rings,
the delta line and the CTA); replace the `▲` text glyph with an SF Symbol (rule 9); stop using
`theme.surface` as a raised face (rule 1 — today's trophy chip does, at `:141-143`, with a third radius of
12); use only `radiusMd`/`radiusSm` (today's CTAs hardcode 16); and keep **all six facts** the live screen
carries — the headline, the number and unit, the lift × reps, the delta over your best, the monthly count
and both actions — plus the **rep-PR form** (`weight == 0` → reps are the headline, `priorBest` carries prior
reps; `:88-109`, `:121-123`). **No kudos row** (rule 8). `PRCelebrationOverlay`'s six-value initializer is
the input to both, unchanged, so the pick can be rebuilt without touching either call site.

Both arms are `#if DEBUG` value-in views over one shared literal fixture in
`PRCelebrationVariations.swift` — no `Date()`, no repository, no `.shared` (constraint 11).

### THE OWNER-PICK GATE

**S4 does not start until the owner has picked.** After S3 is green, the controller downloads
`app-pr-celebration-a.png` and `app-pr-celebration-b.png` into a fresh directory, composes **one** proof card
carrying both beside today's live capture (`app-pr-celebration.png`), and sends it. The pick — **A or B, by
name, with the owner's own reason** — is written to the ledger before S4 is dispatched. If the owner asks for
a third composition, that is a new S3b on this branch and the gate re-opens; if the owner picks neither and
asks to keep what ships, S4 becomes "retire the two ids" alone and the FLOOR returns to 0 anyway.

### Out — the same two ids, at S4

| id | frame | replaced by |
|---|---|---|
| `pr-celebration-a` | 151 | `pr-celebration` (frame 29), rebuilt |
| `pr-celebration-b` | 152 | `pr-celebration` (frame 29), rebuilt |

Frames 151 and 152 are retired numbers and are never reused. `PRCelebrationVariations.swift` goes with them.

### Frame-map only — frame 29's note

`pr-celebration` keeps its id, its case, its capture and its number. Its `frame-map.json` note records that
the composition was rebuilt on 2026-09-18 to the owner's pick, naming the variation it came from — so the
deck's oldest surviving canvas frame stops claiming to be a July lift.

### The FLOOR

**`FLOOR` moves by `0` against master's FLOOR at integration** — two captures in at S3, the same two out at
S4. Against the verified base (`131`), that is `131 → 131`, and I1 still re-derives the literal on the day
by counting the exported files in the last green `app-screenshots` artifact. **The contingency**
(constraint 7): no pick by integration → S4 does not run → N is **+2** → `131 → 133`, the two variation ids
ship live, and the retirement is a follow-up PR. I1 writes whichever happened, with the reason.

**Counts after S4 (the picked path):** `CatalogScreen` = **109** cases, `CatalogScreenTests` ids = **109**,
real `captureCatalog("…")` calls = **107**, `frame-map.json` = **88** entries, max frame **152** (151/152
retired, so the maximum *live* frame is 150), **zero** duplicate frame numbers.

**Captures that change content rather than count** — and they are this plan's best proofs, because a fixture
cannot fake them: **`app-pr-celebration`** (the rebuilt production overlay, frame 29);
**`app-session-scale-down`** and **`app-session-warmup-suggestion`** must be **byte-identical** after S7
(constraint 14 — the extraction is behaviour-preserving or it is a bug); **`app-lobby`** gains the rack
stepper only when its fixture venue lacks a count, which `LobbyWorld` does **not** set, so frame 129 is
unchanged too.

---

## Sequencing

```
 origin/master 67f3f15  (FLOOR 131, frames 1-150, no duplicates)
        │
        ├──► STREAM D · the data  (supabase/**, scripts/**)
        │      D1 rack_counts + set_venue_rack_count + claim_session_venue ──[GATE]──► D2 pgTAP
        │      D3 sessions.venue_id + session_participants.todays_scale   ──[GATE]──► D4 pgTAP
        │
        └──► STREAM S · the app (ONE worker at a time, in order)
               S1  the PR fires on the right event            L · Opus
               S2  the celebration sound, bundled             M · Sonnet
               S3  two compositions, catalog-only             L · Opus
                          │
                    [OWNER-PICK GATE]
                          │
               S4  the production rebuild + the retirement    L · Opus
               S5  the session learns its venue               S · Sonnet   ← needs D1 + D3 applied
               S6  the rack count, asked and spent            L · Opus     ← needs D1 + D3 applied
               S7  today's scale survives a relaunch          M · Opus     ← needs D3 applied
               S8  the three carried small items              S · Sonnet
                          │
                          ▼
                   INTEGRATION  (I1 Sonnet · I2 controller · I3 controller)  →  ONE PR, with proof cards
```

**The hard edges.** S1 → S2 → S3 → S4 are one worker in number order: they share the celebration path, and
S4 is gated on the pick. S5, S6 and S7 all edit `SessionLiveView.swift`, so they are one worker in number
order too; S5 precedes S6 because the cap cannot be read before the session knows its venue. S7 may run
before S6 if the pick stalls Stream S — it needs only D3 — and the controller reorders it rather than idling.
S8 is last because it edits `ScreenshotTests.swift`, whose proof is a green screenshots job (constraint 19).
D1 and D3 are both gates; D2 and D4 wait on them.

**Model ladder, per the 2026-09-13 token addendum.** Opus for the multi-file judgment calls (S1, S3, S4, S6,
S7). Sonnet 5 for everything mechanical from an exact spec — the sound, the venue claim, the carried items,
both migrations and both pgTAP suites, I1. Never Fable, never `fork`. **Two Opus at once, maximum, one per
stream** — and Stream D is entirely Sonnet in this plan, so the ceiling is never reached.

**Seams are reviewed early, not at the end** (the B1 lesson, the B2 proof). **S6's task review must answer
the seam question in writing**: `set_venue_rack_count`'s exact signature and its three parameter names as
PostgREST sends them; `venues.rack_counts`' JSON shape and how a missing key differs from a zero; the
caller's gate (checked in there inside 12 hours); and what the app does when it raises `P0001` (the stepper
says so and stays where it is; the cap stays `nil`). **S5's review answers the smaller twin** for
`claim_session_venue`. B1 shipped a whole round engine with no caller because that question was asked only in
the final review; B2's R-B2-14/R-B2-16 were caught because it was asked early.

---

# STREAM D — the data

Two migrations, two pgTAP suites. `supabase/**` and `scripts/**` only. Both migrations are **gates**
(constraint 8). Neither is irreversible (constraint 9).

### D1 — rack counts on the venue, and the session's venue claim — **M** · Sonnet

**File (new):** `supabase/migrations/20260918000201_venue_rack_counts.sql`

Decisions 1 and 2. Write the header comment first, in the migration's own voice: why the count lives on the
venue and not on the session (a building's racks outlive a crew); why the gate is `venue_checkins` and not
`venue_users` (membership is not presence, and `check_in_to_venue` is the app's only server-verified
geofence); why `created_by` is not the authority (nullable by design since `20260814000002` — a community
hub has no owner, and an owner is not in the room); and why an unknown count is an **absent key**, never a
zero.

```sql
ALTER TABLE public.venues
  ADD COLUMN IF NOT EXISTS rack_counts jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS rack_counts_updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rack_counts_updated_at timestamptz;

CREATE OR REPLACE FUNCTION public.set_venue_rack_count(
  p_venue_id uuid, p_equipment_class text, p_count int
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign-in required' USING ERRCODE = 'P0001';
  END IF;

  IF p_equipment_class IS NULL
     OR p_equipment_class NOT IN ('barbell','dumbbell','machine','cable','bodyweight') THEN
    RAISE EXCEPTION 'unknown equipment class: %', p_equipment_class USING ERRCODE = 'P0001';
  END IF;

  IF p_count IS NULL OR p_count < 1 OR p_count > 99 THEN
    RAISE EXCEPTION 'a rack count is between 1 and 99' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.venue_checkins
     WHERE venue_id = p_venue_id AND user_id = auth.uid()
       AND created_at > now() - interval '12 hours'
  ) THEN
    RAISE EXCEPTION 'you need to be at this gym to set its rack count' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.venues
     SET rack_counts = jsonb_set(rack_counts, ARRAY[p_equipment_class], to_jsonb(p_count), true),
         rack_counts_updated_by = auth.uid(),
         rack_counts_updated_at = now()
   WHERE id = p_venue_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_venue_rack_count(uuid, text, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_venue_rack_count(uuid, text, int) TO authenticated;
```

Then, in the same migration and under its own comment block (decision 2 — same 12-hour presence rule, which
is why it is not a second migration):

```sql
-- Deliberately NOT in 20260918000202: this function's whole content is the
-- venue_checkins presence rule above, and splitting it from that rule would
-- put the rule in two files. The COLUMN it writes lands in the next migration,
-- so this function is created there instead — see 20260918000202.
```

**The function itself ships in D3**, beside the column it writes; D1 only records why the rule lives here.
`COMMENT ON COLUMN public.venues.rack_counts` names decision 1, the five-class whitelist, and the
absent-key-means-unknown rule.

**Interfaces** — *consumes:* `venue_checkins`, `venues`. *Produces:* the column `VenueRackRepository` (S6)
decodes and the RPC it calls.

**TDD steps.** 1. Write the migration. 2. **Commit, stop, hand back** — the controller applies it and records
the timestamp. 3. The controller verifies
`SELECT proname, pronargs, prosecdef FROM pg_proc WHERE proname = 'set_venue_rack_count';` → one row, 3,
true; and `\d public.venues` shows the three new columns. 4. Commit:
`feat(venue): rack counts live on the venue, set by whoever is standing in it` + the trailer.

**Proves:** the number the station split needs has a home and an author, and only presence can write it.

---

### D2 — pgTAP for the rack count — **M** · Sonnet

**File (new):** `supabase/tests/venue_rack_counts_test.sql`. **Fixture block `15xx`** (constraint 17).
`plan(9)`. Fixture: one venue V; lifter A with a `venue_checkins` row at V **2 hours ago**; lifter B with one
**20 hours ago**; lifter C with none. 2099 dates wherever a date is controlled (constraint 16).

1. `has_column('public','venues','rack_counts')` and the default is `'{}'::jsonb`.
2. `has_function('public','set_venue_rack_count', ARRAY['uuid','text','integer'])`.
3. `prosecdef` is true — the DEFINER is what lets the function read the policy-less `venue_checkins`.
4. As A: `set_venue_rack_count(V,'barbell',3)` → `rack_counts->>'barbell'` is `'3'`, and
   `rack_counts_updated_by` is A.
5. As A: a second call with `'machine',2` leaves `'barbell'` at 3 — `jsonb_set` on one key, not a replace.
6. As A: `'bench'` **throws** `'unknown equipment class: bench'` — the whitelist is the five classes, and the
   brief's own example key is the case this assertion exists for.
7. As A: `0` and `100` both **throw** — an unknown count is an absent key, never a zero.
8. As B (checked in 20 hours ago): **throws** `'you need to be at this gym to set its rack count'` — the
   12-hour window is what makes the claim mean "I can see the racks".
9. As C (never checked in): the same raise.

**TDD steps.** Write, run locally if `SUPABASE_DB_URL` is available
(`node scripts/run_pgtap.js supabase/tests/venue_rack_counts_test.sql`), else push. Reset role and claim
between fixture blocks. Commit: `test(venue): pgTAP for the rack count — presence, the whitelist, the clamp`
+ the trailer.

**Proves:** a stranger cannot set a number for a building they are not in, and a typo'd class fails loudly
rather than storing a key nothing reads.

---

### D3 — the session's venue, and today's scale — **S** · Sonnet

**File (new):** `supabase/migrations/20260918000202_session_venue_and_todays_scale.sql`

Decisions 2 and 3. Two additive nullable columns and one function, each under its own header block.

```sql
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS venue_id uuid REFERENCES public.venues(id) ON DELETE SET NULL;

ALTER TABLE public.session_participants
  ADD COLUMN IF NOT EXISTS todays_scale jsonb;

CREATE OR REPLACE FUNCTION public.claim_session_venue(p_session_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_venue uuid;
BEGIN
  IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a participant of this session' USING ERRCODE = 'P0001';
  END IF;

  SELECT venue_id INTO v_venue
    FROM public.venue_checkins
   WHERE user_id = auth.uid() AND created_at > now() - interval '12 hours'
   ORDER BY created_at DESC LIMIT 1;

  IF v_venue IS NULL THEN RETURN NULL; END IF;

  UPDATE public.sessions SET venue_id = v_venue
   WHERE id = p_session_id AND venue_id IS NULL;

  SELECT venue_id INTO v_venue FROM public.sessions WHERE id = p_session_id;
  RETURN v_venue;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_session_venue(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.claim_session_venue(uuid) TO authenticated;
```

**The two header blocks carry the reasoning, not this plan.** `venue_id`: why the claim is DEFINER (the read
of the policy-less `venue_checkins`) while the *write* would have been legal without it (`sessions`' UPDATE
policy already admits any participant, `20260709000006:61-67`); why `venue_id IS NULL` in the WHERE clause
makes first-write-wins a database property; and that `ON DELETE SET NULL` means a deleted hub costs the
session its cap and nothing else. `todays_scale`: **NO NEW POLICY, ON PURPOSE**, in the same words the
energy column used (`20260912000101`), plus the two triggers read and named — `engine_guard` guards three
columns this is not one of, and `checkin_window_guard` returns `NEW` because a warm-up write is always after
check-in opened. `COMMENT ON COLUMN` on both, naming the JSON shape
(`{"exercise_id": uuid, "sets_instead": int}`) and its one writer.

**TDD steps.** 1. Write. 2. **Commit, stop, hand back.** The controller applies it and records the timestamp.
3. The controller verifies both columns and `prosecdef` on the function. 4. Commit:
`feat(session): the session knows its venue, and today's scale outlives a relaunch` + the trailer.

**Proves:** the two reads S5, S6 and S7 need exist live, with nothing new granted to anyone.

---

### D4 — pgTAP for both columns — **M** · Sonnet

**File (new):** `supabase/tests/session_venue_todays_scale_test.sql`. **Fixture block `16xx`.** `plan(8)`.
Fixture: session S (organizer A, participants A and B, non-participant C), venue V, a `venue_checkins` row
for A at V 1 hour ago and none for B. 2099 dates throughout.

1. `has_column('public','sessions','venue_id')` and the FK to `public.venues` exists.
2. `has_column('public','session_participants','todays_scale')`.
3. As A: `claim_session_venue(S)` returns V and `sessions.venue_id` is V.
4. As B (checked into no venue): a second `claim_session_venue(S)` leaves `venue_id` **at V** — first write
   wins, and a later lifter with no presence does not clear it.
5. As C: `claim_session_venue(S)` **throws** `'not a participant of this session'`.
6. As B: an UPDATE writing `todays_scale` on **B's own** row succeeds — the existing own-row policy is
   sufficient, which is the assertion that proves no new policy was needed.
7. As B: the same UPDATE against **A's** row affects **zero rows** — RLS, not an error.
8. As B, with B's row already `check_in_state = 'ready'` and `sessions.scheduled_for` an hour in the past: a
   `todays_scale`-only UPDATE still succeeds — `checkin_window_guard` does **not** raise on a write that
   leaves `check_in_state` alone, which decision 3 asserts and this pins.

**TDD steps.** Write, run locally if possible, else push. Reset role and claim between fixture blocks.
Commit: `test(session): pgTAP for venue_id and todays_scale — first write wins, own row only` + the trailer.

**Proves:** the persistence decision 3 rests on is a property of the database, not of the client that
happened to write first.

---

# STREAM S — the app

Eight tasks, in order, one worker at a time (constraint 2).

### S1 — the PR fires on the right event — **L** · Opus

**Files (new):** `Models/PRFiring.swift`, `GymSyncTests/PRFiringTests.swift`.
**Files (modified):** `Models/PersonalRecordMath.swift`,
`Features/Sessions/Live/SessionLiveView.swift`, `Features/Workout/WorkoutSessionView.swift`.

Docket row 7 (`2026-09-03-field-report-docket.md:10`, P1), and the half of the owner's *"not what we
designed"* that is logic rather than pixels.

**State what is true today in the commit body, from the read, not from the docket.** Neither rule is
implemented:

* **Group** (`SessionLiveView.swift:4516-4536`): `priorBest = try await priorMax(exerciseID:reps:userID:)`,
  then `isPR = weight > prior`. `priorMax` (`:4896`) returns `0` when the lifter has no qualifying history,
  so **the first set of a lift you have never logged is always a PR**, and the overlay fires from inside
  `logSetAndAdvance` on **every** set.
* **Solo** (`WorkoutSessionView.swift:3816-3838`): `PersonalRecordMath.bestWeight(atLeastReps:in:)` returns
  `0` for an empty basis (`PersonalRecordMath.swift:30-35`) and `isPR` is `weight > 0` in that case
  (`:42-45`). Same two properties, same per-set trigger.
* The **rep-PR** twin (`SessionLiveView.swift:4547-4555`, `WorkoutSessionView.swift:3852-3860`) computes
  `priorBestReps` as `max() ?? 0`, so a first bodyweight set is a rep PR too.

**The rule, pure.**

```swift
enum PRFiring {
    struct Context {
        let basisIsEmpty: Bool       // no prior qualifying history for this exercise, this lifter
        let setsLogged: Int          // including the set just written
        let targetSets: Int?         // from the EFFECTIVE routine row; nil = unprescribed
    }
    /// Docket row 7: (a) the first-ever log of an exercise is a baseline, not a
    /// record; (b) the celebration waits until every set of that exercise is done.
    static func shouldCelebrate(isRecord: Bool, context: Context) -> Bool
}
```

Rules, in one place: `isRecord == false` → false. `context.basisIsEmpty` → **false** (the baseline rule) —
the set is still stored and still shows its `PR` tag on the recap, because the docket asks for no
*celebration*, not for the fact to be erased. `targetSets == nil` → celebrate on the record (an unprescribed
exercise has no "all sets", and withholding forever would delete the moment). `setsLogged < targetSets` →
false. Otherwise true.

**`targetSets` comes from `effectiveRoutineExercises`**, not from `routineExercises`: an accepted scale-down
of 4 × 5 → 3 × 5 means the third set is the last one, and the celebration must agree with the number the
screen printed. In the solo body the equivalent is the current routine row the session is running.

**`PersonalRecordMath` gains the guard rather than a second rule.** `bestWeight` keeps returning `0` (other
callers depend on it — `ExerciseHistoryView.swift:89`), and `isPR`'s doc records that an empty basis is a
baseline and that `PRFiring` is what acts on it. **`isPR`'s own behaviour does not change**; only the
celebration gate is new. Say so in the body — the recap's `PR` tags (`SoloRecapView`, `PumpFeedView:586`,
`WorkoutMetricsSheet:120`) must be identical after this task.

**Both call sites adopt it, and the rep-PR path with them** — four `if isPR` / `if isRepPR` branches
(`SessionLiveView.swift:4646`, `:4629`; `WorkoutSessionView.swift:3941`, `:3917`) become
`if PRFiring.shouldCelebrate(...)`. The **record insert and the `previousBest` write are unchanged**: the
database still records the record; only `showPROverlay` is gated.

**TDD steps.** 1. `PRFiringTests` — an empty basis never celebrates; a record on set 2 of 3 does not; the
same record on set 3 of 3 does; `targetSets == nil` celebrates; `isRecord == false` never does; the scaled
case (3 of 3 when the routine said 4) celebrates. 2. The type. 3. The four branches.
4. `git grep -n 'PRFiring.shouldCelebrate'` shows callers in **both** view files (constraint 12).
Commit: `fix(pr): the first log of a lift is a baseline, and the record waits for the last set` + the
trailer.

**Proves:** docket row 7's two rules, in one place, read by both bodies.

---

### S2 — the celebration sound, bundled — **M** · Sonnet

**Files (new):** `Services/CelebrationSound.swift`, `Resources/Sounds/lightweight-baby.mp3`,
`GymSyncTests/CelebrationSoundTests.swift`.
**Files (modified):** `GymSyncApp/project.yml`, `Features/Sessions/Live/SessionLiveView.swift`,
`Features/Workout/WorkoutSessionView.swift`.

The owner's *"keep the sound effect"*. Decision 4 and constraint 21.

**The file.** Copy `lightweight-baby.mp3` (60,857 bytes) from
`.superpowers/sdd/2026-09-18-owner-decisions-round/` to
`GymSyncApp/GymSync/Resources/Sounds/lightweight-baby.mp3`. **Verify the byte count after the copy** and put
it in the report — a truncated binary is a silent failure this task cannot otherwise detect (Swift compiles
in CI; nothing plays there).

**The exact project.yml edit.** `resources:` on the `GymSync` target (`project.yml:95-96`) is an **explicit
list**, not a glob, and today holds one entry:

```yaml
    resources:
      - GymSync/DesignSystem/Fonts
      # The PR celebration's sound, bundled (owner 2026-09-18: "keep the sound
      # effect"). A FOLDER, following the Fonts precedent above: a future
      # bundled sound lands here with no further project.yml edit.
      - GymSync/Resources/Sounds
```

Adding the folder — not the file — is deliberate and the comment says why. **`sources:` is a directory glob
(`- GymSync`), so the new folder would otherwise be compiled as source**; naming it under `resources:` is
what makes XcodeGen copy it into the bundle instead. Verify the entry by reading the surrounding block
before editing; do not reformat the file.

**The player.**

```swift
@MainActor
enum CelebrationSound {
    /// The PR moment's sound. NEVER sets the AVAudioSession category
    /// (the AUDIO SACRED RULE — see VoiceBubblePlayer). Silent, not
    /// interrupting, while a voice room holds the session.
    static func playPR()
}
```

- Returns immediately when `AudioSessionManager.shared.isInVoiceMode` (decision 4).
- Calls `AudioSessionManager.shared.ensureMixablePlayback()` — **its first caller since B1's S11**
  (constraint 12's cautionary case), which restores `.playback + .mixWithOthers` only when `mixWithOthers`
  has been lost.
- `Bundle.main.url(forResource: "lightweight-baby", withExtension: "mp3")` → `AVAudioPlayer`, held in one
  static so a second PR inside the clip restarts rather than layers. A `nil` URL or a throwing initializer
  logs to `AppLogger.audio` and returns — **the celebration must never fail to appear because a sound did
  not load.**
- No `setCategory`, no `setActive`, no `configure()`, no `enterVoiceMode`/`exitVoiceMode` (constraint 21).

**The two call sites**, both of which today carry a comment saying the sound left and do nothing else:
`SessionLiveView.showPROverlay` (`:4918-4922`) and `WorkoutSessionView.showPROverlay` (`:4151-4155`). The
call goes **beside** `isPROverlay = true`, and each stale comment is **replaced** by one line naming the
bundled file and the owner's decision — not left dangling beside its own contradiction.

**No new setting.** Grepped for one: there is no user-facing sound or haptics toggle in this app (`isMuted`
everywhere refers to `VoiceRoomService`'s per-participant voice mute, and `LaunchLoadingOverlay`'s
`player.isMuted` is a video). The silent switch is honoured by the category the app already chose not to
obey, deliberately, on 2026-08-14 (decision 4). Say this in the commit body so the next reader does not go
looking.

**TDD steps.** 1. `CelebrationSoundTests`: `Bundle.main.url(forResource:withExtension:)` is non-nil under the
test bundle's host app, and a missing-resource path returns without throwing. 2. The service. 3. The
project.yml entry. 4. The two call sites; `git grep -n 'CelebrationSound.playPR'` shows both (constraint 12).
Commit: `feat(pr): the celebration's sound returns as a bundled resource, mixing over the lifter's music` +
the trailer.

**Proves:** the owner's *"keep the sound effect"*, without the soundboard, without a bucket, and without ever
touching the audio session's category.

---

### S3 — two compositions of the celebration, catalog-only — **L** · Opus

**Files (new):** `Features/Sessions/PRCelebrationVariations.swift` (`#if DEBUG`).
**Files (modified):** `App/CatalogHostView.swift`, `GymSyncTests/CatalogScreenTests.swift`,
`GymSyncUITests/ScreenshotTests.swift`, `docs/design/frame-map.json`.

The design round. Constraint 6 in full for **each** of the two ids, in **one** commit for both.

**Read before drawing, in this order:** `pr-celebration-live-2026-09-18.png` beside the brief (what the owner
is objecting to), `PRCelebrationOverlay.swift` in full (215 lines — every value the two variations must
carry), `2026-09-05-design-language.md` §§1, 2, 3, 8, 9, and
`2026-09-06-design-congruence-plan.md:1030-1075` (T6.1 — the **one** rule already applied, so the variations
do not un-apply it by accident).

**The two compositions are specified in "New catalog ids" above.** Both are built from the shipped
primitives; both keep all six facts and the rep-PR form; both spend accent exactly once; neither adds a
kudos row. `PRCelebrationVariationA` and `…B` take the **same six values** `PRCelebrationOverlay`'s
initializer takes, so whichever wins can be rebuilt into that type without touching a call site.

**The shared fixture**, one literal in the same file: `exerciseName: "Bench Press"`, `weight: 205`,
`reps: 5`, `priorBest: 200`, `monthlyCount: 3`, `unit: .lbs` — deliberately identical to
`content_prCelebration`'s (`CatalogHostView.swift:323-333`), so the three captures are the same record drawn
three ways and the owner is comparing compositions, not numbers.

**Catalog wiring, both ids, one commit:** cases `prCelebrationA = "pr-celebration-a"` /
`prCelebrationB = "pr-celebration-b"`, two builder arms (value-in, no `Date()`, no repository, no `.shared`
— constraint 11), two ids in `CatalogScreenTests`, two `captureCatalog` methods, two `frame-map.json`
entries at **151** and **152** whose notes say they are a design round on the 2026-09-18 owner decision and
retire at the pick.

**`PRCelebrationOverlay` is not touched by this task.** Frame 29 renders exactly what it renders today, so
the owner's card has an honest "what ships now" panel.

**TDD steps.** 1. Read the four documents named above. 2. The two views and the fixture. 3. The four-part
contract, twice, in one commit. 4. Constraint 19: the proof is a green **screenshots** job, not
`build-test`. Commit: `feat(catalog): two compositions of the PR celebration on the design language` + the
trailer.

**Proves:** the owner has two real screens to choose between, drawn to the language, with the shipped one
beside them.

---

### THE OWNER-PICK GATE — controller

S3 green → the controller downloads the artifact **into a fresh directory**, composes **one** card with
`app-pr-celebration.png` (what ships), `app-pr-celebration-a.png` and `app-pr-celebration-b.png`, names what
each argues in one line, and sends it. **The pick is written to the ledger by name, with the owner's reason,
before S4 is dispatched.** No pick → S4 does not run; see constraint 7's contingency.

---

### S4 — the production rebuild, and the retirement — **L** · Opus · **gated on the pick**

**Files (modified):** `Features/Sessions/PRCelebrationOverlay.swift`, `App/CatalogHostView.swift`,
`GymSyncTests/CatalogScreenTests.swift`, `GymSyncUITests/ScreenshotTests.swift`,
`docs/design/frame-map.json`.
**Files (deleted):** `Features/Sessions/PRCelebrationVariations.swift`.

**The task's first step is to quote the ledger's pick line in the report.** A rebuild begun on a guess is
what constraint 9 exists to prevent.

1. **`PRCelebrationOverlay`'s body becomes the picked composition.** The **initializer, the property list and
   both call sites do not change** (`SessionLiveView.swift:1953-1963`, `WorkoutSessionView.swift:611-623`,
   `CatalogHostView.swift:324-332`) — this is a body rewrite, not a signature change, and the report proves
   it with `git show --stat` plus a grep of the two call sites showing zero diff. The rep-PR form
   (`weight == 0`), `shareText`, and `ordinal(_:)` survive; **`decimalString(_:)` is dead today** (no caller
   in the file) and leaves with the rewrite, which the body notes.
2. **The stale header goes.** Docket `:320` lists `PRCelebrationOverlay.swift`'s *"behaviour-preserving
   extraction"* header among the repo's stale comments. It stops being true at this commit; the new header
   names the design language, the owner's 2026-09-18 decision, and the variation the composition came from.
3. **Both variation ids retire, in the same commit** (constraint 6 in reverse): the two cases, the two
   builder arms, the two view structs, the file that holds them, the two id strings, the two capture methods
   and the two frame-map entries. `git grep -n 'PRCelebrationVariation'` → zero;
   `ls Features/Sessions/PRCelebrationVariations.swift` → absent.
4. **Frame 29's note** records the rebuild and the source variation.

**TDD steps.** 1. Quote the pick. 2. The body rewrite. 3. The retirement, same commit. 4. Constraint 19: the
proof is a green **screenshots** job. Commit: `feat(pr): the celebration rebuilt to the owner's pick; the
design round retires` + the trailer.

**Proves:** what the owner picked is what ships, and no design-round frame outlives its decision.

---

### S5 — the session learns its venue — **S** · Sonnet · **needs D1 + D3 applied**

**Files (modified):** `Models/SessionRepository.swift`, `Features/Sessions/LobbyView.swift`.

Decision 2. `SessionRepository.checkIn(sessionID:method:)` (`:598-616`) gains **one** best-effort call after
its existing UPDATE succeeds:

```swift
// Decision 2: the venue comes from the VENUE check-in (venue_checkins,
// server-verified geofence), never from `gyms` — a gyms row is a private
// per-user geofence and is not a venues.id. Best-effort and last: a session
// with no venue is today's behaviour, and a failure here must never turn a
// successful check-in into an error the lifter sees.
_ = try? await client.rpc("claim_session_venue", params: ["p_session_id": sessionID.uuidString]).execute()
```

The lobby's `checkIn(method:)` (`LobbyView.swift:1873-1885`) already calls `reload()` afterwards, so the
session row's new `venue_id` arrives with the next read; **no new state, no new fetch, no new UI**.
`WorkoutSession` gains `venueID: UUID?` decoding `venue_id` — additive and optional, so every existing
decode site compiles unchanged and every fixture stays valid.

**Constraint 10:** this task adds **no** location read. It does not touch `initiateCheckIn()`,
`CheckInService`, `LocationOneShotHelper`, or `CLLocationManager`; the presence it relies on was recorded by
`check_in_to_venue` at the venue hub, on a different day if need be.

**THE SEAM QUESTION, answered in this task's review:** `claim_session_venue`'s signature and its one
parameter name as PostgREST sends it; its return type and what `NULL` means (no recent venue presence — not
an error); the caller's gate (participants only); and what the app does on `P0001` (nothing visible —
`try?`, and the cap stays `nil`).

**TDD steps.** 1. The model property. 2. The call. 3. `git grep -n 'claim_session_venue'` shows the call site
outside the migration. Commit: `feat(session): a session claims the venue its first checked-in lifter is
standing in` + the trailer.

**Proves:** the session→venue link R-B3 said did not exist, exists — from the one presence claim the server
verifies.

---

### S6 — the rack count, asked once and spent — **L** · Opus · **needs D1 + D3 applied**

**Files (new):** `Models/VenueRackRepository.swift`.
**Files (modified):** `Models/Venue.swift`, `Features/Sessions/LobbyView.swift`,
`Features/Sessions/Live/SessionLiveView.swift`, `Features/Sessions/Live/RoundPieces.swift`,
`GymSyncTests/VenueMathTests.swift`.

Decision 1, and the answer to R-B3.

**1. The class normalizer.** `Venue.equipmentClass(for exerciseEquipment: String) -> String?` beside
`Venue.equipmentClasses` (`:35`): the five classes map to themselves; `ez-bar` and `smith` map to
`"barbell"` (the same collapse `Units.swift:170` and `ProgramGenerator.swift:1730` already make); anything
else returns `nil`, which means unknown, which means no cap. Asserted in `VenueMathTests`.

**2. The repository.** `VenueRackRepository.counts(venueID:) async throws -> [String: Int]` (a `select` of
`rack_counts` on `venues`, readable by everyone) and `.set(venueID:equipmentClass:count:)` (the RPC).
`ErrorMapping.map` on both catches, `GroupRepository.consistencyHonor`'s idiom.

**3. The question, once, in the style card.** In `LobbyView.styleCard` (`:1227-1248`), under the three style
rows and inside the same `.gs3DCard`, one **flat** line (rule 1 — furniture inside a raised box stays flat)
shown only when **all** of: `effectiveSession.style == .rounds`, `effectiveSession.venueID != nil`, the
first plan row's exercise has a known equipment class, and `rackCounts[class] == nil`. It reads
`How many racks here?` with a `−  2  +` stepper and a SKIP (rule §4: *"Questions come as one block with a
SKIP in its header"*). **It never blocks Start**, it disappears once answered or skipped for the session, and
it spends **no accent** — the lobby's accent is Start. Loaded behind the `catalog != nil` guard every other
read in that file carries (constraint 11), so `LobbyWorld` — which sets no venue — renders frame 129
unchanged (constraint 14).

**4. The correction, later.** `StationCard`'s header (`RoundPieces.swift`) gains a small tappable count when
the venue and class are known — the same stepper in a popover, the same RPC, no new screen.

**5. The cap, spent.** `SessionLiveView.swift:4437`'s `equipmentCap: nil` becomes the venue's count for the
**current exercise's** class, `nil` when the venue, the class or the count is unknown. The re-mix at
`.task(id: currentRoutineExercise?.position)` (`:2251`) re-reads it, so a barbell block and a dumbbell block
may split differently. `StationSplit.count` itself is **not changed** — it already implements
`max(1, min(ceil(crew/3), cap ?? .max))` and `SessionStationsTests` already pins it at caps 1 and 2.

**THE SEAM QUESTION, answered in this task's review** (the B1 lesson, the B2 proof): `set_venue_rack_count`'s
exact signature and its three parameter names as PostgREST sends them; `rack_counts`' JSON shape and how an
**absent key** differs from a zero; the caller's gate (a `venue_checkins` row at that venue inside 12 hours);
and the app's behaviour on `P0001` — the stepper reports it inline and keeps its value, the cap stays `nil`,
and Start is never blocked.

**TDD steps.** 1. `VenueMathTests` for the normalizer (five classes, two aliases, one unknown). 2. The
repository. 3. The stepper and its four conditions. 4. The station-card affordance. 5. The cap.
6. `git grep -n 'equipmentCap:'` shows the non-nil call site (constraint 12). Commit:
`feat(session): the venue's rack count caps the split, asked once of whoever is standing there` + the
trailer.

**Proves:** the owner's `min(ceil(n/3), racks at the venue)` — with a number the people in the room maintain.

---

### S7 — today's scale survives a relaunch, and the layering is extracted — **M** · Opus · **needs D3 applied**

**Files (new):** `Models/RoutineLayering.swift`, `GymSyncTests/RoutineLayeringTests.swift`.
**Files (modified):** `Features/Sessions/SessionRunnerView.swift`,
`Features/Sessions/Live/SessionLiveView.swift`, `Models/SessionRepository.swift`,
`GymSyncTests/WarmUpReadinessTests.swift`.

Owner decision 3 and decision 3 above.

**1. The extraction first, so the persistence lands on one layering rather than three.**
`RoutineLayering.apply(_ rows: [RoutineExercise], squadSwaps:, selfScale:, todaysScale:) ->
[RoutineExercise]`, holding the order **unchanged**: squad swap → my self-scale → today's set reduction,
keyed on the routine's own exercise id. `SessionLiveView.effectiveRoutineExercises` (`:621-637`) keeps its
doc comment (it is the best statement of the rule in the repo) and delegates its body;
`Self.swapped(_:to:)` (`:603-613`) moves with the rule, since the door wording
(`swapDoorDetails`) and the layering must stay one function (R-B2-15). `SessionRunnerView.planRows`
(`:249-256`) and `WarmUpReadinessTests` (`:151-155`) call it too — the three hand-copies the docket named.

**`RoutineLayeringTests` is the only place the order is asserted**, and the three old assertions that
duplicated it are deleted rather than left to drift.

**2. The persistence.** `TodaysScale` gains `Codable` with `exercise_id` / `sets_instead` keys.
`SessionRepository.setTodaysScale(sessionID:scale:)` — a direct own-row UPDATE, **not an RPC**, with
`setEnergy`'s reasoning verbatim in its doc (the own-row policy already scopes it;
`20260912000101`'s header is the precedent). `SessionRunnerView`: `todaysScale` (`:79`) is **seeded** from
the viewer's participant row when the rows load, and **written** on Accept (`:384-385`), best-effort —
a failed write leaves the in-memory value and B2's behaviour.

**`suggestionDeclined` is deliberately not persisted**, and the body says so: `coachSuggestion` (`:273`)
already returns `nil` once `todaysScale != nil`, so an accepted scale suppresses the card across a relaunch
by itself. A *declined* suggestion returning after a relaunch is a second column and a second question
nobody has asked — recorded under "does not decide".

**3. Behaviour-preserving, and proven so.** The extraction changes no output: `app-session-scale-down`
(frame 143) and `app-session-warmup-suggestion` (frame 144) must be **byte-identical** afterwards
(constraint 14), and I2 checks exactly that.

**TDD steps.** 1. `RoutineLayeringTests` — a squad swap alone; a self-scale beating a squad swap; a set
reduction riding a swapped slot; all three together; none. 2. The type. 3. The three call sites; the three
old assertions deleted. 4. The `Codable` conformance and the repository call. 5. The seed and the write.
6. `git grep -n 'RoutineLayering.apply'` shows three callers (constraint 12). Commit:
`feat(session): an accepted scale-down outlives a relaunch, and the layering is written once` + the trailer.

**Proves:** the owner's *"Yes"* — and one layering where there were three.

---

### S8 — the three carried small items — **S** · Sonnet

**Files (modified):** `Features/Sessions/WarmUpFixtures.swift`, `Features/Social/PumpFeedView.swift`,
`GymSyncUITests/ScreenshotTests.swift`.

All three are docket leftovers from the B2 close. **Each is its own paragraph in one commit**, and any one
of them that turns out to be larger than stated is dropped and re-docketed rather than grown.

**(a) The fixture id** (docket: *"`WarmUpFixtures.swift:126` suggestion fixture's exercise id matches no
fixture row"*). Verified on master: `WarmUpFixtures.suggestionForCrew.exerciseID` is
`…f021` (`:176`, the docket's line number predates B2's final edits), which is
`LobbyFixtures.planRows[0].**id**` (`LobbyFixtures.swift:114`) — the plan **row**'s identity, not an
exercise id. `SessionRunnerView.planRows` matches `scale.exerciseID == exercise.exerciseID`, so the fixture
asserts on the wrong field and only renders correctly by coincidence. Fix: give `LobbyFixtures.planRows` a
declared exercise-id constant and point both at it, with a comment naming the two ids so the next reader
does not re-conflate them.

**(b) The third radius** (docket: *"`PumpFeedView.swift:452` radius 14"*). Verified at **`:453`**:
`.clipShape(RoundedRectangle(cornerRadius: 14))` on the 88 × 88 photo thumb. Design rule 1 allows two radii
in code — `GSMetrics.radiusMd` (24) and `GSMetrics.radiusSm` (16); the language's "strips 14" is a
**strip**, and an 88 pt square thumbnail is a tile. → `GSMetrics.radiusSm`. **This changes
`app-pump-feed-post` by two pixels of corner**, which is a live content change to a B2 frame — declare it in
the commit body and in I1's accepted deviations, and let I2 confirm nothing else on that frame moved.

**(c) The first test's launch, retried once.** `ScreenshotTests`' class-level `setUp()` already pays a
120 s first-launch warm-up (`:45-104`, Phase A). The residual flake is the **first catalog test's** own
launch, which `captureCatalog` performs with no retry. Give **only** `captureCatalog` a single retry when
the first `launch()` does not produce the expected view inside its budget, log it, and leave the 19
`launchApp()` call sites and every other test untouched. **Constraint 19: the proof is a green screenshots
job.** If the retry cannot be made local to `captureCatalog`, drop this item and re-docket it — it is not
worth reshaping the UI-test target for.

**TDD steps.** 1. (a), and grep for other readers of `f021`. 2. (b). 3. (c). Commit:
`fix(app): the suggestion fixture's exercise id, the pump thumb's radius, one catalog-launch retry` + the
trailer.

**Proves:** three docketed leftovers close, and none of them grew.

---

# INTEGRATION

### I1 — the FLOOR, the frame-map and the accepted deviations — **S** · Sonnet

- `.github/workflows/ios.yml` — **the FLOOR moves by `0` against master's FLOOR at integration** on the
  picked path, **`+2`** on the contingency path (constraint 7). Re-derive the literal on the day:

  ```
  git fetch origin
  grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1
  grep -c 'captureCatalog("' GymSyncApp/GymSyncUITests/ScreenshotTests.swift
  gh run download <last green run> -n app-screenshots -D ./fresh-artifact && ls ./fresh-artifact | wc -l
  ```

  Against the verified base that is `FLOOR=131` → `FLOOR=131`. Extend the comment block above the line in the
  style Phase A, B1 and B2 established: the two design-round ids in at 151/152 and out again at the pick,
  frame 29's rebuild (a content change, not a count change), and *"the delta is the invariant, not the
  literal"*.
- `docs/design/frame-map.json` — 151 and 152 **absent** on the picked path (present on the contingency path,
  with their notes); frame 29's note records the rebuild and its source variation; **zero duplicate frame
  numbers** (a one-line script in the report proves it); everything else untouched.
- `docs/design/accepted-deviations.json` — append, to today's **55**: the celebration's rebuild against its
  July canvas frame (naming §8 as the authority and the variation as the source); `app-pump-feed-post`'s
  two-pixel corner change (S8b); and — if the contingency path ran — one entry per surviving variation id
  saying it is a live design round awaiting a pick.

Commit: `chore(pr): FLOOR unchanged, the design round in and out, frame 29 rebuilt` + the trailer.

### I2 — end-to-end CI, then by eye — **M** · controller

Push and read the run. **Download the artifact into a fresh directory** (constraint 12).

**iOS workflow** — build green; `GymSyncTests` green with the new files (`PRFiringTests`,
`CelebrationSoundTests`, `RoutineLayeringTests`); the screenshots job exports **≥ the new FLOOR** and
"Verify capture count" passes.

**Backend workflow** — pgTAP green for `venue_rack_counts_test.sql` (9) and
`session_venue_todays_scale_test.sql` (8), each of which requires its migration to have been **applied**
(constraint 8); a red with a "does not exist" error means a gate was skipped, not that the SQL is broken.

**Then read the artifact, by eye, in this order:**

1. **The twenty frozen frames** — 129-135, 136-141, 142-146 and the two Home canaries (81, 82) —
   **unchanged** (constraint 14). Frames **143** and **144** in particular: S7's extraction is
   behaviour-preserving or it is a bug.
2. **`app-pr-celebration`** — the rebuilt overlay: accent spent **once**, no `▲` text glyph, no
   `theme.surface` face, only `radiusMd`/`radiusSm`, all six facts present, **no kudos row**. Side by side
   with `pr-celebration-live-2026-09-18.png`.
3. `app-pump-feed-post` — the thumb's corner, and nothing else on that card, changed.
4. `app-lobby` — **no** rack stepper (the fixture venue is nil), and the frame otherwise identical.
5. `app-home`, `app-tab-social`, `app-group-sessions` — unchanged.

**And three things CI cannot photograph, checked by hand and recorded as manual checks in I3 rather than
claimed by a test:** the sound plays on a device and **does not pause Spotify**; the sound is **silent**
during push-to-talk; and a first-ever log of a new lift **stores** its record without firing the
celebration, while the last set of a prescribed exercise **does** fire it.

Fix-forward any red; each fix is its own commit.

### I3 — one PR, with proof cards — **M** · controller

`feat/owner-decisions-2026-09-18` → `master`. The body carries:

1. **What shipped**, in the owner's own words: the celebration is the screen we designed, with its sound
   back and firing on the right event; rack counts belong to the gym and to whoever is standing in it; an
   accepted scale-down survives a relaunch.
2. **The design round**: the two compositions, the pick and the owner's reason, the retirement, frame 29's
   rebuild, the FLOOR delta (0, or +2 with its reason).
3. **The two migrations**, each with the timestamp it was applied to `chjkkwqwdlmaxacwglzm`. Neither is
   irreversible; both are additive.
4. **The deliberate deviations**, each with its reason: the sound plays through **`.playback`**, not spec
   2026-06-28's `.ambient`, because the owner overruled that on 2026-08-14 and `AudioSessionManager` records
   it; the session's venue comes from **`venue_checkins`**, not from `CheckInService.primaryGym()`, because
   a `gyms` row is a private per-user geofence and not a `venues.id`; the rack count is maintained by
   presence rather than by the venue's creator, because `venues.created_by` is nullable by design; an empty
   PR basis suppresses the **celebration** and not the **record**; `suggestionDeclined` is not persisted;
   `app-pump-feed-post`'s corner moved by two pixels.
5. **Proof cards**, each a run URL plus its evidence: the celebration (frame 29 before and after, beside the
   two variations); the rule (`PRFiringTests` green, and the manual first-log check); the sound (the manual
   Spotify and push-to-talk checks, plus `git grep` showing both call sites and
   `ensureMixablePlayback`'s first caller since B1); the data (two pgTAP suites, with the 12-hour presence
   gate and the first-write-wins property named); the cap (`git grep 'equipmentCap:'` showing a non-nil call
   site); the persistence (frames 143/144 byte-identical, and `RoutineLayering.apply`'s three callers).
6. The trailer per constraint 5, plus `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## What this plan does not decide

1. **Whether a declined suggestion should stay declined across a relaunch.** S7 persists the *accepted*
   scale only. A second column and a second question; nobody has asked.
2. **Whether the crew should see a scale-down that was Coach's idea.** Unchanged from B2: the crew sees the
   `selfScales` exercise swap, not the set reduction. Persisting the value changed nothing about who reads it.
3. **What a rack count means for a venue nobody has checked into.** `rack_counts` is `'{}'` and the cap is
   `nil` — today's behaviour. A seeded inventory (from `venues.equipment`, or from a verified venue's own
   data) is a product question.
4. **Whether a wrong rack count needs a dispute path.** Last write wins, with an author recorded. A number
   that flaps between two lifters has no resolution mechanism, and inventing one before it happens is
   speculation.
5. **Whether the session's venue should be correctable.** `claim_session_venue` sets it once and never
   changes it; a crew that moves gyms mid-session, or whose first checked-in lifter's presence was stale,
   has no way to fix the link from the app.
6. **Whether the celebration should be reachable at all outside the session** (a recap replay, a share
   card). §8 describes a splash; nothing asks for a second door.
7. **Whether `PRCelebrationOverlay` should be one type or two.** The solo and crew bodies render the same
   view with the same six values, and this plan keeps it that way; `WorkoutSessionView`'s adoption of the one
   session body is Phase C and may make the question moot.
8. **The held data PR.** B2 D1/D2, B2 D4/D5 and B1 D5/D6 are written, reviewed and held on the data
   worktrees. They ship as their own PR and are not this plan's to re-write.

---

## Self-review (run by the planner, 2026-09-18)

**1. Decision coverage — every owner sentence maps to a task.**

| owner decision | requirement | task |
|---|---|---|
| 1 — *"implement the new screen"* | two compositions on the design language, owner picks, production rebuilt | S3, the gate, S4 |
| 1 — *"I don't think what's live is what we designed"* (logic) | docket row 7: no PR on the first attempt; PR fires after all sets | S1 |
| 1 — *"keep the sound effect"* | `lightweight-baby.mp3` bundled, played at both call sites, mixing over music | S2 |
| 2 — *"make an informed decision"* | `venues.rack_counts` + the presence-gated RPC | D1, D2 |
| 2 — the session→venue link R-B3 said was missing | `sessions.venue_id`, claimed from the venue check-in | D3, D4, S5 |
| 2 — the cap R-B3 costed | `StationSplit.count(crew:equipmentCap:)` spent, with a class normalizer | S6 |
| 2 — *"asked once, in the lobby's style card"* | one flat stepper line under the style rows, skippable, never blocks Start | S6 |
| 3 — *"Yes"* | `session_participants.todays_scale`, seeded on load, written on Accept | D3, D4, S7 |
| docket, B2 leftovers | the three hand-copied layerings | S7 |
| docket, B2 leftovers | `WarmUpFixtures` fixture id; `PumpFeedView` radius 14 | S8 |
| docket, B2 close | the residual first-launch screenshot flake | S8 |
| docket `:320` | `PRCelebrationOverlay`'s stale "behaviour-preserving extraction" header | S4 |

**Four spec corrections, made deliberately, each from a read of master rather than from the brief.**

(a) **The brief's audio prescription is superseded.** It asked for `.ambient + .mixWithOthers` citing spec
2026-06-28. `AudioSessionManager.configure()` (`:24-35`) records the owner's 2026-08-14 overrule —
`.playback`, because *"it should not go silent when the phone is silenced"* — and `ChatView.swift:9`'s AUDIO
SACRED RULE says a player sets no category at all. `CelebrationSound` calls `ensureMixablePlayback()` and
nothing else (decision 4).

(b) **The brief's venue link cannot exist as described.** It said `sessions.venue_id` comes from
*"`CheckInService.primaryGym()` / the geofence match"* through the existing check-in write path. `primaryGym()`
reads **`gyms`** — a private per-user geofence row — and `SessionRepository.checkIn` writes **only**
`session_participants`. There is no `gyms`→`venues` relation anywhere in the repo. The claim comes from
`venue_checkins` instead (decision 2).

(c) **A venue-owner role does exist**, contrary to the brief's *"No venue-owner role exists"*:
`venues.created_by` with a creator-edit policy for unverified venues (`20260814000002`). It is still the
wrong authority, and the plan says **why** (nullable by design since `relinquish_venue`; a community hub has
no owner; an owner is not in the room) rather than asserting the role away.

(d) **The design language has been applied to this screen once**, contrary to the brief's *"never applied"*:
the design-congruence plan's T6.1 (`2026-09-06-design-congruence-plan.md:1036-1075`) applied rule 8's
headline-first order, and the overlay's own comment at `:67-70` records it. The variations must not
un-apply it by accident, which is why S3's reading list names that section.

**2. Placeholder scan.** Grepped the finished document for `TBD`, `TODO`, `FIXME`, `XXX`, `add validation`,
`similar to`, `same as above`, `<fill`, `and so on`, `etc.`: **zero hits outside this sentence**. Every task
names its files, its exact values, its tests, its commit message and its `Proves:` capture.

**Five things this review changed, rather than noted.**

1. **The first draft trusted the brief's check-in path.** Reading `CheckInService.swift:35-51` and
   `SessionRepository.swift:598-616` showed a `gyms` row and a `session_participants`-only write. The whole
   of decision 2 was rewritten around `venue_checkins`, and S5 shrank from "thread the gym match through the
   check-in" to one best-effort RPC call.
2. **The first draft treated docket row 7 as possibly-already-done.** Reading
   `SessionLiveView.swift:4516-4536` and `WorkoutSessionView.swift:3816-3838` showed `prior`/`bestWeight`
   returning **zero** on an empty basis in both bodies and a per-set trigger in both. It is a task, and S1
   states what is true today rather than asking an implementer to find out.
3. **The first draft gave the sound a `.ambient` session and a new setting.** Reading
   `AudioSessionManager.swift:24-35` and `:89-106` found the owner's 2026-08-14 category ruling and a helper
   written for this exact return and callerless since B1. Grepping for a mute/haptics setting found none.
   S2 sets no category and adds no setting.
4. **The first draft persisted `suggestionDeclined` beside `todays_scale`.** Reading
   `SessionRunnerView.swift:273` showed `coachSuggestion` already returns `nil` once `todaysScale != nil`,
   so an accepted scale suppresses the card across a relaunch by itself. The second column was dropped and
   the question recorded.
5. **The first draft gave the pump card's photo thumb `radiusMd`.** The design language's "strips 14" is a
   strip; an 88 pt square thumb is a tile, so `radiusSm` (16) is the rule — and the two-pixel corner change
   to a B2 live frame is declared rather than slipped in.

**3. Cross-task symbol consistency.** Every cross-task symbol was grepped across this document for a single
spelling. The near-miss spellings a second author would reach for — `PRCelebrationSound`, `SoundPlayer`,
`RackCountRepository`, `VenueRacks`, `RoutineLayer`, `PRGate`, `TodayScale`, `PRCelebrationV2` — appear
nowhere in this document except in this sentence.

- `PRFiring.shouldCelebrate(isRecord:context:)` / `PRFiring.Context` — declared S1, four callers across the
  two view files, one test file.
- `CelebrationSound.playPR()` — declared S2, two callers (`showPROverlay` in each body), nothing else.
- `PRCelebrationVariationA` / `PRCelebrationVariationB` — declared S3, rendered by S3's two builder arms,
  deleted by S4.
- `VenueRackRepository.counts(venueID:)` / `.set(venueID:equipmentClass:count:)` and
  `Venue.equipmentClass(for:)` — declared S6, callers in `LobbyView`, `RoundPieces` and `SessionLiveView`.
- `RoutineLayering.apply(_:squadSwaps:selfScale:todaysScale:)` — declared S7, three callers
  (`SessionLiveView`, `SessionRunnerView`, `WarmUpReadinessTests`), one test file.
- `public.set_venue_rack_count(uuid, text, int)` and `public.claim_session_venue(uuid)` — one signature each
  (D1's comment, D3's body), asserted in D2 and D4, wrapped once each in S6 and S5.
- The two design-round ids appear identically in five places each: this plan's two tables, the enum case,
  the `ids` array, the capture method and the frame-map key.

**Gaps I could not close, named rather than papered over:**

- **The three riskiest assumptions, in order.** (1) **The owner's pick arrives inside this plan's window.**
  S4, the FLOOR's delta of 0, and the retirement all hang on it; constraint 7's contingency is what happens
  if it does not, and it is a worse outcome (two design-round ids live on master) rather than a broken one.
  (2) **A rack count maintained by whoever is present stays right.** Last write wins with an author, no
  dispute path, and no way to tell a correction from a mistake — decision 1 is the best answer available,
  not a safe one. (3) **`sessions.venue_id` will be NULL for most sessions for a long time**, because it
  needs a lifter who used the venue-hub check-in within 12 hours; until venue check-ins are common the cap
  is `nil` and the whole of decision 1 is inert in production. The pgTAP proves the mechanism; only usage
  proves the feature.
- **Nothing here proves the sound on hardware.** The simulator does not exercise the silent switch, the
  ringer, or a second audio app. The Spotify and push-to-talk checks are **manual**, listed in I2 and
  recorded in I3, and no test in this plan claims them.
- **The PR-firing change cannot be seen in a frame.** `app-pr-celebration` renders the same fixture whether
  S1 shipped or not, so S1's only proofs are `PRFiringTests` and the manual first-log check. A reviewer who
  reads the frames alone will not see it.
- **`GymSyncUITests` compiles only in the screenshots job** (constraint 19), so S3, S4 and S8 are the three
  tasks whose proof depends on a seed and a job the controller must re-run rather than assume.
- **The held migrations and this plan touch the same two tables.** B2's held `crew_week` reads
  `session_participants`; this plan adds a column to it. Additive columns do not conflict, and the fixture
  namespaces are disjoint by constraint 17 — but the two branches have never been merged together, and the
  first merge of either is where that assumption is actually tested.
