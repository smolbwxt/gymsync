# Pump Check — post-workout photo moment + friends feed (design)

**Date:** 2026-07-27 · **Status:** approved direction (4 user decisions locked)
**Working name:** "Pump Check" — placeholder, rename freely.

## What it is

A BeReal-style moment at the end of every workout: the recap offers a
**1-minute window** to snap a photo of yourself. The photo + an
auto-generated **workout summary card** post to a **friends-only feed** in
the Social tab. The summary is the receipts: each exercise with its sets
underneath (weight × reps), average heart rate (opt-in), and the app's
signature drawn loaded-bar for barbell lifts. Nobody else's feed can render
what was physically on your bar — that's the differentiator over a generic
photo feed.

## Locked decisions (user, 2026-07-27)

1. **Late policy:** BeReal-style. Capture after the 1:00 window gets a
   visible "late" badge. No hard cutoff; summary-only posts (no photo)
   allowed.
2. **Heart rate:** per-post "include heart rate" toggle in the composer,
   **defaulting to the user's existing `share_heart_rate` setting**. HR
   never leaves the device without the toggle on.
3. **Reactions:** emoji tap-reactions in V1, reusing the session-kudos
   emoji set (💪 🔥 👏 🏆 ⚡) and backend pattern. **No comments** in V1
   (comment moderation is its own project).
4. **Bar figures:** one `GSBarLoaderMini` per **barbell exercise**, showing
   its **top set**; all sets still listed as text rows underneath.

## The moment (flow)

- Recap renders (solo `SoloRecapView` or group `GroupRecapView`) → a
  **composer card** mounts at the top with a live 1:00 countdown
  ("Pump check — 0:47").
- Tap → camera capture (front camera default, flip allowed; retakes allowed
  within the recap). Photo review → optional HR toggle → **Post**.
- Capture that starts after the window: post proceeds, `is_late = true`,
  feed shows a "late" chip. The countdown is urgency, not a wall.
- The composer lives **only in the recap**. Dismiss the recap without
  posting and the moment is gone — no posting from history. (Keeps the
  "moment" honest and the scope tight.)
- Skip is always one tap; nothing nags.

## Data model

New table `workout_posts`:

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| author_id | uuid → profiles | |
| session_id | uuid → sessions | provenance only; feed never queries sets |
| photo_path | text nullable | storage object path; null = summary-only post |
| summary | jsonb | **snapshot at post time** (below) |
| includes_hr | bool | |
| avg_bpm / max_bpm | int nullable | only written when includes_hr |
| is_late | bool | computed client-side (capture ts vs recap-appear ts) |
| created_at | timestamptz | |

**Snapshot doctrine:** `summary` is denormalized JSON — duration seconds,
total volume (canonical lbs), and per-exercise entries:
`{ name, equipment, sets: [{ weight_lbs, reps, is_pr, is_failed }] }`.
A post is a moment in time: later set edits/deletes don't rewrite it, RLS
stays a single-table check, and the feed renders with zero joins into
`set_logs`. Weights stored canonical lbs; **rendered in the VIEWER'S unit**
via the units pipeline (the author lifts in kg, a lbs friend sees lbs).

New table `post_reactions`: `(post_id, user_id, emoji)` with emoji CHECK in
the kudos set, PK `(post_id, user_id, emoji)`, toggle = insert/delete own
row.

**Storage:** bucket `workout-photos`, path `{post_id}.jpg`. Client
downscales + re-encodes via the existing `ImageProcessor.jpegForUpload`
idiom (maxDimension ~1600) — re-encoding also strips EXIF/GPS.

## RLS (pgTAP-proven, same posture as show_solo_workouts)

- `workout_posts` SELECT: author, or an **accepted friend** of the author
  (same friendship predicate the solo-workout-privacy policy uses), and the
  viewer has not blocked / been blocked by the author (existing block
  semantics).
- INSERT: author only (`auth.uid() = author_id`). DELETE: author only
  (cascades reactions; storage object removed best-effort client-side).
  No UPDATE — posts are immutable snapshots.
- `post_reactions`: INSERT/DELETE own rows, only on posts the user can
  SELECT. SELECT follows the post's visibility.
- Storage RLS mirrors the post table: author writes, friends-of-author read.

## Feed (Social tab)

- Social tab gains a **Feed** section above crews (or a sub-tab if the
  layout fights it): reverse-chronological friend posts + your own,
  paginated (20/page, keyset on created_at).
- Post card: photo (if any), author row (avatar, name, relative time,
  "late" chip), summary card — exercise rows with `GSBarLoaderMini` for
  barbell top sets, set lines "225 × 5 · PR" in the viewer's unit, avg HR
  line when shared, duration + total volume footer.
- Reactions row: kudos emoji with counts; tap toggles yours.
- Context menu: author → Delete; others → Report (existing `ReportSheet`,
  new target type `post`).
- Empty state: invite to add friends / finish a workout ("Your first pump
  check lands here").

## Safety & compliance

- Photos are UGC → App Store 1.2: report (per-post), block (hides all of an
  author's posts — existing semantics), delete-own. Friends-only visibility
  is the primary risk reducer; there is **no public surface**.
- EXIF/GPS stripped by re-encode. HR is opt-in per post. 
- **Privacy policy addition required** (docs/legal/PRIVACY-POLICY.md):
  workout photos + summary shared to accepted friends; deletable by author.

## Phases (merge per green, standing mode)

- **P1 — backend:** migration (`workout_posts`, `post_reactions`, storage
  bucket + policies) + pgTAP (visibility matrix: friend / non-friend /
  blocked / self; reaction constraints; no-UPDATE; self-insert only).
- **P2 — capture + composer:** recap composer card (countdown, camera,
  review, HR toggle, post/skip), snapshot builder from recap state, upload
  path. Solo recap first.
- **P3 — feed:** Social tab feed UI, post card (mini bars, viewer-unit
  rendering), reactions, delete/report wiring, pagination, empty state.
- **P4 — group recap hook + polish:** composer in GroupRecapView, catalog
  cases (`post-composer`, `feed`, `feed-post`) + screenshot captures,
  discovery tip for the feed, privacy-policy edit.

## Non-goals (V1)

Comments; dual front+back capture; public/non-friend visibility; push
notifications for friends' posts; posting from history; streaks or rewards
for posting; server-side image moderation (revisit if visibility ever
widens beyond friends).
