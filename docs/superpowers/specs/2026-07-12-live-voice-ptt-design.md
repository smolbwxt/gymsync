# Gym Sync — Live Voice (Push-to-Talk) Design

**Date:** 2026-07-12 · **Status:** Approved (user decisions locked) · **Phase:** 3e (after 3d — depends on Edge Function infra) · **Promotes** the spec's v2-deferred "live audio during sessions" into Phase 3 by user request.

## Decisions (user-confirmed)

1. **UX: hold-to-talk.** A press-and-hold button transmits; release stops. Mic is verifiably cold otherwise. No open-mic toggle in v1.
2. **Scope: lobby + live session.** The voice room exists while the session is in `lobby_open`/`editing`/`voting`/`locked`/`in_progress`; joining the lobby or live view auto-joins voice (listen-only until held). Room dies with the session. No persistent group channels.
3. **Music mixing: duck while voice is active.** The user's music keeps playing but dips while voice audio flows, then restores. This consciously relaxes the Phase 1 "never duck" rule FOR LIVE VOICE ONLY — soundboard/pings keep the `.ambient + .mixWithOthers` guarantee.

## Architecture

**Transport: LiveKit Cloud** (managed WebRTC SFU).
- Why: data channels (Supabase Realtime) cannot carry audio; LiveKit has a first-class Swift SDK, a free tier comfortably above v1 scale, active-speaker events for UI, and rooms that map 1:1 to sessions (`room = "session:{session_id}"`).
- Alternatives rejected: mesh WebRTC (TURN infra + N² complexity), Agora/Daily (equivalent but pricier entry), Apple PushToTalk framework alone (it's a UX/system-UI layer, still needs a transport; revisit for background walkie-talkie in v2).

**Token minting: `livekit-token` Edge Function** (the 3d dependency).
- Client calls it with a session_id + its Supabase JWT; the function verifies (service-role) that the caller is a participant AND session state permits voice; signs a short-lived LiveKit access token (room-scoped, canPublish+canSubscribe) with `LIVEKIT_API_KEY/SECRET` held as Edge Function secrets. Nothing sensitive ships in the app.

**Client: `VoiceRoomService`** (LiveKit Swift SDK wrapper).
- Auto-join on entering LobbyView/GroupSessionLiveView (mic track published MUTED); leave on exit/session end.
- Hold-to-talk = unmute while pressed (mute/unmute beats publish/unpublish for latency).
- Active-speaker events → speaking rings on participant rows in both views.
- PTT button in both views: large, thumb-reachable, with a transmitting state.

**Audio session management** — the delicate part.
- `AudioSessionManager` gains `enterVoiceMode()` / `exitVoiceMode()`: voice mode = `.playAndRecord`, mode `.voiceChat`, options `[.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]`; exit restores `.ambient + [.mixWithOthers]`.
- The Phase 1 regression guard (`configure()` yields ambient+mix) MUST keep passing untouched; a new test asserts `exitVoiceMode()` restores exactly that state.
- Ducking behavior: `.voiceChat` mode's system behavior dips other audio while the room is active — matching the user's "duck while voice active" choice at v1 granularity (join-scoped, not per-utterance). Per-utterance ducking is a v2 refinement.
- `NSMicrophoneUsageDescription` added to project.yml ("Gym Sync uses your microphone for push-to-talk with your crew during sessions.").

**Failure posture:** voice is an enhancement — token fetch or room join failures show a small "voice unavailable" pill and never block lobby/session function. No retry storms (one manual retry button).

## Sequencing

3c (soundboard + voice messages) → 3d (push notifications; ships `push-dispatcher` Edge Function + deploy tooling `supabase functions deploy --use-api`, no Docker) → **3e (this)** reuses that tooling for `livekit-token`. LiveKit account + keys are a user-side setup step at 3e start (like the Apple keys were).

## Testing

- Edge Function: deno unit tests (token claims, participant rejection) + a curl smoke against the deployed function with the CI user's JWT.
- pgTAP: none (no schema changes; participant validation lives in the function using existing tables).
- Swift: AudioSessionManager mode-restore test (hermetic); VoiceRoomService is device-QA'd (simulators + CI cannot exercise mic/WebRTC meaningfully).
- Device QA: two-phone (user + controller running a LiveKit web client as ci_test_user_2 — LiveKit rooms accept browser participants, giving the controller a real second voice endpoint for the first time).

## Known limitations (v1)

- Ducking is join-scoped, not per-utterance.
- Foreground only (background PTT via Apple's PushToTalk framework = v2).
- No per-user volume/mute-others controls; no voice for solo sessions (pointless) or outside sessions.
