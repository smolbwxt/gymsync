# Gym Sync — Phase 3e: Live Voice Push-to-Talk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hold-to-talk live voice in the lobby and live session via LiveKit Cloud: auto-join muted, press-to-transmit, speaking indicators, duck-while-active audio, all four designed dock states, mic priming — with the project's sacred audio rules intact.

**Architecture:** A `livekit-token` Edge Function (verifies the caller's Supabase JWT via JWKS, gates on session participation + voice-eligible state, mints a room-scoped LiveKit token). A client `VoiceRoomService` (LiveKit Swift SDK with automatic audio-session management DISABLED; our `AudioSessionManager` gains voice mode and owns the session exclusively). PTT dock UI per the canvas frames.

**Reference:** `.superpowers/ptt-dossier.md` (cited "Dossier §X") — spec extraction, canvas frame markup verbatim, SDK facts verified against livekit/client-sdk-swift@2.15.1 source, audio reconciliation. THE DOSSIER IS THE FACTUAL AUTHORITY; the spec (`docs/superpowers/specs/2026-07-12-live-voice-ptt-design.md`) and canvas markup are its sources.

## Global Constraints

- **AUDIO SACRED RULES**: `AudioSessionManagerTests` + `AudioSessionRestoreTests` byte-untouched and green. Baseline stays `.ambient + .mixWithOthers`. Voice mode (`.playAndRecord`/`.voiceChat`/`[.mixWithOthers,.allowBluetoothA2DP,.defaultToSpeaker]`) is join-scoped and MUST restore exactly the baseline on every exit path. LiveKit's `AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false` BEFORE any connect (Dossier §B.3).
- **VoiceRecorder conflict rule (decision made)**: while a PTT room is connected, the chat voice-message mic is DISABLED (visually 40% + inert, brief tooltip-style caption if trivial) — `VoiceRecorder.exitRecordMode()` would silently kill room audio (Dossier §B.3.4). Recorded as product note for the designer.
- Failure posture: voice is an enhancement — token/join failures show the designed "Voice unavailable · Retry" card (already shipped in Lobby via T4-of-canvas-completion? verify — the lobby voice-unavailable card exists per the earlier frame; REUSE it), never block the session. One manual retry, no storms.
- LiveKit secrets are server-side only (`LIVEKIT_API_KEY/SECRET` in Edge Function secrets; the app receives only `LIVEKIT_URL` + short-lived tokens — ship the URL via Secrets.swift addition or fetch in token response; PICK: return `url` in the token response so the app hardcodes nothing).
- Room = `session:{session_id}`; voice-eligible states: lobby_open, editing, voting, locked, in_progress (Dossier §A.1).
- Migrations: none expected (no schema changes). Edge Function deploy job in `.github/workflows/backend.yml` currently deploys ONLY push-dispatcher — T1 extends it to both functions.
- Git: branch `feature/phase-3e-ptt` (create from master AFTER infra/ci-screenshots merges). Specific-file adds; report BEFORE CI watch; CI green per task; PR `--base master`; merge per standing authorization.
- Design: dock states/kickers/copy per canvas frames (Dossier §A.2 markup verbatim); tokens/zero-radius/44pt-invisible-hits; centered commit-CTAs.

## File Structure

```
supabase/functions/livekit-token/{index.ts, jwt.ts, test.ts, deno.json}   # T1
.github/workflows/backend.yml                                             # T1 (deploy both functions)
GymSyncApp/GymSync/Services/AudioSessionManager.swift                     # T2 (enterVoiceMode/exitVoiceMode)
GymSyncApp/GymSyncTests/AudioSessionVoiceModeTests.swift                  # T2 (new file — restore test)
GymSyncApp/project.yml                                                    # T3 (LiveKit SPM + mic usage string update)
GymSyncApp/GymSync/Services/VoiceRoomService.swift                        # T3
GymSyncApp/GymSync/Features/Sessions/{LobbyView,GroupSessionLiveView}.swift  # T4 (dock + rings)
GymSyncApp/GymSync/Features/Onboarding/… (mic priming reuse)              # T4 if needed per dossier §A.2
GymSyncApp/GymSync/Features/Social/ChatView.swift                         # T4 (mic gating while room connected)
```

---

### Task 1: `livekit-token` Edge Function + CI deploy extension

**Files:** Create `supabase/functions/livekit-token/index.ts`, `jwt.ts`, `test.ts`, `deno.json`; Modify `.github/workflows/backend.yml`.

Contract (Dossier §B.1-B.2 + §A.1 token section):
- Handler: POST `{ session_id }` with the caller's Supabase JWT in Authorization (supabase-swift `functions.invoke` forwards it automatically — Dossier §B.2). Verify the JWT LOCALLY against `SUPABASE_JWKS_URL` (env — already provisioned; fetch JWKS, cache in module scope, verify RS/ES per the project's signing keys; extract `sub` = user id). 401 on invalid/missing.
- Authorization: service-role Postgrest query — caller must be a session participant (`is_session_participant` semantics — query session_participants directly) AND session.state ∈ the 5 voice-eligible states. 403 otherwise (distinct from 401; body says why).
- Mint LiveKit access token (HS256 JWT per LiveKit spec — `jwt.ts` with injectable clock): `iss` = LIVEKIT_API_KEY, `sub` = user id, `name` = username (fetch profile display for participant labels), TTL 15 min, video grant `{ room: "session:{id}", roomJoin: true, canPublish: true, canSubscribe: true }`. Response `{ token, url: LIVEKIT_URL }`.
- Env: LIVEKIT_API_KEY/SECRET/URL (set), SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_JWKS_URL (verify this env exists in function runtime — else construct from SUPABASE_URL + `/auth/v1/.well-known/jwks.json`).
- deno tests (offline, injectable fetch/clock, mirroring push-dispatcher/test.ts style): valid flow → token decodes with exact grants/TTL; non-participant → 403; ineligible state → 403; bad JWT → 401; JWKS cache behavior. `deno test`, `deno check`, `deno lint` clean.
- backend.yml: deno-test job's working-directory strategy must now cover BOTH function dirs (run per-dir or a loop); deploy-functions job deploys `push-dispatcher livekit-token` (CLI accepts multiple names or repeat the command).

Commit `feat(voice): livekit-token edge function — JWKS-verified, participant-gated`. CI (Backend) green.

---

### Task 2: AudioSessionManager voice mode

**Files:** Modify `Services/AudioSessionManager.swift`; Create `GymSyncTests/AudioSessionVoiceModeTests.swift`. DO NOT touch existing audio tests.

Contract (Dossier §A.1 audio section + §B.3):
- `enterVoiceMode()`: `.playAndRecord`, mode `.voiceChat`, options `[.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]`, setActive(true). `exitVoiceMode()`: restore EXACT baseline (`.ambient`, `[.mixWithOthers]`) — same restore shape as VoiceRecorder's exit (read it). Idempotent (double enter/exit safe); a `isInVoiceMode` flag readable by VoiceRecorder gating (T4).
- New test file: enter→exit restores category/options exactly (hermetic, same pattern as AudioSessionRestoreTests); double-exit harmless; Phase-1 `configure()` behavior untouched (existing tests prove — do not modify them).

Commit `feat(voice): audio session voice mode — duck-scoped, baseline-restoring`. iOS CI green.

---

### Task 3: VoiceRoomService + SDK integration

**Files:** Modify `GymSyncApp/project.yml` (SPM: `https://github.com/livekit/client-sdk-swift` from `2.15.0`; update `NSMicrophoneUsageDescription` to cover live voice + voice messages); Create `Services/VoiceRoomService.swift`.

Contract (Dossier §B.3-B.5):
- `@MainActor @Observable final class VoiceRoomService` (singleton or per-view-owned — PICK singleton with join(sessionID:)/leave() reference semantics; document). State machine: `idle / connecting / connected(muted|transmitting) / unavailable(Error) / micDenied`.
- `join(sessionID:)`: mic permission check first (AVAudioApplication — reuse 3c's pattern; denied → `.micDenied`, no request storm — request only on first hold if undetermined? Dossier/design: priming happens contextually — follow Dossier §A.2's priming frame guidance); `AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false` (once, static init); `AudioSessionManager.shared.enterVoiceMode()`; fetch token via `client.functions.invoke("livekit-token", ...)`; `Room.connect(url:token:)`; publish mic track MUTED (`localParticipant.setMicrophone(enabled: true)` then mute, or publish muted per SDK — dossier §B.4 has exact APIs; default `.voiceProcessing` mute mode = OS indicator off, satisfies "verifiably cold").
- `beginTransmit()` / `endTransmit()`: unmute/mute (NOT publish/unpublish). Speaking: RoomDelegate active-speakers events → `speakingParticipantIDs: Set<String>` (map LiveKit identity = user UUID string).
- `leave()`: disconnect, `exitVoiceMode()`, state idle — guaranteed on session end/view dismiss/sign-out (find hooks; sign-out must leave).
- Failure → `.unavailable(error)`; `retry()` re-runs join once.
- No timers; async/await; every path restores audio on failure (defer).

Commit `feat(voice): VoiceRoomService — LiveKit room lifecycle under owned audio session`. iOS CI green (SDK resolves in CI).

---

### Task 4: PTT dock UI + speaking rings + gating

**Files:** Modify `Features/Sessions/LobbyView.swift`, `Features/Sessions/GroupSessionLiveView.swift`, `Features/Social/ChatView.swift`; possibly small GSComponents addition for the dock button.

Contract (canvas frames via Dossier §A.2 — markup verbatim; four dock states + lobby strip):
- PTT dock (sticky above/replacing bottom edge per frames — reconcile with GSTabBar hidden on these pushed screens): four states exactly — Idle ("Hold to talk", surface + 1px divider border, accent mic glyph), Transmitting ("Release to stop", accent fill, bg text, animated bars), Connecting (spinner + "Connecting voice…", 75% opacity), Mic denied / unavailable per their frames (dashed border "MIC OFF · TAP TO ENABLE" → priming/settings; unavailable card w/ Retry — REUSE the shipped voice-unavailable card if present, align copy).
- Hold gesture: same pattern as 3c mic (LongPress pressing:) driving beginTransmit/endTransmit; 44pt+; releases ALWAYS endTransmit (defer-style).
- Auto-join on view appear (both views) when session state eligible; leave on disappear w/ identity guard (the activeSessionID pattern); "Connecting voice…" pill in lobby header per frame.
- Speaking rings: participant rows in both views get the accent ring/border + "talking" caption + animated bars per the lobby strip frame, driven by `speakingParticipantIDs`.
- ChatView: voice-message mic disabled (40% + inert) while `VoiceRoomService.state == connected` (the sacred-rule gating; document copy choice).
- Zero behavior changes to turn engine/realtime beyond these additive hooks.

Commit `feat(voice): PTT dock, speaking indicators, recorder gating per canvas`. iOS CI green.

---

### Task 5: Deploy, smoke, ship

- [ ] Deploy `livekit-token` (manual or via merge CI); curl smoke: obtain ci_test_user_2 JWT via password grant (scripts/qa pattern), POST session_id of a fixture lobby session → token decodes, room/grants correct; non-participant 403; bad JWT 401.
- [ ] Whole-branch opus final review (ledger roll-up); PR `--base master`; merge per standing authorization; watch deploys (functions + TestFlight).
- [ ] Device QA plan: user's phone + controller driving a LiveKit web client as ci_test_user_2 (real second voice endpoint — Dossier §A.1 testing) — hold-to-talk both directions, duck behavior vs Spotify, dock states (airplane-mode → unavailable → retry), mic-denied path, voice-message mic gating, session-end room teardown.

## Self-Review Notes
- Sacred-rule enforcement is structural: LiveKit auto-config disabled (T3), session owned solely by AudioSessionManager (T2), recorder gated (T4), restore tests hermetic (T2). Spec coverage: all Dossier §A.1 locked decisions have tasks; all four dock states + lobby strip mapped (T4); token flow (T1) matches spec's participant+state gate; failure posture per spec.
- Cross-task: VoiceRoomService (T3) consumes T2's enter/exitVoiceMode + T1's function name/response shape `{token,url}`; T4 consumes T3's state machine names exactly as written here.
- No pgTAP (no schema); deno + hermetic Swift tests + device QA cover the rest.
