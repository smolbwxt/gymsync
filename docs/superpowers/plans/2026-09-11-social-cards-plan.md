# Social cards — the trajectory snapshot — implementation plan

**For agentic workers.** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Every task below is
one subagent, one commit, one review. Do not batch tasks; do not start Stage 2 before Task S2.0 is pushed.

**Goal.** Turn the pump-check card from "what just happened" into **a snapshot of where the athlete is in their
fitness trajectory** — the goal, the place in the block, the standing, this week's rung, one highlight, the
workout in plain terms, the picture — and give the Crews card an honor that rewards showing up rather than
lifting most.

**Architecture.** The card is a **snapshot, not a query**. Every friend-visible fact on it is frozen into the
`workout_posts` row at post time by the composer, because `block_goals` and `weekly_goals` are own-rows RLS
(`20260907000001_block_goals.sql:49-51`, `20260906000001_weekly_goals.sql:54-56`) and a viewer can never read
the author's goal — the author reads their own through `BlockGoalRepository` / `WeeklyGoalRepository
.progress(for:)` at post time, and the post carries the result. The Crews honor goes the other way: it is a
live read, but through a new `SECURITY DEFINER` RPC, because `sessions` SELECT RLS is organizer-or-participant
(`20260709000006_create_sessions.sql:49-54`) and a client-side count would silently report "who I lifted with"
rather than "who showed up".

**Tech stack.** Swift 6 / SwiftUI (iOS 18 target), Supabase Postgres + PostgREST + RLS, pgTAP, XCTest +
XCUITest, GitHub Actions (`ios.yml`, `backend.yml`), XcodeGen (`project.yml`).

**Spec (the authority):** `docs/superpowers/specs/2026-09-11-social-cards-design.md`. **Every section binds**;
§8 is the sequencing this plan's two stages follow. Gate documents: the goal-first programming spec
(`docs/superpowers/specs/2026-09-07-goal-first-programming-design.md`) — the card's trajectory line reads its
objects; the design language (`docs/superpowers/specs/2026-09-05-design-language.md`). Round artefacts with
file:line facts: `.superpowers/sdd/2026-09-07-social-cards-round/context-map.md`, `reference-scan.md`,
`decisions.md`. Format exemplar (the shape this plan copies):
`docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md`.

---

## Base branch — read this first

**PR #42 HAS MERGED** — `master` is `fed2f42` (the goal-first release, 16:58Z) with the docs merge `f00f208`
on top. **There is no rebase step in this plan and no waiting.** Both stages fork from `origin/master` at
`f00f208` or later, so everything goal-first is simply *there*.

Verify against `origin/master`, never a local `master` ref — the Home v3 plan lost a day to exactly that.

What both stages may assume, identically:

| | Stage 1 and Stage 2, from `f00f208` |
|---|---|
| base | `origin/master` (`f00f208` or later) |
| `FLOOR` in `ios.yml` | **107** |
| frames taken | 60–100 |
| `BlockGoal*` / `Ladder*` / `BlockGoalRepository` | present |
| `WeeklyGoalKind` cases | nine |

**Stage 1 touches none of the goal-first files**, which is what lets the two stages run as **two parallel
streams off one base** — Stage 1 on `feat/social-cards-crews`, Stage 2 on `feat/social-cards-post` — merged
into `feat/social-cards` at integration, **Stage 1 first**. A single sequential branch is equally correct if
the controller prefers one worker; nothing in the task bodies changes either way. One PR at the end.

The only file both stages touch is the catalog quartet (`CatalogHostView.swift`, `CatalogScreenTests.swift`,
`ScreenshotTests.swift`, `frame-map.json`), and every edit to it is **append-only**: Stage 1 claims
**frame 101**, Stage 2 claims **frame 102**, and integration concatenates in frame order without renumbering.

`FLOOR` is a **minimum** (`ios.yml:371` — `if [ "$COUNT" -lt "$FLOOR" ]`), so each stream's extra captures
pass green against 107 on its own branch. The bump to **110** happens once, in **I1**.

---

## Global Constraints

These bind **every** task. A task that breaks one says so in its commit body, and why.

1. **Swift compiles only in CI.** No macOS toolchain on this machine: no `xcodebuild`, no `swift build`, no
   simulator. Read the code you are changing, reason about the types, push. `.github/workflows/ios.yml` is the
   compiler.
2. **One commit per task**, with this trailer, verbatim:
   ```
   Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
   ```
   Use `git commit -F <file>` or a single-quoted heredoc. A `-m` message containing backticked identifiers has
   silently deleted words in this repo before.
3. **The catalog four-part contract, in ONE commit per id.** A new `CatalogScreen` id lands in all four places
   in the *same* commit:
   - the `case` in `App/CatalogHostView.swift`'s `enum CatalogScreen` (:16-128) **and** its builder arm in the
     same file's `switch` (:136-226);
   - the id string in `GymSyncTests/CatalogScreenTests.swift`'s `ids` array — the test asserts
     `CatalogScreen.allCases.count == ids.count`, so a case without a list entry fails the build;
   - a `func testCatalog…() { captureCatalog("<id>") }` in `GymSyncUITests/ScreenshotTests.swift`
     (helper at :334-349);
   - an entry in `docs/design/frame-map.json` (`"<id>": {"frame": <n>, "title": "<title>"}`). Frames 60–100 are
     taken after PR #42; **this plan's one new id is frame 101**.

   **The FLOOR is bumped only at integration** (task I1), once. A stage branch that raises `FLOOR` before its
   id exists on the integration branch turns CI red for everything else on the same base.
4. **`XCTUnwrap(await …)` does not compile — bind, then unwrap.** `try XCTUnwrap` on an `await` expression is
   a compile error in this target's Swift mode: write `let value = await …` first, then
   `let unwrapped = try XCTUnwrap(value)`.
5. **Never request HealthKit authorization outside `save(_:)` or from a unit test** — a raised sheet hung
   `build-test` for 45 minutes once. The same rule covers the camera and the photo library: `CameraPicker`
   (`PumpCheckComposer.swift:240-276`) presents `UIImagePickerController`, which hangs a simulator run
   identically. Every composer rule in this plan is tested through the **pure** functions that take values as
   parameters (`HighlightMath`, `PostLateness`, `PostTrajectoryMath`); the view is exercised only by the
   catalog, whose photo is a fixture image built in-process (task S2.6a) and never a picker.
6. **Live-DB tests use the `TestSession` teardown factory and far-future rows.**
   `GymSyncTests/TestSession.swift` is the only place a test may create a session; register cleanup with
   `addTeardownBlock` **before** the write (XCTest awaits teardown; `defer { Task { … } }` loses the race with
   process exit — `ModerationRepositoryTests.swift:20-27`). Every date a live-DB test *controls* is **2099**
   (`WeeklyGoalLiveRepositoryTests.swift:15-19`): these run as the shared CI account and a current-week row
   would fight `scripts/seed_qa_fixtures.js`. `workout_posts.created_at` is server-defaulted and cannot be
   2099 — the row is therefore deleted in teardown **and** cascades with its session
   (`20260731000001_workout_posts.sql:22`, `ON DELETE CASCADE`).
7. **No `Date.now` and no live repository reachable from a catalog builder.** Every `content_*` in
   `CatalogHostView` renders from fixture integers and strings (`HomeV2Fixtures.swift:1-10`,
   `WeeklyGoalFixtures.swift:10-14`). **One exception is inherited, not introduced:**
   `content_pumpFeedPost` (:1280, :1294) anchors `createdAt` on `Date().addingTimeInterval(-3600)` so the
   author row reads a stable `1 hour ago` rather than drifting to `3 years ago`. Task S2.9 keeps that anchor
   and makes every *new* fact **relative to it** (`completedAt = createdAt.addingTimeInterval(-47 * 60)`), so
   the lateness tag is a fixed `posted 47 min after` on every run. Nothing else new may read a clock.
8. **The frozen Home frames must stay byte-identical.** `app-home-v3-08a-targets-above-calendar`,
   `app-home-v3-08b-targets-above-join` and `app-home-goal-strip-muscle-sets` are the owner-approved
   compositions. Task **S2.3** extracts `HomeWeeklyGoalStrip.chipView` into a shared component and is the one
   task that can move them; its canary is those three captures unchanged, checked in **I2**.
9. **Design rules, by number** (`2026-09-05-design-language.md`). The ones this plan leans on:
   - **1** — two raised surfaces only (`.gs3DCard` to read, `.gs3DCardStyle` to press); furniture inside a
     raised box stays flat; chips are furniture; radii cards 24 / small 16 / strips 14 / chips 999.
   - **2** — default text; gold has exactly two jobs and neither is here; **accent is spent on the one primary
     action, an invitation line, and the current item** — a finished post is none of the three, so the card's
     new lines carry no accent and its chips carry **no `isNext` ring**; green means done; red is errors only;
     no decorative emoji — **reaction emoji stay, because they are content**.
   - **3** — kickers are 10–11 pt caps, 0.1–0.13 em tracking, `muted`; numbers tabular.
   - **4** — one primary per screen (the composer's is `Post`, and the highlight picker must not become a
     second one); questions above the fold.
   - **9** — sentence case for sentences, caps for kickers; a button says exactly what happens.
10. **Migrations are applied to the live project at a controller gate before pgTAP runs.**
    `.github/workflows/backend.yml:24-27` runs `node scripts/run_pgtap.js` against the **live**
    `SUPABASE_DB_URL` secret. There is no `supabase db push` anywhere in CI — grep-verified. A pgTAP test for
    an object that has not been applied to project `chjkkwqwdlmaxacwglzm` **will fail**. S1.1's and S2.1's
    migrations are applied by the operator (or via the Supabase MCP `apply_migration`) before the matching
    pgTAP task's CI run, and **before the client that decodes the new columns merges**; each commit body says
    when it was applied.
11. **New jsonb keys are camelCase, with no `keyEncodingStrategy`.** The app sets none anywhere, so the
    synthesized encoder's Swift property names are the wire names — `20260906000001_weekly_goals.sql:35-40`
    states the rule and `block_goals.target` inherits it. **`workout_posts.summary` is the exception and stays
    one:** `PostSummary` declares snake_case `CodingKeys` explicitly (`WorkoutPost.swift:20-25, 39-43`) and
    those rows are immutable history. The new columns (`highlight`, `trajectory`) are camelCase; the one new
    field on `PostSummary` (`routineName`) follows **its own type's** snake_case convention
    (`routine_name`), because a single jsonb document may not speak two conventions.
12. **Do not change the shipped weekly-goal or block-goal contracts.** `WeeklyGoalProgress` (its fields), the
    `WeeklyGoalRepository` and `BlockGoalRepository` protocols, `LadderPageModel` and `WeekMath` are frozen.
    This plan **reads** them and snapshots the result; it adds nothing to them.
13. **`workout_posts` has no UPDATE policy and gains none** (`20260731000001_workout_posts.sql:71-72`: "posts
    are immutable snapshots"). Every column this plan adds is written at INSERT, by the composer, once.
14. **Every report claim is verified against `git show <sha> --stat` and the CI artifact, not memory — and
    grep the CALL SITE of every new function before claiming it is live.** A task report that says a file
    changed names the sha it read; a task report that says a capture landed names the run it downloaded it
    from. A definition is not a feature: `git grep -n "<symbol>("` must show a caller outside the symbol's own
    file and its tests, and this project has shipped complete logic with no call site often enough that the
    grep is the claim, not the confidence. This is why task **S2.8** deletes `unreact` rather than leaving it,
    and why **S2.6a** and **S2.10** exist at all: the goal-first final review caught three defects that
    fixture frames had hidden while the production path was broken, so new UI gets a real CI render and a
    seeded row gets a real walk.
15. **Catalog captures launch with tips and tours OFF.** *(ADDED at integration, 2026-09-12 — Stage 1 fix
    round 1.)* `ScreenshotTests.captureCatalog(_:)` now passes `-guidanceTipsEnabled NO`, the same launch
    argument `launchApp()` has always passed. Before it, `captureCatalog()` passed **no** launch arguments at
    all, so any catalog id whose view carries `.gsSpotlight(_:)` or `.gsSpotlightTour(_:)` photographed the
    scrim instead of the screen (both modifiers gate on `GuidanceTip.tipsEnabled`); `crews-tab` is the id that
    found it. **The consequence for this plan: no `content_*` builder needs to mark a tour seen.** A
    per-builder `GuidanceTip.…markSeen()` is now redundant rather than load-bearing — `content_soloLiveSet`'s
    call is kept only because deleting a working call proves nothing, and its comment is corrected to say so.
    The overlay itself is still reviewed, through the `guidance-spotlight` catalog case, which builds
    `GSSpotlightOverlay` directly and is unaffected.

---

## File structure

### Created

| File | Responsibility | Task |
|---|---|---|
| `supabase/migrations/20260911000001_crew_consistency_honor.sql` | `group_consistency_honor(p_group_id)` — the 30-day frequency read | S1.1 |
| `supabase/tests/crew_consistency_honor_test.sql` | pgTAP for the RPC: gate, window, ordering, tie-break | S1.2 |
| `GymSyncApp/GymSync/Models/CrewHonor.swift` | `CrewHonorRow`, `CrewHonor`, `CrewHonorMath`, `GroupRepository.consistencyHonor(groupID:)` | S1.3 |
| `GymSyncApp/GymSyncTests/CrewHonorMathTests.swift` | the crown, the decay, the tie-break, the copy | S1.3 |
| `GymSyncApp/GymSyncTests/CrewHonorLiveRepositoryTests.swift` | the RPC decodes, read-only, against the CI account's own crew | S1.3 |
| `GymSyncApp/GymSyncTests/PresenceIsUngatedTests.swift` | spec §4 pinned: the two presence predicates and their arity | S1.5 |
| `GymSyncApp/GymSync/Features/Social/CrewsTabFixtures.swift` | the hermetic world `crews-tab` renders | S1.6 |
| `GymSyncApp/GymSync/Models/PostTrajectory.swift` | `PostHighlightKind`, `PostHighlight`, `PostTrajectory`, `PostLateness` — the frozen interface | S2.0 |
| `GymSyncApp/GymSyncTests/PostTrajectoryModelTests.swift` | wire shape: camelCase, absent-not-null, round trips | S2.0 |
| `supabase/migrations/20260912000001_workout_posts_trajectory.sql` | the six new `workout_posts` columns | S2.1 |
| `GymSyncApp/GymSync/DesignSystem/GSGoalChip.swift` | the goal chip, extracted from the Home strip, byte-identical | S2.3 |
| `GymSyncApp/GymSyncTests/GSGoalChipTests.swift` | the fill rule and the met rule | S2.3 |
| `GymSyncApp/GymSync/Models/PostTrajectoryMath.swift` | standing, chips, the card's line — pure | S2.4 |
| `GymSyncApp/GymSyncTests/PostTrajectoryMathTests.swift` | every standing, every chip shape | S2.4 |
| `GymSyncApp/GymSync/Models/HighlightMath.swift` | Coach's proposals + `HighlightText.line(_:unit:)` | S2.5 |
| `GymSyncApp/GymSyncTests/HighlightMathTests.swift` | the two kinds this release offers, the dedupe, the viewer's unit | S2.5 |
| `GymSyncApp/GymSync/Models/PostTrajectoryResolver.swift` | the one async read the two context builders share | S2.6 |
| `GymSyncApp/GymSyncTests/PostLatenessTests.swift` | elapsed, derived `is_late`, the tag's three scales | S2.6 |
| `GymSyncApp/GymSyncTests/WorkoutPostLiveRepositoryTests.swift` | the six columns round-trip against the live table | S2.6 |
| `GymSyncApp/GymSync/Features/Workout/PumpComposerFixtures.swift` | the in-process fixture photo the review state's frame needs | S2.6a |
| `GymSyncApp/GymSyncTests/PumpPostCardCopyTests.swift` | the card's seven lines, as strings | S2.7 |

### Modified

| File | Change | Task |
|---|---|---|
| `GymSyncApp/GymSync/Features/Social/SocialTabView.swift` | the honor line on the crew card; the catalog init | S1.4, S1.6 |
| `scripts/seed_qa_fixtures.js` | a participant row on the crew's completed session (S1.4); the CI account's feed post (S2.10) | S1.4, S2.10 |
| `GymSyncApp/GymSync/Features/Social/VenueHubViews.swift` | `showsWhosHere(isCheckedIn:)`, and the law above it | S1.5 |
| `GymSyncApp/GymSync/Features/Home/HomeView.swift` | `showsCrewPulse(liveFriendCount:)`, and the law above it | S1.5 |
| `GymSyncApp/GymSync/App/CatalogHostView.swift` | `crews-tab` (S1.6); `PumpCheckContext`'s four new fields in `content_pumpComposer` (S2.6); `pump-composer-highlight` (S2.6a); `pump-feed-post` re-rendered (S2.9) | S1.6, S2.6, S2.6a, S2.9 |
| `GymSyncApp/GymSyncTests/CatalogScreenTests.swift` | `"crews-tab"` (S1.6); `"pump-composer-highlight"` (S2.6a) | S1.6, S2.6a |
| `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` | `testCatalogCrewsTab()` (S1.6); `testCatalogPumpComposerHighlight()` (S2.6a); `testPumpFeedLive()` (S2.10) | S1.6, S2.6a, S2.10 |
| `docs/design/frame-map.json` | frame 101 (S1.6); frame 102 (S2.6a) | S1.6, S2.6a |
| `GymSyncApp/GymSync/Models/WorkoutPost.swift` | six fields + `PostSummary.routineName` (S2.0); `create`'s new arguments (S2.6); `unreact` deleted (S2.8) | S2.0, S2.6, S2.8 |
| `supabase/tests/workout_posts_test.sql` | `plan(15)` → `plan(23)` | S2.2 |
| `GymSyncApp/GymSync/Features/Home/V2/HomeWeeklyGoalStrip.swift` | `chipView`/`meter`/`fraction` → `GSGoalChip` | S2.3 |
| `GymSyncApp/GymSync/Models/WeeklyGoal.swift` | the switch-site count in `WeeklyGoalKind`'s doc comment | S2.4 |
| `GymSyncApp/GymSync/Features/Workout/PumpCheckComposer.swift` | retake count, the highlight picker, the new payload (S2.6); the `#if DEBUG catalogPhoto` seam (S2.6a) | S2.6, S2.6a |
| `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift` | `PumpCheckContext`'s new fields | S2.6 |
| `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift` | `PumpCheckContext`'s new fields | S2.6 |
| `GymSyncApp/GymSync/Features/Social/PumpFeedView.swift` | the card's seven lines (S2.7); reactions commit (S2.8) | S2.7, S2.8 |
| `.github/workflows/ios.yml` | `FLOOR=107` → `FLOOR=110` | I1, and only I1 |
| `docs/design/accepted-deviations.json` | the `crews-tab` and `pump-composer-highlight` entries | I1 |

### Deleted

| Symbol | Why |
|---|---|
| `WorkoutPostRepository.unreact(postID:emoji:)` (`WorkoutPost.swift:227-238`) | Spec §2 and owner decision 4: a kudos is one gesture and **irreversible**. Grep-verified: its only call site is `PumpFeedView.toggleReaction` (:177), which S2.8 rewrites into a commit. Leaving an uncalled repository method behind is this project's own recurring defect (complete logic, no call site); the `post_reactions` DELETE **policy** stays, because account deletion and the post's own `ON DELETE CASCADE` rely on it. |

---

## New catalog ids and the FLOOR

| id | frame | title | stage | proves |
|---|---|---|---|---|
| `crews-tab` | 101 | Crews tab — two crews, one with the honor line | 1 | spec §3: `MOST CONSISTENT · SAM · 9 SESSIONS` on one card and absent on the other |
| `pump-composer-highlight` | 102 | Pump composer — Coach's picks | 2 | spec §1 line 4: the review state with the proposals, one selected, and `Post` still the only accent |

`pump-feed-post` is an **existing** id (`CatalogHostView.swift:63`) and keeps it. It has no `frame-map.json`
entry today and gains none — it has no canvas lineage, like 35 other catalog ids — so S2.9 changes what it
renders, not what it is called, and adds no capture.

**One capture that is not a catalog id:** `app-pump-feed.png`, from `testPumpFeedLive()` (task S2.10) — a
live-account walk, Crews → Feed, of the post `seed_qa_fixtures.js` writes. It gets **no `frame-map.json`
entry**, which is how this repo already treats a walk capture with no canvas lineage (`app-group-stats` has
none either; `app-tab-social` and `app-friends` have entries only because frames 62 and 19 exist for them).
It counts toward the `FLOOR` like every other exported file.

**`FLOOR` 107 → 110** — `app-crews-tab` + `app-pump-composer-highlight` + `app-pump-feed`.

**`FLOOR` 107 → 110**, in integration task **I1**, once.

---

## Sequencing

```
                         ┌──► STAGE 1 · the Crews card and the presence rule   (S1.1 … S1.6)
                         │      feat/social-cards-crews · touches no goal-first file
 origin/master (f00f208) ┤
   PR #42 already in     │
                         └──► STAGE 2 · the trajectory snapshot        (S2.0 … S2.6a … S2.10)
                                feat/social-cards-post · S2.0 is the frozen interface;
                                nothing below it starts before it is pushed
                                            │
                         both merge ────────┤  Stage 1 first (it owns frame 101)
                                            ▼
                                     INTEGRATION                              (I1 … I3)
                                       feat/social-cards → ONE PR, with proof cards
```

**No rebase arrow, because there is nothing to wait for:** PR #42 is on `master` (`fed2f42`, docs merge
`f00f208`), so both stages fork the same base and may run in parallel or in sequence. Stage 1 merges first at
integration: it owns frame 101 and Stage 2 owns 102, so merging the other way round would leave the
frame-map's append order out of frame order.

Inside Stage 2, S2.0 is the only ordering constraint that matters: **S2.1 … S2.10 all type against it.**
After S2.0, the honest order is S2.1 → S2.2 (backend, so the gate in constraint 10 can run early), then
S2.3 → S2.4 → S2.5 (pure, independent of each other), then S2.6 (the write path), S2.6a (its frame),
S2.7 → S2.8 (the read path), S2.9 (the fixture), S2.10 (the seed and its walk).

---

# STAGE 1 — the Crews card and the presence rule

Spec §3 and §4. Six tasks. Forks from `origin/master` (`f00f208` or later) on `feat/social-cards-crews`;
touches no goal-first file, which is what lets it run beside Stage 2 rather than behind it.

### S1.1 — `group_consistency_honor`, the 30-day frequency read — **M**

**File (new):** `supabase/migrations/20260911000001_crew_consistency_honor.sql`

**Why an RPC at all, when spec §6 says "no table".** It is not a table. It is a function, and it exists
because the client-side read the spec describes cannot see what it needs:
`20260709000006_create_sessions.sql:49-54` scopes `sessions` SELECT to `organizer_id = auth.uid() OR
is_session_participant(...)`, so `SessionRepository.groupSessions(groupID:)` returns **only the sessions the
viewer was in**. Counting per-member from that would render "who I lifted with most" under the words "most
consistent" — a plausible-looking wrong answer, which is the hardest kind to catch in a design round. The
third sibling of `group_stats` / `group_member_stats` (`20260720000003_group_stats_rpc.sql`) is the shape this
repo already uses for exactly this problem, gate and grants included.

Write exactly this:

```sql
-- 20260911000001_crew_consistency_honor.sql
--
-- Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §3 — the
-- Crews card gains FREQUENCY honor, not performance: "who showed up most this
-- month", a crown that decays when they stop (rolling 30 days, ties to the
-- earlier achiever). Plan: docs/superpowers/plans/2026-09-11-social-cards
-- -plan.md, task S1.1.
--
-- THE THIRD SIBLING of group_stats / group_member_stats
-- (20260720000003_group_stats_rpc.sql), and written in that file's shape
-- deliberately: gate FIRST with is_group_member, LEFT JOIN LATERAL per member
-- so two unrelated cardinalities cannot multiply, REVOKE then GRANT.
--
-- WHY THIS IS NOT A CLIENT-SIDE COUNT. `sessions` SELECT RLS is
-- organizer-or-participant (20260709000006_create_sessions.sql:49-54), so the
-- read the card already makes returns only the sessions the VIEWER was in.
-- Counting per-member from that answers "who did I lift with most", under a
-- label that says "who showed up most". SECURITY DEFINER is what makes the
-- label true.
--
-- WHO SHOWED UP = session_participants, not organizer_id. A crew's sessions
-- are scheduled by one person and attended by several; crediting the
-- organizer would make the crown a scheduling award.
--
-- THE TIE-BREAK IS `reached_at ASC` — the LATEST qualifying session of each
-- member, which is the moment they reached the count they now hold. Spec §3:
-- "ties to the earlier achiever". Spec §9.2 leaves the tie-break's WORDING
-- open; this decides only the ORDER, which a card that prints one name has to
-- have.
CREATE OR REPLACE FUNCTION public.group_consistency_honor(p_group_id uuid)
RETURNS TABLE (
  user_id    uuid,
  username   text,
  sessions   int,
  reached_at timestamptz
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT public.is_group_member(p_group_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT gm.user_id,
         p.username,
         COALESCE(agg.session_count, 0)::int AS sessions,
         agg.last_completed_at               AS reached_at
    FROM public.group_members gm
    JOIN public.profiles p ON p.id = gm.user_id
    LEFT JOIN LATERAL (
      SELECT count(DISTINCT s.id) AS session_count,
             max(s.completed_at)  AS last_completed_at
        FROM public.sessions s
        JOIN public.session_participants sp
          ON sp.session_id = s.id AND sp.user_id = gm.user_id
       WHERE s.group_id = p_group_id
         AND s.state = 'completed'
         AND s.completed_at IS NOT NULL
         AND s.completed_at >= now() - interval '30 days'
    ) agg ON true
   WHERE gm.group_id = p_group_id
     -- A member who has not trained in the window is ABSENT, not a zero row:
     -- the crown decays by the row disappearing, and an empty result is the
     -- card's "no honor line" state.
     AND COALESCE(agg.session_count, 0) > 0
   ORDER BY COALESCE(agg.session_count, 0) DESC, agg.last_completed_at ASC;
END;
$$;

-- Self-gated by the is_group_member check above — the same revoke-then-grant
-- idiom as group_stats / group_member_stats. Newly created functions get
-- PUBLIC EXECUTE by default, which anon inherits.
REVOKE EXECUTE ON FUNCTION public.group_consistency_honor(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_consistency_honor(uuid) TO authenticated;
```

**Interfaces** — *consumes:* `public.is_group_member(uuid, uuid)`
(`20260725000002_is_group_member_private_schema.sql`), `group_members`, `profiles`, `sessions`,
`session_participants`. *Produces:* `public.group_consistency_honor(uuid)`, decoded by S1.3's `CrewHonorRow`.

**TDD steps.**

1. Write the migration exactly as above.
2. **Apply it** to project `chjkkwqwdlmaxacwglzm` (operator, or Supabase MCP `apply_migration`) — constraint
   10. S1.2's pgTAP fails without this, and the commit body records the timestamp it was applied.
3. Verify by hand, as the operator, that the function exists and is `SECURITY DEFINER`:
   `SELECT prosecdef FROM pg_proc WHERE proname = 'group_consistency_honor';` → `t`.
4. Commit: `feat(social): group_consistency_honor — who showed up most, over 30 days` + the trailer.

**Proves:** the function exists on the live project and pgTAP (S1.2) can address it.

---

### S1.2 — pgTAP for the honor RPC — **M**

**File (new):** `supabase/tests/crew_consistency_honor_test.sql`

Eight assertions, in this suite's own UUID namespace (`09xx`, unused — grep-verified against every file in
`supabase/tests/`). The fixture: one crew, three members, sessions inside and outside the window.

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

-- Spec §3 / plan task S1.2. group_consistency_honor(p_group_id): the 30-day
-- frequency read behind the Crews card's honor line.
-- Fixture block: 09xx UUIDs (this suite's namespace).
--   A = ...0901 member, 2 sessions in-window (the crown)
--   B = ...0902 member, 2 sessions in-window but LATER (loses the tie-break)
--   C = ...0903 member, 1 session 40 days ago (out of the window)
--   D = ...0904 NON-member (the gate)
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000901', 'honor-a@test.local'),
  ('00000000-0000-4000-f000-000000000902', 'honor-b@test.local'),
  ('00000000-0000-4000-f000-000000000903', 'honor-c@test.local'),
  ('00000000-0000-4000-f000-000000000904', 'honor-d@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000000901', 'honor_a'),
  ('00000000-0000-4000-f000-000000000902', 'honor_b'),
  ('00000000-0000-4000-f000-000000000903', 'honor_c'),
  ('00000000-0000-4000-f000-000000000904', 'honor_d');

INSERT INTO groups (id, created_by, name) VALUES
  ('00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'Honor Crew');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000901', 'admin'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000902', 'member'),
  ('00000000-0000-4000-f000-000000000910', '00000000-0000-4000-f000-000000000903', 'member');

-- Five sessions: A in two (older), B in two (newer — the tie-break loser),
-- C in one that closed 40 days ago, and one A was NOT in that is still open.
INSERT INTO sessions (id, group_id, organizer_id, state, started_at, completed_at) VALUES
  ('00000000-0000-4000-f000-000000000921', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'completed', now() - interval '9 days',  now() - interval '9 days'),
  ('00000000-0000-4000-f000-000000000922', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'completed', now() - interval '5 days',  now() - interval '5 days'),
  ('00000000-0000-4000-f000-000000000923', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000902', 'completed', now() - interval '4 days',  now() - interval '4 days'),
  ('00000000-0000-4000-f000-000000000924', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000902', 'completed', now() - interval '1 day',   now() - interval '1 day'),
  ('00000000-0000-4000-f000-000000000925', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000903', 'completed', now() - interval '40 days', now() - interval '40 days'),
  ('00000000-0000-4000-f000-000000000926', '00000000-0000-4000-f000-000000000910',
   '00000000-0000-4000-f000-000000000901', 'in_progress', now(), NULL);
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000000921', '00000000-0000-4000-f000-000000000901'),
  ('00000000-0000-4000-f000-000000000922', '00000000-0000-4000-f000-000000000901'),
  ('00000000-0000-4000-f000-000000000923', '00000000-0000-4000-f000-000000000902'),
  ('00000000-0000-4000-f000-000000000924', '00000000-0000-4000-f000-000000000902'),
  ('00000000-0000-4000-f000-000000000925', '00000000-0000-4000-f000-000000000903'),
  ('00000000-0000-4000-f000-000000000926', '00000000-0000-4000-f000-000000000901');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000901';

-- 1. A member gets rows.
SELECT results_eq(
  $$SELECT count(*)::int FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910')$$,
  $$VALUES (2)$$,
  'only members who trained in the window appear');

-- 2. The crown is A: equal counts, earlier last session.
SELECT results_eq(
  $$SELECT username FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') LIMIT 1$$,
  $$VALUES ('honor_a'::text)$$,
  'a tie goes to the earlier achiever');

-- 3. The count is DISTINCT completed sessions in the window.
SELECT results_eq(
  $$SELECT sessions FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') WHERE username = 'honor_a'$$,
  $$VALUES (2)$$,
  'the in-progress session does not count');

-- 4. Out of the window is out of the honor.
SELECT is_empty(
  $$SELECT 1 FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') WHERE username = 'honor_c'$$,
  'a session 40 days old has decayed out');

-- 5. `reached_at` is the member's LATEST qualifying completion.
SELECT results_eq(
  $$SELECT (reached_at::date = (now() - interval '5 days')::date)
      FROM public.group_consistency_honor(
        '00000000-0000-4000-f000-000000000910') WHERE username = 'honor_a'$$,
  $$VALUES (true)$$,
  'reached_at is when they reached the count they hold');

-- 6. Ordering is count DESC first — B alone after A's sessions are removed.
SELECT results_eq(
  $$SELECT username FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910') ORDER BY sessions DESC, username LIMIT 2$$,
  $$VALUES ('honor_a'::text), ('honor_b'::text)$$,
  'both tied members are returned, crown first');

-- 7. A non-member is refused, not given an empty list.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000904';
SELECT throws_ok(
  $$SELECT * FROM public.group_consistency_honor(
      '00000000-0000-4000-f000-000000000910')$$,
  'P0001', 'not a member of this group',
  'a non-member cannot read a crew''s honor');

-- 8. anon holds no EXECUTE.
SELECT ok(
  NOT has_function_privilege('anon', 'public.group_consistency_honor(uuid)', 'EXECUTE'),
  'anon cannot execute the honor function');

SELECT * FROM finish();
ROLLBACK;
```

**TDD steps.** 1. Write the file. 2. Push — Backend CI runs it against the live project (which S1.1 already
migrated). 3. Read the TAP output: 8/8. 4. Commit:
`test(social): pgTAP for group_consistency_honor — window, ordering, tie-break, gate` + the trailer.

**Proves:** the honor read is gated, windowed, attributed to attendance, and deterministically ordered.

---

### S1.3 — the honor, as a value the card can hold — **M**

**File (new):** `GymSyncApp/GymSync/Models/CrewHonor.swift`

```swift
import Foundation

// MARK: - The crew's frequency honor
//
// Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §3.
// Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, task S1.3.
//
// FREQUENCY, NOT PERFORMANCE (owner decision 5). The crown is "who showed up
// most this month" over a rolling 30 days — pace-, weight- and volume-blind,
// and continuously losable. Volume already has two homes (the recap and the
// venue hub); this is deliberately not a third.

/// One row of `group_consistency_honor(p_group_id)` (migration
/// 20260911000001).
struct CrewHonorRow: Decodable, Sendable, Equatable {
    let userID: UUID
    let username: String
    let sessions: Int
    /// The member's LATEST qualifying completion — the moment they reached
    /// the count they now hold, and therefore the tie-break.
    let reachedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case sessions
        case reachedAt = "reached_at"
    }
}

/// The one name the card prints.
struct CrewHonor: Equatable, Sendable {
    let username: String
    let sessions: Int
}

enum CrewHonorMath {

    /// The crown, or **nil when nobody has trained in the window** — which is
    /// how the honor DECAYS (spec §3: "a crown that decays when they stop").
    /// A crew at rest has no honor line at all; it does not have an honor
    /// line reading zero.
    ///
    /// The server already orders the rows, and this re-derives the winner
    /// anyway: an ORDER BY is a detail of one query, and the card's meaning
    /// should not move if that query is ever paged, cached or re-sorted.
    static func crown(_ rows: [CrewHonorRow]) -> CrewHonor? {
        let earned = rows.filter { $0.sessions > 0 }
        guard let best = earned.min(by: { lhs, rhs in
            // Most sessions first; on a tie, the EARLIER achiever (spec §3).
            if lhs.sessions != rhs.sessions { return lhs.sessions > rhs.sessions }
            return lhs.reachedAt < rhs.reachedAt
        }) else { return nil }
        return CrewHonor(username: best.username, sessions: best.sessions)
    }

    /// `MOST CONSISTENT · SAM · 9 SESSIONS` — spec §3's line, verbatim.
    ///
    /// Caps because it is a kicker (design rule 3), and the username is
    /// upper-cased here rather than by the view so the one place that decides
    /// the sentence also decides its case.
    static func line(_ honor: CrewHonor) -> String {
        let noun = honor.sessions == 1 ? "SESSION" : "SESSIONS"
        return "MOST CONSISTENT · \(honor.username.uppercased()) · \(honor.sessions) \(noun)"
    }
}

extension GroupRepository {
    /// The crew's 30-day frequency honor. Best-effort, like every other read
    /// the Crews tab makes: a failure leaves the card without an honor line,
    /// never with an error.
    static func consistencyHonor(groupID: UUID) async throws -> [CrewHonorRow] {
        do {
            return try await SupabaseService.shared.client
                .rpc("group_consistency_honor", params: ["p_group_id": groupID.uuidString])
                .execute()
                .value
        } catch { throw ErrorMapping.map(error) }
    }
}
```

**Interfaces** — *consumes:* `SupabaseService.shared.client`, `ErrorMapping.map` (the idiom every
`GroupRepository` method uses, `GymGroup.swift:84-290`). *Produces:* `CrewHonorRow`, `CrewHonor`,
`CrewHonorMath.crown(_:)`, `CrewHonorMath.line(_:)`, `GroupRepository.consistencyHonor(groupID:)` — S1.4 and
S1.6 consume all four.

**TDD steps.**

1. Write the failing test first — `GymSyncApp/GymSyncTests/CrewHonorMathTests.swift`:

```swift
import XCTest
@testable import GymSync

/// Spec §3's crown: frequency, decaying, tie-broken to the earlier achiever.
final class CrewHonorMathTests: XCTestCase {

    private func row(_ username: String, _ sessions: Int,
                     daysAgo: Double) -> CrewHonorRow {
        CrewHonorRow(userID: UUID(), username: username, sessions: sessions,
                     reachedAt: Date(timeIntervalSince1970: 1_788_696_000
                                     - daysAgo * 86_400))
    }

    func testTheCrownIsTheMostSessions() {
        let crown = CrewHonorMath.crown([row("sam", 9, daysAgo: 1),
                                         row("dana", 4, daysAgo: 2)])
        XCTAssertEqual(crown, CrewHonor(username: "sam", sessions: 9))
    }

    func testATieGoesToTheEarlierAchiever() {
        // Dana reached 6 four days ago; Sam reached 6 yesterday.
        let crown = CrewHonorMath.crown([row("sam", 6, daysAgo: 1),
                                         row("dana", 6, daysAgo: 4)])
        XCTAssertEqual(crown?.username, "dana")
    }

    func testACrewAtRestHasNoCrown() {
        XCTAssertNil(CrewHonorMath.crown([]))
        XCTAssertNil(CrewHonorMath.crown([row("sam", 0, daysAgo: 1)]))
    }

    func testTheLineIsTheSpecsLine() {
        XCTAssertEqual(CrewHonorMath.line(CrewHonor(username: "sam", sessions: 9)),
                       "MOST CONSISTENT · SAM · 9 SESSIONS")
    }

    func testOneSessionIsSingular() {
        XCTAssertEqual(CrewHonorMath.line(CrewHonor(username: "dana", sessions: 1)),
                       "MOST CONSISTENT · DANA · 1 SESSION")
    }
}
```

2. Push. `CrewHonorMathTests` fails to compile — `CrewHonor*` does not exist yet. That is the red.
3. Write `Models/CrewHonor.swift` exactly as above.
4. Write the live-DB read's test — `GymSyncApp/GymSyncTests/CrewHonorLiveRepositoryTests.swift`. It is
   **read-only**, so it registers no teardown (constraint 6 governs writes) and it skips where secrets are
   placeholders, the `TestAuth.signInIfConfigured()` idiom every live test in this repo opens with:

```swift
import XCTest
@testable import GymSync

/// `group_consistency_honor` against the live project, as the CI account.
/// READ-ONLY: this test writes nothing, so it has no teardown to register —
/// the row it reads is `scripts/seed_qa_fixtures.js`'s own `[QA] Push Crew`.
final class CrewHonorLiveRepositoryTests: XCTestCase {

    func testTheHonorRPCDecodes() async throws {
        try await TestAuth.signInIfConfigured()
        let groups = try await GroupRepository.myGroups()
        let crew = groups.first { $0.name.hasPrefix("[QA] ") }
        let group = try XCTUnwrap(crew, "seed_qa_fixtures.js has not run for this account")

        // Bind, THEN unwrap — `XCTUnwrap(await …)` is a compile error in this
        // target's Swift mode (global constraint 4).
        let rows = try await GroupRepository.consistencyHonor(groupID: group.id)
        XCTAssertFalse(rows.isEmpty,
                       "the seeded crew has one completed session with a participant row")
        let crown = try XCTUnwrap(CrewHonorMath.crown(rows))
        XCTAssertGreaterThan(crown.sessions, 0)
    }
}
```

5. Push. Both green.
6. Commit: `feat(social): the crew's frequency honor — the crown, its decay, its tie-break` + the trailer.

**Proves:** the crown is a tested value with a live read behind it, before any view renders it.

---

### S1.4 — the honor line on the crew card — **M**

**Files:** `GymSyncApp/GymSync/Features/Social/SocialTabView.swift`, `scripts/seed_qa_fixtures.js`.

Spec §3: "the meta line names who showed up most this month". The card keeps everything it has — avatar, name,
unread dot, the plate bar, the meta line — and gains **one** line under the meta line. Absent when there is no
crown; "a blank line is not a state".

**The view.** Add the state, the fetch and the line:

```swift
/// The crew's 30-day frequency crown, per group (spec §3). Absent for a crew
/// nobody has trained with in the window — the crown DECAYS by disappearing.
@State private var honorByGroup: [UUID: CrewHonor] = [:]
```

In `groupRow(_:)`, immediately after the existing `crewMetaLine` `Text` (:445-451) and inside the same
`VStack`:

```swift
if let honor = honorByGroup[group.id] {
    Text(CrewHonorMath.line(honor))
        .font(GSFont.bold(9.5, relativeTo: .caption2))
        .kerning(0.8)
        .foregroundStyle(theme.neutral500)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .monospacedDigit()
}
```

Same type scale, tracking and tint as the meta line above it (design rule 3: kickers are muted caps), and no
accent — a finished month is not an invitation (rule 2).

In `refresh()`, beside the existing `barByGroup` task group and in the same best-effort shape (stale entries
preserved on failure):

```swift
// The crew's frequency honor (spec §3), widened to 30 days and read through
// `group_consistency_honor` rather than the bar's own session list — the bar
// counts what RLS lets THIS VIEWER see (organizer-or-participant,
// 20260709000006_create_sessions.sql:49-54), which is the wrong question for
// a line that says "who showed up most".
var honorMeta = honorByGroup
await withTaskGroup(of: (UUID, CrewHonor?).self) { taskGroup in
    for group in currentGroups {
        taskGroup.addTask {
            guard let rows = try? await GroupRepository.consistencyHonor(groupID: group.id) else {
                return (group.id, nil)
            }
            return (group.id, CrewHonorMath.crown(rows))
        }
    }
    for await (id, honor) in taskGroup {
        if let honor { honorMeta[id] = honor }
    }
}
honorByGroup = honorMeta
```

> **AMENDED (integration, 2026-09-12) — fix round 1 supersedes the snippet above.** Two things were wrong
> with it and both shipped differently (`SocialTabView.swift`, `refresh()`):
>
> 1. **The crown decays.** `if let honor { honorMeta[id] = honor }` could only ever ADD a crown: a crew whose
>    30-day window had emptied kept the last crown it was given for the life of the process, which is the
>    exact opposite of spec §3's "a crown that decays when they stop". The shipped read carries an explicit
>    `honorOK` flag that separates *"the RPC answered, and the answer is nobody"* from *"the RPC failed"*, and
>    assigns on the first — `honorMeta[id] = honor` with a **nil** `honor` removes the key, and the line
>    disappears. A failed read still preserves the previous value. Both dictionaries are also rebuilt from
>    `currentGroups` rather than carried forward wholesale, so a crew you left cannot keep its bar or its
>    crown.
> 2. **One task group, not two.** The bar read and the honor read run **concurrently inside one task group,
>    one child task per crew** (`async let sessionsRead` beside `async let honorRead`), rather than in a
>    second group after the bar's. Two sequential groups meant two `@State` writes and therefore two paints,
>    and `ScreenshotTests.settleAfterNavigation` is a fixed 1.0 s — the capture could land between them and
>    photograph a card with a bar and no honor line.

**The seed.** `scripts/seed_qa_fixtures.js`, in the "sessions in each state" block (:305-315): the crew's
sessions are created with a `group_id` and **no participants**, so the honor read returns nothing for the one
crew the CI account has, and `app-tab-social` would prove nothing. Add a participant row for the completed one
only:

```js
  const states = ['scheduled', 'lobby_open', 'voting', 'locked', 'in_progress', 'completed'];
  const now = new Date().toISOString();
  for (const state of states) {
    const row = { group_id: group.id, organizer_id: me.id, state, scheduled_for: now };
    if (state === 'in_progress') row.started_at = now;
    if (state === 'completed') { row.started_at = now; row.completed_at = now; }
    const [created] = await rest('sessions', { method: 'POST', headers: rep,
      body: JSON.stringify(row) });
    // ONLY the completed one gets a participant row, and only because
    // `group_consistency_honor` (20260911000001) credits ATTENDANCE rather
    // than the organizer — without it the CI account's crew has no honor line
    // and `app-tab-social` proves nothing. The other five states are left
    // exactly as they were: adding participants to them would change what
    // testLobby/testSessionRecap capture.
    if (state === 'completed') {
      await rest('session_participants', { method: 'POST',
        body: JSON.stringify({ session_id: created.id, user_id: me.id }) });
    }
  }
```

**Interfaces** — *consumes:* `CrewHonorMath.crown(_:)`, `CrewHonorMath.line(_:)`,
`GroupRepository.consistencyHonor(groupID:)` (S1.3). *Produces:* `SocialTabView.honorByGroup`, which S1.6's
catalog init seeds directly.

**TDD steps.**

1. The behaviour under test is `CrewHonorMath`, already covered by S1.3 — this task's proof is a **capture**,
   which is the discipline this repo uses for a view with no logic of its own (`GoalStripFixtures`' own note).
   Write the view change and the seed change.
2. Push.
3. Read the artifact: `app-tab-social` shows the `[QA] Push Crew` card with a fourth line reading
   `MOST CONSISTENT · CI_TEST_USER · 1 SESSION`, under the existing `1 TOGETHER THIS WK · …` meta line.
4. Commit: `feat(social): the Crews card names who showed up most this month` + the trailer.

**Proves:** spec §3 end to end — seed → RPC → crown → line — in `app-tab-social`.

---

### S1.5 — presence is ambient, and the rule is pinned — **S**

**Files:** `GymSyncApp/GymSync/Features/Social/VenueHubViews.swift`,
`GymSyncApp/GymSync/Features/Home/HomeView.swift`,
`GymSyncApp/GymSyncTests/PresenceIsUngatedTests.swift` (new).

Spec §4 adds no feature. It forbids three futures, and the reference scan names the evidence (Peloton gated
its feed to milestones in February 2026 and shipped a whole new banner to compensate). The build item is
therefore a **guard**, and the guard is arity: each presence surface's visibility becomes a one-parameter
static predicate, so a gate cannot be added without changing a signature that a test names.

`VenueHubViews.swift`, above `whosHereSection` (:526):

```swift
    /// **PRESENCE IS NEVER GATED** (spec §4, owner decision 6).
    ///
    /// The ONLY precondition this surface may carry is physical: you are
    /// checked in to this venue. Never a post, never a streak, never an
    /// entitlement — the reference scan's Peloton note
    /// (`.superpowers/sdd/2026-09-07-social-cards-round/reference-scan.md`)
    /// is what that costs when it is broken.
    ///
    /// A ONE-PARAMETER STATIC, on purpose: it is the guard. Adding a gate
    /// means adding a parameter, which breaks `PresenceIsUngatedTests` and
    /// makes the change a conversation rather than a quiet edit.
    static func showsWhosHere(isCheckedIn: Bool) -> Bool { isCheckedIn }
```

and `whosHereSection`'s first line becomes `if Self.showsWhosHere(isCheckedIn: isCheckedIn) {`.

`HomeView.swift`, above `crewPulseSection` (:726) — the same treatment for the strip the owner's ruling 2
already scoped to "a friend is actually lifting":

```swift
    /// **PRESENCE IS NEVER GATED** (spec §4, owner decision 6). See
    /// `VenueHubView.showsWhosHere(isCheckedIn:)` for the full law; the same
    /// arity guard applies here.
    static func showsCrewPulse(liveFriendCount: Int) -> Bool { liveFriendCount > 0 }
```

and `crewPulseSection` becomes `if Self.showsCrewPulse(liveFriendCount: friendsLive.count), let friend = friendsLive.first {`.

**Interfaces** — *consumes:* nothing. *Produces:* `VenueHubView.showsWhosHere(isCheckedIn:)`,
`HomeView.showsCrewPulse(liveFriendCount:)`.

**TDD steps.**

1. Write the failing test first — `GymSyncApp/GymSyncTests/PresenceIsUngatedTests.swift`:

```swift
import XCTest
@testable import GymSync

/// Spec §4 — presence surfaces stay ambient and ungated: the venue hub's
/// "who's here" rows and Home's crew pulse never require a post, a streak or
/// a payment to be seen.
///
/// THE ASSERTION IS THE ARITY. A rule this shape cannot be checked by calling
/// it with `hasPro: false` — there is no such parameter, and that IS the
/// point. These tests pin the two predicates' signatures, so the day someone
/// wires an entitlement in, this file stops compiling and the rule is read
/// before it is broken rather than after.
final class PresenceIsUngatedTests: XCTestCase {

    func testWhosHereAsksOnlyWhetherYouAreCheckedIn() {
        XCTAssertTrue(VenueHubView.showsWhosHere(isCheckedIn: true))
        XCTAssertFalse(VenueHubView.showsWhosHere(isCheckedIn: false))
    }

    func testTheCrewPulseAsksOnlyWhetherAFriendIsLifting() {
        XCTAssertTrue(HomeView.showsCrewPulse(liveFriendCount: 1))
        XCTAssertFalse(HomeView.showsCrewPulse(liveFriendCount: 0))
    }

    /// Spec §4's own phase-2 marker, written down where it will be found.
    /// Live encouragement — a cheer to someone lifting right now — is
    /// DESIGNED and NOT BUILT. Nothing in this build sends one.
    func testLiveEncouragementIsNotBuilt() {
        XCTAssertFalse(HomeCrewPulseStripCheerIsBuilt,
                       "spec §4: live encouragement is phase 2 — see the plan's 'does not decide'")
    }
}

/// Phase 2's flag, and its only definition. A cheer surface arriving is this
/// constant turning true, plus the test above changing with it.
let HomeCrewPulseStripCheerIsBuilt = false
```

2. Push — red (neither static exists).
3. Add the two statics and re-point the two call sites.
4. Push — green; `app-tab-home` and `app-venue-hub` unchanged.
5. Commit: `feat(social): presence is ungated, and the rule is a signature` + the trailer.

**Proves:** spec §4 is enforced by the compiler rather than by memory, and phase 2 is recorded.

---

### S1.6 — `crews-tab`, the Crews tab's first catalog id — **M**

**Files:** `App/CatalogHostView.swift`, `GymSyncTests/CatalogScreenTests.swift`,
`GymSyncUITests/ScreenshotTests.swift`, `docs/design/frame-map.json`,
`Features/Social/SocialTabView.swift`, and a new `Features/Social/CrewsTabFixtures.swift`.

One id, one commit, all four contract parts (constraint 3). **The Crews tab has never had a fixture world** —
`app-tab-social` is the live-account walk (context map, "Catalog ids / fixture worlds"), so the crew card, its
bar, the honor line and the Outside-the-Box rows have never been rendered from values.

| id | frame | renders |
|---|---|---|
| `crews-tab` | 101 | `SocialTabView` with two crews — Push Crew **with** the honor line, Sunday Squad **without** |

**The seam.** `SocialTabView` gains the `catalogFixture*` + `catalogSkipLoad` init `VenueHubView` already
established (`VenueHubViews.swift:294-308`), so `refresh()` never runs and no repository is reachable
(constraint 7):

```swift
    #if DEBUG
    var catalogSkipLoad = false

    /// The catalog's world (plan task S1.6). `VenueHubView`'s own init is the
    /// precedent; the same rule applies — `catalogSkipLoad` suppresses
    /// `refresh()` entirely, so no repository, no clock and no network is
    /// reachable from a frame.
    init(catalogFixtureGroups: [GymGroup] = [],
         catalogFixtureBars: [UUID: CrewBarMeta] = [:],
         catalogFixtureHonors: [UUID: CrewHonor] = [:],
         catalogFixtureFriendCount: Int = 0,
         catalogFixturePendingCount: Int = 0,
         catalogSkipLoad: Bool = false) {
        _groups = State(initialValue: catalogFixtureGroups)
        _barByGroup = State(initialValue: catalogFixtureBars)
        _honorByGroup = State(initialValue: catalogFixtureHonors)
        _friendCount = State(initialValue: catalogFixtureFriendCount)
        _pendingCount = State(initialValue: catalogFixturePendingCount)
        self.catalogSkipLoad = catalogSkipLoad
    }
    #else
    init() {}
    #endif
```

and every `.task`/`.refreshable` entry point into `refresh()` gains the guard the init implies:

```swift
    private func refresh() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        lastRefreshedAt = .now
        …
```

**The fixtures** — `Features/Social/CrewsTabFixtures.swift`, hermetic, fixed ids (because
`GSGroupColor.color(for:)` keys off `group.id`, so a random id would repaint the avatar between runs):

```swift
import Foundation

// MARK: - The Crews tab's fixture world
//
// Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, task S1.6.
// HERMETIC (global constraint 7): integers, strings and two fixed dates, no
// AppState, no repository, no `Date.now`.
//
// FIXED GROUP IDS, because `GSGroupColor.color(for:)` and `.onColor(for:)`
// hash the group's id into the avatar's identity colour
// (`GSGroupColor.swift:33,44`) — a fresh UUID per run would repaint two tiles
// in every screenshot diff.
//
// TWO CREWS, and the difference between them is the whole frame: Push Crew
// has trained (a plate bar, a next lift, a crown), Sunday Squad has not (an
// empty sleeve, no lift scheduled, and NO honor line at all — spec §3's
// decay is the line's absence, never a line reading zero).
enum CrewsTabFixtures {

    static let pushCrewID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d1") ?? UUID()
    static let sundaySquadID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d2") ?? UUID()
    static let creatorID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d3") ?? UUID()

    /// A calendar date at noon UTC from its COMPONENTS, the idiom
    /// `StubBlockGoalRepository.utcDate` records: an epoch literal is
    /// unreadable and therefore unreviewable, and noon survives a simulator
    /// anywhere from UTC-11 to UTC+11 printing the same weekday.
    private static func utcDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month,
                                                  day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// Thursday 2026-09-10, 18:30 UTC — the next lift the meta line names.
    static let nextLift = utcDate(year: 2026, month: 9, day: 10, hour: 18)
    static let createdAt = utcDate(year: 2026, month: 6, day: 1, hour: 12)

    static let groups: [GymGroup] = [
        GymGroup(id: pushCrewID, name: "Push Crew", avatarURL: nil,
                 createdBy: creatorID, createdAt: createdAt, kind: "crew"),
        GymGroup(id: sundaySquadID, name: "Sunday Squad", avatarURL: nil,
                 createdBy: creatorID, createdAt: createdAt, kind: "crew"),
    ]

    static let bars: [UUID: SocialTabView.CrewBarMeta] = [
        pushCrewID: .init(completedThisWeek: 4, plannedThisWeek: 5, nextLift: nextLift),
        sundaySquadID: .init(completedThisWeek: 0, plannedThisWeek: 0, nextLift: nil),
    ]

    /// Spec §3's own line, on the crew that has one.
    static let honors: [UUID: CrewHonor] = [
        pushCrewID: CrewHonor(username: "sam", sessions: 9),
    ]
}
```

**The builder** — `content_crewsTab` in `CatalogHostView`:

```swift
    /// `crews-tab`: the Crews tab from a fixture world — two crew cards (one
    /// with spec §3's honor line, one a crew at rest), the "+ New Crew"
    /// control, and the three Outside the Box rows. The FIRST catalog id this
    /// tab has ever had: `app-tab-social` is the live-account walk, so until
    /// now the crew card has only ever been reviewed against whatever the CI
    /// account happened to contain.
    private var content_crewsTab: some View {
        SocialTabView(catalogFixtureGroups: CrewsTabFixtures.groups,
                      catalogFixtureBars: CrewsTabFixtures.bars,
                      catalogFixtureHonors: CrewsTabFixtures.honors,
                      catalogFixtureFriendCount: 12,
                      catalogFixturePendingCount: 2,
                      catalogSkipLoad: true)
    }
```

`SocialTabView` owns its own `NavigationStack` (:40), so this one is **not** wrapped — unlike the ladder ids,
which are pages.

**Frame-map entry:**

```json
  "crews-tab": { "frame": 101, "title": "Crews tab - two crews, one with the honor line" }
```

**Do not bump `FLOOR`** — I1 does it once.

**TDD steps.** 1. Add the seam, the fixtures, the case, the builder, the id string, the capture method and the
frame-map entry — one commit. 2. Push. 3. `CatalogScreenTests` green (the count guard is the test); a new
`app-crews-tab.png` in the artifact. 4. Commit: `feat(social): crews-tab — the Crews tab's first fixture world`
+ the trailer.

**Proves the stage:** `app-crews-tab` shows the honor line on one card and its absence on the other;
`app-tab-social` shows it on live data (S1.4); `app-venue-hub` and `app-tab-home` unchanged (S1.5).

---

# STAGE 2 — the trajectory snapshot

Spec §1, §2 and §6. Twelve tasks. Forks from `origin/master` (`f00f208` or later) on
`feat/social-cards-post`. **PR #42 is already in that base**, so `BlockGoal`, `Ladder`, `LadderPageModel`,
`BlockGoalRepository`, `WeeklyGoalRepository.progress(for:)` and the nine `WeeklyGoalKind` cases all exist
from the first commit — there is nothing to wait for and nothing to rebase.

### S2.0 — THE INTERFACE: what a post carries — **L**

**Files (new):** `GymSyncApp/GymSync/Models/PostTrajectory.swift`,
`GymSyncApp/GymSyncTests/PostTrajectoryModelTests.swift`.
**File (modified):** `GymSyncApp/GymSync/Models/WorkoutPost.swift`.

**Nothing below starts before this is pushed.** Ten tasks type against these five types; the migration's
column comments quote them.

**The ruling this task encodes, and it is the plan's largest.** Spec §6 adds `goal_id` and `week_start` to
`workout_posts` and calls them "the trajectory and rung the card renders — snapshotted at post time". **A uuid
is not a snapshot of anything a viewer can read.** `block_goals` and `weekly_goals` are own-rows RLS
(`20260907000001_block_goals.sql:49-51`: `USING (user_id = auth.uid())`;
`20260906000001_weekly_goals.sql:54-56`: the same), so a friend holding the author's `goal_id` can resolve
exactly nothing — and owner decision 3 is that the trajectory line, `behind` included, **is visible to
friends**. So the post carries a `trajectory jsonb` with the rendered facts, and `goal_id` / `week_start` stay
as the spec names them: provenance, for the author's own "which block was this" and for any future honest
join. This is also the spec's own stated reason for snapshotting ("so the card does not drift as the ladder
re-ladders") taken to its conclusion.

Write exactly this:

```swift
import Foundation

// MARK: - What a pump-check post carries about the athlete's trajectory
//
// Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §1, §2, §6.
// Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, task S2.0.
//
// A POST IS A SNAPSHOT, NOT A QUERY. `workout_posts.summary` has been an
// immutable snapshot since 2026-07 (WorkoutPost.swift:4-9) and everything
// here joins it, for two reasons that point the same way:
//
//   1. RLS. `block_goals` and `weekly_goals` are own-rows
//      (20260907000001:49-51, 20260906000001:54-56). A friend cannot read the
//      author's goal at all, so a card that resolved `goal_id` at render time
//      would show the trajectory to exactly one person: its author. Owner
//      decision 3 says the opposite.
//   2. Drift. Spec §6: snapshotted "so the card does not drift as the ladder
//      re-ladders". A ladder re-derives every week (goal-first spec §3.5); a
//      post is a moment.
//
// The author resolves these at POST time, through their own
// `BlockGoalRepository` and `WeeklyGoalRepository.progress(for:)` — the only
// reads RLS permits — and the row carries the answer.

/// What kind of thing Coach offered and the lifter picked (spec §1 line 4).
/// Raw values are the wire values of `workout_posts.highlight ->> 'kind'`.
enum PostHighlightKind: String, Codable, Sendable, Equatable {
    case topSet, pr, milestone
}

/// The one editorial line on the card (spec §1 line 4) — chosen by the
/// lifter from Coach's proposals, or absent. No free text: every field below
/// is computed by `HighlightMath` from the session's own snapshot.
///
/// `text` IS UNIT-FREE and the numbers ride beside it, which is spec §6's
/// `{kind, text}` plus the Units doctrine. A frozen string reading "235 lb"
/// would show pounds to a friend whose app is in kilos, and the whole point
/// of `summary`'s canonical pounds (WorkoutPost.swift:6-9) is that the FEED
/// converts. `HighlightText.line(_:unit:)` (task S2.5) is the one place that
/// composes the two halves.
struct PostHighlight: Codable, Sendable, Equatable {
    let kind: PostHighlightKind
    /// The noun phrase — "Top set — Back Squat", "PR — Back Squat",
    /// "Lifetime total crossed".
    let text: String
    /// CANONICAL POUNDS, rendered in the viewer's unit. nil for a highlight
    /// with no weight in it.
    let weightLbs: Decimal?
    let reps: Int?
}

/// Lines 2 and 3 of the card, resolved at post time.
struct PostTrajectory: Codable, Sendable, Equatable {

    /// The third segment of the trajectory line. Three words, no more: spec
    /// §1's table says `on track`, `behind`, `met`.
    enum Standing: String, Codable, Sendable, Equatable {
        case onTrack, behind, met

        /// Sentence case, because the line is a sentence (design rule 9).
        var word: String {
            switch self {
            case .onTrack: return "on track"
            case .behind:  return "behind"
            case .met:     return "met"
            }
        }
    }

    /// One rung chip, in the shape `GSGoalChip` renders (task S2.3).
    ///
    /// NO `isNext`. The Home strip rings the group furthest behind because
    /// that is an invitation to act this week (design rule 2's third job for
    /// accent); a finished post is not an invitation, so the card's chips
    /// carry no ring and the field does not exist to be set by mistake.
    struct Chip: Codable, Sendable, Equatable {
        let name: String
        let done: Double
        let target: Double
        /// The meter's fill, 0...1, when the fraction the NUMBERS print is
        /// not the fraction the METER draws — every span-above-a-floor kind
        /// (`lift`, `bodyWeight`, `benchmark`), where the strip prints
        /// `205 → 225` over a meter measured from where the block started.
        /// nil means `done / target`, the muscle-sets rule.
        let fill: Double?
    }

    /// The milestone as the ladder page words it — `Bench 225 by Oct 18`.
    /// Taken from `LadderPageModel.headline`, never re-worded here: two
    /// spellings of one milestone is two milestones.
    let goalLine: String
    let weekNumber: Int
    let weekCount: Int
    let standing: Standing
    /// This week's rung, as chips. Empty is legal and means the card draws no
    /// line 3.
    let chips: [Chip]

    /// Spec §1 line 2, verbatim: `Bench 225 by Oct 18 · week 3 of 8 · on track`.
    var line: String {
        "\(goalLine) · week \(weekNumber) of \(weekCount) · \(standing.word)"
    }
}

/// How late a post is, precisely (spec §2, borrowed from BeReal).
///
/// The shipped `is_late` was a BOOLEAN computed client-side from the CAPTURE
/// timestamp against a 60 s window (`PumpCheckComposer.swift:35-37, 75`).
/// Spec §2 keeps the column and changes what fills it: elapsed time from the
/// session's COMPLETION to the post. Old rows keep their boolean and the card
/// falls back to it.
enum PostLateness {

    /// The pump-check window, unchanged since 2026-07
    /// (`PumpCheckComposer.swift:49`).
    static let windowSeconds: TimeInterval = 60

    /// Seconds from the session's completion to the post, or **nil when there
    /// is no completion to measure from** — an absence, never a zero.
    static func elapsed(completedAt: Date?, postedAt: Date) -> TimeInterval? {
        guard let completedAt else { return nil }
        return max(0, postedAt.timeIntervalSince(completedAt))
    }

    /// `workout_posts.is_late` for a NEW row (spec §6: "derived for new
    /// ones").
    ///
    /// `fallback` is the composer's capture-time flag and is used only when
    /// the session carries no `completed_at` — a shape this app no longer
    /// writes but old sessions have. Guessing `false` there would quietly
    /// un-late a genuinely late post.
    static func isLate(completedAt: Date?, postedAt: Date, fallback: Bool) -> Bool {
        guard let elapsed = elapsed(completedAt: completedAt, postedAt: postedAt) else {
            return fallback
        }
        return elapsed > windowSeconds
    }

    /// The author row's tag — `posted 47 min after` — or **nil when the post
    /// is inside the window**, which is the on-time case and wears no tag at
    /// all (spec §5: the card's existing behaviour for a prompt post does not
    /// change).
    ///
    /// Three scales, so the tag is always two tokens wide: minutes below
    /// 90 min, hours below 48 h, days above.
    static func tag(completedAt: Date?, postedAt: Date) -> String? {
        guard let elapsed = elapsed(completedAt: completedAt, postedAt: postedAt),
              elapsed > windowSeconds else { return nil }
        let minutes = Int(elapsed / 60)
        if minutes < 90 { return "posted \(max(1, minutes)) min after" }
        let hours = Int(elapsed / 3600)
        if hours < 48 { return "posted \(hours) hr after" }
        return "posted \(Int(elapsed / 86_400)) days after"
    }

    /// `2 retakes` — or nil at zero, because "0 retakes" is a boast.
    static func retakeTag(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 retake" : "\(count) retakes"
    }
}
```

**`WorkoutPost.swift`'s additions.** Six stored properties on `WorkoutPost`, six `CodingKeys`, one optional on
`PostSummary`:

```swift
    /// The session's completion (spec §6), copied at post time. Optional
    /// because old rows have none; `PostLateness` treats that as an absence
    /// rather than as zero.
    let completedAt: Date?
    /// How many times the lifter re-shot before posting (spec §2). OPTIONAL
    /// in Swift though the column is `NOT NULL DEFAULT 0`: a synthesized
    /// `Decodable` does not fall back to a property's default for a missing
    /// key, so an optional is what keeps the feed decoding if a client ever
    /// meets a projection without it. `?? 0` at the one read site.
    let retakeCount: Int?
    let highlight: PostHighlight?
    /// Lines 2 and 3, frozen (see `PostTrajectory`'s doc comment for why this
    /// is not resolved from `goalID`).
    let trajectory: PostTrajectory?
    /// PROVENANCE, not the render source: which block this post belonged to.
    let goalID: UUID?
    /// The rung's week key, `yyyy-MM-dd`. A **String**, because DATE columns
    /// must not go through the SDK's timestamp decoder — the `SessionSeries`
    /// idiom `Models/ProgramEnrollment.swift:36-38` and `WeeklyGoal
    /// .weekStartString` both record.
    let weekStartString: String?
```

```swift
        case completedAt = "completed_at"
        case retakeCount = "retake_count"
        case highlight
        case trajectory
        case goalID = "goal_id"
        case weekStartString = "week_start"
```

and on `PostSummary`:

```swift
    /// The routine this session ran — spec §1 line 5's `Push day · 42 min ·
    /// 7,240 lb`. Optional: a freeform workout has no routine, and every post
    /// written before this field existed decodes with nil (a synthesized
    /// `Decodable` uses `decodeIfPresent` for an Optional).
    ///
    /// SNAKE_CASE, unlike this plan's new columns: `PostSummary` declares its
    /// keys explicitly and has spoken snake_case since 2026-07 (:20-25,
    /// :39-43). One jsonb document may not speak two conventions (global
    /// constraint 11).
    let routineName: String?
```
```swift
        case routineName = "routine_name"
```

**Interfaces** — *consumes:* nothing new. *Produces:* `PostHighlightKind`, `PostHighlight`, `PostTrajectory`,
`PostTrajectory.Standing`, `PostTrajectory.Chip`, `PostLateness`, and `WorkoutPost`'s six fields —
consumed by S2.1 (the column comments), S2.3–S2.10.

**TDD steps.**

1. Write the failing test first — `GymSyncApp/GymSyncTests/PostTrajectoryModelTests.swift`:

```swift
import XCTest
@testable import GymSync

/// The snapshot's wire contract. `workout_posts.highlight` and `.trajectory`
/// are jsonb with CAMELCASE keys and no `keyEncodingStrategy` (global
/// constraint 11), and a field a highlight does not use must be ABSENT rather
/// than null — the same round trip `WeeklyGoalModelTests` proves for
/// `weekly_goals.params`.
final class PostTrajectoryModelTests: XCTestCase {

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testHighlightEncodesOnlyTheFieldsItUses() throws {
        let milestone = PostHighlight(kind: .milestone, text: "Lifetime total crossed",
                                      weightLbs: 1_000_000, reps: nil)
        XCTAssertEqual(try json(milestone).keys.sorted(), ["kind", "text", "weightLbs"])

        let pr = PostHighlight(kind: .pr, text: "PR — Back Squat",
                               weightLbs: 235, reps: 3)
        XCTAssertEqual(try json(pr).keys.sorted(), ["kind", "reps", "text", "weightLbs"])
        XCTAssertEqual(try json(pr)["kind"] as? String, "pr")
    }

    func testTopSetKindIsCamelCaseOnTheWire() throws {
        let top = PostHighlight(kind: .topSet, text: "Top set — Back Squat",
                                weightLbs: 225, reps: 5)
        XCTAssertEqual(try json(top)["kind"] as? String, "topSet")
    }

    func testTrajectoryRoundTrips() throws {
        let trajectory = PostTrajectory(
            goalLine: "Bench 225 by Oct 18", weekNumber: 3, weekCount: 8,
            standing: .onTrack,
            chips: [.init(name: "CHEST", done: 8, target: 12, fill: nil),
                    .init(name: "BENCH PRESS", done: 205, target: 225, fill: 0.25)])
        let data = try JSONEncoder().encode(trajectory)
        XCTAssertEqual(try JSONDecoder().decode(PostTrajectory.self, from: data), trajectory)
        XCTAssertEqual(try json(trajectory).keys.sorted(),
                       ["chips", "goalLine", "standing", "weekCount", "weekNumber"])
    }

    func testTheTrajectoryLineIsTheSpecsLine() {
        let trajectory = PostTrajectory(goalLine: "Bench 225 by Oct 18", weekNumber: 3,
                                        weekCount: 8, standing: .onTrack, chips: [])
        XCTAssertEqual(trajectory.line, "Bench 225 by Oct 18 · week 3 of 8 · on track")
    }

    func testBehindIsSaidPlainly() {
        let trajectory = PostTrajectory(goalLine: "Bench 225 by Oct 18", weekNumber: 5,
                                        weekCount: 8, standing: .behind, chips: [])
        XCTAssertEqual(trajectory.line, "Bench 225 by Oct 18 · week 5 of 8 · behind")
    }
}
```

2. Push — red (nothing exists).
3. Write `Models/PostTrajectory.swift` and `WorkoutPost.swift`'s additions exactly as above.
4. Push — green. The feed still builds: every new property is Optional, including
   `PostSummary.routineName`.
5. Commit: `feat(social): the post's trajectory, highlight and precise lateness — the interface` + the trailer.

---

### S2.1 — `workout_posts` gains the snapshot — **M**

**File (new):** `supabase/migrations/20260912000001_workout_posts_trajectory.sql`

```sql
-- 20260912000001_workout_posts_trajectory.sql
--
-- Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §6.
-- Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, task S2.1.
--
-- The pump-check card becomes a TRAJECTORY SNAPSHOT (spec §1). Six additive,
-- nullable-or-defaulted columns; no existing column changes and no existing
-- row moves.
--
-- STILL NO UPDATE POLICY (20260731000001:71-72: "posts are immutable
-- snapshots"). Every column below is written once, at INSERT, by the
-- composer.
--
-- `is_late` IS NOT DROPPED. Spec §6: "is_late stays for old rows and is
-- derived for new ones". The derivation is `posted_at - completed_at`
-- (`PostLateness.isLate`, plan task S2.0) and it happens in the CLIENT at
-- insert, not in a generated column — converting a populated boolean column
-- into a generated one means dropping it, which would erase what every row
-- written before today says about itself.

ALTER TABLE public.workout_posts
  ADD COLUMN completed_at timestamptz,
  ADD COLUMN retake_count int NOT NULL DEFAULT 0 CHECK (retake_count >= 0),
  -- The kind is CHECKED even though this release only ever writes two of the
  -- three. `milestone` is in the domain from day one so the milestone
  -- proposal can ship with the You hero's MilestoneCatalog without a second
  -- migration — a column's domain is cheap to widen and expensive to change
  -- under rows that already use it.
  ADD COLUMN highlight    jsonb CHECK (
    highlight IS NULL OR (
      jsonb_typeof(highlight) = 'object'
      AND highlight ->> 'kind' IN ('topSet', 'pr', 'milestone')
    )),
  ADD COLUMN trajectory   jsonb CHECK (trajectory IS NULL OR jsonb_typeof(trajectory) = 'object'),
  ADD COLUMN goal_id      uuid REFERENCES public.block_goals(id) ON DELETE SET NULL,
  ADD COLUMN week_start   date;

COMMENT ON COLUMN public.workout_posts.completed_at IS
  'The session''s completion, copied at post time. With created_at this is the precise lateness the card prints ("posted 47 min after") and the value is_late is derived from for new rows. NULL on rows written before 2026-09.';
COMMENT ON COLUMN public.workout_posts.retake_count IS
  'How many times the lifter re-shot before posting (spec 2). Shown on the card above zero.';
COMMENT ON COLUMN public.workout_posts.highlight IS
  'The one line the lifter picked from Coach''s proposals: {kind: "topSet"|"pr"|"milestone", text, weightLbs?, reps?}. CamelCase keys, canonical pounds; the feed renders the weight in the VIEWER''S unit (PostHighlight, HighlightText.line). This release proposes topSet and pr only - milestone is reserved for the You hero''s MilestoneCatalog and is already in the domain so no migration is needed when it ships.';
COMMENT ON COLUMN public.workout_posts.trajectory IS
  'Lines 2 and 3 of the card, RESOLVED at post time: {goalLine, weekNumber, weekCount, standing, chips[{name,done,target,fill?}]}. A snapshot rather than a join because block_goals and weekly_goals are own-rows RLS - a friend can never read the author''s goal - and because a ladder re-derives weekly while a post is a moment.';
COMMENT ON COLUMN public.workout_posts.goal_id IS
  'PROVENANCE: which block this post belonged to. NOT what the card renders (see trajectory). ON DELETE SET NULL - retiring a block must not delete the posts made during it.';
COMMENT ON COLUMN public.workout_posts.week_start IS
  'The rung''s week key (weekly_goals.week_start''s shape and rule: the DEVICE calendar''s week, computed by the client via WeekMath).';
```

**The `block_goals` dependency is real and one-directional:** this migration references a table PR #42
created, which is why Stage 2 cannot start earlier.

**TDD steps.**

1. Write the migration.
2. **Apply it** to `chjkkwqwdlmaxacwglzm` — constraint 10 — *before* S2.2's CI run and before the client that
   decodes the columns merges. The commit body records when.
3. Verify by hand: `SELECT column_name FROM information_schema.columns WHERE table_name = 'workout_posts'
   ORDER BY ordinal_position;` shows the six, and `is_late` is still there.
4. Commit: `feat(social): workout_posts carries the trajectory, the highlight and the completion` + the trailer.

---

### S2.2 — the pgTAP the new columns owe — **S**

**File (modified):** `supabase/tests/workout_posts_test.sql` — `plan(15)` → `plan(23)`.

Eight assertions, appended **after assertion 9 and before assertion 10** (assertion 14 deletes A's post at
`…0720`, so anything reading it must run first). Every existing assertion's SQL is untouched; only the
trailing comment numbers shift.

```sql
-- 9b. The snapshot columns accept a full row.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000701';
SELECT lives_ok(
  $$INSERT INTO workout_posts (id, author_id, session_id, summary, is_late,
                               completed_at, retake_count, highlight, trajectory, week_start)
    VALUES ('00000000-0000-4000-f000-000000000721',
            '00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710',
            '{"duration_seconds": 2520, "total_volume_lbs": 7240, "routine_name": "Push day", "exercises": []}',
            true, now() - interval '47 minutes', 2,
            '{"kind": "pr", "text": "PR", "weightLbs": 235, "reps": 3}',
            '{"goalLine": "Bench 225 by Oct 18", "weekNumber": 3, "weekCount": 8,
              "standing": "onTrack", "chips": [{"name": "CHEST", "done": 8, "target": 12}]}',
            '2026-09-06')$$,
  'a post carries its trajectory, highlight, retakes and completion');

-- 9c. retake_count defaults to zero, never null.
SELECT results_eq(
  $$SELECT retake_count FROM workout_posts
     WHERE id = '00000000-0000-4000-f000-000000000720'$$,
  $$VALUES (0)$$, 'retake_count defaults to 0 on a row that never set it');

-- 9d. A negative retake count is rejected.
SELECT throws_ok(
  $$INSERT INTO workout_posts (author_id, session_id, summary, retake_count)
    VALUES ('00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710', '{}', -1)$$,
  '23514', NULL, 'a negative retake count is rejected');

-- 9e. A scalar where an object belongs is rejected.
SELECT throws_ok(
  $$INSERT INTO workout_posts (author_id, session_id, summary, highlight)
    VALUES ('00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710', '{}', '"pr"')$$,
  '23514', NULL, 'highlight must be a json object');

-- 9e2. The kind domain: `milestone` is ACCEPTED though this release never
-- proposes it (the You hero's MilestoneCatalog will), and an unknown kind is
-- refused. This is the assertion that lets the milestone highlight ship later
-- without a migration.
SELECT lives_ok(
  $$INSERT INTO workout_posts (id, author_id, session_id, summary, highlight)
    VALUES ('00000000-0000-4000-f000-000000000722',
            '00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710', '{}',
            '{"kind": "milestone", "text": "Lifetime total crossed", "weightLbs": 1000000}')$$,
  'the milestone kind is already in the column''s domain');
SELECT throws_ok(
  $$INSERT INTO workout_posts (author_id, session_id, summary, highlight)
    VALUES ('00000000-0000-4000-f000-000000000701',
            '00000000-0000-4000-f000-000000000710', '{}',
            '{"kind": "vibes", "text": "felt strong"}')$$,
  '23514', NULL, 'a kind outside the three is rejected');

-- 9f. The snapshot is still IMMUTABLE — no UPDATE policy came with it.
UPDATE workout_posts SET retake_count = 99
  WHERE id = '00000000-0000-4000-f000-000000000721';
SELECT results_eq(
  $$SELECT retake_count FROM workout_posts
     WHERE id = '00000000-0000-4000-f000-000000000721'$$,
  $$VALUES (2)$$,
  'the new columns are as immutable as the old ones');

-- 9g. The friend sees the standing — spec §1's visibility ruling at the row
-- level: `behind` included, no per-post hide, friends-scoped by the SELECT
-- policy that already existed.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000702';
SELECT results_eq(
  $$SELECT trajectory ->> 'standing' FROM workout_posts
     WHERE id = '00000000-0000-4000-f000-000000000721'$$,
  $$VALUES ('onTrack'::text)$$,
  'an accepted friend reads the author''s standing');
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000701';
```

**TDD steps.** 1. Edit the file; bump `plan(15)` to `plan(23)`. 2. Push — Backend CI runs it against the live
project (S2.1 already applied). 3. 23/23. 4. Commit:
`test(social): pgTAP for the post's trajectory columns — defaults, shapes, immutability, audience` +
the trailer.

---

### S2.3 — the goal chip, extracted — **M**

**Files:** `GymSyncApp/GymSync/DesignSystem/GSGoalChip.swift` (new),
`GymSyncApp/GymSync/Features/Home/V2/HomeWeeklyGoalStrip.swift`,
`GymSyncApp/GymSyncTests/GSGoalChipTests.swift` (new).

Spec §1 line 3: "the same chips the Home strip renders". Today `chipView(_:)` and `fraction(of:)` are
`private` to `HomeWeeklyGoalStrip` (:211-274). **This is the one task that can move a frozen frame**
(constraint 8), so it is a pure lift: every number, font, spacing, colour and modifier below is copied, not
re-chosen.

```swift
import SwiftUI

/// One goal chip: the subject's name as a kicker, a 4 pt meter, the fraction
/// under it.
///
/// LIFTED VERBATIM from `HomeWeeklyGoalStrip.chipView(_:)` (plan task S2.3)
/// so the Home strip and the pump-check card render one chip rather than two
/// that look alike. Every literal here — 7 pt spacing, 9 pt tracked caps,
/// 12 pt tabular fraction, 8 pt padding, the 10 pt ring, the 4 pt track — is
/// the strip's, unchanged, because `app-home-v3-08a-targets-above-calendar`,
/// `-08b-targets-above-join` and `app-home-goal-strip-muscle-sets` are
/// owner-approved and must stay byte-identical.
///
/// The chips carry NO background fill, for the reason the strip's own doc
/// comment gives: their siblings' chip pill is `theme.neutral300`, which on
/// Onyx IS the colour the meter's track uses, so a filled chip would erase
/// the meter it exists to show. Unfilled is also what design rule 1 asks of
/// chips — furniture stays flat.
struct GSGoalChip: View {
    @Environment(\.gsTheme) private var theme

    /// The subject, in caps — the caller owns the case.
    let name: String
    /// Unrounded; the chip shows `Int(done.rounded())`. A set credits
    /// fractionally (`MuscleGroup.credit`), and a lifter reads "9/12", never
    /// "8.5/12".
    let done: Double
    let target: Double
    /// The accent ring — design rule 2's "current item", the group furthest
    /// behind. The Home strip sets it; a finished post never does.
    var isNext: Bool = false
    /// The meter's fill, 0...1, when the fraction the NUMBERS print is not
    /// the fraction the METER draws. nil = `done / target`.
    ///
    /// Only the pump-check card passes this, and only for a span-above-a-
    /// floor kind: a `lift` rung prints `205 / 225` and must draw the share
    /// of the block's own span, or a goal reads 91 % done on the day it
    /// opened — the plausible-looking wrong answer the strip's "subject chip"
    /// note already records paying for once.
    var fill: Double? = nil

    /// The one green this codebase uses, in its "done" job (design rule 2).
    private static let green = Color.gsSuccess

    var body: some View {
        // MET NEEDS AT LEAST ONE REAL TARGET: a plain `done >= target` is
        // TRUE for a 0-target chip, so a group nobody is asking for drew a
        // green `0/0` and read as finished.
        let met = target > 0 && done >= target
        return VStack(alignment: .leading, spacing: 7) {
            Text(name)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            meter(met: met)

            Text("\(Int(done.rounded()))/\(Int(target.rounded()))")
                .font(GSFont.bold(12, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(met ? Self.green : theme.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .overlay(
            isNext
                ? RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.accent, lineWidth: 1.5)
                : nil
        )
    }

    /// Done over target, clamped to 0...1 — an overshoot draws a full meter
    /// rather than one that runs past its own track, and a target of zero
    /// draws an empty one instead of dividing by nothing. `fill` wins when
    /// the caller supplied one.
    var fraction: Double {
        if let fill { return min(max(fill, 0), 1) }
        guard target > 0 else { return 0 }
        return min(max(done / target, 0), 1)
    }

    /// The 4 pt track and its fill, through a `GeometryReader` rather than a
    /// fixed width — a chip's width is a quarter of the page's, which is the
    /// device's, and nothing in a catalog fixture may assume one.
    private func meter(met: Bool) -> some View {
        let value = fraction
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.neutral300)
                if value > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(met ? Self.green : theme.text)
                        .frame(width: proxy.size.width * value)
                }
            }
        }
        .frame(height: 4)
    }
}
```

**`HomeWeeklyGoalStrip`'s side.** `chipRow` (:161-168) becomes:

```swift
    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(progress.chips.enumerated()), id: \.offset) { _, chip in
                GSGoalChip(name: chip.name, done: chip.done,
                           target: chip.target, isNext: chip.isNext)
            }
        }
    }
```

`chipView(_:)` and `fraction(of:)` are deleted. **`meter(fill:met:)` STAYS** — it is also called by
`distanceBody`, `sessionsBody`, `liftBody`, `recoveryBody`, `bodyWeightBody`, `volumeBody` and
`benchmarkBody` for their full-width readings; only the chip's private copy moves. `Self.green` stays for the
same reason.

**Interfaces** — *consumes:* `GSFont`, `Color.gsSuccess`, the theme. *Produces:* `GSGoalChip`, consumed by
`HomeWeeklyGoalStrip.chipRow` and by S2.7's card.

**TDD steps.**

1. Write the failing test first — `GymSyncApp/GymSyncTests/GSGoalChipTests.swift`:

```swift
import XCTest
@testable import GymSync

/// The chip's two rules, tested on the value the view draws rather than on
/// pixels: the fraction, and the override that exists for span kinds.
final class GSGoalChipTests: XCTestCase {

    func testTheFractionIsDoneOverTarget() {
        XCTAssertEqual(GSGoalChip(name: "CHEST", done: 6, target: 12).fraction, 0.5)
    }

    func testAnOvershootDrawsAFullMeterNotAnOverflowingOne() {
        XCTAssertEqual(GSGoalChip(name: "CHEST", done: 18, target: 12).fraction, 1.0)
    }

    func testAZeroTargetDrawsNothingRatherThanDividingByNothing() {
        XCTAssertEqual(GSGoalChip(name: "CHEST", done: 3, target: 0).fraction, 0)
    }

    /// The whole reason `fill` exists: a 205 → 225 lift on its first day.
    func testTheFillOverrideWinsOverThePrintedNumbers() {
        let chip = GSGoalChip(name: "BENCH PRESS", done: 205, target: 225, fill: 0.0)
        XCTAssertEqual(chip.fraction, 0.0,
                       "a lift rung must not draw 91% on the day the block opened")
    }

    func testTheOverrideIsClamped() {
        XCTAssertEqual(GSGoalChip(name: "X", done: 1, target: 2, fill: 4).fraction, 1.0)
        XCTAssertEqual(GSGoalChip(name: "X", done: 1, target: 2, fill: -1).fraction, 0.0)
    }
}
```

2. Push — red.
3. Write `GSGoalChip.swift`; re-point `chipRow`; delete `chipView(_:)` and `fraction(of:)`.
4. Push — green, **and read the artifact**: `app-home-goal-strip-muscle-sets`,
   `app-home-v3-08a-targets-above-calendar`, `app-home-v3-08b-targets-above-join` must be **byte-identical**
   to the run before this commit. If any moved, the lift was not a lift — fix it here, not later.
5. Commit: `refactor(design): GSGoalChip — the Home strip's chip, now shared` + the trailer, with the
   byte-identical result in the body.

**Proves:** one chip, two surfaces, three frozen frames unmoved.

---

### S2.4 — the trajectory, computed — **L**

**Files:** `GymSyncApp/GymSync/Models/PostTrajectoryMath.swift` (new),
`GymSyncApp/GymSyncTests/PostTrajectoryMathTests.swift` (new),
`GymSyncApp/GymSync/Models/WeeklyGoal.swift` (the switch-site count).

```swift
import Foundation

// MARK: - The card's lines 2 and 3, computed once, at post time
//
// Spec §1. Plan task S2.4. PURE: everything here takes resolved values and
// returns a value. No repository, no clock, no view.

enum PostTrajectoryMath {

    /// Which of spec §1's three words the card prints.
    ///
    /// ORDERED, and the order is the argument: an outcome the block already
    /// recorded beats a ladder still being re-derived; a milestone rung that
    /// is in beats everything still ahead of it; a ladder that can no longer
    /// reach the date is `behind` however tidy the weeks behind it look; and
    /// a single missed rung is `behind` too, because spec §1's visibility
    /// ruling exists precisely so a crew can see that.
    static func standing(goal: BlockGoal, page: LadderPageModel) -> PostTrajectory.Standing {
        if goal.outcome == .met { return .met }
        if let last = page.rows.last, last.status == .met { return .met }
        if !page.reachesMilestone { return .behind }
        if page.rows.contains(where: { $0.status == .missed }) { return .behind }
        return .onTrack
    }

    /// This week's rung, as the chips the card draws — at most four, which is
    /// the number the Home strip's row is built for.
    ///
    /// TWO FAMILIES, and the split is what keeps the card honest:
    ///
    ///   * `muscleSets`, `days` and `recovery` carry DISPLAY chips. Their
    ///     `chips` array IS the strip's reading (four groups; seven day
    ///     states; stretches beside LISS minutes), so it passes through.
    ///   * every other kind carries ONE SUBJECT chip, whose `done`/`target`
    ///     are the meter's geometry and not the numbers the strip prints —
    ///     for `lift`, `bodyWeight` and `benchmark` that geometry is measured
    ///     from where the BLOCK started (`WeeklyGoalProgressMath` lines
    ///     502-508). So the chip prints `progress.value / progress.target`,
    ///     which is what the strip's own reading prints, and carries the
    ///     subject chip's fraction as `fill`.
    ///
    /// EXHAUSTIVE, no `default:` — this is the fourteenth such switch in the
    /// app and the reason `WeeklyGoalKind`'s doc comment counts them: a tenth
    /// kind must be a compile error here rather than a card that silently
    /// stops showing a rung.
    static func chips(kind: WeeklyGoalKind,
                      progress: WeeklyGoalProgress) -> [PostTrajectory.Chip] {
        switch kind {
        case .muscleSets, .days, .recovery:
            return progress.chips.prefix(4).map {
                PostTrajectory.Chip(name: $0.name, done: $0.done,
                                    target: $0.target, fill: nil)
            }
        case .distance, .sessionsOfType, .lift, .bodyWeight, .volume, .benchmark:
            guard let subject = progress.chips.first else { return [] }
            let fill = subject.target > 0
                ? min(max(subject.done / subject.target, 0), 1)
                : 0
            return [PostTrajectory.Chip(name: subject.name,
                                        done: progress.value,
                                        target: progress.target,
                                        fill: fill)]
        }
    }

    /// The whole snapshot.
    ///
    /// `weeklyKind`/`weeklyProgress` are optional together: an athlete inside
    /// a block whose current week has no materialised rung yet gets line 2
    /// and no line 3, which is a legible state. An athlete with NO ACTIVE
    /// BLOCK never reaches this function at all — spec §1: "An athlete with
    /// no active block has no line 2 and no line 3; the card is lines 1, 4,
    /// 5, 6, 7" — and `PostTrajectoryResolver` (task S2.6) returns nil there.
    static func snapshot(goal: BlockGoal,
                         page: LadderPageModel,
                         weeklyKind: WeeklyGoalKind?,
                         weeklyProgress: WeeklyGoalProgress?) -> PostTrajectory {
        let rungChips: [PostTrajectory.Chip]
        if let weeklyKind, let weeklyProgress {
            rungChips = chips(kind: weeklyKind, progress: weeklyProgress)
        } else {
            rungChips = []
        }
        return PostTrajectory(goalLine: page.headline,
                              weekNumber: page.weekNumber,
                              weekCount: page.weekCount,
                              standing: standing(goal: goal, page: page),
                              chips: rungChips)
    }
}
```

> **AMENDED (integration, 2026-09-12) — fix round 1 supersedes the `PostTrajectoryMath` snippet above.**
> Three corrections, all shipped in `GymSyncApp/GymSync/Models/PostTrajectoryMath.swift`:
>
> 1. **`standing` has no missed-rung branch.** The snippet's
>    `if page.rows.contains(where: { $0.status == .missed }) { return .behind }` pinned the card to `behind`
>    for the rest of the block after a single bad week, even once the ladder had re-derived and still reached
>    the date. The card must **agree with the ladder page's own coach line**, which says "On track" whenever
>    the ladder still `reachesMilestone`; anything else prints two verdicts on one block — the page telling
>    the athlete they are on track while their post tells their crew they are behind. Shipped:
>    `if goal.outcome == .met { .met }`, then `if page.rows.last?.status == .met { .met }`, then
>    `page.reachesMilestone ? .onTrack : .behind`. A missed week the ladder has absorbed is history, not
>    standing.
> 2. **A `days` rung renders ONE chip, not four.** `days` carries **seven** weekday chips, so the snippet's
>    `prefix(4)` was Monday-to-Thursday: a lifter who trains Thursday to Saturday posted
>    `0/0 · 0/0 · 0/0 · 0/0` — four empty chips under a line claiming a rung. Shipped: `days` gets its own
>    `case`, returning a single `DAYS` chip carrying the strip's own reading (`progress.value` over
>    `progress.target`) and no `fill`, because days-done over days-asked-for already IS the meter's fraction.
> 3. **The `recovery` comment is corrected.** The snippet's "their `chips` array IS the strip's reading"
>    claimed too much for the whole family: the strip renders recovery as a meter plus two lines, not as a
>    chip row. Recovery's chips still pass through, but they are the strip's **facts in the card's own shape**
>    rather than a copy of the strip's layout. `muscleSets` is the only kind for which the stronger claim
>    holds.
>
> So the shipped switch has **three** families where the snippet had two: `muscleSets`/`recovery` (pass
> through, at most four), `days` (one `DAYS` chip), and everything else (one subject chip). Still exhaustive,
> still no `default:`.

`WeeklyGoal.swift`'s `WeeklyGoalKind` doc comment (:28-48) is amended: **fourteen** switches across
**thirteen** sites, with `PostTrajectoryMath.chips(kind:progress:)` added to the list. That count has been
wrong twice before; this task keeps it right.

**Interfaces** — *consumes:* `BlockGoal`, `GoalOutcome`, `LadderPageModel`, `RungStatus`, `WeeklyGoalKind`,
`WeeklyGoalProgress`. *Produces:* `PostTrajectoryMath.standing(goal:page:)`, `.chips(kind:progress:)`,
`.snapshot(goal:page:weeklyKind:weeklyProgress:)` — S2.6 and S2.9 call them.

**TDD steps.**

1. Write the failing test first — `GymSyncApp/GymSyncTests/PostTrajectoryMathTests.swift`. Fixtures are built
   on the real memberwise initializers, the idiom this repo uses (`WeeklyGoalProgressTests.swift:14-37`);
   **there is no `.fixture` helper anywhere in `GymSyncTests`** and this file does not invent one:

```swift
import XCTest
@testable import GymSync

/// Spec §1's lines 2 and 3, as values.
final class PostTrajectoryMathTests: XCTestCase {

    private func goal(outcome: GoalOutcome? = nil) -> BlockGoal {
        BlockGoal(id: UUID(), userID: UUID(), enrollmentID: UUID(),
                  metric: .liftOneRepMax,
                  target: GoalTarget(targetWeightLbs: 225),
                  byDate: nil, preset: .strength, source: .user,
                  outcome: outcome, outcomeValue: nil,
                  createdAt: Date(timeIntervalSince1970: 0),
                  updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func row(_ week: Int, _ status: RungStatus) -> LadderRow {
        LadderRow(weekNumber: week, weekStartString: "2026-09-0\(week)",
                  targetText: "3 × 5 at 200", implication: nil,
                  status: status, isDeload: false, note: nil)
    }

    private func page(_ statuses: [RungStatus], reaches: Bool = true) -> LadderPageModel {
        LadderPageModel(headline: "Bench 225 by Oct 18", dateLine: "Sunday 18 October",
                        coachLine: "On track",
                        rows: statuses.enumerated().map { row($0.offset + 1, $0.element) },
                        reachesMilestone: reaches, weekNumber: 3, weekCount: 8,
                        source: .user)
    }

    // MARK: - standing

    func testAClimbingLadderIsOnTrack() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(), page: page([.met, .met, .current, .ahead])),
            .onTrack)
    }

    func testALadderThatCannotReachTheDateIsBehind() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(),
                                        page: page([.met, .current, .ahead], reaches: false)),
            .behind)
    }

    func testAMissedRungIsBehindEvenWhenTheMilestoneStillReaches() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(), page: page([.met, .missed, .current])),
            .behind)
    }

    func testARecordedOutcomeWins() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(outcome: .met),
                                        page: page([.missed, .missed], reaches: false)),
            .met)
    }

    func testTheLastRungMetIsMet() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(), page: page([.met, .met, .met])),
            .met)
    }

    // MARK: - chips

    func testMuscleSetsChipsPassThroughUnchanged() {
        let progress = WeeklyGoalProgress(
            chips: [.init(name: "CHEST", done: 8, target: 12, isNext: false),
                    .init(name: "BACK", done: 10, target: 12, isNext: false),
                    .init(name: "LEGS", done: 6, target: 12, isNext: true),
                    .init(name: "ARMS", done: 8, target: 8, isNext: false)])
        let chips = PostTrajectoryMath.chips(kind: .muscleSets, progress: progress)
        XCTAssertEqual(chips.map(\.name), ["CHEST", "BACK", "LEGS", "ARMS"])
        XCTAssertEqual(chips[2].done, 6)
        XCTAssertNil(chips[0].fill, "a muscle-sets chip's meter IS its fraction")
    }

    func testNoMoreThanFourChips() {
        let progress = WeeklyGoalProgress(
            chips: (0..<7).map { .init(name: "D\($0)", done: 1, target: 1, isNext: false) })
        XCTAssertEqual(PostTrajectoryMath.chips(kind: .days, progress: progress).count, 4)
    }

    /// The span kinds: the numbers the strip PRINTS, the meter the strip DRAWS.
    func testALiftChipPrintsTheLoadAndDrawsTheBlocksSpan() {
        let progress = WeeklyGoalProgress(
            chips: [.init(name: "BENCH PRESS", done: 5, target: 20, isNext: false)],
            value: 210, target: 225, unitLabel: "lb")
        let chips = PostTrajectoryMath.chips(kind: .lift, progress: progress)
        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(chips[0].done, 210)
        XCTAssertEqual(chips[0].target, 225)
        XCTAssertEqual(try XCTUnwrap(chips[0].fill), 0.25, accuracy: 0.0001)
    }

    func testRecoveryKeepsBothOfItsChips() {
        let progress = WeeklyGoalProgress(
            chips: [.init(name: "STRETCHES", done: 4, target: 6, isNext: false),
                    .init(name: "LISS MIN", done: 90, target: 120, isNext: false)],
            value: 4, target: 6)
        XCTAssertEqual(PostTrajectoryMath.chips(kind: .recovery, progress: progress).count, 2)
    }

    func testAKindWithNoChipYieldsNoLineRatherThanAGuess() {
        XCTAssertTrue(PostTrajectoryMath.chips(kind: .lift,
                                               progress: WeeklyGoalProgress()).isEmpty)
    }

    // MARK: - snapshot

    func testTheSnapshotIsTheSpecsLine() {
        let snapshot = PostTrajectoryMath.snapshot(
            goal: goal(), page: page([.met, .met, .current]),
            weeklyKind: nil, weeklyProgress: nil)
        XCTAssertEqual(snapshot.line, "Bench 225 by Oct 18 · week 3 of 8 · on track")
        XCTAssertTrue(snapshot.chips.isEmpty, "no materialised rung is no line 3")
    }
}
```

Note `testALiftChipPrintsTheLoadAndDrawsTheBlocksSpan`'s `try XCTUnwrap(chips[0].fill)` — `fill` is
`Double?` and `XCTAssertEqual(_:_:accuracy:)` needs a value; the unwrap is of a plain expression, never of an
`await` (constraint 4). The test method therefore carries `throws`.

2. Push — red.
3. Write `PostTrajectoryMath.swift`; amend `WeeklyGoalKind`'s count.
4. Push — green.
5. Commit: `feat(social): the trajectory line and the rung's chips, computed` + the trailer.

---

### S2.5 — Coach's highlights: the top set and the PR — **L**

**Files:** `GymSyncApp/GymSync/Models/HighlightMath.swift` (new),
`GymSyncApp/GymSyncTests/HighlightMathTests.swift` (new).

Spec §1 line 4: "Coach proposes up to three highlights from the session (best e1RM set, any PR, a milestone
total crossed); the lifter picks one or none. No free text."

**Everything comes from the snapshot the composer already holds.** `PostSummary` carries each set's weight,
reps and `isPR` (`WorkoutPost.swift:12-33`), so both proposals this release offers need no fetch at all.

**THE MILESTONE PROPOSAL IS DEFERRED, AND THIS RELEASE SHIPS NO SECOND LADDER — controller ruling.** The You
milestone-hero spec (`docs/superpowers/specs/2026-09-06-you-milestone-hero-design.md`, now on master) defines
**the** catalog: `MilestoneCatalog.swift`, thirty rungs with sources, one currency (plates from pounds).
Writing a private `volumeMilestonesLbs` array here would be exactly the "two accountings of the same pounds"
this plan's own "does not decide" warns about, and the second one would be the one nobody maintains. So:

- `PostHighlightKind.milestone` **stays** in the frozen S2.0 interface and in the column's CHECK (S2.1, S2.2),
  so the schema never has to change when the hero ships;
- `HighlightMath.propose` offers **`topSet` and `pr` only** — "up to three" becomes up to two for now, which
  is the spec's own "up to" doing its job;
- there is **no** `volumeMilestonesLbs` and **no** `lifetimeVolumeLbsAfter` parameter anywhere in this plan —
  `PumpCheckContext` does not carry one either (S2.6), so no host reads `Profile.lifetimeVolumeLifted` for it;
- a doc comment on `propose` says where the third proposal comes from when it arrives.

Recorded as a deviation from spec §1 line 4 in I3.

```swift
import Foundation

// MARK: - Coach's highlight proposals
//
// Spec §1 line 4. Plan task S2.5. PURE and FETCH-FREE: every proposal comes
// out of the post's own summary, which the composer already holds.

enum HighlightMath {

    /// The proposals Coach offers, in spec §1's own order: the best top set,
    /// then the PR. **Two, not three, in this release.**
    ///
    /// THE MILESTONE PROPOSAL IS NOT HERE, and deliberately has no private
    /// ladder standing in for it. The You milestone-hero spec
    /// (`docs/superpowers/specs/2026-09-06-you-milestone-hero-design.md`)
    /// defines the ONE catalog — `MilestoneCatalog.swift`, thirty rungs with
    /// sources, one currency (plates from pounds). A local array of round
    /// numbers here would be a second accounting of the same pounds, and the
    /// second accounting is the one that rots. When the hero ships, the third
    /// proposal is `MilestoneCatalog`'s own "which rung did this session
    /// cross" read, `PostHighlightKind.milestone` is already in this enum and
    /// already in `workout_posts.highlight`'s CHECK, and nothing here changes
    /// shape — only this function grows an arm.
    ///
    /// THE PR SUPPRESSES THE TOP SET WHEN THEY ARE THE SAME SET. Otherwise
    /// the picker offers "Top set — Back Squat 235 × 3" above "PR — Back
    /// Squat 235 × 3", which is one fact twice and makes the lifter choose
    /// between two spellings of it.
    static func propose(summary: PostSummary) -> [PostHighlight] {
        var proposals: [PostHighlight] = []

        let best = bestSet(in: summary)
        let pr = prSet(in: summary)
        var prIsTheTopSet = false
        if let best, let pr {
            prIsTheTopSet = best.exercise == pr.exercise
                && best.set.weightLbs == pr.set.weightLbs
                && best.set.reps == pr.set.reps
        }

        if let best, !prIsTheTopSet {
            proposals.append(PostHighlight(kind: .topSet,
                                           text: "Top set — \(best.exercise)",
                                           weightLbs: best.set.weightLbs,
                                           reps: best.set.reps))
        }
        if let pr {
            proposals.append(PostHighlight(kind: .pr,
                                           text: "PR — \(pr.exercise)",
                                           weightLbs: pr.set.weightLbs,
                                           reps: pr.set.reps))
        }
        // The cap stays at three: the milestone arm lands inside it, and a
        // `prefix` that already fits is what keeps that a one-line change.
        return Array(proposals.prefix(3))
    }

    /// The highest estimated one-rep max of the session's non-failed, weighted
    /// sets — "best" by what it implies, not by what is on the bar, so a heavy
    /// single and a lighter set of eight are compared fairly.
    /// `StatMath.estimatedOneRepMax` is the app's own formula
    /// (`StatMath.swift:125`); this does not invent a second one.
    static func bestSet(in summary: PostSummary)
        -> (exercise: String, set: PostSummary.ExerciseEntry.SetEntry)? {
        var best: (exercise: String, set: PostSummary.ExerciseEntry.SetEntry, e1rm: Decimal)?
        for exercise in summary.exercises {
            for set in exercise.sets where !set.isFailed {
                guard let weight = set.weightLbs, weight > 0,
                      let reps = set.reps, reps > 0 else { continue }
                let e1rm = StatMath.estimatedOneRepMax(weight: weight, reps: reps)
                if best == nil || e1rm > best!.e1rm {
                    best = (exercise.name, set, e1rm)
                }
            }
        }
        return best.map { ($0.exercise, $0.set) }
    }

    /// The session's PR, if it flagged one. `isPR` is stamped into the
    /// snapshot at post time by the recap's own PR read — this does not
    /// re-derive it.
    static func prSet(in summary: PostSummary)
        -> (exercise: String, set: PostSummary.ExerciseEntry.SetEntry)? {
        for exercise in summary.exercises {
            for set in exercise.sets where set.isPR && !set.isFailed {
                return (exercise.name, set)
            }
        }
        return nil
    }

}

/// The card's one highlight line, IN THE VIEWER'S UNIT.
///
/// Separate from `HighlightMath` because it is a rendering rule where those
/// are a training one, and because the composer (which proposes) and the feed
/// (which renders) sit on opposite sides of the wire.
enum HighlightText {
    static func line(_ highlight: PostHighlight, unit: WeightUnit) -> String {
        switch highlight.kind {
        case .topSet, .pr:
            guard let weightLbs = highlight.weightLbs, let reps = highlight.reps else {
                return highlight.text
            }
            let weight = Units.format(pounds: weightLbs, unit: unit,
                                      rounded: false, includeUnit: true)
            return "\(highlight.text) \(weight) × \(reps)"
        case .milestone:
            // NOT PROPOSED IN THIS RELEASE (see `propose`), but rendered
            // anyway: the kind is in the column's domain, a row could carry
            // one from a later build, and a card that met an unknown kind and
            // drew nothing would be a blank line where a milestone was.
            guard let weightLbs = highlight.weightLbs else { return highlight.text }
            let total = StatMath.compactNumber(Units.fromPounds(weightLbs, to: unit))
            return "\(highlight.text) — \(total) \(unit.label)"
        }
    }
}
```

**Interfaces** — *consumes:* `PostSummary`, `StatMath.estimatedOneRepMax(weight:reps:)` (:125),
`StatMath.compactNumber`, `Units.format(pounds:unit:rounded:includeUnit:)`, `Units.fromPounds(_:to:)`,
`WeightUnit.label`. *Produces:* `HighlightMath.propose(summary:)`, `.bestSet(in:)`, `.prSet(in:)`,
`HighlightText.line(_:unit:)` — S2.6 calls `propose`, S2.7, S2.6a and S2.9 call `line`. **No
`volumeMilestonesLbs` and no `milestoneCrossed`**, per the ruling above; `Profile.lifetimeVolumeLifted` is
not consumed anywhere in this plan.

**TDD steps.**

1. Write the failing test first — `GymSyncApp/GymSyncTests/HighlightMathTests.swift`:

```swift
import XCTest
@testable import GymSync

/// Spec §1 line 4, as this release ships it: the top set and the PR, no free
/// text, and a weight that still reads right in a friend's own unit. The
/// milestone proposal waits for `MilestoneCatalog` (controller ruling) and its
/// absence is asserted below, so the day it arrives a test says so.
final class HighlightMathTests: XCTestCase {

    private func set(_ weight: Decimal?, _ reps: Int?,
                     pr: Bool = false, failed: Bool = false)
        -> PostSummary.ExerciseEntry.SetEntry {
        .init(weightLbs: weight, reps: reps, isPR: pr, isFailed: failed)
    }

    private func summary(_ exercises: [PostSummary.ExerciseEntry],
                         volume: Decimal = 7_240) -> PostSummary {
        PostSummary(durationSeconds: 2_520, totalVolumeLbs: volume,
                    exercises: exercises, routineName: "Push day")
    }

    func testTheBestSetIsTheBestEstimatedMaxNotTheHeaviestBar() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell",
                  sets: [set(225, 8), set(245, 1)]),
        ])
        // 225 × 8 implies more than 245 × 1 under StatMath's own formula.
        XCTAssertEqual(HighlightMath.bestSet(in: s)?.set.reps, 8)
    }

    func testFailedAndUnweightedSetsAreNotCandidates() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell",
                  sets: [set(315, 3, failed: true), set(185, 5)]),
            .init(name: "Walking Lunge", equipment: "bodyweight", sets: [set(nil, 20)]),
        ])
        XCTAssertEqual(HighlightMath.bestSet(in: s)?.set.weightLbs, 185)
    }

    func testAPRSuppressesTheTopSetWhenTheyAreTheSameSet() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell",
                  sets: [set(225, 5), set(235, 3, pr: true)]),
        ])
        let proposals = HighlightMath.propose(summary: s)
        XCTAssertEqual(proposals.map(\.kind), [.pr], "one fact, once")
    }

    func testATopSetAndADifferentPRAreBothOffered() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell", sets: [set(315, 5)]),
            .init(name: "Bench Press", equipment: "barbell", sets: [set(185, 3, pr: true)]),
        ])
        XCTAssertEqual(HighlightMath.propose(summary: s).map(\.kind), [.topSet, .pr])
    }

    /// THE MILESTONE PROPOSAL IS NOT OFFERED IN THIS RELEASE (controller
    /// ruling): the one catalog is the You hero's `MilestoneCatalog`, and a
    /// private ladder here would be a second accounting of the same pounds.
    /// This test is the guard on that decision — it fails the day someone
    /// adds an arm without wiring it to the catalog, which is precisely when
    /// somebody should be reading this comment.
    func testNoMilestoneIsProposedUntilTheCatalogShips() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell", sets: [set(315, 5)]),
        ], volume: 7_240)
        XCTAssertFalse(HighlightMath.propose(summary: s).contains { $0.kind == .milestone })
    }

    func testNeverMoreThanThree() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell", sets: [set(315, 5)]),
            .init(name: "Bench Press", equipment: "barbell", sets: [set(185, 3, pr: true)]),
        ])
        XCTAssertLessThanOrEqual(HighlightMath.propose(summary: s).count, 3)
    }

    func testNoCandidatesMeansNoPicker() {
        let s = summary([
            .init(name: "Walking Lunge", equipment: "bodyweight", sets: [set(nil, 20)]),
        ])
        XCTAssertTrue(HighlightMath.propose(summary: s).isEmpty)
    }

    // MARK: - the viewer's unit

    func testTheLineRendersInTheViewersUnit() {
        let pr = PostHighlight(kind: .pr, text: "PR — Back Squat",
                               weightLbs: 225, reps: 3)
        XCTAssertEqual(HighlightText.line(pr, unit: .lbs), "PR — Back Squat 225 lb × 3")
        XCTAssertTrue(HighlightText.line(pr, unit: .kg).contains("kg"),
                      "a frozen string would have shown a kilo lifter pounds")
    }

    func testAMilestoneLineIsCompact() {
        let milestone = PostHighlight(kind: .milestone, text: "Lifetime total crossed",
                                      weightLbs: 1_000_000, reps: nil)
        XCTAssertEqual(HighlightText.line(milestone, unit: .lbs),
                       "Lifetime total crossed — 1M lb")
    }
}
```

2. Push — red.
3. Write `HighlightMath.swift`.
4. Push — green. If `testTheLineRendersInTheViewersUnit` or `testAMilestoneLineIsCompact` disagrees with
   `Units.format` / `StatMath.compactNumber`'s actual spelling, **change the test to what the shipped
   formatter produces** — the formatter is the authority, not this plan's guess at its output — and say so in
   the commit body.
5. Commit: `feat(social): Coach's highlight proposals, and the viewer's own unit` + the trailer.

---

### S2.6 — the composer snapshots the trajectory, the rung and the retakes — **L**

**Files:** `GymSyncApp/GymSync/Models/PostTrajectoryResolver.swift` (new),
`GymSyncApp/GymSync/Models/WorkoutPost.swift`,
`GymSyncApp/GymSync/Features/Workout/PumpCheckComposer.swift`,
`GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift`,
`GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift`,
`GymSyncApp/GymSync/App/CatalogHostView.swift`,
`GymSyncApp/GymSyncTests/PostLatenessTests.swift` (new),
`GymSyncApp/GymSyncTests/WorkoutPostLiveRepositoryTests.swift` (new).

**Three sites construct `PumpCheckContext`, not two** — grep-verified:
`WorkoutSessionView.swift:4281`, `GroupSessionLiveView.swift:6087` and **`CatalogHostView.swift:1261`**
(`content_pumpComposer`). The third is a catalog fixture and fills the four new fields with values, never a
resolver: `completedAt: nil`, `trajectory: nil`, `goalID: nil`, `weekStartString: nil` — the idle composer
has no photo, so no picker and no lateness are in that frame, and `app-pump-composer` stays byte-identical.
Leaving it out would break the build, which is why it is named here rather than discovered in CI. **Task
S2.6a adds a second builder beside it** for the review state, which is where the picker lives.

**The resolver** — the one place that reads the author's own goal. It is a free function rather than a method
on the composer because both context builders need it and neither is a good home for the other's copy:

```swift
import Foundation

// MARK: - Resolving the trajectory, once, at post time
//
// Spec §1 lines 2-3, §6. Plan task S2.6.
//
// THE ONLY READS RLS PERMITS. `BlockGoalRepository` and
// `WeeklyGoalRepository` both answer for `auth.uid()` alone, so this runs as
// the AUTHOR, before the post exists, and the row carries the answer. A feed
// card never calls it.

enum PostTrajectoryResolver {

    /// What the composer needs to staple onto the post, or **nil when the
    /// athlete has no active block** — spec §1: "An athlete with no active
    /// block has no line 2 and no line 3".
    ///
    /// Best-effort throughout, like every other read on this path: a blip
    /// costs the post its trajectory, never the post itself.
    static func resolve(
        now: Date = .now,
        calendar: Calendar = .current,
        blockGoals: any BlockGoalRepository = LiveBlockGoalRepository(),
        weeklyGoals: any WeeklyGoalRepository = LiveWeeklyGoalRepository()
    ) async -> (trajectory: PostTrajectory, goalID: UUID, weekStartString: String)? {
        guard let goal = await blockGoals.activeGoal(),
              let page = await blockGoals.page(goalID: goal.id) else { return nil }

        // The DEVICE calendar's week, via WeekMath — the one definition of
        // "this week" on Home (`WeeklyGoal.swift`'s WeekMath note). Computing
        // a second one here would put the card's rung and the strip's rung in
        // different weeks for every user whose week does not start on Monday.
        let weekStart = WeekMath.weekStartString(now, calendar: calendar)

        var kind: WeeklyGoalKind?
        var progress: WeeklyGoalProgress?
        if let weekly = await weeklyGoals.goal(weekStart: weekStart) {
            kind = weekly.kind
            progress = await weeklyGoals.progress(for: weekly)
        }

        let trajectory = PostTrajectoryMath.snapshot(goal: goal, page: page,
                                                     weeklyKind: kind,
                                                     weeklyProgress: progress)
        return (trajectory, goal.id, weekStart)
    }
}
```

**`PumpCheckContext`** gains four fields — the payload the session view already builds, widened:

```swift
struct PumpCheckContext {
    let sessionID: UUID
    let summary: PostSummary
    let avgBpm: Int?
    let maxBpm: Int?
    let includeHRDefault: Bool
    /// The moment the recap appeared — anchor of the 1:00 window.
    let windowStart: Date
    // ── the trajectory snapshot (spec §1, §2, §6) ─────────────────────────
    /// The session's own completion. The precise late tag measures from here,
    /// not from `windowStart`: spec §2 says "elapsed time from the session's
    /// completion to the post", and a recap opened ten minutes late would
    /// otherwise read as a prompt post.
    let completedAt: Date?
    /// Resolved by `PostTrajectoryResolver`, nil for an athlete with no block.
    let trajectory: PostTrajectory?
    let goalID: UUID?
    let weekStartString: String?
}
```

Both builders fill them. `WorkoutSessionView.pumpCheckContext` (:4280-4288):

```swift
    private var pumpCheckContext: PumpCheckContext? {
        guard let session = completedSession, let windowStart = recapAppearedAt else { return nil }
        return PumpCheckContext(
            sessionID: session.id,
            summary: buildPostSummary(),
            avgBpm: recapHRStats?.avg,
            maxBpm: recapHRStats?.max,
            includeHRDefault: ThemeStore.shared.shareHeartRate && recapHRStats != nil,
            windowStart: windowStart,
            completedAt: session.completedAt,
            trajectory: resolvedTrajectory?.trajectory,
            goalID: resolvedTrajectory?.goalID,
            weekStartString: resolvedTrajectory?.weekStartString)
    }

    /// Resolved once, when the recap appears — `pumpCheckContext` is a
    /// computed property and may not await.
    @State private var resolvedTrajectory:
        (trajectory: PostTrajectory, goalID: UUID, weekStartString: String)?
```

filled from the same `.task` that sets `recapAppearedAt`:
`resolvedTrajectory = await PostTrajectoryResolver.resolve()`.

`GroupSessionLiveView.buildPumpCheckContext(session:sets:)` (:6039-6088) is already `async`, so it awaits the
resolver inline and passes `session.completedAt` the same way. `buildPostSummary()` / the group builder's `PostSummary(…)` both gain
`routineName: routine?.name` and `routineName: routineName` respectively.

**`WorkoutPostRepository.create`** takes the snapshot and **derives `is_late` itself**:

```swift
    /// … (the existing upload-then-insert doc comment stays) …
    ///
    /// `isLate` IS NO LONGER A PARAMETER. Spec §2 makes it a derivation from
    /// `postedAt − completedAt` (`PostLateness.isLate`), so the one place
    /// that writes the row is the one place that decides it — a caller can no
    /// longer hand in a lateness that disagrees with the timestamps beside it.
    /// `capturedLate` survives as the FALLBACK for a session with no
    /// `completed_at`, which is a shape this app no longer writes.
    static func create(sessionID: UUID,
                       summary: PostSummary,
                       photoJPEG: Data?,
                       includesHR: Bool,
                       avgBpm: Int?,
                       maxBpm: Int?,
                       completedAt: Date?,
                       capturedLate: Bool,
                       retakeCount: Int,
                       highlight: PostHighlight?,
                       trajectory: PostTrajectory?,
                       goalID: UUID?,
                       weekStartString: String?,
                       postedAt: Date = .now) async throws -> WorkoutPost
```

with `PostInsert` gaining the matching seven keys (`completed_at`, `is_late`, `retake_count`, `highlight`,
`trajectory`, `goal_id`, `week_start`) and the body computing
`isLate: PostLateness.isLate(completedAt: completedAt, postedAt: postedAt, fallback: capturedLate)`.

> **AMENDED (integration, 2026-09-12) — `is_late` is derived SERVER-side, not by the client.** Fix round 1
> added a third migration, `supabase/migrations/20260912000002_workout_posts_is_late_trigger.sql`: a
> `BEFORE INSERT` trigger (`public.workout_posts_derive_is_late`) sets
> `NEW.is_late := (now() - NEW.completed_at) > interval '60 seconds'` whenever `completed_at` is present.
>
> The reason is that the client derived the boolean from the **device** clock while the tag the card prints
> beside it — "posted 47 min after" — is computed from `created_at`, which is the **server's** `now()`. Two
> clocks, one fact: a device an hour fast wrote `is_late = true` onto a post whose own timestamps said it was
> prompt, and nothing in the row disagreed with itself loudly enough to be noticed.
>
> Still **not** a generated column, for the reason 20260912000001 already gives: making a populated boolean
> generated means dropping it, which would erase what every pre-2026-09 row says about itself. A `BEFORE
> INSERT` trigger touches new rows only. **The NULL branch is the contract:** a row with no `completed_at`
> keeps whatever the client sent, because there is nothing to measure from and guessing `false` would quietly
> un-late a genuinely late post. The 60 s window is therefore spelled twice, in two languages — here and as
> `PostLateness.windowSeconds` in Swift — and there is no way to share one literal across the wire.
>
> `PostLateness.isLate` and the `capturedLate` fallback both **stay** in the client: they still decide what is
> sent for a completion-less row, and `PostLatenessTests` still covers them. The trigger overrides the value
> whenever it can measure one. This also amends the self-review's deviation note below, which states the
> opposite.

**The composer.** Three changes to `PumpCheckComposerCard`:

1. `@State private var retakeCount = 0`, incremented in the Retake button (:175-178) before it re-opens the
   camera.
2. The highlight picker, in `reviewBlock`, between the HR toggle and the Post/Retake row:

```swift
            // Spec §1 line 4: Coach proposes, the lifter picks ONE OR NONE.
            // No free text, and no new primary — `Post` is the one accent on
            // this card (design rule 4). Selection is the "current item" job
            // of accent (rule 2): a 1.5 pt ring, the same one
            // `GSGoalChip.isNext` draws.
            if !proposals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("COACH'S PICKS")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral500)
                    ForEach(Array(proposals.enumerated()), id: \.offset) { _, proposal in
                        Button {
                            // Tapping the chosen one clears it — "or none" is
                            // reachable without a fourth control saying None.
                            highlight = (highlight == proposal) ? nil : proposal
                        } label: {
                            Text(HighlightText.line(proposal, unit: ThemeStore.shared.weightUnit))
                                .font(GSFont.bodyMedium(12.5, relativeTo: .caption))
                                .foregroundStyle(theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(theme.bg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                                        .strokeBorder(highlight == proposal
                                                      ? theme.accent : theme.divider,
                                                      lineWidth: highlight == proposal ? 1.5 : 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
```

   with `@State private var highlight: PostHighlight?` and

```swift
    /// Computed, not stored: the summary is immutable and
    /// `HighlightMath.propose` is pure, so there is nothing to keep in sync.
    private var proposals: [PostHighlight] {
        HighlightMath.propose(summary: context.summary)
    }
```

3. `post(_:)` passes the lot through:

```swift
            _ = try await WorkoutPostRepository.create(
                sessionID: context.sessionID,
                summary: context.summary,
                photoJPEG: jpeg,
                includesHR: includeHR && context.avgBpm != nil,
                avgBpm: context.avgBpm,
                maxBpm: context.maxBpm,
                completedAt: context.completedAt,
                capturedLate: capturedLate,
                retakeCount: retakeCount,
                highlight: highlight,
                trajectory: context.trajectory,
                goalID: context.goalID,
                weekStartString: context.weekStartString)
```

**Interfaces** — *consumes:* `BlockGoalRepository.activeGoal()`/`.page(goalID:)`,
`WeeklyGoalRepository.goal(weekStart:)`/`.progress(for:)`, `WeekMath.weekStartString(_:calendar:)`,
`PostTrajectoryMath.snapshot(…)`, `HighlightMath.propose(…)`, `HighlightText.line(_:unit:)`,
`PostLateness.isLate(completedAt:postedAt:fallback:)`.
*Produces:* `PostTrajectoryResolver.resolve(now:calendar:blockGoals:weeklyGoals:)`, `PumpCheckContext`'s five
new fields, `WorkoutPostRepository.create`'s new signature — consumed by S2.7 (what it renders) and S2.10.

**TDD steps.**

1. Write the failing tests first — `GymSyncApp/GymSyncTests/PostLatenessTests.swift`:

```swift
import XCTest
@testable import GymSync

/// Spec §2's precise lateness: elapsed from the session's COMPLETION to the
/// post, on three scales, with the binary `is_late` derived from the same two
/// timestamps.
final class PostLatenessTests: XCTestCase {

    private let completed = Date(timeIntervalSince1970: 1_788_696_000)
    private func posted(after seconds: TimeInterval) -> Date {
        completed.addingTimeInterval(seconds)
    }

    func testInsideTheWindowIsNotLateAndWearsNoTag() {
        XCTAssertFalse(PostLateness.isLate(completedAt: completed,
                                           postedAt: posted(after: 45), fallback: true))
        XCTAssertNil(PostLateness.tag(completedAt: completed, postedAt: posted(after: 45)))
    }

    func testTheSpecsOwnExample() {
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 47 * 60)),
                       "posted 47 min after")
        XCTAssertTrue(PostLateness.isLate(completedAt: completed,
                                          postedAt: posted(after: 47 * 60), fallback: false))
    }

    func testTheThreeScales() {
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 89 * 60)),
                       "posted 89 min after")
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 90 * 60)),
                       "posted 1 hr after")
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 50 * 3600)),
                       "posted 2 days after")
    }

    func testJustPastTheWindowStillReadsAsAMinuteNotAsZero() {
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 61)),
                       "posted 1 min after")
    }

    func testNoCompletionFallsBackToTheCaptureFlagRatherThanGuessing() {
        XCTAssertTrue(PostLateness.isLate(completedAt: nil, postedAt: completed, fallback: true))
        XCTAssertFalse(PostLateness.isLate(completedAt: nil, postedAt: completed, fallback: false))
        XCTAssertNil(PostLateness.tag(completedAt: nil, postedAt: completed))
    }

    func testRetakesAreSilentAtZero() {
        XCTAssertNil(PostLateness.retakeTag(0))
        XCTAssertEqual(PostLateness.retakeTag(1), "1 retake")
        XCTAssertEqual(PostLateness.retakeTag(2), "2 retakes")
    }
}
```

2. Write the second failing test — `GymSyncApp/GymSyncTests/WorkoutPostLiveRepositoryTests.swift`. It is the
   only place the six columns meet the live table:

```swift
import XCTest
@testable import GymSync

/// `WorkoutPostRepository.create` against the real `workout_posts`, in the
/// repo's live-DB idiom.
///
/// CLEANUP IS THE LAW (TestSession.swift's header): the session comes from
/// `makeTempSoloSession()`, which pre-registers its own deletion, and the
/// post's deletion is registered BEFORE the write on top of that —
/// `workout_posts.session_id` is ON DELETE CASCADE
/// (20260731000001:22), so the post would go with the session anyway, and
/// belt-and-braces costs one line.
///
/// THE DATES THIS TEST CONTROLS ARE 2099. `created_at` is server-defaulted
/// and cannot be; the teardown is what keeps this account's feed clean.
final class WorkoutPostLiveRepositoryTests: XCTestCase {

    private let farFuture = Date(timeIntervalSince1970: 4_102_444_800) // 2100-01-01

    func testTheSnapshotColumnsRoundTrip() async throws {
        try await TestAuth.signInIfConfigured()
        let session = try await makeTempSoloSession()

        let trajectory = PostTrajectory(
            goalLine: "Bench 225 by Oct 18", weekNumber: 3, weekCount: 8,
            standing: .behind,
            chips: [.init(name: "CHEST", done: 8, target: 12, fill: nil)])
        let highlight = PostHighlight(kind: .pr, text: "PR — Back Squat",
                                      weightLbs: 235, reps: 3)
        let summary = PostSummary(durationSeconds: 2_520, totalVolumeLbs: 7_240,
                                  exercises: [], routineName: "Push day")

        var createdID: UUID?
        addTeardownBlock {
            if let createdID {
                try? await WorkoutPostRepository.delete(id: createdID, photoPath: nil)
            }
        }

        let post = try await WorkoutPostRepository.create(
            sessionID: session.id, summary: summary, photoJPEG: nil,
            includesHR: false, avgBpm: nil, maxBpm: nil,
            completedAt: farFuture.addingTimeInterval(-47 * 60),
            capturedLate: false, retakeCount: 2, highlight: highlight,
            trajectory: trajectory, goalID: nil, weekStartString: "2099-01-04",
            postedAt: farFuture)
        createdID = post.id

        XCTAssertEqual(post.retakeCount, 2)
        XCTAssertEqual(post.trajectory, trajectory)
        XCTAssertEqual(post.highlight, highlight)
        XCTAssertEqual(post.weekStartString, "2099-01-04")
        XCTAssertEqual(post.summary.routineName, "Push day")
        XCTAssertTrue(post.isLate, "47 minutes after the session is late, derived")

        let completedAt = post.completedAt
        let unwrapped = try XCTUnwrap(completedAt)   // bind, THEN unwrap
        XCTAssertEqual(PostLateness.tag(completedAt: unwrapped, postedAt: post.createdAt) != nil,
                       true)
    }
}
```

3. Push — red.
4. Write the resolver, widen `PumpCheckContext` and both builders, widen `create`, and change the composer.
5. Push — green. `app-pump-composer` is unchanged — it is the **idle** state and has no photo, so the picker
   is not in it. **S2.6a is what renders the picker in CI**, and it is not optional: the picker is new UI and
   no design change merges on a fixture nobody rendered.
6. Commit: `feat(social): the composer snapshots the trajectory, the rung, the retakes and the pick` +
   the trailer.

---

### S2.6a — `pump-composer-highlight`, the review state rendered in CI — **M**

**Files:** `GymSyncApp/GymSync/Features/Workout/PumpCheckComposer.swift`,
`GymSyncApp/GymSync/Features/Workout/PumpComposerFixtures.swift` (new),
`App/CatalogHostView.swift`, `GymSyncTests/CatalogScreenTests.swift`,
`GymSyncUITests/ScreenshotTests.swift`, `docs/design/frame-map.json`.

**Why this exists — controller ruling.** Real CI renders before any design change merges, and the highlight
picker is new UI. The goal-first final review caught three defects that fixture frames had hidden while the
production path was broken; the answer to that is *more* real rendering, not less. The review state was
previously unrenderable only because `CameraPicker` cannot be driven headless — which is a reason to bypass
the picker, not to skip the frame.

One id, one commit, all four contract parts (constraint 3):

| id | frame | renders |
|---|---|---|
| `pump-composer-highlight` | 102 | `PumpCheckComposerCard` in its **review** state: the fixture photo, the HR toggle, `COACH'S PICKS` with two proposals and the PR one selected, `Post` and `Retake` |

**The seam.** `PumpCheckComposerCard` gains the `#if DEBUG` init the rest of the catalog already uses
(`VenueHubView.swift:294-308` is the precedent), and **no HealthKit or camera call is reachable from it**
(constraint 5):

```swift
    #if DEBUG
    /// The catalog's photo. Non-nil drops the card straight into its REVIEW
    /// state — the same state a capture produces — without going anywhere
    /// near `CameraPicker`/`UIImagePickerController`, which cannot be driven
    /// headless and hangs a simulator run if it is presented.
    ///
    /// An IMAGE BUILT IN PROCESS, not a bundled asset: hermetic (global
    /// constraint 7), no file to keep in the target, and identical on every
    /// run.
    init(context: PumpCheckContext, catalogPhoto: UIImage?) {
        self.context = context
        _includeHR = State(initialValue: context.includeHRDefault)
        _photo = State(initialValue: catalogPhoto)
        _retakeCount = State(initialValue: catalogPhoto == nil ? 0 : 2)
        _highlight = State(initialValue: HighlightMath
            .propose(summary: context.summary).first { $0.kind == .pr })
    }
    #endif
```

`PumpComposerFixtures.swift`:

```swift
#if DEBUG
import UIKit

// MARK: - The pump composer's fixture world
//
// Plan task S2.6a. HERMETIC (global constraint 7): one solid-colour image
// drawn in process, one fixture summary, no clock, no camera, no HealthKit.
enum PumpComposerFixtures {

    /// A 1200 × 1200 flat tile standing in for a capture. Solid, not a
    /// gradient or noise: the frame is judged on the CARD, and a photo with
    /// detail in it invites a reviewer to judge the photo.
    static let photo: UIImage = {
        let size = CGSize(width: 1200, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()
}
#endif
```

**The builder** — `content_pumpComposerHighlight` in `CatalogHostView`:

```swift
    /// `pump-composer-highlight`: the composer's REVIEW state — the state a
    /// capture lands in, and the only place spec §1 line 4's picker appears.
    /// Two proposals (the top set and the PR — this release proposes no
    /// milestone, task S2.5), the PR selected, `Post` still the one accent on
    /// the card (design rule 4).
    private var content_pumpComposerHighlight: some View {
        ScrollView {
            PumpCheckComposerCard(
                context: PumpCheckContext(
                    sessionID: UUID(),
                    summary: Self.pumpComposerFixtureSummary,
                    avgBpm: 142, maxBpm: 171,
                    includeHRDefault: true,
                    windowStart: Date(),
                    completedAt: nil, trajectory: nil,
                    goalID: nil, weekStartString: nil),
                catalogPhoto: PumpComposerFixtures.photo)
                .padding(16)
        }
    }

    /// TWO candidate exercises, so the picker has TWO rows: a heavy top set
    /// on one lift and a PR on another. A single PR set would collapse to one
    /// proposal (S2.5's dedupe) and the frame would not show a choice being
    /// made, which is the whole of what line 4 is.
    private static let pumpComposerFixtureSummary = PostSummary(
        durationSeconds: 2520,
        totalVolumeLbs: 7240,
        exercises: [
            .init(name: "Back Squat", equipment: "barbell", sets: [
                .init(weightLbs: 315, reps: 5, isPR: false, isFailed: false),
            ]),
            .init(name: "Bench Press", equipment: "barbell", sets: [
                .init(weightLbs: 185, reps: 3, isPR: true, isFailed: false),
            ]),
        ],
        routineName: "Push day")
```

`windowStart: Date()` is the **inherited** clock anchor `content_pumpComposer` already carries (:1261-1268)
and it is out of this frame anyway: the review state shows no countdown. Nothing else here reads a clock.

**Frame-map entry:**

```json
  "pump-composer-highlight": { "frame": 102, "title": "Pump composer - Coach's picks" }
```

**Do not bump `FLOOR`** — I1 does it once.

**TDD steps.** 1. Add the seam, the fixtures, the case, the builder, the id string, the capture method and the
frame-map entry — one commit. 2. Push. 3. `CatalogScreenTests` green (the count guard is the test); a new
`app-pump-composer-highlight.png` in the artifact, showing two picks with the PR ringed. 4. Confirm
`app-pump-composer` (the idle state) is **unchanged** — the new init is a second one, not a replacement.
5. Commit: `feat(social): pump-composer-highlight — Coach's picks, rendered by CI` + the trailer.

**Proves:** spec §1 line 4's UI exists and looks like something, before a human is asked to approve it.

---

### S2.7 — the card's seven lines — **L**

**File:** `GymSyncApp/GymSync/Features/Social/PumpFeedView.swift`,
`GymSyncApp/GymSyncTests/PumpPostCardCopyTests.swift` (new).

Spec §1's anatomy, top to bottom, inside the card that already exists. Nothing is removed.

| # | line | change |
|---|---|---|
| 1 | who and when | the `late` tag becomes the precise tag; a retake tag joins it |
| 2 | the trajectory line | **new** — `post.trajectory?.line` |
| 3 | this week's rung | **new** — `GSGoalChip` row |
| 4 | one highlight | **new** — `HighlightText.line(_:unit:)` |
| 5 | the workout in plain terms | the stats line gains the routine name |
| 6 | the picture | unchanged |
| 7 | reactions | unchanged here; S2.8 makes them commit |

`PumpPostCard.body`'s `VStack` becomes:

```swift
        VStack(alignment: .leading, spacing: 0) {
            authorRow
                .padding(12)

            // Lines 2 and 3 sit ABOVE the photo, because they are the reason
            // the card exists (spec §1: "a snapshot of where people are in
            // their fitness trajectory") and a 300 pt photo between the name
            // and the trajectory would bury it below the fold.
            if let trajectory = post.trajectory {
                trajectoryBlock(trajectory)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            if post.photoPath != nil {
                photoBlock
            }

            summaryBlock
                .padding(12)

            reactionsRow
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
```

> **AMENDED (integration, 2026-09-12) — the card ships spec §1's order; the snippet above did not.** Fix
> round 1 (review fix 4) found the snippet left the photo between line 3 and line 4, so the card would have
> rendered **1, 2, 3, picture, 4, 5, 7** — the highlight and the plain-terms line pushed *below* a 300 pt
> photo. Spec §1's anatomy is 1 who and when, 2 the trajectory, 3 this week's rung, 4 the highlight, 5 the
> workout in plain terms, **6 the picture**, 7 reactions.
>
> Shipped (`PumpFeedView.swift`, `PumpPostCard.body`): `authorRow`, then `trajectoryBlock` (lines 2-3), then
> `summaryBlock` (lines 4-5 and the per-exercise rows they sit with), then `photoBlock`, then `reactionsRow`.
> The picture is **sixth**. The per-exercise rows are not one of the seven lines — they are detail this card
> has shown since 2026-07 — so they travel with the summary rather than being split from it.

```swift
            Spacer()
            // Spec §2: the binary `late` chip becomes elapsed time, and the
            // retake count shows above zero. An OLD row (no `completed_at`)
            // keeps the chip it was written with — an honest fallback rather
            // than a computed "0 min".
            if let retakes = PostLateness.retakeTag(post.retakeCount ?? 0) {
                GSTag(text: retakes, style: .neutral)
            }
            if let lateness = PostLateness.tag(completedAt: post.completedAt,
                                               postedAt: post.createdAt) {
                GSTag(text: lateness, style: .neutral)
            } else if post.isLate {
                GSTag(text: "late", style: .neutral)
            }
```

the new block:

```swift
    /// Lines 2 and 3 — the trajectory and this week's rung (spec §1).
    ///
    /// A STRIP, not a card: `surface` at 14 pt, design rule 1's "lines that
    /// belong to the card above them". The card is already the one raised
    /// object on this idea and a second extrusion inside it would make two.
    ///
    /// NO ACCENT anywhere in here, `behind` included. Accent has three jobs
    /// (rule 2) and none of them is "a fact about someone else's week"; red
    /// is errors only, and being behind is not an error. The standing is
    /// carried by the WORD, which is what spec §1 asks for.
    private func trajectoryBlock(_ trajectory: PostTrajectory) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(trajectory.line)
                .font(GSFont.bodyMedium(12.5, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(theme.neutral700)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if !trajectory.chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(trajectory.chips.enumerated()), id: \.offset) { _, chip in
                        // isNext is never set: a finished post is not an
                        // invitation (design rule 2).
                        GSGoalChip(name: chip.name, done: chip.done,
                                   target: chip.target, fill: chip.fill)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
```

and `summaryBlock`'s stats line (:311-321) gains line 4 above it and the routine name inside it:

```swift
            // Line 4 — the lifter's one pick. Bold body text, no glyph and no
            // colour: the set rows below already carry a `PR` tag in accent,
            // and a second accent on the same card would be two.
            if let highlight = post.highlight {
                Text(HighlightText.line(highlight, unit: unit))
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
            }

            // Line 5 — `Push day · 42 min · 7,240 lb`. The routine name is
            // dropped rather than replaced for a freeform session; "Workout ·
            // 42 min" names nothing.
            HStack(spacing: 6) {
                let minutes = max(1, post.summary.durationSeconds / 60)
                if let routineName = post.summary.routineName, !routineName.isEmpty {
                    Text(routineName)
                    Text("·")
                }
                Text("\(minutes) min")
                Text("·")
                Text("\(StatMath.compactNumber(Units.fromPounds(post.summary.totalVolumeLbs, to: unit))) \(unit.label)")
                if post.includesHR, let avg = post.avgBpm, let maxBpm = post.maxBpm {
                    Text("·")
                    Text("avg \(avg) · max \(maxBpm) bpm")
                }
                Spacer(minLength: 0)
            }
            .font(GSFont.body(11.5, relativeTo: .caption))
            .foregroundStyle(theme.neutral500)
```

**Interfaces** — *consumes:* `PostLateness.tag`/`.retakeTag`, `PostTrajectory.line`, `GSGoalChip`,
`HighlightText.line(_:unit:)`, `PostSummary.routineName`. *Produces:* the rendered card; S2.9 captures it.

**TDD steps.**

1. Write the failing test first — `GymSyncApp/GymSyncTests/PumpPostCardCopyTests.swift`. A SwiftUI body is
   not unit-testable, so the test pins the **strings** the card composes, which is where every decision
   actually lives:

```swift
import XCTest
@testable import GymSync

/// Spec §1's card, as the strings it prints. The view is a layout of these.
final class PumpPostCardCopyTests: XCTestCase {

    func testTheTrajectoryLineIsOneSentenceWithThreeParts() {
        let trajectory = PostTrajectory(goalLine: "Bench 225 by Oct 18", weekNumber: 3,
                                        weekCount: 8, standing: .behind, chips: [])
        XCTAssertEqual(trajectory.line.components(separatedBy: " · ").count, 3)
        XCTAssertTrue(trajectory.line.hasSuffix("behind"),
                      "spec §1: no per-post hide — `behind` is said in the open")
    }

    func testAnAthleteWithNoBlockHasNoTrajectoryToPrint() {
        // The card branches on `post.trajectory == nil`; the resolver returns
        // nil for an athlete with no active block (task S2.6).
        let post = PumpPostCardCopyTests.post(trajectory: nil, highlight: nil)
        XCTAssertNil(post.trajectory)
    }

    func testTheStatsLineNamesTheRoutineWhenThereIsOne() {
        let summary = PostSummary(durationSeconds: 2_520, totalVolumeLbs: 7_240,
                                  exercises: [], routineName: "Push day")
        XCTAssertEqual(summary.routineName, "Push day")
        let freeform = PostSummary(durationSeconds: 2_520, totalVolumeLbs: 7_240,
                                   exercises: [], routineName: nil)
        XCTAssertNil(freeform.routineName,
                     "a freeform session drops the name rather than inventing one")
    }

    func testAnOldRowKeepsItsBinaryLateTag() {
        let posted = Date(timeIntervalSince1970: 1_788_696_000)
        XCTAssertNil(PostLateness.tag(completedAt: nil, postedAt: posted),
                     "no completion means the card falls back to `is_late`")
    }

    private static func post(trajectory: PostTrajectory?,
                             highlight: PostHighlight?) -> WorkoutPost {
        WorkoutPost(id: UUID(), authorID: UUID(), sessionID: UUID(), photoPath: nil,
                    summary: PostSummary(durationSeconds: 2_520, totalVolumeLbs: 7_240,
                                         exercises: [], routineName: nil),
                    includesHR: false, avgBpm: nil, maxBpm: nil, isLate: false,
                    createdAt: Date(timeIntervalSince1970: 1_788_696_000),
                    completedAt: nil, retakeCount: 0, highlight: highlight,
                    trajectory: trajectory, goalID: nil, weekStartString: nil)
    }
}
```

2. Push — red (`PostSummary(…routineName:)` and `WorkoutPost`'s widened memberwise init exist from S2.0, so
   the red here is the missing card behaviour the strings describe; if the test compiles green at step 2,
   strengthen it before writing the view).
3. Write the card's four changes.
4. Push — green. `app-pump-feed-post` still renders (S2.9 re-fixtures it).
5. Commit: `feat(social): the pump-check card is a trajectory snapshot` + the trailer.

---

### S2.8 — a kudos is one gesture — **M**

**File:** `GymSyncApp/GymSync/Features/Social/PumpFeedView.swift`,
`GymSyncApp/GymSync/Models/WorkoutPost.swift`.

Spec §2, owner decision 4: "tapping an emoji or a sound reaction commits it; there is no un-react. Counts stay
visible, because the object is accomplishment, not a mood."

`toggleReaction` becomes `commitReaction`:

```swift
    /// Optimistic, and ONE-WAY. Spec §2 (Strava's kudos): a reaction commits.
    /// A second tap on a chip you already own does nothing — it is not an
    /// error and it gets no message, because nothing went wrong; the gesture
    /// simply has no second half any more.
    ///
    /// Still optimistic, still rolled back on failure: a tap that never
    /// reached the server must not leave a count that says it did.
    @MainActor
    private func commitReaction(post: WorkoutPost, emoji: String) async {
        guard !mineByPost[post.id, default: []].contains(emoji) else { return }
        mineByPost[post.id, default: []].insert(emoji)
        countsByPost[post.id, default: [:]][emoji, default: 0] += 1
        do {
            try await WorkoutPostRepository.react(postID: post.id, emoji: emoji)
        } catch {
            mineByPost[post.id, default: []].remove(emoji)
            countsByPost[post.id, default: [:]][emoji, default: 1] -= 1
        }
    }
```

and three call-site changes in the card:

- the emoji chip's `onReact(emoji)` is unchanged — the `Button` stays, because a chip that is not yours is
  still tappable and a chip that is yours now simply no-ops;
- the sound chip's `.contextMenu { … "Remove my sound" … }` (:421-429) is **deleted**. It was the one
  remaining un-react in the UI;
- `WorkoutPostRepository.unreact` is **deleted** (see "Deleted", above): grep-verified single call site, and
  an uncalled repository method is this project's own recurring defect.

**Interfaces** — *consumes:* `WorkoutPostRepository.react(postID:emoji:)`. *Produces:* nothing new.
*Removes:* `WorkoutPostRepository.unreact(postID:emoji:)`, `PumpPostCard`'s sound context menu.

**TDD steps.**

1. Grep first, and put both results in the commit body:
   `git grep -n "unreact" -- 'GymSyncApp/**/*.swift'` → one definition, one call site.
   `git grep -n "Remove my sound" -- 'GymSyncApp/**/*.swift'` → one.
2. Make the three changes and delete the method.
3. Push — the build is the proof that nothing else called either.
4. Commit: `feat(social): a kudos commits — the client stops offering un-react` + the trailer, naming the
   consequence plainly: a sound attached by mistake is now permanent, which is what an irreversible gesture
   means.

**Note for the PR body:** the `post_reactions` DELETE **policy** stays
(`20260731000001_workout_posts.sql:111-113`). It is not dead: account deletion and the post's own
`ON DELETE CASCADE` both rely on the row being removable.

---

### S2.9 — `pump-feed-post`, re-rendered from a world with a block — **M**

**File:** `GymSyncApp/GymSync/App/CatalogHostView.swift`.

The id, its frame position and its place in `CatalogScreenTests` all stay; only what it renders changes
(spec §7: "`pump-feed-post` (existing) re-rendered from a fixture world that has a block goal and a
current-week rung — the trajectory line, rung chips, highlight and precise late tag all in frame").

```swift
    /// `pump-feed-post`: two feed cards from a world that HAS a block — a
    /// friend's photo post carrying the full trajectory snapshot (signed-URL
    /// fetch fails in the harness, so the photo block shows its honest
    /// placeholder), and the viewer's own late, summary-only post. Exercises
    /// cover the barbell mini-bar and a bodyweight entry.
    ///
    /// THE CLOCK ANCHOR IS INHERITED, NOT INTRODUCED (global constraint 7):
    /// `createdAt` has been `Date().addingTimeInterval(…)` since 2026-07 so
    /// the author row reads a stable `1 hour ago` rather than drifting into
    /// `3 years ago`. Every NEW fact is anchored RELATIVE to it —
    /// `completedAt` is 47 minutes before its own post — so `posted 47 min
    /// after` is the same string on every run.
    private var content_pumpFeedPost: some View {
        let friendPostedAt = Date().addingTimeInterval(-3600)
        let myPostedAt = Date().addingTimeInterval(-7200)
        return ScrollView {
            VStack(spacing: 14) {
                PumpPostCard(
                    post: WorkoutPost(
                        id: UUID(), authorID: UUID(), sessionID: UUID(),
                        photoPath: "posts/fixture/fixture.jpg",
                        summary: Self.pumpFixtureSummary,
                        includesHR: true, avgBpm: 142, maxBpm: 171,
                        isLate: true,
                        createdAt: friendPostedAt,
                        // Spec §2's own example, exactly: 47 minutes.
                        completedAt: friendPostedAt.addingTimeInterval(-47 * 60),
                        retakeCount: 2,
                        highlight: Self.pumpFixtureHighlight,
                        trajectory: Self.pumpFixtureTrajectory,
                        goalID: StubBlockGoalRepository.fixtureGoalID,
                        weekStartString: "2026-09-06"),
                    author: nil, isMine: false,
                    myReactions: ["🔥"],
                    reactionCounts: ["🔥": 3, "💪": 1, "snd:airhorn": 2],
                    ownedSoundSlugs: ["airhorn"],
                    soundNames: ["airhorn": "Airhorn"],
                    onReact: { _ in }, onDelete: {}, onReport: {})
                PumpPostCard(
                    post: WorkoutPost(
                        id: UUID(), authorID: UUID(), sessionID: UUID(),
                        photoPath: nil,
                        summary: Self.pumpFixtureSummary,
                        includesHR: false, avgBpm: nil, maxBpm: nil,
                        isLate: true,
                        createdAt: myPostedAt,
                        // A DAY-SCALE tag beside the friend's minute-scale
                        // one, so one frame shows both spellings.
                        completedAt: myPostedAt.addingTimeInterval(-50 * 3600),
                        retakeCount: 0,
                        highlight: nil,
                        // NO BLOCK on this one: spec §1's "An athlete with no
                        // active block has no line 2 and no line 3" is a state
                        // the reviewer has to be able to see.
                        trajectory: nil, goalID: nil, weekStartString: nil),
                    author: nil, isMine: true,
                    myReactions: [],
                    reactionCounts: [:],
                    ownedSoundSlugs: [],
                    soundNames: [:],
                    onReact: { _ in }, onDelete: {}, onReport: {})
            }
            .padding(16)
        }
    }

    private static let pumpFixtureSummary = PostSummary(
        durationSeconds: 2520,
        totalVolumeLbs: 7240,
        exercises: [
            .init(name: "Back Squat", equipment: "barbell", sets: [
                .init(weightLbs: 225, reps: 5, isPR: false, isFailed: false),
                .init(weightLbs: 235, reps: 3, isPR: true, isFailed: false),
            ]),
            .init(name: "Walking Lunge", equipment: "bodyweight", sets: [
                .init(weightLbs: nil, reps: 20, isPR: false, isFailed: false),
            ]),
        ],
        routineName: "Push day")

    /// The pick `HighlightMath` would have proposed for the summary above —
    /// the PR set, which suppresses the top set because they are one set.
    private static let pumpFixtureHighlight = PostHighlight(
        kind: .pr, text: "PR — Back Squat", weightLbs: 235, reps: 3)

    /// THE CATALOG'S ONE BLOCK. Bench 225 by Oct 18, week 3 of 8 — the same
    /// block `StubBlockGoalRepository` describes for the ladder page and the
    /// goal door, so a reviewer paging through the artifact sees ONE athlete
    /// rather than three who happen to lift similar numbers.
    ///
    /// `behind`, deliberately: `on track` is the easy frame, and spec §1's
    /// binding ruling is that the hard one ships too, with no per-post hide.
    private static let pumpFixtureTrajectory = PostTrajectory(
        goalLine: "Bench 225 by Oct 18", weekNumber: 3, weekCount: 8,
        standing: .behind,
        chips: [
            .init(name: "CHEST", done: 8, target: 12, fill: nil),
            .init(name: "BACK", done: 10, target: 12, fill: nil),
            .init(name: "LEGS", done: 6, target: 12, fill: nil),
            .init(name: "ARMS", done: 8, target: 8, fill: nil),
        ])
```

**Do not touch `CatalogScreenTests`, `ScreenshotTests` or `frame-map.json`** — the id already exists in all
of them it belongs to, and the FLOOR does not move for a re-render.

**TDD steps.** 1. Rewrite the builder and the three fixtures. 2. Push. 3. Read the artifact:
`app-pump-feed-post` shows, on the first card — `posted 47 min after`, `2 retakes`,
`Bench 225 by Oct 18 · week 3 of 8 · behind`, four rung chips, `PR — Back Squat 235 lb × 3`, and a stats line
leading with `Push day` before the minutes and the volume (whose spelling belongs to
`StatMath.compactNumber`, not to this plan) — and, on the second, a card with **no** lines 2–4 and a
`posted 2 days after` tag.
4. Commit: `feat(social): pump-feed-post renders the trajectory snapshot` + the trailer.

**Proves:** spec §1's anatomy and §2's two tags, in one frame, both with a block and without.

---

### S2.10 — the CI account's feed post, seeded and walked — **L**

**Files:** `scripts/seed_qa_fixtures.js`, `GymSyncApp/GymSyncUITests/ScreenshotTests.swift`.

The seed has never written a `workout_posts` row — grep-verified. This adds one, attached to the Murph
attempt session the script already walks to `completed` with a real `session_participants` row (:649-785), and
pointed at the block goal and current week the same run creates (:1044-1123). Placed **after** the block-goal
block, because it reads `blockGoal.id` and `currentWeekStart`.

```js
  // --- the CI account's pump check: a post that carries a trajectory -------
  // Plan task S2.10 (spec §1, §6). The FIRST workout_posts row this script
  // has ever written. Its job is end-to-end proof that the six columns
  // migration 20260912000001 added accept what the client writes into them —
  // the script fails loudly on any 4xx (see `rest`, :55-61), so a column
  // whose type or CHECK disagrees with `PostTrajectory` turns the seed step
  // red rather than failing silently on a device months later.
  //
  // Attached to the MURPH ATTEMPT session: workout_posts' INSERT policy is
  // is_session_participant (20260731000001:64-69) and that session already
  // has a real participant row for `me`. (This script runs as the service
  // role, which bypasses RLS — the point of matching the policy anyway is
  // that the fixture describes a state a real client could have produced.)
  //
  // Idempotent on a FIXED id, because workout_posts has no natural key:
  // upsert on `id` converges a re-run instead of stacking a post per run.
  //
  // THE TRAJECTORY IS A LITERAL, and deliberately so. `goalLine` is worded by
  // `LadderMath.page` in Swift; re-deriving that wording in JavaScript would
  // be a second opinion about the same milestone, and the wording's
  // authority is the catalog fixture plus PostTrajectoryMathTests. This row
  // proves the COLUMNS, not the copy.
  const QA_POST_ID = '00000000-0000-4000-f000-000000000730';
  const [murphRow] = await rest(
    `sessions?select=completed_at&id=eq.${murphSession.id}`);
  const postCompletedAt = murphRow && murphRow.completed_at;
  await rest('workout_posts?on_conflict=id', { method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates,return=representation' },
    body: JSON.stringify({
      id: QA_POST_ID,
      author_id: me.id,
      session_id: murphSession.id,
      photo_path: null,
      summary: {
        duration_seconds: 2520,
        total_volume_lbs: 7240,
        routine_name: 'Push day',
        exercises: [{
          name: 'Back Squat', equipment: 'barbell',
          sets: [
            { weight_lbs: 225, reps: 5, is_pr: false, is_failed: false },
            { weight_lbs: 235, reps: 3, is_pr: true, is_failed: false },
          ],
        }],
      },
      includes_hr: false,
      is_late: true,
      completed_at: postCompletedAt,
      retake_count: 2,
      highlight: { kind: 'pr', text: 'PR — Back Squat', weightLbs: 235, reps: 3 },
      trajectory: {
        goalLine: 'Bench 225 by Oct 18', weekNumber: 3, weekCount: 8,
        standing: 'onTrack',
        chips: [
          { name: 'CHEST', done: 8, target: 12 },
          { name: 'BACK', done: 10, target: 12 },
          { name: 'LEGS', done: 6, target: 12 },
          { name: 'ARMS', done: 8, target: 8 },
        ],
      },
      goal_id: blockGoal.id,
      week_start: currentWeekStart,
    }) });
  console.log(`  workout post ${QA_POST_ID}: a pump check carrying block goal ${blockGoal.id}'s week 3`);
```

`postCompletedAt` may be null for a session the walk left `in_progress`; the column is nullable and the card
falls back to the binary tag, which is the honest rendering of that state rather than a fabricated completion.

**The walk that looks at it — controller ruling.** A seeded row proves the columns accept what the client
writes and nothing about what anyone sees; the goal-first final review is the precedent for why that is not
enough. So this task also adds the live capture, in `ScreenshotTests.swift` beside `testFriends()` (:739-756),
whose Crews → row navigation idiom it copies exactly:

```swift
    /// The pump feed on the LIVE account — the post `seed_qa_fixtures.js`
    /// writes, rendered by the real `PumpFeedView` against the real
    /// repositories, trajectory and all.
    ///
    /// This is the capture a fixture frame cannot stand in for: the catalog's
    /// `app-pump-feed-post` builds `PumpPostCard` directly with values, so it
    /// would look perfect while `WorkoutPostRepository.feed()`'s decode, the
    /// signed-URL fetch or the trajectory column's round trip were broken.
    ///
    /// CONTAINS, not BEGINSWITH, for the reason `testFriends` gives: the row's
    /// composed accessibility label prepends an icon and appends a subtitle.
    func testPumpFeedLive() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Crews")
        settle()

        let feedRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Pump checks from your friends'")
        ).firstMatch
        if feedRow.waitForExistence(timeout: 15) {
            feedRow.tap()
            settleAfterNavigation()
        }
        // A second settle: the feed's `.task` fetches the page, then hydrates
        // authors and reactions in a second round trip — the same two-cycle
        // wait `testExerciseDetail` and `testActivityFeed` already take.
        settleAfterNavigation()
        attachScreenshot(app, named: "app-pump-feed.png")
    }
```

**No `frame-map.json` entry**, and that is the repo's own rule rather than an omission: a walk capture gets a
frame only where a canvas frame exists for it (`app-tab-social` → 62, `app-friends` → 19), and there has never
been a pump-feed canvas frame — grep-verified, `frame-map.json` contains no `pump` key. `app-group-stats` is
the standing precedent for a walk capture with no entry. It still counts toward the `FLOOR`.

**TDD steps.** 1. Add the seed block. 2. Add `testPumpFeedLive()`. 3. Push — the iOS workflow's "Seed QA
fixture world" step (`ios.yml:195`) runs the script; a rejected column fails the step before any test runs.
4. Confirm the log line, then **read `app-pump-feed.png` in the artifact**: the CI account's own card, with
`Bench 225 by Oct 18 · week 3 of 8 · on track`, four rung chips, `PR — Back Squat 235 lb × 3`, `2 retakes`
and a stats line leading with `Push day`. An empty feed here is a real defect in `feed()`, the RLS or the
decode — which is the whole reason this capture exists. 5. Commit:
`test(social): the CI account's feed post carries a trajectory, and CI looks at it` + the trailer.

**Proves:** the migration's columns accept the client's shapes on the live project, **and** that the
production read path renders them — the half a fixture frame can never prove.

---

# INTEGRATION

Merge **Stage 1 first, then Stage 2** into `feat/social-cards` (Stage 1 owns frame 101, Stage 2 owns 102, so
merging the other way round leaves the frame-map's append order out of frame order). The only conflicts are
the four append-only catalog files — concatenate in frame order, never renumber. Three tasks.

### I1 — `FLOOR`, the frame-map and the accepted deviations — **S**

- `.github/workflows/ios.yml` — **the FLOOR rises by +3 over master's FLOOR at integration**, which is the
  invariant; the literal `110` in the line below was written against master's FLOOR of 107 and is amended.
  One edit, this task only. Extend the comment block above it in the style the goal-first plan's I4
  established:

  > **AMENDED (integration, 2026-09-12).** Master moved before this branch merged: the B2+B9 congruence merge
  > (`aa04eed`) took the FLOOR to **111** — T2.4's `app-tab-stats-2`, T2.3's `app-block-calendar`, and B9's
  > `app-crew-room` and `app-group-sessions`. So the edit is `FLOOR=111` → `FLOOR=114` at **`ios.yml:370`**,
  > not `FLOOR=107` → `FLOOR=110` at `:358`. The +3 does not change: two catalog ids and one live walk.
  > Arithmetic, verified: `ScreenshotTests` carries 108 `func test` methods on master and 111 after the two
  > stream merges, and three methods attach a SECOND file each (`app-tab-stats-2`,
  > `app-ladder-on-track-2`, `app-calendar-scheduling-2`) — 108 + 3 = 111, 111 + 3 = 114.

  ```
  # social cards (I1, 2026-09-11-social-cards-plan.md): 111 -> 114. THREE new
  # captures: two catalog ids (crews-tab frame 101, pump-composer-highlight
  # frame 102) and ONE live-walk capture (app-pump-feed, testPumpFeedLive —
  # no frame-map entry, the app-group-stats precedent). `pump-feed-post` was
  # RE-RENDERED rather than added (spec §7), so it moves no count.
  ```

- `docs/design/frame-map.json` — verify `crews-tab` at **101** and `pump-composer-highlight` at **102**, that
  60–100 are unrenumbered, and that there are no duplicate frame numbers. `app-pump-feed` deliberately has no
  entry (S2.10).
- `docs/design/accepted-deviations.json` — append **two** entries. Neither id has an authoritative canvas
  frame (there was no proof round for the social cards; the spec is the authority), which is the posture the
  `home-v3-*`, `calendar-scheduling` and `venue-*` entries already take:

  ```json
  {
    "screenId": "crews-tab",
    "reason": "Social cards, integration task I1. Frame 101 (Stage 1 task S1.6) has no numbered canvas frame - the authority is spec 3 of 2026-09-11-social-cards-design.md ('the meta line names who showed up most this month - MOST CONSISTENT . SAM . 9 SESSIONS - a crown that decays when they stop'). The Crews tab has never had a catalog fixture at all: app-tab-social is the live-account walk, so this is the first frame in which the crew card, its plate bar, the honor line and the Outside the Box rows are rendered from values rather than from whatever the CI account happened to contain. Two crews, and the SECOND one carries no honor line on purpose - the decay is the line's absence."
  }
  ```

  ```json
  {
    "screenId": "pump-composer-highlight",
    "reason": "Social cards, integration task I1. Frame 102 (Stage 2 task S2.6a) has no numbered canvas frame - the authority is spec 1 line 4 of 2026-09-11-social-cards-design.md ('Coach proposes up to three highlights from the session; the lifter picks one or none. No free text'). The composer's REVIEW state had never been rendered by CI because CameraPicker cannot be driven headless; S2.6a adds a DEBUG-only catalogPhoto seam that drops the card into that state with an in-process fixture image, so the picker is reviewed before it ships. TWO proposals, not three: this release proposes topSet and pr only - the milestone proposal waits for the You hero's MilestoneCatalog rather than shipping a second ladder."
  }
  ```

Commit: `chore(social): FLOOR 111 -> 114, frames 101-102, accepted deviations` + the trailer
(amended from `107 -> 110`, above).

### I2 — end-to-end CI, then by eye — **M**

Push and read the run.

**iOS workflow**
- build green;
- `GymSyncTests` green — **ten new test files**: `CrewHonorMathTests`, `CrewHonorLiveRepositoryTests`,
  `PresenceIsUngatedTests`, `PostTrajectoryModelTests`, `GSGoalChipTests`, `PostTrajectoryMathTests`,
  `HighlightMathTests`, `PostLatenessTests`, `WorkoutPostLiveRepositoryTests`, `PumpPostCardCopyTests` — and
  the `CatalogScreenTests` count guard, which now carries two more ids;
- the screenshot job exports **≥ 114** app captures and "Verify capture count" passes *(amended from 110 —
  see I1)*.

**Backend workflow**
- pgTAP green for `crew_consistency_honor_test.sql` (new, 8 assertions) and `workout_posts_test.sql`
  (extended, 23) — which requires S1.1's and S2.1's migrations to have been **applied to the project**
  (constraint 10). If either is red with a "does not exist" error, the gate was skipped, not the SQL broken.

**Then read the artifact, by eye, in this order:**

> **AMENDED (integration, 2026-09-12) — what "unchanged" means for items 1, 2, 8 and 9.** The canary is
> **0 % of pixels differ below the status bar and above the home-indicator band** — the controller's
> `compare_frames.py` definition — **not** "byte-identical". A PNG re-encoded by a different simulator run is
> not byte-identical even when nothing on the screen moved, and the status-bar clock and the home indicator
> move on every run by construction. Read the frames below against that definition.

1. `app-home-v3-08a-targets-above-calendar` and `-08b-targets-above-join` — **unchanged** (0 % pixels differ
   in the compared band). These are the canary for S2.3's extraction; if either moved, stop and fix S2.3
   rather than re-approving a frame.
2. `app-home-goal-strip-muscle-sets` — **unchanged**, and the tighter canary: it renders the *production*
   strip through `HomeWeeklyGoalStrip`, whose `chipRow` S2.3 rewrote.
3. `app-crews-tab` — two crew cards; the first carries `MOST CONSISTENT · SAM · 9 SESSIONS` under its meta
   line, the second carries no honor line at all; both bars, both next-lift lines, the three Outside the Box
   rows.
4. `app-tab-social` — the live account's `[QA] Push Crew` card carries the honor line from the seed
   (`MOST CONSISTENT · CI_TEST_USER · 1 SESSION`). This is the honor's end-to-end proof: seed → RPC → crown
   → line.
5. `app-pump-feed-post` — the first card: `posted 47 min after`, `2 retakes`, the trajectory line ending in
   `behind`, four rung chips in the strip, `PR — Back Squat 235 lb × 3`, and a stats line that now **leads
   with `Push day`** before the minutes and the volume (whose spelling is `StatMath.compactNumber`'s, not
   this plan's). The second card: no lines 2–4 at all, and `posted 2 days after`.
6. `app-pump-composer-highlight` — the review state: the fixture photo, `COACH'S PICKS` with **two** rows
   (`Top set — Back Squat 315 lb × 5` and `PR — Bench Press 185 lb × 3`), the PR one ringed in accent, and
   `Post` still the only accent button on the card. No milestone row — that is the controller's ruling, visible
   in the frame.
7. `app-pump-feed` — the **live** account's feed, through the real `PumpFeedView`: the seeded post with its
   trajectory line, four rung chips, `PR — Back Squat 235 lb × 3` and `2 retakes`. An empty feed here is a
   defect in `feed()`, the RLS or the decode, and it is the one capture a fixture frame cannot stand in for.
8. `app-venue-hub` and `app-tab-home` — **unchanged**. S1.5 re-pointed two conditions at statics that return
   exactly what the conditions returned.
9. `app-pump-composer` — **unchanged**: it is the idle state, and S2.6a added a second init rather than
   replacing the one it uses.

Fix-forward any red; each fix is its own commit on the integration branch.

### I3 — one PR, with proof cards — **M**

`feat/social-cards` → `master`. The body carries:

1. **What shipped**, in the spec's own vocabulary: the card is a trajectory snapshot; the Crews card carries
   frequency honor; presence stays ungated.
2. **The two new catalog ids, the one new walk capture, and the FLOOR change** (111 → 114 — amended from
   107 → 110, see I1), as the table from this plan.
3. **The two migrations**, and how and when each was applied to `chjkkwqwdlmaxacwglzm`.
4. **The deliberate deviations**, each with its reason:
   - **a `trajectory jsonb` column the spec does not list.** Spec §6 names `goal_id` and `week_start` as "the
     trajectory and rung the card renders"; own-rows RLS on `block_goals` and `weekly_goals` means a friend
     can resolve neither, and owner decision 3 says the standing is visible to friends. The ids stay as
     provenance; the rendered facts are snapshotted. (S2.0.)
   - **a `SECURITY DEFINER` RPC for a spec section that says "no table".** It is not a table; it exists
     because `sessions` SELECT RLS would have made a client-side count answer a different question than the
     label claims. (S1.1.)
   - **`PostHighlight` carries `weightLbs` and `reps` beside spec §6's `{kind, text}`** — the Units doctrine:
     a frozen "235 lb" shows pounds to a friend in kilos. (S2.0, S2.5.)
   - **Coach proposes up to TWO highlights, not three** — spec §1 line 4's third proposal is the milestone
     total, and the one catalog for that is the You milestone-hero spec's `MilestoneCatalog` (thirty rungs,
     one currency). Shipping a private ladder of round numbers here would have been a second accounting of
     the same pounds. `PostHighlightKind.milestone` is already in the frozen interface AND in
     `workout_posts.highlight`'s CHECK, so the third proposal arrives as one new arm in
     `HighlightMath.propose` and no migration. (S2.1, S2.2, S2.5 — controller ruling.)
   - **the card's rung chips carry no `isNext` ring** — accent's three jobs (design rule 2) do not include a
     fact about someone else's finished week. (S2.0, S2.7.)
   - **the sound reaction's "Remove my sound" menu is gone and `unreact` is deleted** — owner decision 4's
     consequence, stated plainly: a sound attached by mistake is permanent.
   - **`PumpCheckContext` gained four fields rather than the composer gaining a fetch** — a catalog builder
     must never reach a repository (constraint 7), and the composer is one `#if DEBUG` seam away from being
     a catalog view.

   **AMENDED (integration, 2026-09-12) — nine more, from the two fix rounds and this integration.** Each is a
   deliberate departure from what this plan or the spec wrote down, and each belongs in the PR body beside
   the seven above:

   - **`standing` has no missed-rung branch** — the card agrees with the ladder page's coach line rather than
     printing a second verdict on the same block. (S2.4, fix round 1.)
   - **a `days` rung renders ONE `DAYS value/target` chip**, not `prefix(4)` of seven weekday states — four
     empty chips under a line claiming a rung. (S2.4, fix round 1.)
   - **`is_late` is derived by a server-side `BEFORE INSERT` trigger**, a THIRD migration
     (`20260912000002_workout_posts_is_late_trigger.sql`) the plan did not list — the client derived it from
     the device clock while the tag beside it is computed from the server's `created_at`. (S2.6, fix round 1.)
   - **the card's order is spec §1's, with the picture SIXTH** — the plan's S2.7 snippet left the photo
     between lines 3 and 4. (S2.7, fix round 1.)
   - **the crown decays** — the honor read assigns nil on a *successful empty* result, and the bar and honor
     reads share one task group per crew so the card paints once. (S1.4, fix round 1.)
   - **catalog captures launch with `-guidanceTipsEnabled NO`** — `captureCatalog()` passed no launch
     arguments, so a tour scrim photographed itself over `crews-tab`. (Global constraint 15, fix round 1.)
   - **the unit suffix is `lbs`, not `lb`** — `HighlightText` follows the app's shipped spelling rather than
     this plan's prose.
   - **`let`-optional memberwise-init repair** — a fixture could not be constructed as written.
   - **the live test asserts a controlled `postedAt`** rather than restating the seed's content — a live test
     that repeats the seed proves the seed, not the code.
   - **the milestone proposal is deferred**, so Coach proposes TWO — already listed above; repeated here
     because it is the one deviation the frame shows.
   - **the seed writes `created_at` explicitly** — a re-run kept the first run's value while `now()` moved on,
     and the live card read "posted 55 days after".
   - **`PostTrajectoryResolverTests` was added** — the resolver's injection seam had no test.
   - **the retake counter increments when the photo ARRIVES**, not when Retake is tapped — a cancelled
     retake counted itself.
   - **a unique-violation on react is treated as already committed**, not as a failure — a kudos the server
     already holds is a kudos.
5. **Proof cards**, each a CI run URL plus its specific evidence:
   - **Stage 1** — Backend green (`crew_consistency_honor_test.sql`, 8/8); `app-crews-tab` and
     `app-tab-social` both carrying the honor line; `PresenceIsUngatedTests` green and `app-venue-hub`
     unchanged.
   - **Stage 2, the write path** — Backend green (`workout_posts_test.sql`, 23/23);
     `WorkoutPostLiveRepositoryTests` green (the six columns round-trip against the live table); the seed
     step's `workout post …` log line.
   - **Stage 2, the read path** — `app-pump-feed-post` with every one of spec §1's seven lines in frame and
     the no-block card beside it, **and `app-pump-feed`**: the same lines rendered by the production feed
     against the seeded row, which is the half a fixture cannot prove.
   - **Stage 2, the new UI** — `app-pump-composer-highlight`: the picker, two proposals, one selected, one
     accent button.
   - **The refactor** — the three frozen Home frames byte-identical after S2.3, and `app-pump-composer`
     unchanged after S2.6a added a second init.
6. The trailer per constraint 2, plus `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## What this plan does not decide

Spec §9's four open items are carried, unchanged, plus four this plan opened.

1. **Whether a sound reaction stays one-tap-irreversible when the sound is purchased content** (spec §9.1).
   S2.8 makes every reaction commit, purchased sounds included, because owner decision 4 draws no line
   between them. If the shop's rack should behave differently, that is a product decision this plan is not
   entitled to make on the owner's behalf, and the change would be one branch in `commitReaction`.
2. **The honor's tie-break wording when two people share the count** (spec §9.2). S1.1 decides the ORDER (the
   earlier achiever) because a card that prints one name must have one; nothing on the card says a tie
   happened, and whether it should is open.
3. **Live encouragement** (spec §9.3) — the cheer's surface and its rate limit. Phase 2. S1.5 records the
   marker in code so it is found rather than remembered.
4. **Whether the feed should digest a friend's `behind` weeks when they have not posted** (spec §9.4).
   Deliberately out: the card is a snapshot the athlete takes, not surveillance.
5. **When the milestone highlight ships, and what it reads — RULED for this release, open for the next.**
   There is no second ladder: `HighlightMath.propose` offers `topSet` and `pr` only, and the milestone
   proposal waits for the You milestone-hero spec's `MilestoneCatalog` (thirty rungs, sources, one currency).
   What this plan has settled is that the wait costs nothing later: the kind is in the enum, the kind is in
   the column's CHECK (S2.2 asserts a `milestone` row inserts today), and `HighlightText.line` already
   renders one. What it has NOT settled is which rung a session "crosses" when the catalog's rungs are not
   all volume — that is the hero round's question, on the hero round's data.
6. **Whether the crew card's plate bar should become server-computed too.** The honor line is
   `SECURITY DEFINER` and therefore crew-wide; the bar beside it still counts what `sessions` RLS lets the
   *viewer* see (`SocialTabView.swift:541-558`), so two lines on one card answer subtly different questions
   — "sessions together that I was in" above "who showed up most, across the crew". Spec §5 does not list the
   bar as changing and this plan does not change it, but the divergence is real and is flagged here rather
   than discovered later.
7. **Whether the trajectory line should open the ladder page on your own post.** It is a line, not a door;
   spec §1 does not ask for one, and a door on a friend's card would lead somewhere RLS forbids. A door on
   *your own* card is plausible and undesigned.
8. **What the card shows for an athlete whose week has a rung but whose kind has no chip.**
   `PostTrajectoryMath.chips` returns `[]` and line 3 is absent (S2.4's
   `testAKindWithNoChipYieldsNoLineRatherThanAGuess`). Every shipped kind populates a chip today, so this is
   a defensive branch rather than a visible state — but if a future kind ships without one, the card quietly
   loses a line rather than failing.

---

## New catalog ids and the FLOOR

| id | frame | title | stage | proves |
|---|---|---|---|---|
| `crews-tab` | 101 | Crews tab — two crews, one with the honor line | 1 | spec §3: the honor line on one card, its absence on the other; the plate bar, the next lift and the three Outside the Box rows from values for the first time |
| `pump-composer-highlight` | 102 | Pump composer — Coach's picks | 2 | spec §1 line 4: the review state, two proposals, one selected, `Post` still the only accent |

Plus one capture that is **not** a catalog id: `app-pump-feed.png`, from `testPumpFeedLive()` (S2.10) — the
live account's feed through the production `PumpFeedView`. No `frame-map.json` entry, per the
`app-group-stats` precedent (a walk capture gets a frame only where a canvas frame exists for it).

**`FLOOR` 107 → 110**, in integration task **I1**, once: `app-crews-tab` + `app-pump-composer-highlight` +
`app-pump-feed`.

`pump-feed-post` (frame: none, as today) is **re-rendered**, not added — spec §7's own wording — so it moves
no count and claims no frame.

---

## Self-review (run by the planner, 2026-09-11)

**1. Spec coverage — every section maps to a task.**

| spec | requirement | task |
|---|---|---|
| §1 line 1 | who and when, with the honesty tag | S2.7 |
| §1 line 2 | the trajectory line, from `block_goals` + the rung's status via `BlockGoalRepository` | S2.0, S2.4, S2.6 |
| §1 line 3 | this week's rung, the strip's own chips, via `WeeklyGoalRepository.progress(for:)` | S2.3, S2.4, S2.6, S2.7 |
| §1 line 4 | one highlight, lifter picks one or none, no free text | S2.5, S2.6, S2.6a — **two proposals, not three**, see the deviation |
| §1 line 5 | the workout in plain terms, reworded | S2.0 (`routineName`), S2.6, S2.7 |
| §1 lines 6–7 | the picture, the reactions | unchanged (S2.7 keeps both blocks intact) |
| §1 | posted only after a workout is finished | unchanged — the composer has lived only in the recap since 2026-07 (`PumpCheckComposer.swift:8-10`), and this plan adds no other entry point |
| §1 | the standing, `behind` included, visible to friends with no per-post hide | S2.0 (no hide field exists to set), S2.2 (assertion 9g), S2.9 (the frame ships `behind`) |
| §1 | no active block → no lines 2 and 3 | S2.4 (`snapshot`), S2.6 (the resolver returns nil), S2.9 (the second card) |
| §2 | precise lateness from `posted_at − completed_at` | S2.0 (`PostLateness`), S2.1, S2.6, S2.7 |
| §2 | the retake count, shown above zero | S2.0, S2.6, S2.7 |
| §2 | a kudos is irreversible; counts stay | S2.8 |
| §2 | no post-to-view gate | **nothing to build** — none exists; `PumpFeedView.refresh()` is a bare page read and this plan adds no precondition. Recorded here so the absence is deliberate rather than forgotten. |
| §3 | the Crews card's frequency honor, 30 days, decaying, tie to the earlier achiever | S1.1, S1.2, S1.3, S1.4 |
| §3 | no volume leaderboard on the card | S1.3 — the honor carries `sessions` only; `group_member_stats` is untouched |
| §4 | presence never gated; live encouragement is phase 2 | S1.5 |
| §5 | what does not change | honoured: the camera flow, the reaction vocabulary, the context menu, the feed's ordering, the venue hub's sections and the Crews tab's three rows are all untouched |
| §6 | `completed_at`, `retake_count`, `highlight`, `goal_id`, `week_start`; `is_late` derived | S2.1, S2.6 |
| §6 | RLS unchanged | S2.1 adds no policy; S2.2 assertion 9g proves the existing friends-scope carries the new column |
| §7 | `pump-feed-post` re-rendered; `crews-tab` new; two ids → FLOOR +2 | S2.9, S1.6, S2.6a, S2.10, I1 — **with one correction, below** |
| §8 | the sequencing | Stage 1 / Stage 2 / integration |
| §9 | what the design does not decide | carried into "What this plan does not decide" 1–4 |

**One spec correction, made deliberately.** §7 says "Two ids → FLOOR +2 at integration". Neither half
survives contact with the tree: `pump-feed-post` already exists (`CatalogHostView.swift:63`,
`CatalogScreenTests`, and a `testCatalogPumpFeedPost` capture at `ScreenshotTests.swift:397`), so re-rendering
it adds no capture — while the controller's "real CI renders before any design change merges" adds two the
spec never counted: `pump-composer-highlight` (the picker, S2.6a) and `app-pump-feed` (the live walk, S2.10).
The arithmetic that matters is the artifact's, and it is **107 → 110**.

**Gaps I could not close, named rather than papered over:**

- **~~The highlight picker has no CI frame.~~ CLOSED by task S2.6a** (controller ruling). The draft left spec
  §1 line 4's UI to unit tests and an operator's device screenshot, on the grounds that `CameraPicker` cannot
  be driven headless. That is a reason to bypass the picker, not to skip the frame: `S2.6a` adds a
  `#if DEBUG` `catalogPhoto` init that drops the card into its review state with an image drawn in process,
  and `pump-composer-highlight` (frame 102) renders it every run.
- **~~The seeded feed post is proved by the backend, not by a picture.~~ CLOSED by task S2.10's second half**
  (controller ruling). `testPumpFeedLive()` walks Crews → Feed on the live account and attaches
  `app-pump-feed.png`, so the production read path — `feed()`'s decode, the RLS audience, the trajectory
  column's round trip — is looked at rather than assumed. This is the guard the goal-first final review
  argued for: three defects there survived because fixture frames looked right while the production path was
  broken.
- **`is_late` is derived in the client, not by the database.** Spec §6 says "derived"; a generated column
  would need the existing populated column dropped and re-added, which erases what every pre-2026-09 row says
  about itself. The derivation therefore lives in `PostLateness.isLate` and is enforced by `create` owning it
  (no caller can pass a lateness in) rather than by a constraint. A row written by anything other than this
  client could still disagree with its own timestamps.
  > **AMENDED (integration, 2026-09-12) — this is no longer true, and the last sentence is why it changed.**
  > Fix round 1 moved the derivation to a `BEFORE INSERT` trigger
  > (`20260912000002_workout_posts_is_late_trigger.sql`) so the boolean is measured on the same clock that
  > stamps `created_at`. Still not a generated column, for exactly the reason given above. See the amendment
  > under S2.6.

**2. Placeholder scan.** Grepped the finished document for `TBD`, `TODO`, `FIXME`, `XXX`, `add validation`,
`similar to`, `same as above`, `<fill`, `and so on`, `…etc`: **zero hits**. Every task names its files, its
interfaces, its commit message and its proof. The three "phase 2" markers (live encouragement, the purchased-
sound question, the costed remedies above) are scope statements the spec itself makes, each listed in "What
this plan does not decide" or in the gaps.

**Four things this review changed, rather than noted:**

1. **The first draft had the card reading `BlockGoalRepository` at render time**, straight from spec §1's
   "Source" column. Checked against `20260907000001_block_goals.sql:49-51` and `20260906000001_weekly_goals
   .sql:54-56`: own-rows RLS, both. The card would have shown the trajectory to its author and a blank to
   every friend — which is the exact opposite of owner decision 3, and would have looked *fine* in every
   catalog frame, because a catalog frame has no RLS. The `trajectory jsonb` column and S2.0's whole doc
   comment come from that check.
2. **The first draft reused `WeeklyGoalProgress.Chip` verbatim for line 3.** Read
   `WeeklyGoalProgressMath.swift:502-511`: for `lift`, `bodyWeight` and `benchmark` the chip's `done`/`target`
   are *span-above-a-floor* geometry (5 / 20), not the numbers the strip prints (210 / 225). Rendering them
   through the chip view would have printed "BENCH PRESS 5/20". `PostTrajectory.Chip.fill` and
   `PostTrajectoryMath.chips`' two families exist because of that read.
3. **The first draft computed the Crews honor client-side from `SessionRepository.groupSessions`**, as spec
   §3 describes ("the same read the plate bar already makes, widened to 30 days"). `sessions` SELECT RLS is
   organizer-or-participant, so the count would have been the viewer's own attendance wearing a crew-wide
   label. S1.1's RPC, and the "why an RPC at all" paragraph, come from that.
4. **The first draft's `app-tab-social` proof did not exist.** The seed creates the `[QA]` crew's completed
   session with no `session_participants` row (`seed_qa_fixtures.js:305-315`), and the honor credits
   attendance — so the live crew would have had no honor line and the by-eye check would have passed on an
   empty string. S1.4 adds the participant row, in the task whose proof needs it.

**3. Type consistency across tasks.** Every cross-task symbol was grepped across the finished document for a
single spelling. The near-miss spellings a second author would plausibly reach for —
`PostTrajectorySnapshot`, `CrewHonour`, `GSGoalChipView`, `highlightFor`, `resolveTrajectory` — appear
nowhere in this document except in this sentence.

- `PostTrajectory` — declared S2.0 (5 stored properties + `line`); built by `PostTrajectoryMath.snapshot`
  (S2.4); carried by `PumpCheckContext` and `WorkoutPostRepository.create` (S2.6); rendered by
  `PumpPostCard.trajectoryBlock` (S2.7); fixtured in S2.9 and S2.10. One spelling, one field order.
- `PostTrajectory.Chip` — four fields (`name`, `done`, `target`, `fill`) at every site: S2.0's declaration,
  S2.4's two construction paths, S2.7's `GSGoalChip` call, S2.9's fixture, S2.10's JSON. `isNext` appears on
  it nowhere.
- `PostHighlight` — four fields (`kind`, `text`, `weightLbs`, `reps`); produced by `HighlightMath.propose`
  (S2.5), selected in the composer (S2.6), rendered by `HighlightText.line(_:unit:)` (S2.5) at both call
  sites (the picker and the card).
- `PostLateness` — five members (`windowSeconds`, `elapsed`, `isLate`, `tag`, `retakeTag`); `isLate` is
  called only by `WorkoutPostRepository.create`, `tag`/`retakeTag` only by `PumpPostCard.authorRow`.
- `GSGoalChip` — five parameters (`name`, `done`, `target`, `isNext` defaulted, `fill` defaulted) and one
  public computed `fraction`; called by `HomeWeeklyGoalStrip.chipRow` (four args) and
  `PumpPostCard.trajectoryBlock` (four args, `fill:` instead of `isNext:`). The test addresses `fraction`,
  never the body.
- `CrewHonor` / `CrewHonorRow` / `CrewHonorMath` — `crown(_:)` and `line(_:)` are the only two functions;
  called in S1.4 (the view) and S1.6 (the fixture) with the same labels; `CrewHonorRow`'s four keys match the
  RPC's four output columns (`user_id`, `username`, `sessions`, `reached_at`) exactly.
- `PostTrajectoryResolver.resolve(now:calendar:blockGoals:weeklyGoals:)` — one signature, two call sites
  (`WorkoutSessionView`'s `.task`, `GroupSessionLiveView.buildPumpCheckContext`), returning the same
  three-label tuple both times.
- `WorkoutPostRepository.create` — thirteen labels after S2.6, in the order S2.6 writes them; called from
  `PumpCheckComposerCard.post(_:)` and from `WorkoutPostLiveRepositoryTests`, with the same labels in the
  same order.
- `PumpCheckContext` — ten stored properties after S2.6; constructed at three sites
  (`WorkoutSessionView:4281`, `GroupSessionLiveView:6087`, `CatalogHostView:1261`), and **all three are named
  in S2.6's Files** so none is left compiling against the old memberwise initializer.
- `WeeklyGoalKind` — nine cases; `PostTrajectoryMath.chips` lists all nine across its two arms with no
  `default:`, and S2.4 updates the doc comment's count to match.
