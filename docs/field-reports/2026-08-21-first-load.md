# Field report — first load (owner, 2026-08-21)

Twelve items from real use. Status legend: SHIPPED (this batch) ·
DIAGNOSED (cause known, fix scoped) · DESIGNED (build plan below, queued)
· DOCKET (needs its own pass).

## Shipped this batch

1. **Delete workouts from ledger** — SHIPPED. `sessions` had no DELETE
   policy, so client deletes silently affected zero rows. Organizer-scoped
   policy added (migration 20260821000002), `SessionRepository
   .deleteSession` deletes set logs then the row, ledger rows take a
   long-press → Delete. PRs derived from a deleted session deliberately
   survive: records are records.
2. **No warm-up timer on solo** — SHIPPED. The persisted default was 0
   ("keeps existing behavior untouched" at build time), so the phase never
   appeared unless configured. Never-configured now defaults to 5 minutes;
   an explicit 0 still means off.
3. **Machine suggestions ending in 5** — SHIPPED. The stepper was already
   stack-aware (`tunerStep`); the SUGGESTIONS weren't. All prefill paths
   (history ladder, RPE step, engine advance) now snap to
   `Units.loadIncrement(forEquipment:)` — machines/cables land on 10 lb /
   5 kg, no bar offset assumed.
4. **Tap weight → manual entry** — SHIPPED. The big number in the entry
   card is now tappable; decimal-pad alert, parsed in the lifter's unit.
5. **EZ bars are lighter** — SHIPPED. `ez_bar_weight_lbs` on user
   settings (default 15 lb, per-user because home EZ bars vary 15-25);
   the solo bar loader and plate math select it whenever the current
   exercise's equipment is ez-bar. (Note: the 3 ez-bar-labeled curls held
   from the catalog QA can now be reconsidered once equipment subclass
   filtering exists.)

## Diagnosed / designed, queued next

6. **Recovery tracking without HR wrong + stacked histogram** — PARTIAL
   DIAGNOSIS. `setStartedAt` initializes at VIEW LOAD, so exercise one
   counts from screen-open, not from work actually starting; subsequent
   accounting inherits the skew. Fix: stamp on first interaction. The
   design request is the keeper: a per-set STACKED HISTOGRAM — bottom
   segment = rest taken, top segment = set duration — replacing the bare
   timer for no-HR lifters. Data exists (`loggedAt` deltas + rest
   windows). One focused pass: fix the stamp, build the histogram.
7. **Paired wearables should auto-connect** — DESIGNED. Apple Watch pairs
   via WatchConnectivity (own watch app), not BLE, so the BLE pairing
   screen never "discovers" it. Plan: on session start, source ladder —
   (1) WCSession `isPaired && isWatchAppInstalled` → auto-select watch
   HR, no pairing UI; (2) previously-paired BLE strap → auto-reconnect;
   (3) only then offer the pairing sheet. Whoop/Garmin broadcast standard
   BLE HR — (2) covers them once paired once.
9. **Every-other-week scheduling** — DESIGNED. SessionSeries is
   weekday-rule based with no interval. Plan: `interval_weeks` column
   (default 1) + anchor date; occurrence expansion filters weeks where
   `floor((week - anchorWeek)) % interval != 0`; editor gains a
   Weekly/Every-other-week toggle. Migration + math + picker, one pass.

## Docket (own passes, in priority order)

8. **Schedule workouts from within groups** — group context → series
   editor with the group preselected; mostly a navigation + preselect
   pass once 9 lands.
10. **Program builder for yourself** — author weeks in succession, adopt
    as a custom program. Foundation exists (program_templates +
    template weeks + enrollment machinery Coach already uses); the build
    is the authoring UI + "adopt" writing the same rows Coach writes.
    Significant, well-paved.
11. **Hot-swap workouts mid-session** — scale a workout down locally in
    a group, or push an opt-in variant to the whole squad. Needs design:
    per-member routine overlays vs. broadcast swaps, and the substitution
    graph is the natural swap source. DESIGN CONVERSATION first.
12. **Video during sets (trainer watches form)** — async form clips
    attached to sets for trainer review (not live streaming, v1).
    Capture UI + storage + trainer playback + retention policy. DESIGN
    CONVERSATION first (privacy + storage cost decisions are the owner's).


# Second load (owner, same day)

## Shipped this batch

13. **Rest notifications not firing** (locked / foreground / minimized) —
    SHIPPED. Root cause: local notifications need their own authorization
    and the only request lived in the PUSH priming screen — decline that
    once and every rest cue dies silently. Authorization now requested
    lazily at the first rest window (the prompt lands in context), and an
    in-app haptic+chime fires from the timer itself so a denied
    permission can never silence the in-app moment.
14. **No core from Coach** — SHIPPED. Only full-body and bro templates
    carried a core slot; upper/lower and PPL had none. Core now rides
    lower and legs days.
15. **Set progression on overshoot** (8@50 → 14@70 → "8@75") — SHIPPED,
    corpus-tuned as requested. The mined rule: "increase the load so you
    return to training within that range." Two+ reps past the ceiling now
    projects the range-floor load from the actual e1RM (inverse Epley)
    instead of stepping once; and the machine-grid snap (item 3) fixes
    the off-stack "75". The field case now lands on 80.
16. **Cross-routine last-weight blindness** — SHIPPED (root cause:
    duplicate catalog rows split the history; the widget read one row's
    history, suggestions another's). History fetches now expand to the
    ALIAS FAMILY (the dedup pass's alias_of), so face pulls are one lift
    no matter which duplicate a routine referenced.

## Docketed / diagnosed

17. **Sports-specific programming + per-sport research** — corpus
    expansion pass (sport S&C channels) + sport_prep goal deepening.
    DESIGN + research swarm, own pass.
18. **Coach aware of most-starred routines** — popularity signal into
    selection/templates. Needs the starring data surface first. DOCKET.
19. **Watch: live sessions not pushed, HR not communicated** +
    **HR seen (recap avg/max) but live widget empty** — one WEARABLE
    PASS: the recap proves HR reaches HealthKit while the live widget
    only reads BLE. Source ladder (WCSession watch -> remembered BLE ->
    pairing sheet) + live widget reading the HealthKit stream + watch
    session push. Highest-priority next pass.
20. **Failed-set send hangs seconds** — no obvious synchronous culprit in
    the log path; needs timing instrumentation. Diagnose next pass.
21. **Session cover blocks swiping to the rest of the app** — structural:
    a live-session mini-bar (browse the app, session persists) is the
    right shape. DESIGN CONVERSATION.
22. **Body scan input on Coach page** — profile editor addition
    (measurements/bodyfat feeding ageBand/context). Rides the profile
    editor pass.
23. **Rest-screen text on the swipe-up widget border** — cosmetic layout;
    fix with the recovery-histogram pass (same screen).

# Design rulings (owner, 2026-08-21)

- **Hot-swap**: ANYONE can suggest a swap and push for squad consensus
  (vote, not organizer fiat). Self-scaling is quiet-but-visible: shown on
  the member's set when their turn comes, never announced.
- **Form video**: storage gated to PRO or coach-linked athletes; coaches
  can extend client storage for a fee (billing rails = own pass; v1
  ships retention tiers without payments). LIVE broadcast during your
  set in group workouts: optional, opt-in toggle on the logging screen —
  live video infra is phase 2 of this feature.
- **Mini-bar**: it exists (LiveSessionPill) and was loved — doubled its
  height/type for visibility, and the routine-detail "Start Workout"
  now presents as a SHEET like the resume path (the push was the trap
  that blocked swiping down).
- **Sports**: football, baseball, wrestling first. Channel roster added
  to the pipeline (Garage Strength, Overtime Athletes, Westside,
  Driveline, Cressey, Tread, Daru, PJF) — enumerate/select/fetch running.
- **Core placement**: corpus consulted (route_core.py) — 15 top
  transcripts inc. RP's "Do You Actually Need to Train Abs?" under
  deep-read; template placement will follow the findings.


# Rulings round 2 + core verdict (owner, 2026-08-21)

- **Hot-swap consensus: UNANIMOUS.** A pushed variant applies only when
  every present member accepts; any decline keeps the original. Quiet
  self-scaling unaffected.
- **Video retention: NONE for non-PRO.** Free users' clips do not
  persist at all; PRO stores, coach-linked extends (fee rails later).

## Core programming — the corpus verdict (83 findings, 8 channels)

- NECESSITY (7ch): goal-dependent but real. "Compounds are enough" is
  REJECTED (Menno; FHP's cited EMG study: indirect activation is far
  below direct work; Ethier cites -16% ab size in 30 days after
  removing direct work while still squatting/deadlifting). Visibility
  is fat loss; SIZE is training.
- DOSE (7ch): train abs like a muscle - 2-4x/week, ~3-6 sets/session,
  hypertrophy reps 10-15 (5-30 range), LOADED and progressed. Our core
  slot on lower/legs days at accessory volume = corroborated.
- SELECTION (8ch, strongest): loaded flexion (weighted/cable crunches,
  reverse crunches, leg raises) >> unloaded planks (RP: no eccentric,
  no growth) and >> twists/side bends for physique (Menno: oblique
  growth thickens the waist). SHIPPED: the core slot now demotes
  twist/rotation/side-bend/oblique/plank names for physique-flavored
  focuses; conditioning keeps stability work. The machine-first
  accessory ladder already buries bodyweight planks.
- PLACEMENT (thin, 2ch): end of session; our slot position stands.
