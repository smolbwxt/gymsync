# Phase P — PR Celebration Takeover — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** one shared full-screen PR celebration (canvas frame 29) used by group sessions (existing), solo sessions (new), and the debug catalog (replacing a drift-prone reproduction) — proven by the parity score dropping from 64% into the noise band.

**Architecture:** pure-Swift refactor + reuse. Extract `GroupSessionLiveView`'s existing p29 overlay into `PRCelebrationOverlay`; adopt in `WorkoutSessionView`'s live path at PR-detection time; re-point `CatalogHostView`. No backend changes, no new detection logic.

**Tech Stack:** SwiftUI; CI-only compilation (`build-test`), harness parity for acceptance.

## Global Constraints

- **Behavior-preserving refactor for group sessions:** the extraction must not change `GroupSessionLiveView`'s trigger conditions, dismiss semantics (user-dismissed, NO auto-timeout), or visual output. Read the existing overlay code fully before lifting it; parameterize only what varies.
- **Solo trigger = the existing PR-detection path** at set-log time in `WorkoutSessionView` (the shared detect/record helper already writes `personal_records`) — present the overlay from its success path; do NOT add new detection.
- The recap's `prCelebrationCard` (heaviest-PR summary) is a DIFFERENT element — leave it.
- Swift compiles only in CI. Implementers commit, never push; the controller pushes + watches. Cite real declarations (file:line) for every call you write.
- Watch the memberwise-init trap: no new plain `private` stored properties on View structs used cross-file.
- Never `git add -A`.

## File Structure

- Create: `GymSyncApp/GymSync/Features/Sessions/PRCelebrationOverlay.swift` (sessions-domain shared view — both consumers live under Features/).
- Modify: `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift` (adopt; delete the now-lifted private overlay body).
- Modify: `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift` (solo adoption at detect-time).
- Modify: `GymSyncApp/GymSync/App/CatalogHostView.swift` (re-point `content_prCelebration`, delete the reproduction + its copied `catalogDecimalString` if now unused).

---

## Task 1: Extract `PRCelebrationOverlay` + group adoption (behavior-preserving)

- [ ] Read `GroupSessionLiveView.swift`'s PR overlay in full: the `isPROverlay`/`prOverlayExerciseName` state (~lines 116-118), the overlay view body, its presentation site (ZStack layer / fullScreenCover?), trigger call sites, and dismiss action.
- [ ] Create `PRCelebrationOverlay.swift`: the lifted view, `init` taking exactly the data the current body consumes (exercise name + whatever else it renders) + `onDismiss: () -> Void`. Keep every color/font/layout token identical. `@Environment(\.gsTheme)` as in the original.
- [ ] Adopt in `GroupSessionLiveView`: same state, same presentation layer, body replaced by `PRCelebrationOverlay(...)`. The diff for this file should be near-pure deletion + one call.
- [ ] Commit: `refactor(pr): extract PRCelebrationOverlay from GroupSessionLiveView (behavior-preserving)`.

## Task 2: Solo adoption

- [ ] Read `WorkoutSessionView.swift`: find the set-log path and the shared PR detect/record helper's success return (the code that creates a `PersonalRecord` mid-session). Cite file:line.
- [ ] Add `@State private var soloPROverlay: PersonalRecord?` (or name/weight fields matching Task 1's init) + present `PRCelebrationOverlay` on the same layer idiom Task 1 preserved, triggered from the detect success path. Dismiss returns to the session.
- [ ] Ensure the recap `prCelebrationCard` path is untouched.
- [ ] Commit: `feat(pr): solo sessions present the full-screen PR celebration (frame 29)`.

## Task 3: Catalog re-point + parity acceptance

- [ ] `CatalogHostView.content_prCelebration` → render `PRCelebrationOverlay` with fixture data (name e.g. "Bench Press", plausible weight/reps per its init), `onDismiss: {}`. Delete the reproduction body and `catalogDecimalString` if unused elsewhere in the file.
- [ ] Commit: `fix(parity): catalog pr-celebration renders the real overlay`.
- [ ] Controller: push, watch CI (build-test → screenshots → parity), download the parity report, confirm `pr-celebration` ≤ ~25% and no other row regressed. Whole-branch review (small branch) → merge.

## Self-Review
Spec §1→Task 1, §2→Task 2, §3→Task 3, acceptance→Task 3 controller step. No placeholders: tasks are read-first refactor steps with exact state names cited from ground-truth grep (isPROverlay/prOverlayExerciseName @ GroupSessionLiveView:116-118, prCelebrationCard @ WorkoutSessionView:449). Types: overlay init defined in Task 1 is the single contract Tasks 2/3 consume.
