# The group session and the lobby — one body, a chosen style — design

**Status:** brainstorm closed with the owner on 2026-09-12 (two rounds, eight numbered answers); written for the
owner's review before any code. **Gate documents:** the design language
(`docs/superpowers/specs/2026-09-05-design-language.md`, especially "same body, different frame"), the goal-first
programming spec (`docs/superpowers/specs/2026-09-07-goal-first-programming-design.md` — the plan card reads its
rungs), the social-cards spec (`docs/superpowers/specs/2026-09-11-social-cards-design.md` — the post's reactions
change here), and the read-only context map of the flow as built
(`.superpowers/sdd/2026-09-12-lobby-round/context-map.md`, 405 lines with file:line evidence; every size and
state claim below comes from it).

## Why

The owner, 2026-09-03: *"simplify the group session + pregame lobby"*; 2026-09-11: *"the presession lobby looks
untouched"*; 2026-09-12: *"if everyone goes at their own pace … someone finishes minutes before anyone else and it
feels detached … lock people into a cadence"*, then *"let them choose the style … ordered cadence, freestyle, or
everyone at the same time — a HIIT workout, biking together"*, and *"any weight, volume or set change, in or out of
a workout, is a suggestion, not an unprompted change."*

What exists (context map §1–§4): one `LobbyView` (2,098 lines) serves scheduled solo and crew sessions alike, so a
lifter training alone sees WHO'S HERE, a talk dock and Lock in & Start; the live group workout is
`GroupSessionLiveView` (6,160 lines, 22 modifiers on its outermost body, 86 `@State` values) with a
two-participant-only spectate subtree that no catalog frame reaches and that the parked Start crash implicates;
warm-up is split (minutes set in the lobby, the "I'm warm" vote after Start inside the live view); three of the eight
session states (`editing`, `voting`, `locked`) are never set by any code; the soundboard and throwable plates are
interleaved through the live view (21+ symbols), nine more files, three tables, a You-tab widget and a tour step.

## 1. Vocabulary

| Word | Meaning |
|---|---|
| **Session** | One workout, solo or crew, from check-in to recap. |
| **Lobby** | Where a crew waits for its people. Crew sessions only. |
| **Start** | The moment the crew walks into the gym together: the leader taps it, or it fires when everyone is ready (consensus). After Start there is no lobby. |
| **Warm-up** | The first phase of every session, solo or crew, on the shared warm-up screen. |
| **Style** | How a crew session moves: **Rounds**, **Freestyle**, or **Together**. Chosen by the organizer at scheduling, defaulted by routine type, changeable in the lobby until Start. |
| **Round** | In Rounds: one set each; the round closes when the last lifter logs. Rest is the round. |
| **Station** | A subset of the crew rotating on one piece of equipment. Rotation depth never exceeds three. |
| **Spotter mode** | What a lifter does in rounds their prescription has no set for: cheer, talk, film — with the crew, not a solo recap. |
| **Suggestion** | Any change to weight, volume or sets, proposed by Coach or a crewmate, that applies only when the athlete accepts it. |

## 2. Solo: check in, warm up, lift

No lobby. From Home's start control or a scheduled solo session, the path is **check-in → warm-up → sets → rest →
… → recap**. Two screens carry the lift: **the set** (log the weight and reps) and **the rest** (recovery readout,
the next prescription, and the "is the plan still achievable" check). Nothing here is new; it is the solo flow as
shipped, named so the crew flow can be described against it.

The **warm-up screen** is where the decision moments live that a confirmatory lobby would have held: the **plan
card** (the routine, or today's rung when a program is running, with a swap control) and **one Coach line** (a
readiness suggestion — *"today is 4×5 at 225; you slept five hours — want 3×5?"* — accepted with one tap or
ignored). Owner decision: no separate confirmatory screen for solo.

## 3. Crew: lobby, Start, warm up together, then the chosen style

### 3.1 The lobby (crew only)

Three things, on the design language's surfaces: the **roster** as an arrival track (`ON THE WAY · AT THE GYM ·
CHECKED IN`, replacing the check-in chips; stages derive from `check_in_state` plus the geofence/travel signals the
lobby already has), the **talk dock** (push-to-talk stays, as shipped in `PTTDockRow`), and **Start**. The plan
card sits above them so the crew sees what it is about to do. **Start** is the leader's tap, or fires when every
checked-in lifter has marked ready (consensus). "Start anyway" stays for the leader when someone is late.

Gone from the lobby: the routine proposal-and-vote flow and its three realtime subscriptions (the `editing`,
`voting`, `locked` states were designed for it and are dead), the warm-up minutes stepper (warm-up is a phase, not
a number), and every soundboard reference (§5).

### 3.2 Start is walking into the gym together — then warm up together

Owner decision (answer 3): the crew does **not** warm up in the lobby. Start ends the lobby for everyone and opens
the **shared warm-up screen** — the same screen solo uses, in its crew frame: the plan card, the Coach line for
each lifter privately, and the crew's readiness ("I'm warm" per lifter, visible to all). The session's style phase
begins when everyone is warm or the leader moves on. Today's `mark_warmup_ready` / `start_lifting` RPCs already
model exactly this hand-off and stay.

### 3.3 The three styles

**Rounds** (default for rack and strength routines). The unit is the round. Everyone does one set of their current
exercise; the round closes when the last lifter logs; the next set cannot start before that (the soft gate). A
lifter holding a round past a threshold gets a no-shame skip: the crew moves on, they rejoin next round, nothing is
recorded against them. **Turn order is fixed within an exercise** (check-in order seeds it, as `start_session` does
today) and **re-drawn at each exercise change** when stations re-mix. **Stations:** a crew larger than three is
split so no rotation is deeper than three (five → three and two); groupings re-mix at exercise changes so different
people rest together, and the app measures each lifter's actual rest and re-mixes only while averages are close.
Both stations end together because the workout is counted in rounds. **Spotter mode** fills a lifter's idle rounds.

The two solo screens map onto Rounds unchanged: **your turn** is the set screen; **the round** is the rest screen,
where the countdown becomes "who is still to go" beside elapsed rest, the recovery readout, the next prescription
and the achievability check.

**Freestyle.** Own pace, with glue: a shared progress rail (sets done over total, per lifter) and an end-together
nudge — a lifter two sets ahead sees their rest stretch and a Coach suggestion for an accessory; a lifter behind
sees the crew's rest wait. The recap is shared. Freestyle without the rail recreates the detachment the owner
described.

**Together** (default for cardio, HIIT, biking). Everyone runs the same interval clock; there is no turn. The crew
frame shows every lifter's readout on one timeline.

### 3.4 Two modes of exercise change in a crew (answer 7)

1. **A change to the routine for everyone** — proposed to the crew, consensus sought, applied for all on
   acceptance. This is what the shipped `SwapProposal` / group swap sheet does; it stays, redesigned as a consent
   card in the design language.
2. **A personal scale-down for one lifter** — never broadcast, applied only to that lifter's prescription (Coach's
   substitution graph, as solo uses it), and visible where the crew looks anyway: in "who's up next and what they
   are doing". Nothing is pushed to anyone.

### 3.5 Ending

Unchanged mechanics: leave hands off your turn; the last present lifter's leave ends the session; "End for
everyone" is the leader's. The recap is one shared recap, reached together by design of the styles above.

## 4. The suggestion principle

Owner rule, binding everywhere: **every change to weight, volume or sets — in a workout or outside it — is a
suggestion the athlete accepts, never an unprompted change.** It applies to Coach's in-workout adjustments (the rest
screen's "drop to 3×5?"), to the Freestyle nudge, to both crew change modes, and to programming. One shipped
behaviour violates it and changes with this spec: the goal-first release **re-ladders a block automatically** on the
first Home load of a new week (`BlockGoalLiveRepository.swift:1074`, inside the detect-if-missing path that
`HomeView.swift:1799` runs). It becomes a **proposal card** — *"Coach proposes a new ladder: …"* — on Home and the
ladder page, applied on accept; `LET COACH RE-LADDER` remains the explicit trigger. Weekly-goal proposals already
comply; build-time volume titration is not a change to an existing plan and is untouched. The consent-card pattern
is the one Coach chat already uses for swaps and rules.

## 5. What leaves the app

- **The soundboard and the throwable plates are tabled indefinitely** (answer 6). Everything that points to them is
  scrubbed: the live-view dock and throws, the You-tab widget and its tour step, the Watch UI, the Shop's sound
  rack, and — because they exist only to play those sounds — the **sound reactions on pump-check posts** (the feed's
  reaction vocabulary becomes emoji only; spec §9.1 of the social cards spec closes with it). The implementation is
  archived at a git tag (`archive/soundboard-2026-09`) before removal; the tables and their rows stay until a later
  migration decides otherwise. Push-to-talk is untouched — the map confirmed nothing in the voice path depends on
  the soundboard.
- **The spectate subtree, the BOARD scoreboard, and the two-participant-only branches** go with the rotation view
  they served; the round model has no equivalent and the parked crash's two leading hypotheses lived there.
- **The dead session states** `editing`, `voting`, `locked` and the proposal-vote flow.

## 6. Data

- `sessions.style` (`rounds` | `freestyle` | `together`), set at scheduling, editable until Start; a default per
  routine type computed client-side.
- Stations: `sessions.stations jsonb` — the current exercise's assignment of lifters to stations and each station's
  turn order, re-written by the server at exercise changes; `sessions.round int` is the server-owned round counter,
  advanced when the last lifter of the round logs, so every client agrees when a round closes. (A separate table is
  not needed: the assignment is transient and only the current one matters.)
- Per-lifter substitutions inside a crew session: the existing substitution mechanism keyed by (session, lifter,
  exercise); readable by crewmates for "who's up next".
- Warm-up readiness: the existing `mark_warmup_ready` / `start_lifting` RPCs; the `warmup_minutes` column becomes
  unused.
- The suggestion principle needs no new table: proposals render from the values Coach would have written.
- RLS: unchanged in shape; the station and substitution reads are crew-scoped like `session_participants`.

## 7. Catalog and proof

The group live workout has never had a catalog frame (context map §5). This spec requires frames for: the lobby
(waiting, everyone ready, a late arrival), the shared warm-up in its crew frame, Rounds (your turn; the round wait
with two stations; spotter mode), Freestyle (the rail with one lifter ahead), Together (the shared clock), the
consensus swap card, and a personal scale-down visible in "who's up next". The solo warm-up screen with the plan
card and a Coach suggestion gets one frame. Proof cards before merge, as always; FLOOR moves by the count of new
captures at integration.

## 8. Sequencing

1. **A focused design round first** (answer 8): the session screens — lobby, warm-up, set, rest/round, the three
   style frames, the two change cards — and the **pump-check cards** brought onto the design language, as rendered
   proofs for the owner, the way the Home and You rounds were run.
2. **Phase A — the lobby and the shared warm-up screen.** `LobbyView` de-furnished into the crew frame; the
   warm-up screen shared by solo and crew; proposals collapsed to the consensus card; the soundboard scrubbed from
   these surfaces; frames for every lobby and warm-up state. About a week and a half of one stream.
3. **Phase B — one session body.** The crew frames (Rounds with stations and spotter mode, Freestyle, Together) on
   the solo workout body; the two change modes; the server-side round counter; the retirement of
   `GroupSessionLiveView` and the archive of the soundboard. Three to four weeks; the whole-branch review is where
   the parked crash's hypotheses get their first real observation.
4. **The suggestion principle's one shipped fix** (the re-ladder proposal card) ships with Phase A, since it is a
   card on Home and the ladder page and touches nothing in the session.

## 9. What this design does not decide

1. The round-hold threshold before a skip is offered, and the copy of the skip.
2. How "on the way" is signalled for the arrival track — the geofence and travel override exist; whether an ETA is
   asked for is open.
3. Whether Together sessions share heart-rate readouts by default (the HR share setting exists per user).
4. When the soundboard's tables are dropped.
5. Live encouragement (a cheer to someone lifting now) — phase 2 of the social cards spec; the round wait is its
   natural surface, and it is still not built here.

## Owner decisions (2026-09-12) — binding

1. A crew session's style is the crew's choice — Rounds, Freestyle, or Together — defaulted by routine type; not
   prescribed.
2. Stations keep the rotation no more than three deep; groupings re-mix so different people rest together.
3. Solo has no lobby: check-in, warm-up, lift. The decision moments live on the warm-up screen.
4. Every weight, volume or set change, in or out of a workout, is a suggestion the athlete accepts.
5. Start is everyone walking into the gym; the crew warms up together after it, not in the lobby.
6. Turn order is fixed within an exercise and re-drawn at exercise changes.
7. Spotter mode: yes.
8. The soundboard and throwables are tabled indefinitely; everything pointing to them is scrubbed; the
   implementation is archived.
9. Two modes of exercise change in a crew: a routine change with consensus, and a quiet personal scale-down.
10. Proof frames for the live session are part of the plan, after a focused design round that also covers the
    pump-check cards.
