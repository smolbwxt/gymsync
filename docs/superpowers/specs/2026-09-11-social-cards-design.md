# Social cards — the trajectory snapshot — design

**Status:** approved in conversation 2026-09-11 (owner: "go with your suggestions", on the four-part proposal of
2026-09-07); this document is the written form. **Gate documents:** the goal-first programming spec
(`docs/superpowers/specs/2026-09-07-goal-first-programming-design.md`) — the card reads the goal and ladder objects
it defines; the design language (`docs/superpowers/specs/2026-09-05-design-language.md`). Round artefacts:
`.superpowers/sdd/2026-09-07-social-cards-round/` (context map of the three card families, the cited reference
scan of Strava / Hevy / BeReal / Locket / GymRats / Ladder / Peloton / WHOOP / Nike Run Club, and the decisions).

## Why

The owner, on the B1 proof cards: *"a very focused round for the social cards"*, then: *"not what just happened
that worked out, but a sense of where they are in their current goals for the week, where they're on their
programming, anything they want to highlight about their lift … a snapshot of where people are in their fitness
trajectory"* — *"a blend of accomplishment-first and BeReal: serendipity that offers accountability, not a moment
of curated perfect perfection"* — and: *"it's only after you finish a workout."*

What exists today (context map): the pump-check post card (author row with a `late` tag, full-bleed photo,
exercise and set lines with PR tags, a stats line, emoji and owned-sound reaction chips), the Crews tab card
(identity-coloured avatar, name, unread dot, a hand-drawn plate bar of sessions this week, a caps meta line),
and the venue hub rows. The reference scan found the pump check already carries more of BeReal's DNA (late tag,
retakes, uncounted reactions) than anything surveyed; what it lacks is the trajectory, and what the Crews card
lacks is any honor that is not performance.

## 1. The pump-check card is a trajectory snapshot

Posted **only after a workout is finished**: the post window opens on completion; a post that comes later wears
the honesty tag (§2). No random prompt.

Anatomy, top to bottom — every line reads from an object that already exists:

| # | Line | Source |
|---|---|---|
| 1 | **Who and when** — avatar, name, relative time, the honesty tag | `workout_posts`, `profiles`, §2 |
| 2 | **The trajectory line** — goal · place in the block · standing: `Bench 225 by Oct 18 · week 3 of 8 · on track` (or `behind`, `met`) | `block_goals` (+ the ladder's current rung status) via `BlockGoalRepository` |
| 3 | **This week's rung** — the same chips the Home strip renders for that athlete's current week | `weekly_goals` row for the post's week via `WeeklyGoalRepository.progress(for:)` |
| 4 | **One highlight** — a top set, a PR, a milestone plate total; one line, chosen by the lifter from Coach's suggestions at post time | `set_logs` of the session (PR detection already exists); the milestone catalog for plate totals |
| 5 | **The workout in plain terms** — `Push day · 42 min · 7,240 lb` | the session and its set logs (today's stats line, reworded) |
| 6 | **The picture** | the post's photo, as today |
| 7 | **Reactions** — emoji and owned sounds, as today, with §2's kudos rule | `post_reactions` |

**Visibility (owner decision):** the trajectory line, `behind` included, is visible to friends **by default, with
no per-post switch to hide the standing**. Hiding it is how a feed drifts back to curated perfection; a crew that
only ever sees `on track` cannot hold anyone to anything. The privacy control is one level up: who your friends
are. An athlete with no active block has no line 2 and no line 3; the card is lines 1, 4, 5, 6, 7.

Line 4 is the only editorial choice on the card. Coach proposes up to three highlights from the session (best
e1RM set, any PR, a milestone total crossed); the lifter picks one or none. No free text.

## 2. Three honesty mechanics, borrowed

- **Precise lateness** (BeReal): the `late` tag becomes `posted 47 min after` — elapsed time from the session's
  completion to the post — and the **retake count** shows (`2 retakes`) when it is above zero. The existing
  `is_late` column becomes a derived read from `posted_at − completed_at`; the retake count is a new integer on
  the post row, written by the composer.
- **A kudos is one gesture and irreversible** (Strava): tapping an emoji or a sound reaction commits it; there is
  no un-react. Counts stay visible (they are today), because the object is accomplishment, not a mood.
- **Not borrowed:** BeReal's post-to-view gate. Your crew sees your trajectory whether or not they posted today;
  a toll booth in front of accountability is the opposite of accountability.

## 3. The Crews card gains frequency honor, not performance

Strava's Local Legend idea on the crew's own card: the meta line names **who showed up most this month** —
`MOST CONSISTENT · SAM · 9 SESSIONS` — a crown that decays when they stop (rolling 30 days, ties to the
earlier achiever). No volume leaderboard on the card; volume lives in the recap and the venue hub. The card's
job stays "get me into the crew, and tell me the next lift": avatar, name, the plate bar, the next lift, the
honor line. Source: `sessions` completed by group members in the last 30 days — the same read the plate bar
already makes, widened to 30 days.

**AMENDED (2026-09-12, implementation):** the honor's source is a `SECURITY DEFINER` RPC,
`group_consistency_honor` (`20260911000001_crew_consistency_honor.sql`), **not** "the same read the plate bar
already makes". That read is RLS-scoped to the viewer — `sessions` SELECT policy admits only sessions the
viewer organised or attended — so counting it client-side would have answered "who showed up most *that I can
see*" under a label that says "who showed up most". The line has to speak for the whole crew, so the count
happens once, inside the database, above RLS.

## 4. Presence surfaces stay ambient and ungated

The venue hub's "who's here" rows and Home's crew pulse never require a post, a streak or a payment to be seen
(the reference scan's Peloton note: gating exactly this drew a backlash in February). Live encouragement — a
cheer to someone lifting right now — is written down as **phase 2**, not built.

## 5. What does not change

The post composer's camera flow, the reaction vocabulary, the report/delete context menu, the feed's ordering
(chronological, friends), the venue hub's sections, the Crews tab's three "outside the box" rows.

## 6. Data

- `workout_posts`: add `completed_at timestamptz` (the session's completion, copied at post time), `retake_count
  int not null default 0`, `highlight jsonb` (`{kind: "topSet"|"pr"|"milestone", text}`), `goal_id uuid null`,
  `week_start date null` (the trajectory and rung the card renders — snapshotted at post time so the card does not
  drift as the ladder re-ladders); `is_late` stays for old rows and is derived for new ones.
- `post_reactions`: no schema change; the client stops offering un-react.
- Crews honor: no table; computed from `sessions` per group over 30 days, cached with the card's existing bar
  read.
- RLS: unchanged (posts and reactions are already friends-scoped).

## 7. Catalog and proof

New/changed ids: `pump-feed-post` (existing) re-rendered from a fixture world that has a block goal and a
current-week rung — the trajectory line, rung chips, highlight and precise late tag all in frame;
`crews-tab` (**new** — the Crews tab has never had a catalog fixture; the live-account walk is the only capture
today) rendering two crews, one with the honor line. Two ids → FLOOR +2 at integration. Proof cards before merge,
as always.

## 8. Sequencing

1. **Now:** the Crews card honor line and the presence rule (§3, §4) — they read nothing new.
2. **After goal-first ships (PR #42):** the card's data half (§1 lines 2–3, §6) reads `BlockGoalRepository` and
   the ladder's rung status — the objects that PR creates.
3. **With it:** the honesty mechanics (§2) and the highlight picker (§1 line 4).

## 9. What this design does not decide

1. Whether a sound reaction stays one-tap-irreversible when the sound is purchased content (the shop's rack).
2. The honor's tie-break wording when two people share the count.
3. Live encouragement (phase 2): the cheer's surface and its rate limit.
4. Whether the feed should show a friend's `behind` weeks in a digest when they have not posted — deliberately
   out: the card is a snapshot the athlete takes, not surveillance.

## Owner decisions (2026-09-07 → 2026-09-11) — binding

1. The card is a **snapshot of where someone is in their fitness trajectory**: weekly goal standing, place in the
   programming, an optional lift highlight, the workout in simple terms, a picture.
2. **Only after finishing a workout** — no random prompt.
3. **The trajectory line, "behind" included, is visible to friends by default with no per-post hide.**
4. Borrow the precise late tag, the retake count and the irreversible single kudos; do not borrow the post-to-view
   gate.
5. The Crews card carries **frequency honor, not performance**.
6. **Presence is never gated.**
