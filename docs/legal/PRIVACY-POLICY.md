# GymSync Privacy Policy

**Effective date:** [SET BEFORE PUBLISHING]
**Contact:** [SUPPORT EMAIL — SET BEFORE PUBLISHING]

> DRAFT — written from the app's actual data flows as implemented (see the
> repo's schema and services for ground truth). Have a lawyer review before
> public launch: this app touches health-adjacent data, location, and an
> 18+ social feature, which is exactly the combination that deserves
> professional eyes. This draft is a head start, not legal advice.

## What we collect, and why

**Account.** Email address and the profile you create (username, display
name, optional avatar photo). Used to sign you in and identify you to
people you choose to train with.

**Workout data.** Routines, scheduled sessions, sets (reps, weight, RPE),
personal records, streaks, body-weight log entries, and training-program
enrollments. This is the product: it exists so you can see your own
history and progress.

**Heart rate (optional).** If you use the Apple Watch app and explicitly
turn on heart-rate sharing, your live heart rate is relayed to the members
of the group session you're in, for the duration of that session. Heart
rate is read through Apple HealthKit only with your permission. Workouts
can be exported back to Apple Health if you allow it. Health data is never
used for advertising or shared with third parties, and we do not sell it
— HealthKit data is used solely to provide the features above.

**Location (optional, moment-in-time).** Two features check where you are
when you use them: session check-in (confirming you're at your gym) and
Local Hubs (18+; confirming you're at a venue before joining its hub).
Your coordinates are checked at that moment and are not stored as a
location history. On a hub, other members can only see that you're present
if you explicitly toggle yourself visible, and you can turn that off at
any time.

**Workout photos ("pump checks", optional).** After a workout you can
choose to post a photo of yourself with a summary of that workout
(exercises, sets, and — only if you switch it on for that post — your
average and maximum heart rate). Posts are visible **only to friends you
have accepted**; there is no public feed. Location metadata is removed
from photos before upload. You can delete any of your posts at any time,
which removes the photo and summary for everyone.

**Social content.** Group chat messages, soundboard plays, and — if you
opt in — your workouts and leaderboard entries as visible to friends or
group members. Voice in live sessions is real-time only and is not
recorded.

**Diagnostics.** Crash reports and basic device information (via Sentry)
to fix bugs. No advertising identifiers; no ads; no data brokers.

## What other people can see

Only what the feature implies and you've opted into: group members see the
session content you share with that group; friends see workouts you've
marked shareable; hub members see your presence only while you've toggled
it on. Blocking someone hides you from each other across the app.

## Third-party services

- **Supabase** — database, authentication, and realtime infrastructure
  (data processor).
- **Apple** — HealthKit (on-device permissioned), push notifications,
  TestFlight/App Store.
- **LiveKit** — real-time voice transport for live sessions (not recorded).
- **Sentry** — crash reporting.
- **YouTube** — exercise demo videos are embedded via YouTube's
  privacy-enhanced player (youtube-nocookie.com); YouTube's own terms and
  privacy policy apply when you play one.

We do not sell your data, and we do not share it with advertisers.

## Retention and deletion

Your data is retained while your account exists. **Delete Account** (in
the You tab) permanently deletes your account and personal data; shared
resources you created (groups, sessions) are handed to another member
rather than deleted out from under them. Offline-queued workout data is
removed from the device on sign-out.

## Age

GymSync is not directed at children under 13. The Local Hubs feature is
restricted to users who attest they are 18 or older.

## Changes

We'll update this page and the effective date when the policy changes
materially.
