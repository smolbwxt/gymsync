# Field report docket — 2026-09-03 (owner device pass, iPhone 15)

Owner's list, verbatim intent, triaged by the controller. Order of attack is at the bottom.
Screenshot context: Home tab, light palette + coral accent, streak tile reads "1 · 2/4 DAYS THIS WEEK".

| # | Report | Type | Severity | Triage notes |
|---|---|---|---|---|
| 6 | Group workouts crash on launch | crash | **P0** | Reproduce from Sentry first (org `mattaniah`, project `gymsync`; resolve the release to its date before blaming a recent change — testers run stale builds). Suspects: the 2026-08-28 `Profile` change (`onboardedAt` — third memberwise-init trap already bit the catalog fixture, fb2875b) hitting a group-member decode; `ProgramToday.resolveRoutine` attach-on-load in LobbyView (F10, untested by CI). |
| 8 | Streak reset although 2 exercises were completed that week | logic | P1 | Tile shows "2/4 days this week" beside streak 1 — the streak is week-goal based; owner expects activity to preserve it. Read `StreakMath` + the home tile derivation; decide the rule (consecutive weeks hitting the goal vs. any-activity weeks) — owner decision, then fix + tests. |
| 7 | Don't set a PR on the first attempt of a workout; PR fires only after all sets of an exercise are complete | logic | P1 | Two rules: (a) first-ever log of an exercise is a baseline, not a PR celebration; (b) PR evaluation moves from per-set to exercise-complete. Touches `PRService`/celebration trigger + bodyweight rep-PR path (build 518). Needs tests for both rules. |
| 5 | Set logger truncates text beyond 9 reps on iPhone 15 | layout | P1 | Two-digit reps overflow a fixed-width field or a `minimumScaleFactor` is missing. Reproduce via the catalog (`plate-math` / log-set states) at iPhone 15 width; fix the frame, not the font. |
| 1 | After-action report is not obvious; copy should be "Talk to Coach about today's lift" | UX copy | P2 | The AAR door reads as a single-lift thread. Rename the entry point and make it a first-class row on the recap + Home "today" block. |
| 4 | Swap-exercise "same movement" list is truncated and incomplete; open the exercise editor instead | UX | P2 | Replace the truncated substitution list with the full exercise picker/editor sheet (the substitution graph can pre-sort it). |
| 2 | Define what weights mean: dumbbell per hand vs total, barbell total, plate-loaded and isometrics per side? | product definition | P2 | Owner decision needed. Proposed convention (matches Hevy/Strong): dumbbell + kettlebell = **per hand**; barbell = **total incl. bar**; plate-loaded machine = **total plates added**; per-side isometric holds / unilateral = **per side**. Then: a one-line hint under the weight field per equipment class, a glossary row in Settings, and the volume math must agree (dumbbell volume ×2 hands). |
| 9 | Not every stretch has an exercise page | catalog gap | P2 | Audit stretches in the 891-exercise catalog for missing detail pages / demo videos; backfill or hide the door where nothing exists. |
| 3 | Self-reported energy level pre and post workout | new feature | P3 | Design first: a 1–5 dial at session start and on the recap; store on the session; Coach's diagnostic layer and the rest-recovery proxy can read it. Owner decision on scale and wording. |

## Sentry leads for #6 (pulled 2026-09-03)
- **GYMSYNC-D9** (build 187, iPhone16,1, iOS 26.4.2; 6 events / 2 users, 2026-08-30 23:59Z to 08-31 00:07Z) and
  **GYMSYNC-DA** (build 189, iPhone18,3, iOS 26.5.1; 1 event, 2026-08-31 00:00Z): both
  `EXC_BAD_ACCESS ... Stack overflow` with the crashed thread deep in
  `swift_getTypeByMangledName -> TypeDecoder::decodeMangledType/decodeGenericArgs` (hundreds of frames),
  entered from `ZStack.init -> ViewBodyAccessor.updateBody -> DynamicBody.updateValue`. That is the runtime
  instantiating metadata for an enormously nested generic SwiftUI view type - the same family as the
  Release type-check timeouts that forced the LobbyView / GroupSessionLiveView body splits. Tags:
  `screen: home`, `session_active: false` (the screen tag may lag the navigation). Both issues are marked
  resolved in Sentry (auto-resolve or manual) - re-open on reproduction.
- **No events in the last 36 h**: the owner's device crash did not reach Sentry. Either the crash happens
  before the SDK flushes (launch-time), the build predates the DSN, or the offline envelope has not sent yet.
- Ask the owner: TestFlight build number on the device, and the exact tap that crashes (a crew session row
  on Home, the lobby's Start, or the live view appearing).
- First code suspects: `LobbyView` / `GroupSessionLiveView` view-type depth (any new nesting since the last
  layering fix), `ProgramToday.resolveRoutine` attach-on-load added in F10 (832b6d7) on the lobby path.

## Order of attack (proposed)
1. **#6 crash** — Sentry pull now; fix as soon as the current P2 restyle branches land (its own `fix/` branch, TestFlight immediately).
2. **#8 streak, #7 PR rules, #5 set-logger truncation** — one `fix/field-2026-09-03` branch, tests for #8 and #7.
3. **#1, #4, #9** — one UX branch.
4. **#2 weight semantics** — owner confirms the convention above, then implement hint + glossary + volume math.
5. **#3 energy level** — brainstorm + spec.

## Owner decisions needed before build
- #2: confirm or amend the weight convention table.
- #8: what should a streak count — consecutive weeks that hit the weekly goal, or consecutive weeks with any logged training?
- #3: scale (1–5? 1–10? words?) and whether it is optional.
