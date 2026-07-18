# Phase L — Discover + Public Workout Leaderboards — Design

**Status:** approved scope (roadmap Phase L) — the largest missing product pillar. Product law: master spec §Public Workout Repository (schema ~404-432), Flow 4 (~790-797), the duration-edit leaderboard rule (Flow 6 ~831-836), Library tab structure (~690), leaderboard channel (~969), pushes (`leaderboard_passed`, reserved in 3d).

## Components

### 1. Attempts + leaderboards backend
- Tables per master spec verbatim: `workout_attempts` (routine must be public; is_opt_in_leaderboard default false) + `leaderboard_entries` (denormalized routine_id; time_seconds/total_volume/top_sets jsonb; is_complete; is_edited — time stays ORIGINAL when a session's duration is edited, with the "✏️ edited" indicator rule).
- `routines` public-workout fields already exist in schema (visibility/is_featured/default_sort/scoring_metrics/scoring_top_set_exercise_id — verify which shipped in the original migration vs need adding; fix-forward as needed).
- Recompute: on attempt completion (trigger on the attempt/session completion path — the spec's `leaderboard-recompute` job; a trigger or DEFINER function per the repo's established patterns, NOT a new Edge Function unless triggers can't express it). Volume/top-set update on set_log edits per spec; time locked at completion.
- RLS per spec: attempts + entries readable by anyone WHEN `is_opt_in_leaderboard=true`, else owner-only.

### 2. Attempt flow
- Flow 4: public workout detail → **Attempt Solo** (Flow 3 with the routine pre-selected) and **Attempt with Friends** (Flow 2 schedule sheet pre-loaded); per-attempt "Show me on leaderboard" opt-in toggle at attempt start; on completion → attempt row + entries computed; system message to the user's group chat ("attempted The Murph — 42:13, #187") — the spec's `system_leaderboard` chat kind (added in 3d's kinds? verify — extend the CHECK if needed, NOT VALID+VALIDATE doctrine for chat_messages now).
- `leaderboard_passed` push: the reserved 3d payload case — enqueue when a new entry displaces a ranked opt-in user (recompute-time detection; keep the fan-out bounded — notify only the directly-passed user per spec).

### 3. Discover UI
- Library gains the **Discover** sub-tab (master spec's four-sub-tab structure; Campaigns stays Phase C): featured/public workout grid → workout detail (description, scoring metrics, sortable leaderboard — Time / Total Volume / Top Set / Recent per `default_sort`/`scoring_metrics`, "✏️ edited" indicator, opt-in rows only) → the two Attempt CTAs.
- **Top Lifters** global leaderboard (lifetime_volume_lifted, all opted-in users — needs a global opt-in surface? The spec puts cumulative volume on public leaderboards as a 4th metric + a separate Top Lifters board; v1 honest read: Top Lifters ranks profiles by lifetime volume — public data per profiles RLS (anyone reads public fields) — no extra opt-in needed; cite + record).
- Publishing: RoutineBuilder's publish path (curator-gated per curation phase) gains the public-workout fields (default_sort, scoring metrics, top-set exercise).
- The M-phase routine-detail block/report surface becomes REACHABLE via Discover detail (close that dead surface).

### 4. Content
- Seed featured workouts ("The Murph" + 2-3 strength/hypertrophy templates) via the existing pack/seed idioms (curator account) — content task folded in.

## Acceptance
- pgTAP: attempts/entries RLS (opt-in vs owner-only both directions), recompute correctness (time/volume/top_sets from a fixture session), duration-edit lock (time unchanged, is_edited flips), leaderboard_passed enqueue on displacement.
- Parity: Discover grid + workout detail captures vs any authoritative frames (check the canvas — Discover may be undesigned → system-designed + deviations; the Library frame's sub-tab row will shift → deviation note).
- Live: an attempt by the CI account produces an entry (seed extension).

## Non-goals
Campaigns sub-tab (Phase C); user sound/routine community publishing beyond the curator model; global search; pagination beyond a sane LIMIT.
