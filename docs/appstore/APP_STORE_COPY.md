# App Store Connect copy — v1.0 (2026-08-28)

Every field below is within ASC's limit (counted). Paste as-is.

## Name (30 max)
GymSync

## Subtitle (30 max — exactly 30)
AI-built programs. Real crews.

## Promotional text (170 max — 161; editable without review, rotate freely)
Log your lifts, chase PRs, and run real multi-week programs — solo or
live with your crew. Coach builds your block around your goals, your
joints, your schedule.

## Description (4000 max)
GymSync is the lifting app for people who don't train alone.

Log fast, run real programs, and lift live with your crew — while Coach,
an AI that runs privately on your iPhone, builds every block around your
goals, your schedule, and the joints you're working around.

LOG WITHOUT BREAKING YOUR REST TIMER
• One-tap set logging with smart weight suggestions from your own history
• Personal records celebrated the second they happen
• Supersets, drop sets, and to-failure sets — prescribed and tracked
• Syncs workouts to Apple Health

PROGRAMS WITH A FINISH LINE
• Multi-week blocks with weekly targets from your real estimated 1RM
• Percentages turned into actual barbell weights — no math at the rack
• Built-in deload weeks and honest week-by-week progression
• Re-baseline or repeat a week when life happens

COACH — A CONVERSATION, NOT A FORM
• Tell Coach your goal, your days, your equipment, and what hurts
• Get a complete block: routines, weekly volume, rest, and the reasoning
• Injury-aware: name a joint and every lift that loads it stays out
• Standing rules — "pulls before arms", "no leg extensions" — honored in
  every build and shown on a card before anything changes
• Built on published training research, cited inside the app
• Runs on-device with Apple Intelligence — your answers stay on your phone

LIFT TOGETHER
• Live group sessions: share a room code and take turns on the bar
• Crew leaderboards by volume, kudos, and session recaps
• Community campaigns — move a shared total with your whole gym
• Gym hubs: see who's training at your gym right now
• Challenge workouts like The Murph, with time and volume leaderboards

FOR TRAINERS
• Invite clients, prescribe routines and programs, and track their week
  — with permissions the client controls

YOUR NUMBERS, HONESTLY
• Lifetime volume, weekly trends, per-exercise history and PR graphs
• Streaks that count what you actually did

The core of GymSync is free: logging, five routines, live group
sessions, crews, PRs, and streaks. GymSync Pro adds Coach-built
programs, unlimited routines, full history, and deeper stats.

Questions or ideas? We read everything: see the support link below.

## Keywords (100 max — 94; commas, no spaces)
workout log,lifting,gym tracker,strength,hypertrophy,program,barbell,coach,crew,friends,pr,5x5

Notes: don't repeat "GymSync" (the name is already indexed), and "fitness"
is largely wasted (category term). Rotate via promo text learnings later.

## What's New (v1.0)
Welcome to GymSync — log your lifts, run a real program, and train live
with your crew. Built with love, chalk, and published research.

## Support URL (required)
⚠️ MUST CHANGE — the repo went private on 2026-09-03 (IP protection, and a
precondition for putting CI on the Mac mini: see docs/ops/mac-mini-runner.md).
The old value below depended on the repo being public and now returns 404 to
everyone who is not signed in as the owner. Apple requires a Support URL that
is publicly reachable, and a dead one is a Guideline 1.5 rejection —
App Review does check it.

Superseded value (do not use):
~~https://github.com/smolbwxt/gymsync/issues~~

Replacement: add a `support.html` to the smolbwxt/gymsync-legal repo, which
already serves the privacy policy and terms over GitHub Pages, and use:
https://smolbwxt.github.io/gymsync-legal/support.html

That repo MUST stay public. GitHub Pages does not serve sites from private
repositories on the Free plan, so privating it would take down the privacy
policy URL as well — and that one is a hard App Store requirement, not just a
support link.

Changing these URLs in App Store Connect does not require a resubmission, so
this can be fixed independently of any build.

## Marketing URL (optional)
Leave blank for v1.0 — it's optional and an empty field beats a thin page.
Add the real site when the web portal ships.

## Copyright
© 2026 Tommy Smola
(Must match the legal entity on your Apple Developer account — if you
enrolled as an individual, your name; if you enrolled as an LLC, the
LLC's exact legal name.)

## Screenshots (1284×2778 — the size this ASC form accepts; upload in this order)
| # | File | Story it tells |
|---|---|---|
| 1 | 01-personal-record | The payoff — full-screen PR celebration |
| 2 | 02-crew-session-leaderboard | You don't train alone — crew recap + kudos |
| 3 | 03-program-week-by-week | Real programming — %1RM → actual weights, deload |
| 4 | 04-program-catalog | Blocks with a finish line |
| 5 | 05-workout-complete | The solo loop — PR + Apple Health |
| 6 | 06-the-murph-challenge | Challenge workouts + leaderboards |
| 7 | 07-stats-volume | Your numbers (light theme variety) |
| 8 | 08-gym-hub | Your gym, live |

First three are what shows in search results — payoff, social, programming.
Source: CI screenshot suite (run 33197562124), 1206×2622 originals
scaled to fill 1284×2778 with a 13px center crop (no stretch). ASC
rejected 1320×2868 — this account's form wants the 6.5" sizes
(1242×2688 / 1284×2778). The suite also
contains shots with test-fixture data (ProposalConflictTest-*) and the
dormant Pro paywall ("Coming soon" button) — never upload those; the
paywall shot especially would draw an App Review question.

## Apple Watch screenshot (416×496 — Series 10 46mm)
`watch-whose-turn.png` — the real watch app (Phase W) captured in the
watch simulator by the `watch-screenshot` CI job (runs on commits tagged
`[watch-shot]`): whose-turn surface with the debug-only `--marketing-demo`
seed (PUSH CREW — PUSH DAY · Bench Press · Your turn). Never a mock-up:
guideline 2.3.3 wants the app as the binary renders it. The seed and the
screenshot-mode freshness pin are `#if DEBUG` — the released watch app
contains neither.
