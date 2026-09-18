# One session body, a chosen style — Phase B1 — implementation plan

**For agentic workers.** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Every task below is
one subagent, one commit, one review. Do not batch tasks; do not start a Stream S task before the Stream D
gate it names has been applied to the live project. **The intended model is written beside every task** and
in the sequencing table (token addendum, 2026-09-13).

**Goal.** Give the crew's live workout the three styles the owner chose — **Rounds** with stations and
spotter mode, **Freestyle** with the shared rail, **Together** with one interval clock — on **one session
body**, with a **server-owned round counter** so every client agrees when a round closes; and take the
soundboard, the throwable plates and the sound reactions out of the app after archiving them at a tag.

**Architecture.** Three moves, in this order of dependence:

1. **The body that survives is the scheduled-session body.** The spec (§8 item 3) says "the crew frames …
   on the solo workout body" and "the retirement of `GroupSessionLiveView`". The context map found that
   these are the same object: a scheduled **solo** session already runs *inside* `GroupSessionLiveView` as a
   rotation of one (`SessionRunnerView.swift:149` → `SessionInProgressView.swift` (18 lines) →
   `GroupSessionLiveView(voicePersistsOnPop: true)`; the view's own comment at `:2818-2820` — "a solo
   rotation's turn never changes (self to self)"). `WorkoutSessionView.swift` (4,344 lines) is a **second**
   live body reached only from ad-hoc starts (`HomeView.swift:2208`, `DiscoverWorkoutDetailView.swift:186`,
   `RoutinesListView.swift:339`, `RootView.swift:463`, `CatalogHostView.swift:1872`) and it has none of the
   crew mechanics — no rotation, no voice dock, no presence, no heart-rate roster, no group recap.
   **So Phase B1 strips and renames the scheduled body rather than porting it onto the ad-hoc one.** S4
   deletes the spectate subtree, the BOARD scoreboard, the roster-failure legacy layout, the soundboard dock
   and the throw (≈1,650 lines); S5 moves what is left to
   `Features/Sessions/Live/SessionLiveView.swift`. `WorkoutSessionView` keeps the ad-hoc path for one more
   release — the same deviation Phase A shipped for `WarmUpPhaseView`, and the two close together in
   Phase C.
2. **Style is a frame over that one body.** `SessionInProgressView` (the 18-line router) becomes the
   **style router**: `rounds` keeps the turn gate and shows the round wait / spotter mode while it is not
   your turn; `freestyle` drops the gate and shows the shared rail; `together` drops the gate and shows one
   interval clock. Each presentation is a **separate view struct over plain values** — the shape Phase A
   proved with `WarmUpScreen` — so every catalog frame renders a presentation and never the live body.
3. **The round and the stations are the server's.** `sessions.round` advances **only** inside a new
   `public.advance_round` RPC that checks, server-side, that every present lifter has logged since
   `round_started_at`; `sessions.stations` is written **only** by `public.set_session_stations`, keyed by
   the exercise position so a re-mix is replayable. A `BEFORE UPDATE` trigger on `sessions` rejects direct
   client writes to those three columns and freezes `style` once lifting has started — the same
   engine-GUC idiom `engine_guard` uses (`20260714000001_session_engine_rpcs.sql:69-71`).

**Tech stack.** Swift 6 / SwiftUI (iOS 17 target), Supabase Postgres + PostgREST + RLS, pgTAP, XCTest +
XCUITest, Deno (edge functions), GitHub Actions (`ios.yml`, `backend.yml`), XcodeGen (`GymSyncApp/project.yml`
— `sources:` is a directory glob, so a new `Features/Sessions/Live/` folder needs **no** project.yml edit).

**Spec (the authority):** `docs/superpowers/specs/2026-09-12-group-session-and-lobby-design.md`. **Sections
§1, §3.3, §3.5, §3.6, §4, §4a, §5, §6, §7, §8 item 3 and §9a bind this plan.** §3.4 (the two change modes)
and §5's pump-check card are **Phase B2** and are quoted here only where B1 must not foreclose them. All
twenty-two owner decisions bind; decisions **1, 2, 6, 7, 8, 11, 13, 14, 15, 17** are the ones B1 builds.
Gate documents: the design language (`docs/superpowers/specs/2026-09-05-design-language.md`) and the
social-cards spec (`docs/superpowers/specs/2026-09-11-social-cards-design.md` §9.1 — the feed's reaction
vocabulary becomes emoji only). Round artefacts with file:line facts:
`.superpowers/sdd/2026-09-13-group-session-phase-b-plan/context-map.md` and the Phase A ledger
(`.superpowers/sdd/2026-09-12-group-session-phase-a-plan/progress.md`, `review-final.md`).
Format exemplar (the shape this plan copies): `docs/superpowers/plans/2026-09-12-group-session-phase-a-plan.md`.

**The reference frames.** Every production screen below is built to a catalog frame from the 2026-09-12
design round, now on master under `GymSyncApp/GymSync/Features/Sessions/Variations/` (DEBUG-only):

| frame | id | file | what production copies |
|---|---|---|---|
| 123 | `round-wait-v2` | `RoundVariationsV2.swift` | the round wait: two aligned station cards, the rest card with the recovery curve, THE SESSION · WHERE WE ARE, the Coach thread row |
| 114 | `round-skip-offer` | `RoundVariations.swift:251` | the hold threshold's quiet skip line and its copy |
| 128 | `round-spotter-v3` | `SessionVariationsV3.swift` | spotter mode: Cheer primary, Film beside it, the crew's live heart rates **with zone colours**, the Coach row |
| 117 | `together-clock` | `StyleVariations.swift:320` | Together: one interval clock, every lifter's heart rate on one timeline, coloured by zone (the **v1** render — owner decision 17 restored the colours that `-v2` removed) |
| 116 | `freestyle-rail` | `StyleVariations.swift:117` | Freestyle: the shared progress rail, the stretched rest, Coach's accessory suggestion |

**Production code must not import, reference or `#if DEBUG`-depend on the `Variations/` folder.** Every SV\*
type there is a DEBUG-only catalog fixture. The production views are built from the same shipped primitives
the SV\* wrappers use — `GSInitialsAvatar`, `GSSectionHeader`, `GSDivider`, `GSHeartRatePill`
(`GSComponents.swift:2376`), `.gs3DCard(cornerRadius:lipHeight:)`, `.gs3DCardStyle(...)`,
`GSPrimaryButtonStyle`, `PTTDockRow`, `Color.gsSuccess`, `GSMetrics.radiusMd`/`radiusSm`, `GSFont` — plus
Phase A's own production components in `Features/Sessions/SessionPieces.swift` (`SessionPlanCard`,
`CoachDoorRow`, `SessionStripModifier`, `CrewWeekStrip`).

---

## Base branch — read this first

**This plan forks from `origin/master` at `0843cfc`** (PR #70, the spec's decisions 21–22), which is
Phase A's merge (`c8fbea7`) plus two docs PRs. Verified on 2026-09-13 against `origin/master`, never a local
`master` ref:

```
git fetch origin
git log origin/master --oneline -1                             # 0843cfc
grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1           # FLOOR=134  (line 443)
python -c "import json;d=json.load(open('docs/design/frame-map.json'));print(len(d), max(v['frame'] for v in d.values()))"
                                                               # 90 135
grep -c '^    case ' GymSyncApp/GymSync/App/CatalogHostView.swift          # 112
grep -c 'captureCatalog(' GymSyncApp/GymSyncUITests/ScreenshotTests.swift  # 112
```

| | Stream D and Stream S, from `0843cfc` |
|---|---|
| base | `origin/master` `0843cfc` |
| `FLOOR` in `ios.yml:443` | **134** |
| frames taken | 1-135 |
| next free frame | **136** |
| `CatalogScreen` cases | 112 |
| `Features/Sessions/Variations/` | 9 files, **13** frame-bearing ids (112-119, 123-126, 128) |
| `sessions.style` / `.stations` / `.round` / `.round_started_at` | absent until D1 is applied |
| `soundboard_sounds` / `soundboard_favorites` / `private.owns_soundboard_sound` | present until D5 is applied |
| `sessions.state` CHECK | still 8 values (Phase A ruled the three dead ones not droppable **in Phase A**) |

---

## Global Constraints

These bind **every** task. A task that breaks one says so in its commit body, and why.

1. **One release branch, `feat/group-session-phase-b`, and this plan is its first commit.** Fork it from
   `origin/master` (verified above), commit this file, push. Every task below lands on that branch. One PR
   at the end (I3).

2. **Two streams, and only because their files are disjoint by path.**
   - **Stream D** touches `supabase/**` and `scripts/**` and nothing else.
   - **Stream S** touches `GymSyncApp/**`, `docs/design/**` and `.github/workflows/ios.yml` and nothing else.

   **S1-S13 run sequentially, in number order** — S4, S5, S6 and S11 all edit the same 6,060-line file, and
   two workers on one file is the gamble this rule exists to forbid. Stream D may run beside Stream S
   throughout, subject to constraint 8's gates. **At most two Opus agents at once** (one per stream);
   dispatch the long pole first.

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

7. **The FLOOR is `−N over master's FLOOR at integration`, never a literal.** This plan's N is **−4** (six
   production captures in, ten design-round captures out). A falling floor is the one case where the literal
   must be right — a floor above the real count fails every run — so **I1 counts the exported files in the
   last green artifact** before writing it.

8. **Migrations are gates.** `.github/workflows/backend.yml:24-27` runs `node scripts/run_pgtap.js` against
   the **live** `SUPABASE_DB_URL`; there is no `supabase db push` anywhere in CI. A pgTAP test for an object
   that has not been applied to project `chjkkwqwdlmaxacwglzm` **will fail**. So each migration task ends:
   **commit, stop, hand back.** The controller applies it live (Supabase MCP `apply_migration`), says
   "applied", and only then does the matching pgTAP task — and any Swift task that decodes the new column —
   start. Each commit body records the timestamp it was applied.

9. **THE IRREVERSIBLE GATE — the archive lands before the removal, and the removal before the drop.**
   Owner decision 8 and 14, in this exact order, no step skipped:
   1. **S0** creates the annotated tag `archive/soundboard-throwables-2026-09` on the last commit that still
      contains the implementation, **pushes it**, and proves it (`git ls-tree` lists the files at the tag);
      the controller **also exports the live rows** (`soundboard_sounds`, `soundboard_favorites`, and every
      `snd:%` row in `chat_message_reactions` / `post_reactions`) to
      `.superpowers/sdd/2026-09-13-group-session-phase-b-plan/soundboard-rows-<date>.json`. A tag archives
      code; it does not archive data.
   2. **S11 / S12** remove the code.
   3. **D5** — the drop migration — is **written only after S0's tag is on the remote and S11/S12 are
      pushed**. It is applied live by the controller like any other gate, and it cannot be undone.

   No task may reorder these. A drop applied before the tag is pushed is unrecoverable work.

10. **Never request HealthKit or LOCATION authorization outside their one permitted call site, and never
    from a test.** A raised sheet hung `build-test` for 45 minutes once. The permitted sites are
    `LobbyView.initiateCheckIn()` and `SessionRunnerView`'s check-in control (Phase A's N4, recorded).
    **No Phase B view may request either.** The heart-rate surfaces in S8/S9 read what
    `HeartRateBroadcastService` / `WatchConnectivityBridge` already publish; they never start a HealthKit
    query.

11. **No live repository, and no `Date.now`, reachable from a catalog builder.** Every `content_*` renders
    from fixture integers, strings and dates built from components. Every new production view in this plan
    is a **value-in view** (no repository of its own) or carries a `catalogFixture*` + `catalogSkipLoad`
    init in the `LobbyView` / `SocialTabView` shape, with `refresh()` returning immediately when
    `catalogSkipLoad` is set. Phase A's N3 — three lobby frames polling a live repository with a fixture
    UUID — is the defect this constraint exists to prevent; do not repeat it.

12. **Every report claim is verified against `git show <sha> --stat` and the CI artifact, not memory — and
    grep the CALL SITE of every new function before claiming it is live.** Download artifacts **into a fresh
    directory** (`gh run download -n app-screenshots` into a new folder; a half-extracted stale
    `app-screenshots/` is how a plan "proves" a frame it never rendered). A definition is not a feature:
    `git grep -n "<symbol>("` must show a caller outside the symbol's own file and its tests.

13. **Design rules, by number** (`2026-09-05-design-language.md`), with **one exception this phase turns
    on**:
    - **1** — two raised surfaces only: `.gs3DCard` to read, `.gs3DCardStyle`/`.gs3D` to press; furniture
      inside a raised box stays flat; strips are `surface` at 14 pt. The two radii are
      `GSMetrics.radiusMd` (cards) and `GSMetrics.radiusSm` (tiles), lips 6 pt on cards and 4-5 on tiles.
    - **2** — **accent is spent once per screen.** The round wait's accent is the **ring on the lifter whose
      turn it is**; spotter mode's is **CHEER**; Together's is the **clock's current interval**; Freestyle's
      is the **rail's own marker**. Gold stays streak/check-in only; `Color.gsSuccess` means done/present
      (the station card's logged tick); red is errors.
    - **4a, and it applies for the first time here** — **heart-rate zone colours are the one exception**
      (owner decision 17). Wherever a heart rate is shown — the recovery curve's endpoint, the spotter's
      crew rows, Together's timeline — the zone colour is allowed **and the zone word (`Z1`-`Z4`)
      accompanies it**, so the meaning never rests on colour alone. `GSHeartRatePill` already tints by
      `HeartRateZone`; the **word** is what the production rows must add. Nothing else in this plan gains a
      colour.
    - **3** — kickers 10-11 pt caps, 0.1-0.13 em tracking, muted; numbers tabular (`.monospacedDigit()`).
    - **9** — sentence case for sentences, caps for kickers; a button says exactly what happens. No
      decorative emoji; SF Symbols for glyphs.

14. **The frozen frames must not move.** Phase A's seven production frames (129-135) and the two Home
    canaries (`app-home-v3-08a-targets-above-calendar` frame 81, `-08b-targets-above-join` frame 82) are
    owner-approved compositions. No task in this plan edits `LobbyView.swift`'s composition except **S2**,
    which adds one card; S2's proof is that `app-session-lobby-waiting`, `-ready`, `-late` and
    `session-lobby-week` still render their approved content with the style card added where the plan says.
    "Unchanged" means 0 % of pixels differ below the status bar and above the home-indicator band.

15. **Do not rename an existing `CatalogScreen` raw value, and do not reuse a retired one.** Every
    production id in this plan is prefixed `session-`.

16. **Live-DB tests use the `TestSession` teardown factory and far-future rows.**
    `GymSyncTests/TestSession.swift` is the only place a test may create a session; register cleanup with
    `addTeardownBlock` **before** the write. Every date a live-DB test controls is **2099**.

17. **pgTAP conventions.** `BEGIN;` → `CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;` →
    `SELECT plan(N);` → a comment naming the migration under test and declaring the fixture block →
    `auth.users` inserted before `profiles` → role switching with `SET LOCAL role authenticated;
    SET LOCAL request.jwt.claim.sub = '<uuid>';` → `SELECT * FROM finish(); ROLLBACK;`.
    **Fixture-block namespaces already taken** inside `00000000-0000-4000-?000-00000000??xx`: `01xx`-`09xx`
    (a known collision at `09xx` — do not add a third), `0axx`, `0bxx`, `0cxx`, `0dxx`, `0exx`.
    **This plan takes `0fxx` (D2), `10xx` (D4), `11xx` (D6) and `12xx` (D8).**

18. **`XCTUnwrap(await …)` does not compile — bind, then unwrap.**

19. **The UI-test target's compile risk, named.** `GymSyncUITests` is built by the **screenshots** job
    (`ios.yml:326-329`), which runs **after** the seed step — `build-test` does **not** build it. Phase A
    shipped three pushes with `GymSyncUITests` uncompiled because the seed died on live-DB 504s. So a task
    that edits `ScreenshotTests.swift` (S13) is not proven by a green `build-test`: **its proof is a green
    screenshots job**, and the controller re-runs the job rather than assuming.

20. **Do not change the shipped session-engine contracts.** `start_session`, `advance_turn`,
    `mark_warmup_ready`, `start_lifting`, `evaluate_lateness`, `mark_no_shows`, the `check_in_state` CHECK
    and `session_participants`' four policies are frozen. This plan **adds** four columns, one trigger and
    two RPCs beside them, and **narrows** the `sessions.state` CHECK (D7) — which is the one shipped
    contract it does change, deliberately, with its blast radius written out in "The five data decisions".

21. **Push-to-talk, the heart-rate path and the PR sound are not collateral.** The soundboard removal
    (S11, S12) touches three shared services and must leave all three working:
    `Services/AudioSessionManager.swift` keeps its `.playback` + `.mixWithOthers` baseline (`:25-29`,
    `:87-97` — field report #39, "the PR sound pauses Spotify"; the **PR celebration** still depends on it);
    `Services/SessionBroadcastService.swift` subscribes to the soundboard **and** the reaction stream in one
    call (`:64-95`) — only the soundboard half leaves; `Services/BroadcastChannelDecision.swift` and
    `WatchConnectivityBridge` carry the **heart-rate** path beside the sound path (`:35`, `:44`) and B1's
    spotter and Together screens depend on it.

---

## File structure

### Created

| File | Responsibility | Task |
|---|---|---|
| `supabase/migrations/20260913000101_session_style_stations_round.sql` | `sessions.style`, `.stations`, `.round`, `.round_started_at` + CHECKs + comments | D1 |
| `supabase/tests/session_style_stations_round_test.sql` | pgTAP: the four columns, the CHECKs, the participant write of `style` | D2 |
| `supabase/migrations/20260913000102_session_round_engine.sql` | `private.session_round_guard` trigger, `public.advance_round`, `public.set_session_stations` | D3 |
| `supabase/tests/session_round_engine_test.sql` | pgTAP: the guard, the round rule, idempotency, the station shape | D4 |
| `supabase/migrations/20260913000104_soundboard_drop.sql` | the irreversible drop (rows, policies, CHECKs, function, two tables) | D5 |
| `supabase/tests/soundboard_absent_test.sql` | pgTAP: the tables and function are gone, `snd:%` is rejected by both reaction tables | D6 |
| `supabase/migrations/20260913000103_session_states_narrow.sql` | `sessions.state` CHECK down to five values | D7 |
| `supabase/tests/session_states_narrow_test.sql` | pgTAP: the five survive, the three throw | D8 |
| `GymSyncApp/GymSync/Models/SessionStyle.swift` | `SessionStyle`, `SessionStyleDefault.style(forExercises:)`, `SessionStyleCopy` | S1 |
| `GymSyncApp/GymSync/Models/SessionStations.swift` | `SessionStations`, `StationSplit.count/assign`, `RestMeasure.medians(from:)` | S1, S3 |
| `GymSyncApp/GymSync/Models/RoundHold.swift` | `RoundHold` — the floor, the multiplier, the cap, the one extension | S1 |
| `GymSyncApp/GymSyncTests/SessionStyleTests.swift` | the default law, the raw values, the copy | S1 |
| `GymSyncApp/GymSyncTests/SessionStationsTests.swift` | depth ≤ 3, the cap, every lifter once, the re-mix law | S3 |
| `GymSyncApp/GymSyncTests/RoundHoldTests.swift` | the floor, the multiplier, the cap, the extension, the median | S1 |
| `GymSyncApp/GymSync/Features/Sessions/Live/SessionLiveView.swift` | the surviving session body (moved from `GroupSessionLiveView.swift`) | S5 |
| `GymSyncApp/GymSync/Features/Sessions/Live/RoundPieces.swift` | `StationCard`, `RestRecoveryCard`, `CrewHeartRatesCard`, `SkipOfferLine` | S6, S7, S8 |
| `GymSyncApp/GymSync/Features/Sessions/Live/RoundWaitView.swift` | the round wait, value-in | S6 |
| `GymSyncApp/GymSync/Features/Sessions/Live/SpotterView.swift` | spotter mode, value-in | S8 |
| `GymSyncApp/GymSync/Features/Sessions/Live/TogetherClockView.swift` | Together: the clock and the HR timeline, value-in | S9 |
| `GymSyncApp/GymSync/Features/Sessions/Live/FreestyleRailView.swift` | Freestyle: the rail, the stretched rest, the accessory suggestion | S10 |
| `GymSyncApp/GymSync/Features/Sessions/Live/LiveFixtures.swift` | the hermetic worlds the five live ids render | S6, S8, S9, S10 |
| `GymSyncApp/GymSyncTests/RoundWaitCopyTests.swift` | every string the round wait and the skip line print | S6, S7 |

### Modified

| File | Change | Task |
|---|---|---|
| `GymSyncApp/GymSync/Models/Session.swift` | `WorkoutSession.style`, `.stations`, `.round`, `.roundStartedAt` | S1 |
| `GymSyncApp/GymSync/Models/SessionRepository.swift` | `setStyle`, `advanceRound`, `setStations` | S1 |
| `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift` | one card: the crew's style choice, above the dock | S2 |
| `GymSyncApp/GymSync/Services/LobbyRealtimeService.swift` | the session DB channel already watches `sessions` UPDATE (`:150`) — the style card re-reads on it; **no new subscription** | S2 |
| `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift` | S4 strips ≈1,650 lines; S5 moves the file; S6-S10 wire the presentations | S4, S5, S6-S10 |
| `GymSyncApp/GymSync/Features/Sessions/SessionInProgressView.swift` | the 18-line router becomes the **style router** | S5 |
| `GymSyncApp/GymSync/Features/Shop/ShopView.swift` | `rackCard` (the sound-rack door) leaves; PRO and Coaching stay | S11 |
| `GymSyncApp/GymSync/Features/You/YouTabView.swift` | the rack line in the SHOP widget's subtitle; the widget itself stays | S11 |
| `GymSyncApp/GymSync/Services/GuidanceTips.swift` | the `tour.you.rack` step (`:140-142`) leaves | S11 |
| `GymSyncApp/GymSync/Services/SessionBroadcastService.swift` | the soundboard stream leaves; **the reaction stream stays** | S11 |
| `GymSyncApp/GymSyncShared/WatchEnvelope.swift` | `soundboardTap` and `soundboardFavorites` leave; the HR kinds stay | S11 |
| `GymSyncApp/GymSync/Services/WatchConnectivityBridge.swift` | the sound path leaves; the HR path stays | S11 |
| `GymSyncApp/GymSync/Features/Social/PumpFeedView.swift` | `snd:` reaction pills and the attach path leave (`:492`, `:518`) | S12 |
| `GymSyncApp/GymSync/Features/Social/ChatView.swift`, `CrewRoomView.swift`, `Models/ChatMessage.swift` | the `snd:` half of the reaction vocabulary leaves | S12 |
| `GymSyncApp/GymSync/App/CatalogHostView.swift` | six ids in, ten out | S13 |
| `GymSyncApp/GymSyncTests/CatalogScreenTests.swift` | six ids in, ten out | S13 |
| `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` | six capture methods in, ten out | S13 |
| `docs/design/frame-map.json` | frames 136-141 in; 112-117, 123, 124, 126, 128 out | S13 |
| `supabase/functions/livekit-token/index.ts` + `test.ts` | `VOICE_ELIGIBLE_STATES` (`:88`) drops the three dead states | D7 |
| `scripts/seed_qa_fixtures.js` | `PRELIVE_STATES` (`:99`) and the states array (`:335`) drop them | D7 |
| `supabase/tests/rls_proposals_test.sql` | its fixture writes `lobby_open` instead of `editing` (`:19`) | D7 |
| `.github/workflows/ios.yml` | the FLOOR, once | I1, and only I1 |
| `docs/design/accepted-deviations.json` | six entries appended | I1 |

### Deleted

| File / symbol | Why |
|---|---|
| `GroupSessionLiveView.spectateFixedPage` (`:1811-2285`) and the spectating header/roster grid (`:3609-3849`) | Spec §5: the spectate subtree and its two-participant-only branches go with the rotation view they served. Spotter mode replaces them. |
| the roster-failure `legacyScrollLayout` (`:2295-2750`) | Reached only when the roster fails to load; the round wait is the state that composition was standing in for. Its stale MARK at `:2286` ("Warm-up page") goes with it — Phase A moved the warm-up out. |
| `soundboardDock` (`:3029-3139`), the soundboard state (`:61-174`) and the reaction actions' sound half (`:4948-5043`) | Owner decision 8. |
| `the throw` (`:5044-5143`), `PlateDragState` (`:127-133`), `DesignSystem/GSPlateToken.swift` | Throwables are soundboard sounds thrown as plates; the file's own v6 comment (`:5-13`) already says the metaphor "doesn't fit anymore". |
| `ROUND SCOREBOARD` (`:5144-5288`) | Spec §5: the BOARD goes. |
| `Features/Sessions/SoundLibrarySheet.swift`, `Features/Shop/MyRackView.swift`, `Features/Shop/WeeklyRack.swift`, `Models/Soundboard.swift`, `Services/SoundboardPlayer.swift`, `GymSyncWatch/SoundboardView.swift` | Owner decision 8; no caller survives S11. |
| `GymSyncTests/PlateClassTests.swift`, `PlateDeltaTests.swift`, `PlateMathTests.swift` | They test the throw's drag/class geometry only. **`Models/PlateMath.swift` and `PlateClass.swift` stay** — `Units.weightKicker` and the bar loader read them; grep before deleting anything in this row. |
| the ten design-round variation views (frames 112-117, 123, 124, 126, 128) + their four-part registrations, and the files that hold nothing else: `RoundVariations.swift`, `RoundVariationsV2.swift`, `StyleVariations.swift`, `StyleVariationsV2.swift`, `SessionVariationsV3.swift` | S13, and the reverse contract in constraint 6. `CardVariations.swift` (118, 119), `CardVariationsV2.swift` (125) and the two Kits **stay** — Phase B2 retires them. |

**Not deleted, deliberately:** `WorkoutSessionView.swift` and `WarmUpPhaseView.swift` (the ad-hoc path —
Phase C); `routine_proposals` / `routine_proposal_votes` and their policies, triggers and pgTAP suite (their
app code left in Phase A; `supabase/functions/account-deletion-cascade/index.ts` still references the
tables, so dropping them is its own change with its own edge-function deploy); `sessions.warmup_minutes`
(Phase A froze it); `Models/RecoveryBuffer.swift` — S6 **reuses** its `sparkline(barCount:)` for the
recovery curve, which is exactly what spec §6's "no new store" means.

---

## The five data decisions, stated

### 1. Which live body survives — decided, with the count

| | `GroupSessionLiveView` | `WorkoutSessionView` |
|---|---|---|
| lines | 6,060 | 4,344 |
| reached from | scheduled sessions, **solo and crew** (`SessionRunnerView:149` → `SessionInProgressView:16`) | ad-hoc starts only, five call sites |
| rotation / turn engine | yes (`:395-608`, `advance_turn`) | no |
| voice dock, presence, chat, kudos | yes | no |
| heart-rate roster | yes (`:4818-4860`) | no |
| group recap, PR celebration | yes (`:5766+`) | recap only |

**Ruling: the scheduled body survives.** Porting rotation, presence, voice and the HR roster onto
`WorkoutSessionView` would rebuild everything this phase depends on, in the same branch that is also adding
three styles — and the parked Start-in-lobby crash lives in the code being *deleted*, so deleting it is the
observation the spec asks for (§8 item 3). "Retiring `GroupSessionLiveView`" is therefore executed as
**strip (S4) → move and rename to `SessionLiveView` (S5) → route by style (S5)**, and
**`WorkoutSessionView` survives for one more release** as a named deviation.

### 2. The style default has no routine-type column — derive it, do not add one

Spec §6: *"a default per routine type computed client-side."* There is no routine type: `routines`
(`20260709000005_create_routines.sql:1-9`) has no type column. The only signals are per exercise —
`exercises.category` (`compound|isolation|cardio|mobility`, `20260709000002:5`) and
`routine_exercises.cardio_zone` / `cardio_minutes` (`20260814000009:11-12`). So `SessionStyleDefault`
(S1) is a pure function over the routine's rows:

```
if every non-mobility row is category == "cardio", OR any row has cardio_minutes != nil  ->  .together
otherwise                                                                                ->  .rounds
```

**Freestyle is never a default** — owner decision 1 names defaults for strength and for cardio/HIIT/biking
only; Freestyle is a choice the crew makes. No column is added; the spec said client-side and the data
supports client-side.

### 3. The station default cannot see the venue's racks — parameterise, do not fabricate

The owner's 2026-09-12 refinement is `min(ceil(n/3), racks at the venue)`. **Neither half of the second term
exists.** `venues.equipment` (`20260814000010_venue_equipment.sql:9`) is a text[] of equipment **classes**
(`barbell`, `dumbbell`, `machine`, …), not counts, and **no session→venue link exists at all** (grepped:
zero references to a venue in any `sessions` migration or in `Session.swift` / `CheckInService.swift`).

**Ruling:** `StationSplit.count(crew:equipmentCap:)` = `max(1, min(ceil(crew / 3), equipmentCap ?? Int.max))`,
and **every caller in B1 passes `nil`**. The cap is a real parameter with a real test; what B1 does not do
is invent a rack count from an equipment class list. Naming the venue for a session and counting its racks
is one column, one picker and an owner question — recorded in "What this plan does not decide".

### 4. The round counter and the station assignment are server-owned, and here is why a policy is not enough

`"organizer or participant can update session"` (`20260726000001…:172-178`) is
`USING (organizer_id = auth.uid() OR private.is_session_participant(...))` with **no column list**, so the
moment `round` exists, any participant can write any number into it. Spec §6 wants the opposite: *"the
server-owned round counter … so every client agrees when a round closes."* D3 therefore adds

- **`private.session_round_guard`** — `BEFORE UPDATE ON public.sessions`, rejecting any direct change to
  `round`, `round_started_at` or `stations` unless the engine GUC is set (`current_setting('gymsync.engine',
  true) = 'on'`, the exact idiom `engine_guard` uses), and rejecting a change to `style` once
  `lifting_started_at IS NOT NULL` (spec §1: "changeable in the lobby until Start");
- **`public.advance_round(p_session_id, p_expected_round)`** — SECURITY DEFINER, participant-gated, locks
  the session row, **no-ops when `p_expected_round <> round`** (`advance_turn`'s idempotency guard,
  `20260801000001:76-82`, verbatim reasoning: rotations wrap, so only a monotonic number is safe), and
  advances **only if every non-`no_show` participant has a non-penalty `set_logs` row with
  `logged_at >= round_started_at`**. That predicate is the whole point: a client cannot push the round
  forward early, and a client that crashes cannot hold it back — anyone's replay closes it once the
  condition is true;
- **`public.set_session_stations(p_session_id, p_exercise_position, p_stations)`** — SECURITY DEFINER,
  participant-gated, **idempotent on `p_exercise_position`** (if the stored assignment already names that
  position it is returned unchanged, so two clients re-mixing at the same exercise change cannot disagree),
  validating that no station is deeper than three and that every present participant appears exactly once.

`advance_turn` is **not** modified (constraint 20). The client that logs calls `advance_turn` as it does
today and then `advance_round`; the second call is cheap, safe to repeat, and safe to lose.

### 5. Sound reactions are rows, not a table — so the drop has four parts, and one of them is a new CHECK

`20260811000004_sound_reactions.sql` added **no table**. It added `private.owns_soundboard_sound`, two
RESTRICTIVE INSERT policies (one per reaction table), and it **widened `post_reactions_emoji_check`** to
admit `emoji LIKE 'snd:%'`. `chat_message_reactions` has **no emoji CHECK at all**
(`20260710000003_create_chat.sql:20-25`) — the restrictive policy is the only thing keeping unowned `snd:`
rows out. So D5 must:

1. `DELETE` every `emoji LIKE 'snd:%'` row from `chat_message_reactions` and `post_reactions` (exported by
   S0 first — constraint 9);
2. drop both `"sound reactions require ownership"` policies;
3. restore `post_reactions_emoji_check` to the emoji-only list **and add** a matching CHECK to
   `chat_message_reactions.emoji` — otherwise dropping the policy makes that column *more* permissive than
   it was before the soundboard existed;
4. `DROP FUNCTION private.owns_soundboard_sound`, then `DROP TABLE public.soundboard_favorites`,
   `public.soundboard_sounds`.

Storage objects under the sounds bucket are **not** dropped by the migration; the controller removes them
by hand after the drop is green (`scripts/cleanup_storage_orphans.js` is the existing tool). **Accepted
consequence:** testers still running an older TestFlight build lose the soundboard the moment D5 is applied
— which is what "tabled indefinitely" means, and the archive tag is how it comes back if the owner reverses.

### 6. The three dead states — Phase A's grep, and what B1 pays to close it

Phase A ruled `editing` / `voting` / `locked` not droppable **in Phase A** and handed the cost to Phase B
with the grep attached. It is still accurate, and it is four files plus the Swift read-side:

| Kind | Where |
|---|---|
| the CHECK | `20260709000006_create_sessions.sql:5-7` |
| a server trigger's deny-list | `20260803000002_set_logs_reject_prelive.sql:19` |
| an edge function's allow-list | `supabase/functions/livekit-token/index.ts:88` + `test.ts:451` |
| a pgTAP fixture that writes `'editing'` | `supabase/tests/rls_proposals_test.sql:19` |
| a QA seed that writes `'voting'` and `'locked'` | `scripts/seed_qa_fixtures.js:99, :335` |
| read-side bucketing, Swift | `SessionRepository.swift:477`, `LobbyView.swift:120,431`, `GroupSessionLiveView.swift:347`, `CrewRoomView.swift:621`, `GroupView.swift:407`, `SocialTabView.swift:645`, `SentryContext.swift:45` |

**Ruling: D7 narrows the CHECK and fixes the four non-Swift sites in the same commit.** The edge function
deploys **only from master** (`backend.yml:48`, `if: github.ref == 'refs/heads/master'`), so the allow-list
change is inert on the branch and deploys with the merge — after the CHECK is already applied, which is the
safe order (a state nothing can be in, still listed as voice-eligible, grants nothing). The **Swift**
bucketing sets are harmless once no row can hold the value; S13 removes them as mechanical cleanup and
proves it by grep.

---

## New catalog ids, the retirements, and the FLOOR

### In — six production ids, frames 136-141

| id | frame | title | renders | task |
|---|---|---|---|---|
| `session-style-choice` | 136 | Crew lobby — the crew picks the style | `LobbyView` over `LobbyFixtures.waiting` with the style card: three tappable rows (Rounds / Freestyle / Together), Rounds pre-selected as the routine's default, the one-line consequence under each | S13 |
| `session-round-wait` | 137 | Rounds, the round wait — two stations, the recovery curve, the plan | `RoundWaitView` over `LiveFixtures.roundWait`: RACK A (3, one ringed, one tick, one scale-down line) and RACK B (2) at equal height, the rest card with the elapsed clock beside the curve, THE SESSION · WHERE WE ARE, the Coach thread row, the gated foot | S13 |
| `session-round-skip` | 138 | Rounds — the hold threshold's quiet skip line | `RoundWaitView` over `LiveFixtures.roundHold`: the same screen with the skip line present, reading the owner's copy | S13 |
| `session-round-spotter` | 139 | Spotter mode — the crew's heart rates in their zone colours | `SpotterView` over `LiveFixtures.spotter`: who's to go, the crew's live HR rows (colour **and** the zone word), the Coach row, Cheer primary with Film beside it | S13 |
| `session-together-clock` | 140 | Together — one interval clock, four hearts on one timeline | `TogetherClockView` over `LiveFixtures.together` | S13 |
| `session-freestyle-rail` | 141 | Freestyle — the shared rail, one lifter ahead | `FreestyleRailView` over `LiveFixtures.freestyle`: the rail, the stretched rest, Coach's accessory suggestion as an Accept / Not today suggestion | S13 |

### Out — ten design-round ids the production frames replace

| id | frame | replaced by |
|---|---|---|
| `round-wait-a` | 112 | `session-round-wait` |
| `round-wait-b` | 113 | `session-round-wait` |
| `round-skip-offer` | 114 | `session-round-skip` |
| `round-spotter` | 115 | `session-round-spotter` |
| `freestyle-rail` | 116 | `session-freestyle-rail` |
| `together-clock` | 117 | `session-together-clock` |
| `round-wait-v2` | 123 | `session-round-wait` |
| `round-spotter-v2` | 124 | `session-round-spotter` |
| `together-clock-v2` | 126 | `session-together-clock` |
| `round-spotter-v3` | 128 | `session-round-spotter` |

**Staying for Phase B2:** `swap-consensus-card` (118), `pump-check-card-v2` (119),
`swap-consensus-card-v2` (125) — B2 builds their production frames and retires them, which empties
`Variations/` and lets the two Kit files go with them.

### The FLOOR

**`FLOOR` moves by `−4` against master's FLOOR at integration** — six production captures in, ten
design-round captures out. Against the base this plan verified (`134`), that is `134 → 130`. **The `−4` is
the invariant; the `130` is arithmetic I1 re-does on the day**, by counting the exported files in the last
green `app-screenshots` artifact. After S13: `CatalogScreen` = **108** cases, `captureCatalog(` = **108**,
`frame-map.json` = **86** entries, max frame **141**.

**No capture other than these sixteen moves count.** Three existing captures change *content*, and they are
this plan's best proofs because a fixture cannot fake them: **`app-lobby`** (the live account's real
`LobbyView`) gains the style card; **`app-tab-you`** loses the rack line from the SHOP widget's subtitle;
**`app-pump-feed-post`** loses its sound-reaction pill if the seeded post carries one (S12 checks the seed
and says which).

---

## Sequencing

```
 origin/master 0843cfc  (FLOOR 134, frames 1-135)
        │
        ├──► STREAM D · the data  (supabase/**, scripts/**)
        │      D1 columns ──[GATE]──► D2 pgTAP
        │      D3 round engine ──[GATE]──► D4 pgTAP
        │      D7 dead states ──[GATE]──► D8 pgTAP
        │      D5 soundboard DROP  ── requires S0 tag pushed AND S11+S12 pushed ──[GATE]──► D6 pgTAP
        │
        └──► STREAM S · the app (ONE worker at a time, in order)
               S0  the archive tag + the row export           (controller)
               S1  THE INTERFACE: style, stations, hold        Opus
               S2  the crew picks the style, in the lobby      Sonnet   ← needs D1 applied
               S3  the station split and the re-mix            Opus     ← needs D3 applied
               S4  the strip: spectate, BOARD, dock, the throw Opus
               S5  one body, and the style router              Sonnet
               S6  the round wait                              Opus
               S7  the hold threshold, the skip, the minute    Sonnet
               S8  spotter mode                                Sonnet
               S9  Together                                    Opus
               S10 Freestyle                                   Sonnet
               S11 the soundboard leaves the app               Sonnet
               S12 the reaction vocabulary becomes emoji only  Sonnet
               S13 the catalog: six in, ten out                Sonnet
                          │
                          ▼
                   INTEGRATION  (I1 Sonnet · I2 controller · I3 controller)  →  ONE PR, with proof cards
```

**The hard edges.** S2 writes `sessions.style` (needs D1 applied). S3 calls `set_session_stations` and S6/S7
read `sessions.round` (need D3 applied). S5 must follow S4 (moving a file mid-strip loses the diff). S6-S10
must follow S5 (they mount inside the router). S11/S12 must follow S0 and precede D5 (constraint 9). S13 is
last in Stream S because it retires the variation views S6-S10 were built against — retire them only once
production renders.

**Model ladder, per the 2026-09-13 token addendum.** Opus for the multi-file streams and the judgment calls
(S1, S3, S4, S6, S9, and D3/D5 in Stream D). Sonnet 5 for everything mechanical from an exact spec — the
lobby card, the router move, the copy-and-constants tasks, the removals, the catalog tail, I1. Never Fable,
never `fork`. **Two Opus at once, maximum, one per stream.**

---

# STREAM D — the data

Four migrations, four pgTAP suites. `supabase/**` and `scripts/**` only. Every migration is a **gate**
(constraint 8); D5 is additionally bound by the irreversible-gate rule (constraint 9).

### D1 — `style`, `stations`, `round`, `round_started_at` — **S** · Sonnet

**File (new):** `supabase/migrations/20260913000101_session_style_stations_round.sql`

Spec §6, owner decisions 1 and 2. Four columns on `public.sessions`, no policy (the shipped
organizer-or-participant UPDATE policy already grants the write; D3's trigger is what narrows it):

```sql
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS style text NOT NULL DEFAULT 'rounds'
    CHECK (style IN ('rounds','freestyle','together')),
  ADD COLUMN IF NOT EXISTS stations jsonb,
  ADD COLUMN IF NOT EXISTS round integer NOT NULL DEFAULT 1 CHECK (round >= 1),
  ADD COLUMN IF NOT EXISTS round_started_at timestamptz;
```

Each column carries a `COMMENT ON COLUMN` naming spec §6 and the plan task, in D1's voice:
`style` — set at scheduling from the routine's own exercises, editable by any participant until Start
(`lifting_started_at`), after which `private.session_round_guard` freezes it; `stations` — the CURRENT
exercise's assignment only, written solely by `public.set_session_stations`, shape
`{"exercise_position": int, "stations": [{"name": text, "lifter_ids": [uuid], "turn_order": [uuid]}]}`,
transient by design (spec §6: "a separate table is not needed"); `round` — the server-owned counter,
advanced only by `public.advance_round`; `round_started_at` — stamped by the same RPC, and the timestamp the
round-close predicate measures sets against. Defaults chosen so **every shipped row reads as a one-station
Rounds session at round 1**, which is what the shipped rotation already is.

**Interfaces** — *consumes:* `public.sessions`. *Produces:* four columns, decoded by S1's `WorkoutSession`,
guarded by D3.

**TDD steps.** 1. Write the migration. 2. **Commit, stop, hand back** — the controller applies it and
records the timestamp. 3. The controller verifies:
`SELECT column_name, data_type, column_default FROM information_schema.columns WHERE table_name='sessions' AND column_name IN ('style','stations','round','round_started_at');`
→ four rows. 4. Commit: `feat(session): style, stations, round and round_started_at on sessions` + the trailer.

**Proves:** the four columns exist live, so D2, S1 and S2 can address them.

---

### D2 — pgTAP for the four columns — **M** · Sonnet

**File (new):** `supabase/tests/session_style_stations_round_test.sql`. **Fixture block `0fxx`.** `plan(9)`.
Fixture: one `lobby_open` session, organizer A, participants B and C, non-participant D.

1. `has_column` × 4 (`style`, `stations`, `round`, `round_started_at`).
2. `col_type_is('sessions','style','text')`, `col_type_is('sessions','stations','jsonb')`,
   `col_type_is('sessions','round','integer')`.
3. As B: `UPDATE sessions SET style='together' WHERE id=<s>` **succeeds** and reads back `together` — the
   crew chooses, not only the organizer (owner decision 1).
4. As B: `style='sprints'` **throws** (the CHECK).
5. A fresh session's `round` reads **1** and `stations` reads **NULL**.

**TDD steps.** Write, run locally if `SUPABASE_DB_URL` is available
(`node scripts/run_pgtap.js supabase/tests/session_style_stations_round_test.sql`), else push.
Commit: `test(session): pgTAP for style, stations, round` + the trailer.

**Proves:** the columns are the shape S1 decodes and any participant may set the style before Start.

---

### D3 — the round engine: one trigger, two RPCs — **L** · Opus

**File (new):** `supabase/migrations/20260913000102_session_round_engine.sql`

Three objects, in this order. Write the header comment first: it states decision 4 above in the migration's
own voice (why a policy is not enough; why the guard copies `engine_guard`'s GUC idiom; why `advance_turn`
is untouched).

**(a) `private.session_round_guard()` + `BEFORE UPDATE ON public.sessions`.** Returns `NEW` unchanged when
`current_setting('gymsync.engine', true) = 'on'`. Otherwise: raise `P0001` `'round, round_started_at and
stations are engine-owned'` if any of the three is `DISTINCT FROM` its OLD value; raise `P0001`
`'the style is fixed once lifting has started'` if `NEW.style IS DISTINCT FROM OLD.style AND
OLD.lifting_started_at IS NOT NULL`. Nothing else is guarded — this trigger must not become a second
authorization layer.

**(b) `public.advance_round(p_session_id uuid, p_expected_round integer DEFAULT NULL) RETURNS integer`**,
SECURITY DEFINER, `SET search_path = public`. Body, in order:

1. `SELECT state, round, round_started_at INTO … FROM public.sessions WHERE id = p_session_id FOR UPDATE;`
2. **Idempotency first, before authorization** — `IF p_expected_round IS NOT NULL AND p_expected_round <>
   v_round THEN RETURN v_round; END IF;` with `advance_turn`'s comment adapted: a replayed close is sent by
   whoever logged last, and by the time it drains the round may already have moved; a mismatch means
   "already handled", which is success.
3. Authorization: `IF NOT private.is_session_participant(p_session_id, auth.uid()) THEN RAISE EXCEPTION
   'not a participant of this session' USING ERRCODE='P0001'; END IF;`
4. `IF v_state <> 'in_progress' THEN RAISE EXCEPTION 'session is not in progress' USING ERRCODE='P0001';
   END IF;`
5. **The round-close predicate** — return `v_round` unchanged unless

   ```sql
   NOT EXISTS (
     SELECT 1 FROM public.session_participants sp
      WHERE sp.session_id = p_session_id
        AND sp.check_in_state <> 'no_show'
        AND NOT EXISTS (
          SELECT 1 FROM public.set_logs sl
           WHERE sl.session_id = p_session_id
             AND sl.user_id    = sp.user_id
             AND sl.is_penalty = false
             AND sl.logged_at >= COALESCE(v_round_started_at, '-infinity'::timestamptz)))
   ```

   — every present lifter has a non-penalty set since the round opened. Burpee/penalty rows are excluded on
   purpose: a penalty is not a set of the round.
6. `PERFORM set_config('gymsync.engine','on',true);`
   `UPDATE public.sessions SET round = round + 1, round_started_at = now() WHERE id = p_session_id;`
   `PERFORM set_config('gymsync.engine','',true);` — reset inside the same transaction, exactly as
   `evaluate_lateness` does, so a pgTAP transaction cannot inherit the bypass.
7. `RETURN v_round + 1;`

**(c) `public.set_session_stations(p_session_id uuid, p_exercise_position integer, p_stations jsonb)
RETURNS jsonb`**, SECURITY DEFINER. Locks the row; participant-gated; **returns the stored value unchanged
when `stations->>'exercise_position'` already equals `p_exercise_position`** (the re-mix is replayable and
two clients cannot disagree); otherwise validates that `p_stations` is an array of objects each with
`name`, `lifter_ids`, `turn_order`; that no `lifter_ids` array is longer than **3**
(`RAISE 'a station may not be deeper than three'`); and that the union of `lifter_ids` equals the set of
non-`no_show` participants exactly once each (`RAISE 'every present lifter belongs to exactly one
station'`). Then writes `jsonb_build_object('exercise_position', p_exercise_position, 'stations',
p_stations)` under the engine GUC and returns it.

`GRANT EXECUTE ON FUNCTION public.advance_round(uuid, integer), public.set_session_stations(uuid, integer,
jsonb) TO authenticated;`

**Interfaces** — *consumes:* D1's columns, `session_participants`, `set_logs`. *Produces:* the two RPCs S1
wraps and S3/S6 call.

**TDD steps.** 1. Write it. 2. **Commit, stop, hand back** for the live apply. 3. Commit:
`feat(session): the round engine — a guard, advance_round, set_session_stations` + the trailer.

**Proves:** the round advances only when the server says the round is over, and the stations are validated
where they are written.

---

### D4 — pgTAP for the round engine — **M** · Sonnet

**File (new):** `supabase/tests/session_round_engine_test.sql`. **Fixture block `10xx`.** `plan(12)`.
Fixture: one `in_progress` session, `round_started_at = now() - interval '10 minutes'`, participants A
(organizer), B, C; a fourth row D marked `no_show`; a non-participant E.

1. As A, a direct `UPDATE sessions SET round = 9` **throws** `P0001`.
2. As A, a direct `UPDATE sessions SET stations = '{}'::jsonb` **throws**.
3. As A, `UPDATE sessions SET style='freestyle'` on a session with `lifting_started_at` set **throws**.
4. Same UPDATE on a session with `lifting_started_at IS NULL` **succeeds**.
5. With only A and B having logged, `advance_round(<s>)` returns **1** and the row still reads 1.
6. After C logs, `advance_round(<s>)` returns **2** and `round_started_at` has moved.
7. D's absence does not block the close — the `no_show` row is excluded (assert with D having logged
   nothing).
8. A **penalty-only** row for C does not count as C's set (insert `is_penalty = true`, assert no close).
9. `advance_round(<s>, 1)` after the close returns **2** and changes nothing (idempotency).
10. As E (non-participant), `advance_round` **throws** `'not a participant of this session'`.
11. `set_session_stations` with a four-deep station **throws**.
12. `set_session_stations` called twice with the same `p_exercise_position` returns the identical jsonb and
    writes once.

Commit: `test(session): pgTAP for the round engine — the guard, the close rule, idempotency` + the trailer.

**Proves:** the counter cannot be forged, cannot be double-advanced, and closes exactly when every present
lifter has logged.

---

### D7 — the three dead states leave the CHECK — **M** · Sonnet

**Files:** `supabase/migrations/20260913000103_session_states_narrow.sql` (new);
`supabase/functions/livekit-token/index.ts` + its `test.ts`; `scripts/seed_qa_fixtures.js`;
`supabase/tests/rls_proposals_test.sql`.

Runs **after** D1 and D3 are applied (it re-declares a CHECK on the same table; ordering keeps the migration
history readable). The migration:

1. A header comment carrying decision 6's table verbatim — this is the change Phase A costed and deferred.
2. `UPDATE public.sessions SET state = 'lobby_open' WHERE state IN ('editing','voting','locked');` — with a
   comment saying the expected count is **zero in production and non-zero on the QA project**, because the
   seed writes them; the UPDATE is what makes the CHECK swap safe either way.
3. `ALTER TABLE public.sessions DROP CONSTRAINT sessions_state_check;`
   `ALTER TABLE public.sessions ADD CONSTRAINT sessions_state_check CHECK (state IN
   ('scheduled','lobby_open','in_progress','completed','abandoned'));`

Then, in the same commit: `VOICE_ELIGIBLE_STATES` (`index.ts:88`) becomes
`["lobby_open", "in_progress"]` and `test.ts:451`'s assertion follows it; `seed_qa_fixtures.js:99`'s
`PRELIVE_STATES` becomes `['scheduled','lobby_open']` and `:335`'s array drops `'voting'`/`'locked'`
(**keep six rows** — replace them with `'abandoned'` and a second `'completed'` so
`app-group-sessions` still photographs six state glyphs and the docket's "seed an abandoned session" note is
closed in passing); `rls_proposals_test.sql:19` writes `'lobby_open'`.

**TDD steps.** 1. Write all four. 2. **Commit, stop, hand back** — the controller applies the migration and
re-runs the seed. 3. Commit: `feat(session): the dead states leave the CHECK, the seed and the voice
allow-list` + the trailer.

**Proves:** no session can hold a state no code sets, and the four writers of those states agree.

---

### D8 — pgTAP for the narrowed CHECK — **S** · Sonnet

**File (new):** `supabase/tests/session_states_narrow_test.sql`. **Fixture block `12xx`.** `plan(4)`:
inserting each of `editing`, `voting`, `locked` **throws** (three `throws_ok`), and `lobby_open` succeeds.
Commit: `test(session): pgTAP for the narrowed session state CHECK` + the trailer.

---

### D5 — the soundboard drop — **M** · Opus · **IRREVERSIBLE**

**File (new):** `supabase/migrations/20260913000104_soundboard_drop.sql`

**Do not write this file until the controller has confirmed all three of:** S0's tag is on the remote; S0's
row export exists in the workspace; S11 and S12 are pushed. The task's first step is to state those three
facts in the report with their shas.

The migration, in decision 5's order, each step commented with what it undoes and where that thing came
from:

```sql
DELETE FROM public.chat_message_reactions WHERE emoji LIKE 'snd:%';
DELETE FROM public.post_reactions        WHERE emoji LIKE 'snd:%';

DROP POLICY IF EXISTS "sound reactions require ownership" ON public.chat_message_reactions;
DROP POLICY IF EXISTS "sound reactions require ownership" ON public.post_reactions;

ALTER TABLE public.post_reactions DROP CONSTRAINT IF EXISTS post_reactions_emoji_check;
ALTER TABLE public.post_reactions ADD  CONSTRAINT post_reactions_emoji_check
  CHECK (emoji IN ('💪', '🔥', '👏', '🏆', '⚡'));

-- chat_message_reactions never had a CHECK; the restrictive policy was the
-- only gate. Dropping it without this would leave the column MORE permissive
-- than before the soundboard shipped.
ALTER TABLE public.chat_message_reactions ADD CONSTRAINT chat_message_reactions_emoji_check
  CHECK (emoji NOT LIKE 'snd:%');

DROP FUNCTION IF EXISTS private.owns_soundboard_sound(uuid, text);
DROP TABLE IF EXISTS public.soundboard_favorites;
DROP TABLE IF EXISTS public.soundboard_sounds;
```

Note in the header that `chat_message_reactions` keeps its open vocabulary otherwise (it has always accepted
any emoji text) — this CHECK closes exactly the `snd:` door and nothing else, which is the smallest change
that leaves the table no looser than it was.

**TDD steps.** 1. Confirm the three preconditions in writing. 2. Write the migration. 3. **Commit, stop,
hand back.** The controller applies it, then deletes the storage objects by hand. 4. Commit:
`feat(soundboard): drop the tables, the ownership function and the sound-reaction rows` + the trailer, with
the tag name and the export path in the body.

**Proves:** the subsystem is gone from the database, and the reaction vocabulary is emoji only on both
tables.

---

### D6 — pgTAP for the absence — **S** · Sonnet

**File (new):** `supabase/tests/soundboard_absent_test.sql`. **Fixture block `11xx`.** `plan(5)`:
`hasnt_table('public','soundboard_sounds')`, `hasnt_table('public','soundboard_favorites')`,
`hasnt_function('private','owns_soundboard_sound')`, an INSERT of `emoji = 'snd:airhorn'` into
`post_reactions` **throws**, and the same into `chat_message_reactions` **throws**.
Commit: `test(soundboard): pgTAP proving the tables, the function and the snd: vocabulary are gone` + the
trailer.

---

# STREAM S — the app

Thirteen tasks plus S0, in order, one worker at a time (constraint 2).

### S0 — the archive tag, and the rows — **S** · controller

Not an implementer task: the controller does it, because it pushes a tag and reads live data.

1. `git tag -a archive/soundboard-throwables-2026-09 <sha> -m "…"` where `<sha>` is the branch tip
   **immediately before** S11's commit — the last commit that still contains the implementation. In practice
   that is the tip after S10.
2. `git push origin archive/soundboard-throwables-2026-09`.
3. Prove it: `git ls-tree -r archive/soundboard-throwables-2026-09 --name-only | grep -iE
   "Soundboard|SoundLibrary|GSPlateToken|MyRackView|WeeklyRack"` lists **nine or more** files, and
   `git tag -l archive/soundboard-throwables-2026-09` prints on a fresh clone.
4. Export the rows (Supabase MCP, read-only) to
   `.superpowers/sdd/2026-09-13-group-session-phase-b-plan/soundboard-rows-2026-09-13.json`:
   `soundboard_sounds`, `soundboard_favorites`, and `SELECT * FROM public.chat_message_reactions WHERE
   emoji LIKE 'snd:%'` / the same on `post_reactions`. Record the four row counts in the ledger.

**Deviation, recorded:** spec §5 named the tag `archive/soundboard-2026-09`; the controller's brief
(2026-09-13) names it `archive/soundboard-throwables-2026-09` because the throwables are archived with it
and the plate token is not a soundboard file by name. The plan uses the brief's name; I3 records the
change.

**Proves:** the implementation is recoverable from a pushed ref, and the rows are recoverable from a file,
before anything is deleted.

---

### S1 — THE INTERFACE: style, stations, the hold — **M** · Opus

**Files (new):** `Models/SessionStyle.swift`, `Models/SessionStations.swift`, `Models/RoundHold.swift`,
`GymSyncTests/SessionStyleTests.swift`, `GymSyncTests/RoundHoldTests.swift`.
**Files (modified):** `Models/Session.swift`, `Models/SessionRepository.swift`.

The values every later task types against. Nothing here renders; everything here is tested.

```swift
enum SessionStyle: String, Codable, CaseIterable, Sendable { case rounds, freestyle, together }
```
plus `SessionStyleCopy` — for each case a `title` (`Rounds` / `Freestyle` / `Together`), a `line` (the
consequence, sentence case, one line each: *"One set each. The round closes when the last lifter logs."* /
*"Own pace, one shared rail — you finish together."* / *"One clock for everyone. No turns."*) and a
`glyph` (SF Symbol). One spelling, asserted by a copy test.

`SessionStyleDefault.style(forExercises rows: [(category: String, cardioMinutes: Int?)]) -> SessionStyle` —
decision 2's rule, with tests for: all-cardio → `.together`; any `cardioMinutes` → `.together`; a strength
routine → `.rounds`; mobility-only rows ignored; an **empty** routine → `.rounds` (a crew with no plan is a
rack crew).

`SessionStations` — `Codable`, `Equatable`, snake_case coding keys matching D1's jsonb exactly
(`exercise_position`, `stations`, `name`, `lifter_ids`, `turn_order`), with a round-trip test against a
literal JSON string copied from D1's column comment. **The JSON literal in the test is the contract**; if
D3's validation and this decoder ever disagree, the test says so.

`StationSplit.count(crew: Int, equipmentCap: Int?) -> Int` — decision 3's formula, tested at
crew 1/3/4/5/6/7 with `nil` and with caps 1 and 2.

`RoundHold` — the constants in **one** place (spec §9a, owner decision 11): `floorSeconds = 90`,
`multiplier = 1.5`, `capSeconds = 180`, `extensionSeconds = 60`;
`threshold(medianRestSeconds:) -> TimeInterval = min(max(90, 1.5 × median), 180)`; and
`RestMeasure.medians(from logs: [SetLog], since: Date) -> [UUID: TimeInterval]` — per-lifter median of the
gaps between consecutive `loggedAt` values, the input both the hold threshold and S3's re-mix read. Tests:
a median of 40 s → 90 s (the floor wins); 80 s → 120 s; 200 s → 180 s (the cap wins); one log → no median;
the extension applies once.

`WorkoutSession` gains `style: SessionStyle`, `stations: SessionStations?`, `round: Int`,
`roundStartedAt: Date?` with the existing decoder's snake_case convention; `SessionRepository` gains
`setStyle(sessionID:style:)` (a PostgREST PATCH), `advanceRound(sessionID:expectedRound:) async throws ->
Int` and `setStations(sessionID:exercisePosition:stations:) async throws -> SessionStations` (both RPC
calls, in `advanceTurn`'s idiom at `SessionRepository.swift:823`).

**TDD steps.** Write the tests first (they are pure), then the types, then the repository methods (which no
test calls — constraint 12 is satisfied by S2/S3/S6 being their call sites, not by a test).
Commit: `feat(session): the style, station and round-hold interface` + the trailer.

**Proves:** every later task has one spelling to type against, and the three rules the owner pinned are
pinned in code with their numbers.

---

### S2 — the crew picks the style, in the lobby — **M** · Sonnet · **needs D1 applied**

**File (modified):** `Features/Sessions/LobbyView.swift` (+ `LobbyFixtures.swift` for the frame).

One card, between "how the crew feels" and THE CREW'S WEEK, in Phase A's own card idiom
(`.gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)`, `GSSectionHeader("HOW THIS SESSION MOVES")`):
three rows, one per `SessionStyle`, each a tappable flat row inside the card (design rule 1 — furniture
inside a raised box stays flat) showing the title, the consequence line and a selected mark
(`checkmark.circle.fill` in `Color.gsSuccess`, never a second accent — the lobby's accent is Start).

- The selected value is `currentSession.style`; the card's first paint uses it, not a local default.
- The **default** is applied once, by the organizer's client only, when `session.style` has never been set
  away from `rounds` **and** the routine's rows say otherwise: call
  `SessionStyleDefault.style(forExercises:)` over the plan rows the lobby already loaded and, if it differs,
  `SessionRepository.setStyle`. Guard it with the same one-shot `@State` flag idiom the consensus Start uses
  so a re-render cannot re-write it.
- A tap on a row calls `setStyle` and optimistically updates; the existing `session:{id}:db` channel
  (`LobbyRealtimeService.swift:147-157`) already watches `sessions` UPDATE, so crewmates see the change with
  **no new subscription** (constraint: do not add one).
- After Start the card is not rendered at all — `lifting_started_at != nil` is the same gate D3's trigger
  enforces server-side, so the UI never offers a write the server will reject.
- `catalogSkipLoad` short-circuits the default write (constraint 11): a catalog build must not PATCH a
  fixture UUID.

`LobbyFixtures.waiting` gains `style: .rounds` so frame 136 renders Rounds selected with the other two
readable.

**TDD steps.** 1. `SessionStyleTests` already pins the copy. 2. Add `LobbyStyleCardTests` asserting the
one-shot default rule as a pure function (`shouldApplyDefault(current:derived:hasApplied:)`) — extract that
predicate rather than testing the view. 3. Read `LobbyView` end to end before editing; it is 1,896 lines and
has hit "unable to type-check this expression in reasonable time" twice — put the card in its own
`@ViewBuilder private var styleCard` rather than inlining it in the scroll body.
Commit: `feat(lobby): the crew picks the style — rounds, freestyle or together` + the trailer.

**Proves:** the style is a crew decision written to the row the live body reads, and frame 136 shows it.

---

### S3 — the station split and the re-mix — **L** · Opus · **needs D3 applied**

**Files:** `Models/SessionStations.swift` (extended), `GymSyncTests/SessionStationsTests.swift` (new),
and the caller in the live body (S5's file, so S3 lands **after** S5 in the file but is written against the
same symbols — sequence it here because S4/S5 are pure deletions and moves; if the controller reorders, S3
moves with them).

`StationSplit.assign(lifters: [UUID], count: Int, restMedians: [UUID: TimeInterval], previous:
SessionStations?) -> [[UUID]]` — owner decision 2, spec §3.3:

- depth never exceeds **3** (assert for crews 1…12);
- every lifter appears **exactly once** (assert as a set equality, not a count);
- **the re-mix law**, spec §3.3's "re-mixes only while averages are close": compute the spread
  `max(median) − min(median)` over the lifters that have a median. **Spread ≤ 45 s** → *rotate*: deal the
  lifters into stations from the previous assignment shifted by one, so different people rest together at
  every exercise change. **Spread > 45 s** → *pair by rest*: sort by median and deal in blocks, so the long
  resters wait together and the short resters are not held up. Lifters with no measured rest yet sort to the
  middle. `RoundHold.remixSpreadSeconds = 45` lives beside the other constants and is the only place the
  number appears.
- **turn order is fixed within an exercise** (owner decision 6): `assign` returns the station arrays in turn
  order, and the caller writes them once per exercise position and never again — `set_session_stations`'s
  idempotency on `p_exercise_position` is what enforces that server-side.

The caller: in the live body, when the current exercise position changes and the crew is larger than three,
compute the medians from `allSessionSets` (the uncapped, `logged_at ASC` array the body already holds —
`GroupSessionLiveView.swift:828`'s own doc comment says it is the one to use), call `assign`, then
`SessionRepository.setStations`. On failure, keep the previous assignment and log — a station re-mix that
fails must never block a round.

**TDD steps.** Tests first: eleven cases covering depth, membership, both re-mix branches, the empty
`previous`, and a crew of 3 (one station, no re-mix). Then the function, then the call site, then
`git grep -n "StationSplit.assign("` to prove the caller exists outside the tests.
Commit: `feat(session): the station split — never deeper than three, re-mixed by measured rest` + the
trailer.

**Proves:** a crew of five lifts as three and two, and the pairs change at each exercise while the crew's
rests stay close.

---

### S4 — the strip: spectate, BOARD, the dock, the throw — **L** · Opus

**File (modified):** `Features/Sessions/GroupSessionLiveView.swift` — deletions only, ≈1,650 lines.

Delete, by MARK, verifying each has no surviving caller before it goes:

| what | lines |
|---|---|
| Sister page: spectating | `:1811-2285` |
| the roster-failure `legacyScrollLayout` and its stale warm-up MARK | `:2286-2750` |
| Soundboard Dock | `:3029-3139` |
| Spectating header card | `:3609-3679` |
| Roster grid (spectating) | `:3680-3849` |
| Soundboard & Reaction Actions — **the sound half only** | `:4948-5043` |
| The throw | `:5044-5143` |
| ROUND SCOREBOARD | `:5144-5288` |
| the soundboard/broadcast `@State` block | `:61-174`, the sound members only |
| `PlateDragState` | `:127-133` |

Then `arenaBase` (`:2754-2769`) collapses from a three-way switch to **`myTurnFixedPage` only** — the other
two arms are gone. The reaction pills, the chat sheet, the voice mixer, the watch bridge, the HR roster,
the hot-swap flow, the set feed, the recap payload and the pump-check context all **stay**.

**The rule for this task:** delete nothing whose only evidence of deadness is that it looks unused. For each
symbol removed, the report carries `git grep -n "<symbol>"` output showing the remaining hits are the
deletion itself. The three plate test files go **only** if `PlateMath`/`PlateClass` keep their other
callers (`Units.weightKicker`, the bar loader) — grep and say so.

**Interfaces** — *consumes:* nothing new. *Produces:* a file S5 can move without carrying dead weight.

**TDD steps.** No new tests; the existing `GymSyncTests` suite must stay green and
`SessionEngineTests`/`WatchConnectivityBridgeTests` are the ones most likely to notice a wrong deletion.
Commit: `refactor(session): the spectate subtree, the BOARD, the dock and the throw leave the live view` +
the trailer, with the before/after `wc -l`.

**Proves:** the file that becomes the one session body carries only what the one session body needs — and
the parked Start crash's two leading hypotheses are deleted rather than debugged.

---

### S5 — one body, and the style router — **M** · Sonnet

**Files:** `Features/Sessions/GroupSessionLiveView.swift` → `Features/Sessions/Live/SessionLiveView.swift`
(git mv + rename the type); `Features/Sessions/SessionInProgressView.swift` (rewritten).

1. `git mv` the file into `Features/Sessions/Live/` and rename the type `GroupSessionLiveView` →
   `SessionLiveView` **everywhere** (`git grep -n "GroupSessionLiveView"` must return only doc comments
   afterwards, and those get re-pointed in the same commit). The initializer keeps its two arguments
   (`session:voicePersistsOnPop:`) plus a new `style: SessionStyle` with **no default** — an explicit
   argument at the one call site is what makes the router readable.
2. `SessionInProgressView` becomes the style router — the same 20-line shape, one `switch`:

   ```swift
   switch session.style {
   case .rounds:    SessionLiveView(session: session, style: .rounds,    voicePersistsOnPop: true)
   case .freestyle: SessionLiveView(session: session, style: .freestyle, voicePersistsOnPop: true)
   case .together:  SessionLiveView(session: session, style: .together,  voicePersistsOnPop: true)
   }
   ```

   The switch is deliberately not collapsed to one line: S6-S10 hang their presentations off `style` inside
   the body, and the router is where a reader learns that three styles exist. Its doc comment says so, and
   says that `SessionRunnerView:149` is its only caller.
3. Inside the body, `style` gates the turn: `.rounds` keeps today's `isMyTurn` gate on the inline LOG THIS
   SET card; `.freestyle` and `.together` do not gate it. That is the **only** behavioural change in this
   task; everything else is a move.

**TDD steps.** No new tests. Push and let CI compile — this is the highest compile-risk task in the plan
(a 4,400-line file, moved and renamed) and it is deliberately alone in its commit so a red run points at one
thing. Commit: `refactor(session): GroupSessionLiveView becomes SessionLiveView, routed by style` + the
trailer.

**Proves:** `git grep -n "GroupSessionLiveView"` is empty, and one body serves three styles.

---

### S6 — the round wait — **L** · Opus

**Files (new):** `Features/Sessions/Live/RoundPieces.swift`, `Live/RoundWaitView.swift`,
`Live/LiveFixtures.swift`, `GymSyncTests/RoundWaitCopyTests.swift`. **Modified:** `Live/SessionLiveView.swift`.

The production twin of frame 123, value-in, top to bottom:

1. **The station cards** (`StationCard` in `RoundPieces.swift`) — **built from fixed slots, not stretched**,
   the reference frame's whole argument (`RoundVariationsV2.swift:34-115`): `titleHeight = 14`,
   `columnHeight = 70`, `contentHeight = titleHeight + 10 + columnHeight`, each lifter column `width 52`
   with a **reserved line** for the personal scale-down whether or not there is one. Kicker = the station's
   name, right-aligned `logged/total` in tabular digits, a `Color.gsSuccess` tick on a lifter who has
   logged, the **accent ring** on the lifter whose turn it is (radius `36 × 0.28`, `lineWidth 2`). Two cards
   side by side at `spacing: 10`. `.gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)`.
2. **The rest card** (`RestRecoveryCard`) — the elapsed clock in a **fixed 96 pt** column so the curve's
   left edge lands in the same place on every render, the recovery curve beside it, a `GSDivider()`, then
   the next prescription and the achievability line (spec §2). The curve reads
   `RecoveryBuffer.sparkline(barCount:)` (`Models/RecoveryBuffer.swift`) over the samples the watch bridge
   already publishes — **no new store** (spec §6). Its endpoint carries the zone colour **and** the zone
   word (constraint 13 / §4a).
3. **THE SESSION · WHERE WE ARE** — Phase A's `SessionPlanCard` with `showsProgress`, the current exercise
   marked, sets done over total. Not a volume line: the reference frame's doc comment argues it and the
   owner chose it.
4. **The Coach thread row** — Phase A's `CoachDoorRow` (`SessionPieces.swift:576`) with the same
   `SessionCoachThreadRepository.open(sessionID:)` door the lobby uses (`LobbyView.swift:1135-1157`), so
   spec §3.6's "reachable from the lobby, the round wait and spotter mode" is one object in three places.
   The subtitle says why it is unlocked.
5. **The foot** — `PTTDockRow` and a **raised neutral** gated control reading `WAITING ON <names>`; the next
   act belongs to the crew, so it is not an accent button.

`RoundWaitView` takes plain values: `stations: [StationCard.Model]`, `rest: RestModel`, `plan: [SessionPlanRow]`,
`coach: CoachDoorRow.Model`, `waitingOn: [String]`, `skip: SkipOffer?` (S7 fills it). `LiveFixtures.roundWait`
is the frame-123 world: RACK A = Sam (ringed), Dana (tick), Lee (tick + a scale-down line), RACK B = two.
Mount it in `SessionLiveView` for `.rounds` when it is not your turn, replacing what the spectate page used
to do.

**TDD steps.** 1. `RoundWaitCopyTests` asserts every string the screen prints, as strings. 2. Build the
pieces, then the screen, then the mount. 3. `git grep -n "RoundWaitView("` shows the live mount **and** the
catalog builder. Commit: `feat(session): the round wait — stations on fixed slots, the recovery curve, the
plan, Coach` + the trailer.

**Proves:** frame 137, and a crewmate who is not lifting sees the crew rather than a scoreboard.

---

### S7 — the hold threshold, the skip, and the minute — **M** · Sonnet

**Files:** `Live/RoundPieces.swift` (`SkipOfferLine`), `Live/RoundWaitView.swift`,
`Live/SessionLiveView.swift`, `GymSyncTests/RoundHoldTests.swift` (extended).

Spec §9a and owner decision 11, with every number from `RoundHold` (S1) and none inline:

- The threshold starts when the **second-to-last** lifter of the round logs — derived from
  `allSessionSets`, not from a timer that starts when the view appears.
- At the threshold, the round wait shows **one quiet line**, not a dialog:
  `"<Name>'s still resting — go ahead without him?"` (the spec's copy; the pronoun comes from nothing the
  app knows, so the production string is `"<Name>'s still resting — go ahead without them?"` and the copy
  test pins it). Tapping it is **any crewmate's** tap and calls `advanceRound`; nothing happens on its own.
- The held lifter's own screen shows **"I need a minute"** once per exercise; tapping it extends the
  threshold by `RoundHold.extensionSeconds` and tells the crew (a broadcast on the existing session channel,
  the same `SessionBroadcastService` reaction path — no new channel).
- A skipped lifter's set **stays in their plan**; nothing is recorded against them; they rejoin at the top
  of the next round. That is already true of the data model — the task's job is to not add anything that
  makes it untrue (no `skipped` flag, no penalty row).

`LiveFixtures.roundHold` is frame 138: the same world with the line present.

**TDD steps.** Extend `RoundHoldTests` with the "second-to-last log" derivation and the once-per-exercise
extension; add the copy assertions. Commit: `feat(session): the hold threshold, the crew's skip and the one
minute` + the trailer.

**Proves:** frame 138, and a crew is never held by one lifter for more than three minutes without being
offered a way on — by a tap, never automatically.

---

### S8 — spotter mode — **M** · Sonnet

**Files (new):** `Live/SpotterView.swift`, `RoundPieces.swift` (`CrewHeartRatesCard`).
**Modified:** `Live/SessionLiveView.swift`, `LiveFixtures.swift`.

The production twin of frame 128 (`round-spotter-v3` — the **v3**, with the zone colours restored by owner
decision 17):

- the line at the top: *"You're with the crew until round N — not in a recap on your own."*;
- **who's to go** — the surviving turn strip, neutral (the accent here is CHEER);
- **`CrewHeartRatesCard`** — `THE CREW, RIGHT NOW` / `SHARED BY DEFAULT` (owner decision 13), one row per
  lifter: `GSHeartRatePill(bpm:zone:)` (already tints by `HeartRateZone`) **plus the zone word `Z1`-`Z4`**
  beside it, the lifting lifter marked by **weight, not colour**. Rows read
  `heartRateFor(_:)`'s freshness gate (`SessionLiveView`, ex-`:4818-4860`) — a stale reading renders as an
  em dash, never as a last-known number;
- the **Coach thread row**, the same object as S6;
- the foot: `PTTDockRow`, then `Cheer` (primary, accent) and `Film` beside it. **Film opens the existing
  clip path** (`SetLogClip`); if that path is not reachable from here without new plumbing, the button is
  omitted rather than faked, and the task says so.

Mounted for `.rounds` when the lifter's prescription has no set in this round.

**TDD steps.** Copy tests for the four strings; a `HeartRateZone` word-mapping test (`Z1`-`Z4` ↔
`warmup/moderate/hard/max`) since the mapping is new. Commit: `feat(session): spotter mode — cheer, film,
and the crew's heart rates in their zones` + the trailer.

**Proves:** frame 139, and an idle round has a job.

---

### S9 — Together — **M** · Opus

**Files (new):** `Live/TogetherClockView.swift`. **Modified:** `Live/SessionLiveView.swift`,
`LiveFixtures.swift`.

The production twin of frame 117 (`together-clock`, the **v1** render — decision 17 restored its colours):

- **one interval clock**: the current interval's name, the countdown as the screen's largest numeral
  (tabular), the next interval named under it. The intervals come from the routine's own cardio rows —
  `routine_exercises.cardio_minutes` / `cardio_zone` (`20260814000009:11-12`), which is the only interval
  data the app has. A routine with no cardio rows renders **one open interval** ("Work") and the plan says
  so rather than inventing a structure;
- **every lifter's heart rate on one timeline**, coloured by zone, the zone word in the row label
  (§4a) — the timeline is a shared x-axis over the samples the broadcast already carries, not a per-lifter
  chart;
- **no turn**: the body's turn gate is off for `.together` (S5), so the log control is available to
  everyone at once;
- the foot: `PTTDockRow` and the shipped End control.

**TDD steps.** A pure `TogetherIntervals.plan(from:)` with tests (rows → intervals; no cardio rows → one
open interval; a zone with no minutes is skipped). The view is value-in over that.
Commit: `feat(session): Together — one interval clock, the crew's hearts on one timeline` + the trailer.

**Proves:** frame 140, and a HIIT session has no turns.

---

### S10 — Freestyle — **M** · Sonnet

**Files (new):** `Live/FreestyleRailView.swift`. **Modified:** `Live/SessionLiveView.swift`,
`LiveFixtures.swift`.

The production twin of frame 116:

- **the shared rail** — sets done over total, per lifter, on one axis, so the spread is the subject;
- **the stretched rest** — a lifter two or more sets ahead sees their rest target extended, with the reason
  in words (*"You're two sets up — Coach is stretching your rest to keep the crew together."*). It is a
  **suggestion**: the rest is not enforced, and the line carries `Accept` / `Not today` through the shipped
  `GSConsentCard` (`DesignSystem/GSConsentCard.swift`) — spec §4, owner decision 4, no exceptions;
- **Coach's accessory suggestion** for the lifter ahead, the same consent card, the same rule;
- a lifter behind sees the crew's rest wait, stated, with nothing to accept.

Pure `FreestylePace.standing(sets:)` computes ahead/behind/level and is tested; the view renders it.

Commit: `feat(session): Freestyle — the shared rail, the stretched rest, Coach's accessory` + the trailer.

**Proves:** frame 141, and own-pace stops meaning detached.

---

### S11 — the soundboard leaves the app — **L** · Sonnet · **after S0**

**Deleted:** `Features/Sessions/SoundLibrarySheet.swift`, `Features/Shop/MyRackView.swift`,
`Features/Shop/WeeklyRack.swift`, `Models/Soundboard.swift`, `Services/SoundboardPlayer.swift`,
`DesignSystem/GSPlateToken.swift`, `GymSyncWatch/SoundboardView.swift`,
`GymSyncTests/PlateClassTests.swift`, `PlateDeltaTests.swift`, `PlateMathTests.swift` (subject to S4's
grep), `GymSyncTests/CurationRepositoryTests.swift`'s soundboard cases.
**Modified:** `Features/Shop/ShopView.swift` (the `rackCard` NavigationLink only — PRO and Coaching stay),
`Features/You/YouTabView.swift` (the SHOP widget's subtitle; the widget stays — it is PRO's door),
`Services/GuidanceTips.swift` (`:140-142`, the `tour.you.rack` step),
`Services/SessionBroadcastService.swift` (the soundboard stream and `sendSound`; **the reaction stream at
`:64-95` stays**), `GymSyncShared/WatchEnvelope.swift` (`soundboardTap` `:47`, `soundboardFavorites` `:243`),
`Services/WatchConnectivityBridge.swift` and `GymSyncWatch/ContentView.swift` / `WatchSessionStore.swift`
(the sound path; **the HR path stays**), `Services/BroadcastChannelDecision.swift` (its comment at `:35`
and `:44` describes both paths — re-point it, do not delete the decision),
`GymSyncTests/WatchEnvelopeTests.swift` / `WatchConnectivityBridgeTests.swift` /
`AudioSessionManagerTests.swift` (the sound cases), `scripts/add_sound.js` (deleted),
`scripts/cleanup_storage_orphans.js` (its soundboard branch).

**Do not touch** `Services/AudioSessionManager.swift`'s `.playback` + `.mixWithOthers` baseline: the PR
celebration sound depends on it (constraint 21). Its two comments *mention* the soundboard — re-point them,
keep the behaviour.

**TDD steps.** 1. `git grep -in "soundboard\|SoundLibrary\|GSPlateToken\|sendSound\|soundFavorites"` before
and after; the after must be **empty outside `Variations/CardVariations.swift`** (a DEBUG fixture B2
retires) and this plan's own doc references. 2. The watch target compiles only in CI — `WatchEnvelope` is a
member of **both** targets (`project.yml:78-94`, `:219-225`), so a field removed there must be removed on
both sides in this one commit. Commit: `feat(soundboard): the dock, the rack, the watch UI and the tour step
leave the app` + the trailer, naming the archive tag.

**Proves:** the app has no soundboard, and push-to-talk, the heart-rate path and the PR sound still do.

---

### S12 — the reaction vocabulary becomes emoji only — **M** · Sonnet · **after S0**

**Modified:** `Features/Social/PumpFeedView.swift` (`:492`'s `snd:` pill branch and `:518`'s
`onReact("snd:" + slug)` attach path), `Features/Social/ChatView.swift`,
`Features/Social/CrewRoomView.swift`, `Models/ChatMessage.swift` (the `snd:` half of the reaction model),
and the tests that assert them.

Spec §5 and the social-cards spec §9.1: the feed's and the chat's reaction vocabulary becomes the five
emoji. A reaction row that still carries a `snd:` prefix (there will be none after D5, but the app may see
one from a cache) is **skipped, not rendered as text** — assert that in a unit test, because "renders
`snd:airhorn` as a chip" is exactly the defect a naive removal ships.

**Check the seed** (`scripts/seed_qa_fixtures.js`) for a seeded `snd:` reaction on the pump post; if one
exists, the seed change belongs to D7's owner (Stream D) and this task reports it rather than editing
`scripts/**` (constraint 2).

Commit: `feat(social): sound reactions leave the feed and the chat — emoji only` + the trailer.

**Proves:** `git grep -n '"snd:'` is empty in `GymSyncApp/`, and `app-pump-feed-post` renders emoji pills.

---

### S13 — the catalog: six production ids in, ten variation ids out — **M** · Sonnet

**Modified:** `App/CatalogHostView.swift`, `GymSyncTests/CatalogScreenTests.swift`,
`GymSyncUITests/ScreenshotTests.swift`, `docs/design/frame-map.json`.
**Deleted:** `Variations/RoundVariations.swift`, `RoundVariationsV2.swift`, `StyleVariations.swift`,
`StyleVariationsV2.swift`, `SessionVariationsV3.swift`.

The four-part contract in **one commit per direction** (constraint 6): six ids in with their builder arms
over `LiveFixtures` and `LobbyFixtures`; ten ids out with their view structs. Before deleting the five
variation files, `git grep` every SV\* symbol they declare against the two surviving Kit files and
`CardVariations*.swift` — the Kits are shared, and a symbol the remaining frames use must not leave with
its file (if one does, move it into `SessionVariationKit.swift` in the same commit and say so).

While here, the mechanical cleanup decision 6 named: remove `editing` / `voting` / `locked` from the Swift
read-side sets (`SessionRepository.swift:477`, `LobbyView.swift:120,431`, `SessionLiveView` (ex-`:347`),
`CrewRoomView.swift:621`, `GroupView.swift:407`, `SocialTabView.swift:645`, `SentryContext.swift:45`) and
the assertions that enumerate them (`SentryContextTests.swift:102-104`, `EventKitBridgeTests.swift:81`,
`WatchDisplayFormattingTests.swift:86`). Only after D7 is applied.

**Counts after this task:** `CatalogScreen` 108, `captureCatalog(` 108, `frame-map.json` 86 entries, max
frame 141. `CatalogScreenTests` asserts 108 == 108.

**TDD steps.** Constraint 19: a green `build-test` does **not** prove `ScreenshotTests.swift` compiles.
This task's proof is a green **screenshots** job; if the seed 504s, the controller re-runs it.
Commit: `feat(catalog): six production session ids in, ten design-round ids out` + the trailer.

**Proves:** the six frames render from fixtures, and the deck no longer carries alternatives to screens that
now exist.

---

# INTEGRATION

### I1 — the FLOOR, the frame-map and the accepted deviations — **S** · Sonnet

- `.github/workflows/ios.yml` — **the FLOOR moves by `−4` against master's FLOOR at integration**. Re-derive
  the literal on the day:

  ```
  git fetch origin
  grep -n 'FLOOR=' .github/workflows/ios.yml | tail -1
  grep -c 'captureCatalog(' GymSyncApp/GymSyncUITests/ScreenshotTests.swift
  gh run download <last green run> -n app-screenshots -D ./fresh-artifact && ls ./fresh-artifact | wc -l
  ```

  Against the verified base that is `FLOOR=134` → `FLOOR=130`. Extend the comment block above the line in
  the style Phase A established: the six ids in with their frame numbers, the ten out with theirs, and
  "the −4 is the invariant, not the literal 130".
- `docs/design/frame-map.json` — 136-141 present, 112-117 / 123 / 124 / 126 / 128 absent, everything else
  unrenumbered, no **new** duplicate frame numbers (41 / 69 / 70 are pre-existing and are not this plan's).
- `docs/design/accepted-deviations.json` — append **six** entries, one per new id, each naming the retired
  frame it was built to and the spec section that is its authority. The `session-round-spotter` entry also
  records that the frame renders the **v3** composition (zone colours) rather than the `-v2` one the second
  design pass approved, because owner decision 17 reversed it; the `session-together-clock` entry records
  the same for frame 117 over 126.

Commit: `chore(session): FLOOR 134 -> 130, frames 136-141 in and ten out, accepted deviations` + the trailer.

### I2 — end-to-end CI, then by eye — **M** · controller

Push and read the run. **Download the artifact into a fresh directory** (constraint 12).

**iOS workflow** — build green; `GymSyncTests` green with the new files (`SessionStyleTests`,
`SessionStationsTests`, `RoundHoldTests`, `RoundWaitCopyTests`, and the plate tests **absent**);
the screenshots job exports **≥ the new FLOOR** and "Verify capture count" passes.

**Backend workflow** — pgTAP green for `session_style_stations_round_test.sql` (9),
`session_round_engine_test.sql` (12), `session_states_narrow_test.sql` (4) and `soundboard_absent_test.sql`
(5) — each of which requires its migration to have been **applied** (constraint 8); a red with a
"does not exist" error means a gate was skipped, not that the SQL is broken. `deno test` green for
`livekit-token` with the narrowed allow-list.

**Then read the artifact, by eye, in this order:**

1. `app-home-v3-08a` / `-08b` and Phase A's `app-session-lobby-waiting`, `-ready`, `-late`,
   `session-lobby-week` — **unchanged** except the style card where S2 put it (constraint 14).
2. `app-session-style-choice` — three rows, Rounds ticked in `gsSuccess`, exactly one accent on the page
   (Start).
3. `app-session-round-wait` — **the two station cards are the same height** and their avatar rows share a
   baseline; one accent ring; the curve beside the clock; the plan; the Coach row; the neutral gated foot.
4. `app-session-round-skip` — the same screen with the quiet line, and **no dialog**.
5. `app-session-round-spotter` — four HR rows, each with a colour **and** a `Z` word; CHEER the one accent.
6. `app-session-together-clock` — one clock, four hearts on one timeline, zone words present.
7. `app-session-freestyle-rail` — the rail with one lifter ahead and the stretched-rest suggestion carrying
   `Accept` / `Not today`.
8. **`app-lobby`** — the live account's real lobby with the style card against seeded data. The one capture
   a fixture cannot stand in for.
9. `app-tab-you` — the SHOP widget present, **no rack line**; `app-pump-feed-post` — emoji pills only;
   `app-group-sessions` — still six state glyphs (D7 kept the count by swapping the states).

Fix-forward any red; each fix is its own commit.

### I3 — one PR, with proof cards — **M** · controller

`feat/group-session-phase-b` → `master`. The body carries:

1. **What shipped**, in the spec's vocabulary: a crew session moves the way the crew chose; a round is the
   server's number; an idle round has a job; the soundboard is archived, not lost.
2. **The six new ids, the ten retirements, the FLOOR (−4)**, as this plan's tables.
3. **The four migrations**, each with the timestamp it was applied to `chjkkwqwdlmaxacwglzm`, and **the
   archive tag with its sha and the row-export path** for the irreversible one.
4. **The deliberate deviations**, each with its reason: the surviving body is the scheduled one and
   `WorkoutSessionView` lives for one more release; the style default is derived from exercise categories
   because no routine type exists; the station cap is a parameter passed `nil` because no rack count and no
   session→venue link exist; `advance_turn` was not modified — `advance_round` sits beside it; the tag is
   named `archive/soundboard-throwables-2026-09`, not spec §5's `archive/soundboard-2026-09`; the QA seed's
   six session rows changed **states** to keep the glyph count; testers on older builds lose the soundboard
   the moment D5 applies; spec §7's "your turn" frame is Phase B2's, because it needs a fixture init on the
   live body itself.
5. **Proof cards**, each a run URL plus its evidence: the data (four pgTAP suites, with the round-close and
   idempotency assertions named); the styles (frames 136, 140, 141 beside the retired 116/117/126 from the
   design round's own run); Rounds (137, 138, 139 beside 112-115/123/124/128); the retirement
   (`git grep GroupSessionLiveView` empty, the before/after `wc -l`, `app-lobby` live); the removal
   (`git grep -in soundboard` empty outside `CardVariations.swift`, the tag listed on a fresh clone, D6
   green).
6. The trailer per constraint 5, plus `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## What this plan does not decide

1. **How a session knows its venue, and how many racks that venue has.** Decision 3. Until a session carries
   a venue and a venue carries counts, `StationSplit`'s cap is `nil` and the split is `ceil(n/3)`. The owner
   asked for the equipment-aware default; this is the honest half of it, and the other half is a column, a
   picker and a question about who maintains rack counts.
2. **What Together does with a routine that has no cardio rows.** S9 renders one open interval. A real
   interval editor (work/rest, rounds, per-lifter zones) is a feature nobody has specified.
3. **Whether Freestyle's stretched rest should be enforced.** It is a suggestion (§4), so a lifter who
   declines simply keeps their rest and the rail shows the gap. Whether the crew should see the decline is
   not decided.
4. **When `WorkoutSessionView` adopts the one session body.** Phase C. Until then a scheduled solo session
   and an ad-hoc one lift on different screens, exactly as they warm up on different screens today.
5. **Whether the `routine_proposals` tables drop.** Phase A left them; their app code is gone but
   `account-deletion-cascade` still references them, so the drop is its own change with its own edge-function
   deploy. B1 narrows the states those tables' flow was designed for and stops there.
6. **What the crew's Coach thread says when a round opens.** The door is the lobby's door (S6, S8). Seeding
   the thread with the session's focus is Coach engine work.
7. **Whether a skipped lifter should be told they were skipped.** Spec §9a says nothing is recorded against
   them and they rejoin next round; whether their own screen says "the crew moved on" is a copy decision
   nobody has made.

---

## Self-review (run by the planner, 2026-09-13)

**1. Spec coverage — every Phase B1 sentence maps to a task.**

| spec | requirement | task |
|---|---|---|
| §1 / decision 1 | style = rounds / freestyle / together, defaulted by routine type, the crew's choice, changeable until Start | S1 (the default), S2 (the choice), D1 + D3 (the column and the freeze) |
| §3.3 / decision 2 | stations, rotation never deeper than three, re-mixed at exercise changes by measured rest | S1, S3, D3 |
| §3.3 / decision 6 | turn order fixed within an exercise, re-drawn at exercise changes | S3 + `set_session_stations`'s idempotency on the exercise position |
| §3.3 | the round closes when the last lifter logs; the soft gate | D3's close predicate, S5's turn gate |
| §3.3 / §6 | `sessions.style`, `stations jsonb`, `round int` | D1 |
| §3.3 | the round wait: station cards, rest + recovery curve, next prescription, achievability, the session where we are | S6 |
| §3.3 / decision 7 | spotter mode: cheer, film, talk, the crew's heart rates | S8 |
| §3.3 | Freestyle: the shared rail, the stretched rest, the accessory suggestion | S10 |
| §3.3 / decision 13 | Together: one clock, every heart rate on one timeline, shared by default | S9 |
| §3.6 | the session's Coach thread from the round wait and spotter mode, the lobby's door reused | S6, S8 |
| §4 / decision 4 | every weight, volume or set change is a suggestion | S10 (both suggestions ride `GSConsentCard`); nothing else in B1 changes a prescription |
| §4a / decision 17 | heart-rate zone colours, with the zone word | constraint 13, S6, S8, S9 |
| §5 / decisions 8, 14 | the soundboard, throwables, sound reactions, the Shop rack — archived, removed, dropped | S0, S11, S12, D5, D6 |
| §5 | the spectate subtree, the BOARD, the two-participant branches | S4 |
| §5 | the dead session states | D7, D8, S13 — Phase A's deferred cost, paid |
| §5 | the shipped pump-check card | **Phase B2** |
| §3.4 | the consensus swap card and the quiet scale-down | **Phase B2** |
| §6 | the recovery curve reads the samples the bridge records; no new store | S6 (`RecoveryBuffer.sparkline`) |
| §6 | per-lifter substitutions readable by crewmates in "who's up next" | **Phase B2** (the scale-down's *reserved line* ships in S6's station card so B2 fills it without a re-layout) |
| §6 | `crew_week(session_id)` | **Phase B2** |
| §7 | production frames for Rounds (the round wait, spotter), Freestyle, Together | S13 — frames 137-141 |
| §7 | a frame for "your turn" | **Phase B2** — it needs a fixture init on the live body; named as a deviation |
| §7 | the variation ids retire as each production frame lands | S13 — ten out |
| §8 item 3 | one session body; the retirement of `GroupSessionLiveView` | S4, S5 |
| §9a / decision 11 | the hold threshold, the crew's tap, "I need a minute" | S1 (the constants), S7 |
| decisions 15, 22 | live encouragement stays verbal; `pro_until` stays readable | **nothing to build** — verified: no task adds an encouragement feature or touches the profiles policy |

**Two spec corrections, made deliberately.** §6 says the style default is "computed client-side" *per
routine type* — there is no routine type, so S1 computes it from the routine's exercise categories, which is
the only signal that exists (decision 2). §5's tag name is superseded by the controller's
`archive/soundboard-throwables-2026-09` (S0).

**2. Placeholder scan.** Grepped the finished document for `TBD`, `TODO`, `FIXME`, `XXX`, `add validation`,
`similar to`, `same as above`, `<fill`, `and so on`, `etc.`: **zero hits outside this sentence**. Every task
names its files, its exact values, its tests, its commit message and its `Proves:` capture.

**Four things this review changed, rather than noted.**

1. **The first draft advanced the round inside `advance_turn` on a rotation wrap.** Read
   `20260801000001_advance_turn_version_guard.sql`: that function is the frozen contract three pgTAP suites
   assert, and a wrap is not the same event as "everyone logged" the moment there are two stations. The
   close predicate in D3 counts set_logs per present participant instead — it works for one station and for
   three, and it leaves the frozen RPC alone.
2. **The first draft trusted `sessions`' UPDATE policy to protect the round.** Read
   `20260726000001…:172-178`: organizer **or participant**, no column list. Any crewmate could have written
   `round = 99`. That read produced `private.session_round_guard`, and with it the free win of freezing
   `style` at Start on the server rather than only in the UI.
3. **The first draft dropped the sound-reaction policies and stopped.** Read
   `20260710000003_create_chat.sql:20-25`: `chat_message_reactions.emoji` has **no CHECK** — the restrictive
   policy was the only gate, so dropping it would have left the column *more* permissive than before the
   soundboard existed. D5 adds the CHECK.
4. **The first draft planned to fold the crew frames onto `WorkoutSessionView`,** reading spec §8's "on the
   solo workout body" literally. The context map's headline finding is that scheduled solo already runs
   inside `GroupSessionLiveView`; folding would have rebuilt rotation, presence, voice and the HR roster in
   the same branch that adds three styles. Decision 1 states the reversal and its cost.

**3. Cross-task symbol consistency.** Every cross-task symbol was grepped across this document for a single
spelling. The near-miss spellings a second author would reach for — `SessionStyleKind`, `StationAssignment`,
`RoundHoldRule`, `SessionRoundRepository`, `RoundRestView`, `SpotterModeView`, `advanceRoundCounter` —
appear nowhere in this document except in this sentence.

- `SessionStyle` — three cases, `rawValue` identical to D1's CHECK; declared S1; read by S2, S5, S13.
- `SessionStations` — four coding keys identical to D1's column comment and D3's validation; declared S1,
  written by S3, read by S6.
- `StationSplit.count(crew:equipmentCap:)` and `.assign(lifters:count:restMedians:previous:)` — one
  signature each, callers in S3 and its tests only.
- `RoundHold` — five constants (`floorSeconds`, `multiplier`, `capSeconds`, `extensionSeconds`,
  `remixSpreadSeconds`) in one file; read by S3 and S7; every number in the plan traces to one of them.
- `RestMeasure.medians(from:since:)` — one signature, two callers (S3's re-mix, S7's threshold).
- `SessionLiveView(session:style:voicePersistsOnPop:)` — one initializer, one call site
  (`SessionInProgressView`), created by S5.
- `RoundWaitView` / `SpotterView` / `TogetherClockView` / `FreestyleRailView` — one file each, two callers
  each (the live body and the catalog builder), value-in with no repository.
- `public.advance_round(uuid, integer)` and `public.set_session_stations(uuid, integer, jsonb)` — one
  signature each in D3, wrapped once in `SessionRepository` (S1), called in S3 and S6/S7.
- The six production ids appear identically in five places each: this plan's two tables, the enum case, the
  `ids` array, the capture method and the frame-map key.

**Gaps I could not close, named rather than papered over:**

- **The equipment-aware station cap has no data** (decision 3). B1 ships `ceil(n/3)` and a real parameter.
- **Nothing in B1 proves the round engine with two real devices.** D4 proves the predicate with three roles
  in one transaction; the app-side is proven by frames and by one live account. A genuine two-phone round
  close is a manual check, listed as such in I3 rather than claimed by a test.
- **The catalog cannot photograph the live body.** Every B1 frame renders a presentation over fixtures, so
  "your turn", the log card and the turn gate are proven only by CI compiling them and by the live
  `app-lobby` walk stopping at the lobby. Spec §7's your-turn frame is B2's for exactly this reason.
- **`GymSyncUITests` compiles only in the screenshots job** (constraint 19), so S13 is the one task whose
  proof depends on a seed that has failed twice this week.
- **The Watch app is unbuilt on this machine and lightly tested in CI.** S11 removes a field from a type
  shared by both targets; if anything in this plan breaks the watch build, it is that commit.

---

# Phase B2 — the outline (one page)

**Why the split.** The honest task count for the whole of spec §8 item 3 plus the Phase A hand-offs is
**twenty-one app tasks**: the thirteen in B1 above and the eight below, against a size rule of about twelve.
B1 is drawn where the spec's own dependency lies — the styles, the stations, the round counter, the body
and the removal are one change: none of them can ship without the others, and all five are what makes the
crew session *move*. B2 is everything that sits **on** that body without changing how it moves: two cards,
one strip, three lines and two pieces of hygiene. B2 gets its own plan file, its own branch and its own PR,
written after B1's whole-branch review, so that its file:line facts are read against the body B1 actually
ships rather than the one this plan predicts.

| # | task | size | model | notes |
|---|---|---|---|---|
| B2-1 | **The consensus swap card** (`swap-consensus-card-v2`, frame 125): the bespoke `swapVoteBanner` (`:2908`) and `groupSwapSheet` (`:2967`) become `GSConsentCard` with two **tappable** exercise rows that open their exercise pages, the pips, the consequence line, Agree / Keep. `receiveSwap` / `evaluateUnanimity` / `castVote` keep their wire format. | L | Opus | spec §3.4 mode 1 |
| B2-2 | **The quiet personal scale-down**, visible in "who's up next": `selfScales` (`:266`) already exists and is never broadcast; B1's station card already **reserves the line** — B2 fills it, and adds the picker via `ExerciseSubstitutionRepository.forExercise`. | M | Sonnet | spec §3.4 mode 2 |
| B2-3 | **The pump-check card v2** (frame 119) replaces `PumpPostCard` (`PumpFeedView.swift:217-225`): highlight as a raised island, photo beside it opening the workout's metrics, trajectory strip and rung chips, set rows on one line, the plain-terms line. Same seven facts, about half the height. | L | Opus | spec §5 |
| B2-4 | **`crew_week(session_id)`** — the SECURITY DEFINER RPC (participants only) returning per participant sessions-done-this-week and the weekly goal, plus the production wiring of `CrewWeekStrip` (`LobbyView.swift:1067-1072` returns a DEBUG fixture today). A migration gate + pgTAP. | M | Sonnet | decision 21; frame 135 goes live |
| B2-5 | **The lobby plan card's per-lifter rung line** — `planRungLine` (`LobbyView.swift:201-206`) falls back to the routine's name; the block's rung reaches the screen. `SessionRunnerView.swift:128-131` carries the identical deferral for the warm-up. | M | Sonnet | Phase A hand-off |
| B2-6 | **Coach's readiness suggestion on the warm-up** — re-add the deleted `CoachSuggestionBlock` **with its signal** (`coachLine` is passed nil from `SessionRunnerView.swift:135`; `WarmUpScreen`'s `coachLine`/`onAccept…` plumbing is already wired and inert — Phase A's N7). Accept / Not today, per §4. | M | Opus | Phase A hand-off + spec §2 |
| B2-7 | **`SessionEntryView` hands the lobby its roster** (final-review finding 10) and **N5** — `ScreenshotTests`' class-level `setUp()` (`:75-102`) duplicates `launchApp()`'s three launch-argument pairs. | S | Sonnet | Phase A hand-offs |
| B2-8 | **The seed pins the QA session relative to the walk** — Home reads CHECK IN or START A WORKOUT depending on whether the walk runs inside the seeded check-in window, and the arrival track's "late" becomes deterministic with it. Plus the your-turn frame (spec §7) once the live body has a fixture init. | M | Sonnet | docket, Phase A close |

**Also carried into B2's plan, not into B1:** the `routine_proposals` table drop and its edge-function
reference; the frame-map's pre-existing duplicate numbers 41 / 69 / 70; the retirement of the last three
variation ids (118, 119, 125) and, with them, the two Kit files and the `Variations/` folder itself.
