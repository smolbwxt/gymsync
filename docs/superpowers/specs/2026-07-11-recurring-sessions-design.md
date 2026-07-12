# Gym Sync — Recurring Sessions Design

**Date:** 2026-07-11 · **Status:** Approved (Approach A) · **Depends on:** Phase 3a (shipped)

## Problem

Scheduling one session at a time doesn't match how gym crews operate: they train on a weekly cadence (Push Mon / Pull Wed / Legs Fri) for a program block. Users need Teams-style recurring scheduling: configure a weekly rule once, get every session on the calendar, and edit/cancel either a single occurrence or the whole series.

## Decisions (user-confirmed)

1. **Shape:** weekly pattern with per-day routine — pick weekdays, each selected day carries a local time and an optional routine.
2. **End:** until-date only (no "forever"). Hard cap: 26 weeks from creation. Bounded series → all occurrences materialize upfront; no cron dependency.
3. **Edit semantics:** full Teams parity — Edit/Cancel × This-occurrence/Whole-series toggles.
4. **Late joiners:** new group members are auto-invited to all FUTURE scheduled sessions of that group (trigger).
5. **Scope v1:** series require a group. Ad-hoc friend-set series deferred. One time slot per weekday per series (two-a-days = create a second series).

## Architecture (Approach A: series entity + upfront materialization)

Every occurrence is a REAL `sessions` row created at series creation. All existing machinery (lobby, check-in, penalties, announcements, upcoming lists, future streaks) works untouched. The series entity exists to anchor the rule, Teams-style series operations, and the summary announcement.

### Schema

```sql
session_series (
  id            uuid PK,
  group_id      uuid NOT NULL REFERENCES groups ON DELETE CASCADE,
  organizer_id  uuid NOT NULL REFERENCES profiles,
  timezone      text NOT NULL,              -- IANA, organizer's tz at creation
  until_date    date NOT NULL,              -- inclusive; CHECK <= created + 26 weeks
  late_penalty  jsonb NOT NULL DEFAULT '{"exercise":"burpee","per_minute":5}',
  ended_at      timestamptz,                -- series cancelled early (history kept)
  created_at    timestamptz DEFAULT now()
)

session_series_days (
  series_id   uuid REFERENCES session_series ON DELETE CASCADE,
  weekday     int CHECK (weekday BETWEEN 1 AND 7),   -- 1=Sunday (Swift Calendar convention)
  time_local  time NOT NULL,
  routine_id  uuid REFERENCES routines ON DELETE SET NULL,
  PRIMARY KEY (series_id, weekday)
)

ALTER TABLE sessions ADD COLUMN series_id uuid REFERENCES session_series ON DELETE SET NULL;
```

RLS: both tables readable by members of the series' group (`is_group_member`); INSERT/UPDATE/DELETE organizer-only (`organizer_id = auth.uid()`, and organizer must be a group member on INSERT). Days inherit via a `series_organizer`/`series_group` SECURITY DEFINER helper.

**New sessions DELETE policy** (none exists today): organizer may DELETE own sessions WHERE `state = 'scheduled'` — powers occurrence-cancel and series-regenerate. Started/completed sessions remain undeletable.

### Materialization (client-side, at creation)

`SeriesRepository.create(...)`:
1. Insert `session_series` + `session_series_days`.
2. Generate occurrence dates from tomorrow(*) through `until_date` in the series timezone using Swift `Calendar` (DST-correct by construction). (*) first occurrence = next matching weekday/time strictly in the future.
3. Bulk-insert `sessions` rows (`state='scheduled'`, `series_id`, per-day `routine_id`, series `late_penalty`) and `session_participants` (organizer `online`, all other group members `invited`).
4. Call `finalize_series(series_id)` RPC (below).

### Announcement suppression

The Phase 3a lifecycle trigger would post 📅 once per materialized session (~78 spam messages). Change: `announce_session_lifecycle` skips INSERT announcements when `NEW.series_id IS NOT NULL` (start/complete/abandon announcements still fire per occurrence). New SECURITY DEFINER RPC `finalize_series(p_series_id)` — validates caller is the series organizer, composes ONE summary from the rule ("🔁 Sessions scheduled Mon/Wed/Fri until Sep 1"), inserts a single `system_session` chat message with payload `{series_id, until_date, weekdays}`.

### Teams operations

| Operation | Mechanism |
|---|---|
| Edit occurrence | UPDATE that sessions row (scheduled_for / routine_id) — existing participant UPDATE policy covers organizer |
| Cancel occurrence | DELETE that sessions row (new scheduled-only organizer DELETE policy) |
| Edit series forward | UPDATE series + days → DELETE future rows (`series_id=X AND state='scheduled' AND scheduled_for > now()`) → re-materialize from rule → `finalize_series` posts an updated summary |
| Cancel series | UPDATE `ended_at=now()` → DELETE future scheduled rows. Past/started occurrences keep `series_id` for history |

Series ops are client-orchestrated (no server transaction): a mid-operation failure leaves fewer future sessions than intended, recoverable by re-running the edit. Acceptable at v1 scale; noted as a known limitation.

### Late-joiner trigger

```sql
AFTER INSERT ON group_members:
  INSERT INTO session_participants (session_id, user_id, check_in_state)
  SELECT s.id, NEW.user_id, 'invited'
  FROM sessions s
  WHERE s.group_id = NEW.group_id AND s.state = 'scheduled' AND s.scheduled_for > now()
  ON CONFLICT DO NOTHING;
```

Applies to ALL group sessions (series or single) — deliberate: the invite follows the group, matching Teams channel-meeting behavior. SECURITY DEFINER.

### UI

- **ScheduleSessionView**: "Repeats" toggle (Group path only). On: weekday chips; each selected day expands to time picker + optional routine picker; until-date picker (default +8 weeks, max +26). Schedule button becomes "Schedule Series" and shows the occurrence count ("24 sessions").
- **Home/Group lists**: series occurrences show a 🔁 badge.
- **LobbyView toolbar** (organizer, when session has `series_id` or is scheduled): Edit menu → "This session" (time/routine sheet) / "The series" (rule editor sheet); Cancel menu → "This session" / "Rest of series" — each with confirmation dialogs. Non-series scheduled sessions get the occurrence-level items only.

### Realtime

`session_series`/`session_series_days` are NOT added to the realtime publication — series metadata changes always manifest as sessions-table changes (already published). **Rule (from 3a lesson): any future postgres_changes subscription ships its publication migration in the same task.**

### Testing

- pgTAP: RLS positive/negative for both tables + sessions DELETE policy (organizer deletes scheduled ✓, participant ✗, started ✗); announcement suppression (bulk insert with series_id → 0 messages; finalize_series → exactly 1); late-joiner trigger (new member gains invites to future, not past/started); finalize_series organizer guard.
- XCTest (live DB): create 2-week Mon/Wed series → correct occurrence count/dates/routines/participants; cancel-rest deletes future only; edit-forward regenerates; occurrence cancel deletes one.
- Device QA: schedule series → single 🔁 chat summary; Teams menus; late-joiner (ci_test_user_2 removed/re-added to group gains future invites).

## Known limitations (v1)

- Series ops not transactional (client-orchestrated; re-run to heal).
- No per-occurrence "detached" marker: an edited occurrence still belongs to the series, so a later "edit series forward" regenerates over it (Teams preserves exceptions; we document that series-edit wins). 
- One slot per weekday; no monthly patterns; no forever (bounded ≤ 26 weeks).
- Timezone fixed at creation (organizer moving timezones doesn't shift the series).
