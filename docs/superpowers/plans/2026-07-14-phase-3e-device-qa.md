# Phase 3e Live Voice — Device QA Checklist

Voice is the one feature code review can't fully verify: it needs two real
audio endpoints. Your phone is one; for the second, either a friend's phone
(TestFlight) or LiveKit's web sandbox — the controller can mint a token for
`ci_test_user_2` on demand (ask, and you'll get a join URL/token for the
session you're in; room names are casing-canonicalized so web + iOS land in
the same room).

**Build:** the TestFlight build from PR #19's merge (check build number ≥ the
run that just deployed).

## A. First contact
- [ ] Open a group session lobby → "Connecting voice…" pill appears, then
      clears. Dock shows round mic + "Tap to talk · hold to talk live".
- [ ] First-ever join on this device: mic permission prompt appears at a
      sensible moment (on join, not app launch).

## B. The two gestures (core)
- [ ] TAP the mic → fills accent, one expanding ring, "MIC OPEN · TAP TO
      MUTE" + "Tap toggles · press-and-hold for walkie-talkie". Speak — second
      endpoint hears you. Your row shows the glow + bars on THEIR screen.
- [ ] TAP again → back to idle. Second endpoint confirms silence.
- [ ] HOLD → "HOLDING · 0:0X — RELEASE TO STOP" with a counting timer, two
      staggered rings. Release → mutes immediately (confirm on second endpoint).
- [ ] While TAP-opened, do a HOLD on the button, then release → mic MUTES
      (known adopted-mic behavior — confirm it matches this description, and
      say if it feels wrong; it's a one-line change to alter).
- [ ] Rapid tap-tap-tap and rapid hold-release-hold: dock state always ends
      matching reality (the invariant: UI derives from the actual room state).

## C. Simultaneous talk (the point of the feature)
- [ ] Both endpoints open mics and talk over each other → both heard at once,
      no queueing, no cutting out.
- [ ] Speaking rings/bars light on BOTH rows simultaneously in the roster.

## D. Music duck (sacred rules)
- [ ] Play Spotify/Apple Music. Enter the lobby (voice connects) → music
      keeps playing (mixed, possibly quieter while voice mode is active).
- [ ] Leave the session (back out) → music returns to full normal within ~1s.
- [ ] Soundboard sounds still play while voice is connected.

## E. Failure states
- [ ] Airplane mode → enter lobby → voice-unavailable banner with Retry.
      Disable airplane mode → Retry → connects.
- [ ] Settings → GymSync → mic OFF → enter lobby → "MIC OFF" dock state;
      its tap leads toward Settings. Re-enable → re-enter → works.

## F. Gating + teardown
- [ ] While voice is connected, open the group chat → the voice-MESSAGE mic
      button is dimmed (40%) and inert. Leave the session → it works again.
- [ ] Kill the app mid-transmission → second endpoint sees you drop within
      ~15s (token TTL is not the mechanism — LiveKit disconnect is; just
      confirm you don't linger audible).
- [ ] Sign out while in a session → no crash; voice gone.

## G. Regression touchpoints
- [ ] Voice messages in chat still record/play when NOT in a live session.
- [ ] Chess-clock turn flow unaffected by voice being connected.
- [ ] Push notifications still arrive (backend deploy re-deployed both
      functions).

Report anything off — findings feed the follow-up queue (already tracked:
muted-others roster rows, first-run coach mark, connected toast, voice mixer
sheet, back-nav rejoin blip).
