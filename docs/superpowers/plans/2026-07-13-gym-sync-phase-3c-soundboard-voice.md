# Gym Sync — Phase 3c: Soundboard, Voice Messages & the PR Moment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The comms layer — in-session soundboard + emoji reactions (ephemeral broadcast, chat echoes), Instagram-style voice messages in chat (hold-to-record, category-swap audio), and the PR celebration moment — per the canvas section "Comms, soundboard & the PR moment" and "Talk to your crew mid-set" (PTT visual hints only; live PTT stays 3e).

**Architecture:** Broadcast primitives ride the existing `session:{id}` realtime channel (spec §5 wire shapes; client rate-limit 1/s). Soundboard audio = public bucket + `soundboard_sounds` table (global read). Voice messages = new private `chat-audio` bucket with the proven path-derived RLS, `kind='audio'` (CHECK + policy extension), AVAudioRecorder with a scoped `.playAndRecord` swap that ALWAYS restores `.ambient + .mixWithOthers`. Playback everywhere through the existing ambient config (mixes with Spotify — the sacred rule holds for playback).

**Tech Stack:** unchanged + AVFoundation recording. Next free migrations: `20260715000001+`.

## Global Constraints

- All prior constraints (RLS+pgTAP patterns, fix-forward, repositories, CI-verified Swift, publication-with-subscription rule — no new postgres_changes subscriptions in this phase; broadcast/presence need no publication).
- **AUDIO SACRED RULE:** playback never ducks/pauses user music (`.ambient + .mixWithOthers`, existing `AudioSessionManagerTests` regression guard MUST stay green untouched). Recording may swap categories ONLY while actively recording; a new hermetic test asserts the restore.
- **Soundboard broadcast wire shape (spec §5):** `{ "user_id": uuid, "sound_slug": slug, "ts": ms }` on channel `session:{sessionID}` event `soundboard`; reactions: event `reaction`, payload `{ user_id, emoji, ts }`. Client-side rate limit: 1 send/sec/user (drop, don't queue). Missed events lost by design; soundboard plays persist via `chat_messages kind='soundboard_echo'` inserted by the ORIGINATING client into the session's GROUP chat (sessions without a group: no echo).
- **Voice messages:** `.m4a` (AAC 64kbps mono), 60s hard cap, path `chat-audio/{group_id}/{message_id}.m4a`, `kind='audio'` requires `storage_path`; render with duration; playback via signed URL.
- **Canvas authority** for all UI ("Comms, soundboard & the PR moment"; soundboard dock treatment in "Live Session — real-time rotation"; voice bubble + PR moment treatments). Canvas-only elements without app data → skip + list. Restyle-scope discipline: existing screens gain the new elements this plan's features create — nothing else.
- Placeholder sound assets are programmatically synthesized (script committed) — the design counterpart/user replaces them later; slugs are the stable contract.
- Branch `feature/phase-3c-comms`; PR `--base master`; standard CI loop.

## Explicitly deferred

- Live PTT/hot-mic (3e — spec committed), push notifications (3d), heart rate (P5), waveform scrubbing on voice bubbles, sound upload by users (`is_curated` stays true), reaction ANIMATIONS beyond the canvas pill treatment, session sub-thread chat.

## File Structure

```
supabase/migrations/
├── 20260715000001_comms_schema.sql          # Task 1 (soundboard_sounds, kind CHECK+policy, chat-audio bucket)
supabase/tests/comms_schema_test.sql         # Task 1
scripts/
├── gen_soundboard_assets.py                 # Task 2 (synth WAVs)
└── seed_soundboard.js                       # Task 2 (upload + rows, service key)
GymSyncApp/GymSync/
├── Services/SoundboardPlayer.swift          # Task 3 (AVAudioPlayer pool ≤8)
├── Services/SessionBroadcastService.swift   # Task 3 (broadcast send/receive + rate limit)
├── Services/VoiceRecorder.swift             # Task 5 (record + category swap/restore)
├── Services/AudioSessionManager.swift       # Task 5 (enterRecordMode/exitRecordMode added)
├── Models/ChatMessage.swift                 # Task 5 (sendVoice)
├── Features/Sessions/GroupSessionLiveView.swift  # Task 4 (soundboard dock + reaction bar + PR flair), Task 7 (PR moment)
├── Features/Social/ChatView.swift           # Task 4 (echo rendering), 5/6 (record button, voice bubble)
GymSyncApp/GymSyncTests/
├── CommsSchemaTests? (no — backend pgTAP only)
├── AudioSessionRestoreTests.swift           # Task 5 (hermetic category restore)
└── VoiceMessageTests.swift                  # Task 6 (live send/fetch round trip)
```

---

### Task 0: Branch

- [ ] `cd /g/Projects/GymSync && git checkout master && git pull --ff-only && git checkout -b feature/phase-3c-comms`

---

### Task 1: Comms schema — soundboard table, kind extensions, audio bucket

**Files:** Create `supabase/migrations/20260715000001_comms_schema.sql`; Test `supabase/tests/comms_schema_test.sql`.

**Interfaces:**
- Consumes: `chat_messages` CHECK + INSERT/UPDATE policies (latest versions live in `20260711000002_storage_buckets.sql` — READ it; copy-with-delta fix-forward), `is_group_member`, storage policy patterns.
- Produces:
  - `public.soundboard_sounds(id uuid PK default, slug text UNIQUE NOT NULL, display_name text, storage_path text NOT NULL, duration_ms int, is_curated bool default true)` — RLS: global SELECT (authenticated), NO client writes (seeded via service role).
  - `chat_messages.kind` CHECK gains `'audio'` (already includes soundboard_echo): constraint must be dropped/re-added (`ALTER TABLE ... DROP CONSTRAINT <find name via \d or pg_constraint>` — implementer queries `pg_constraint` for the actual CHECK name, then re-adds with the full list + 'audio').
  - INSERT policy recreated: client kinds allowed = `('text','image','audio','soundboard_echo')`; `audio` AND `image` require storage_path; `soundboard_echo` requires payload (sound_slug inside). UPDATE policy recreated to match kinds list (soft-delete parity).
  - Buckets: `chat-audio` (private) with the member-path INSERT/SELECT policies (mirror chat-images, folder = group id); `soundboard` (public) read-all.
- pgTAP: member sends audio kind w/ storage_path (lives_ok); audio without storage_path rejected (42501); member inserts soundboard_echo w/ payload (lives_ok); outsider audio rejected (42501); soundboard_sounds readable (seed a row as superuser) + client INSERT rejected (42501); chat-audio outsider upload rejected (42501); member upload allowed. RECOUNT plan(N). Full suite green (Phase 2 chat tests must survive the policy recreation).
- Commit `feat(db): comms schema — soundboard table, audio message kind, audio buckets`.

---

### Task 2: Soundboard assets + seeding

**Files:** Create `scripts/gen_soundboard_assets.py`, `scripts/seed_soundboard.js`.

**Interfaces:** Produces 4 seeded sounds with STABLE slugs Tasks 3/4 reference: `airhorn`, `lets-go`, `ding`, `boo` — rows in `soundboard_sounds` + files in the public `soundboard` bucket.

- `gen_soundboard_assets.py` (run with the Midas venv python — has numpy? use stdlib `wave`+`math` only): synthesizes 4 short WAVs (44.1kHz 16-bit mono, ≤1.5s): airhorn = sawtooth-ish stacked square waves w/ vibrato; lets-go = two rising tones; ding = decaying sine 1568Hz; boo = descending low square. Writes to `.superpowers/soundboard/*.wav` (scratch).
- `seed_soundboard.js` (service key via .env.local, mirrors create_second_test_user.js fetch style): uploads each WAV to `soundboard/{slug}.wav`, upserts `soundboard_sounds` rows (slug, display_name, storage_path, duration_ms). Idempotent (upsert + upload upsert:true header `x-upsert: true`).
- Run both; verify via `node scripts/db_query.js "SELECT slug, storage_path FROM soundboard_sounds"` (4 rows).
- Commit `feat: soundboard placeholder assets + seeding (slugs: airhorn, lets-go, ding, boo)`.

---

### Task 3: SoundboardPlayer + SessionBroadcastService

**Files:** Create `Services/SoundboardPlayer.swift`, `Services/SessionBroadcastService.swift`.

**Interfaces (Task 4 compiles against):**
- `@MainActor final class SoundboardPlayer` (spec §6.1 pool): `func play(slug: String) async` — resolves the sound's public URL (`soundboard` bucket getPublicURL via storage_path from a cached `soundboard_sounds` fetch), downloads once into a local file cache (`URLCache`/tmp dir keyed by slug), plays via pooled `AVAudioPlayer` (≤8 concurrent, FIFO eviction). NEVER touches the audio session category (ambient config already active). `static let shared`.
- `@MainActor final class SessionBroadcastService`:
  - `subscribe(sessionID: UUID, onSoundboard: @escaping @MainActor (userID: UUID, slug: String) -> Void, onReaction: @escaping @MainActor (userID: UUID, emoji: String) -> Void) async` — supabase channel `session:{id}` (broadcast; SDK: `channel.broadcastStream(event:)` or `onBroadcast` — adapt per 2.51 API, document), self-cleaning; `unsubscribe() async`.
  - `sendSound(sessionID: UUID, slug: String) async` / `sendReaction(sessionID: UUID, emoji: String) async` — broadcast with the spec wire shapes; CLIENT RATE LIMIT: drop sends within 1s of the previous send (shared per-service timestamp).
  - Sound echo: `sendSound` ALSO inserts `chat_messages` `kind='soundboard_echo'`, `body: "🔊 {display name}"`, `payload: {sound_slug}` into the session's group chat WHEN the session has a groupID (caller passes groupID: UUID?).
- No XCTests (broadcast needs 2 live clients) — CI compile; device QA.
- Commit `feat: soundboard player pool + session broadcast service`.

---

### Task 4: In-session comms UI — soundboard dock + reactions + echo rendering

**Files:** Modify `Features/Sessions/GroupSessionLiveView.swift`, `Features/Social/ChatView.swift`.

**Interfaces:** Consumes Task 3 services + canvas: "Live Session — real-time rotation" (soundboard dock treatment — the `gs-dock-scroll` strip) + "Comms, soundboard & the PR moment" (tiles, reaction pills).

Contract:
- GroupSessionLiveView: bottom dock per canvas — horizontally scrolling sound tiles (the 4 slugs w/ display names, GS-styled) + a reaction strip (🔥💪😂👏). Tap sound → `SoundboardPlayer.play(slug:)` locally + `sendSound(...)`; incoming `onSoundboard` → play + transient "{name} 🔊 airhorn" overlay line; reactions → transient floating overlay (canvas pill treatment; simple opacity/offset animation, 2s). Wire subscribe/unsubscribe into the existing lifecycle (.task/.onDisappear alongside SessionLiveService).
- ChatView: render `kind == .soundboardEcho` messages per canvas (system-ish row with 🔊 + body; payload sound_slug tappable → SoundboardPlayer.play — replay from history).
- HARD RULE: zero behavioral drift elsewhere; canvas-only extras skipped + listed.
- Commit `feat: in-session soundboard dock, reactions, chat echoes`.

---

### Task 5: Voice recording — category swap + send path

**Files:** Create `Services/VoiceRecorder.swift`; Modify `Services/AudioSessionManager.swift`, `Models/ChatMessage.swift`; Test `GymSyncTests/AudioSessionRestoreTests.swift`.

**Interfaces (Task 6 compiles against):**
- `AudioSessionManager`: add `func enterRecordMode() throws` (`.playAndRecord`, mode `.default`, options `[.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]`, setActive) and `func exitRecordMode()` (restore EXACTLY `configure()`'s state: `.ambient + [.mixWithOthers]`, best-effort, never throws out). `configure()` itself UNTOUCHED (regression test file untouched).
- `@MainActor final class VoiceRecorder`: `startRecording() async throws` (mic permission via `AVAudioApplication.requestRecordPermission` — iOS 17 API; denial → `.validation("Microphone access needed for voice messages")`; enterRecordMode; AVAudioRecorder AAC 64k mono to tmp URL; 60s auto-stop), `stopRecording() -> (url: URL, duration: TimeInterval)?` (stop, exitRecordMode ALWAYS — defer), `cancelRecording()` (stop+delete+restore). Duration from recorder.currentTime at stop.
- `ChatRepository.sendVoice(groupID: UUID, fileURL: URL, duration: TimeInterval) async throws -> ChatMessage`: client message UUID; upload Data to `chat-audio/{group}/{id}.m4a` (StorageService gains `uploadChatAudio(groupID:messageID:data:) -> String` + `signedChatAudioURL(path:)` — mirror the image pair); insert `kind='audio'`, storage_path, `payload: {duration_seconds}` — wait: payload isn't decoded... store duration in `body` as e.g. `"0:42"` prerendered AND payload jsonb for future; body is the simple contract Task 6 renders.
- `project.yml`: `NSMicrophoneUsageDescription` ("Gym Sync uses your microphone to record voice messages for your crew.").
- Tests: `AudioSessionRestoreTests` (hermetic on simulator): `enterRecordMode()` then `exitRecordMode()` → `AVAudioSession.sharedInstance().category == .ambient && categoryOptions.contains(.mixWithOthers)`; existing `AudioSessionManagerTests` MUST still pass unmodified.
- Commit `feat: voice recording — scoped category swap, m4a capture, audio send path`.

---

### Task 6: Voice bubbles in chat

**Files:** Modify `Features/Social/ChatView.swift`; Test `GymSyncTests/VoiceMessageTests.swift`.

Contract:
- Input bar gains a mic button (canvas treatment): press-and-hold to record (DragGesture/LongPress w/ onEnded; slide-away or a Cancel affordance cancels), live elapsed indicator while held; release → stop → `sendVoice`. Uses VoiceRecorder; all failure paths restore audio session (verify by code path — defer in recorder covers it).
- `messageContent` gains the `.audio` branch per canvas: play/pause button + duration label (from body) in a GS bubble; playback via a small `VoiceBubblePlayer` (AVAudioPlayer on the ambient session — mixes with music; one at a time: starting a bubble stops the previous). Signed URL resolved+cached like images (extend the existing imageURLs pattern or a parallel audioURLs dict + on-demand download to tmp before play — AVAudioPlayer needs local data; download once, cache by message id).
- Live test `VoiceMessageTests`: generate a tiny valid m4a? — hermetically synthesizing AAC is impractical; instead record via AVAudioRecorder on simulator? Mic on CI simulator is unreliable. PRAGMATIC: test `sendVoice` with a small fixture file committed at `GymSyncTests/Fixtures/test-voice.m4a` (generate once locally in Task 5 via a 1s silent AAC render using AVAudioEngine offline — implementer notes how) → upload+insert round trip: kind .audio, storage_path prefix, body duration; fetch confirms. If fixture generation proves unworkable on CI, fall back to uploading WAV bytes as the fixture (server doesn't transcode; playback correctness stays device-QA) — document choice.
- Commit `feat: voice message bubbles — hold to record, tap to play`.

---

### Task 7: The PR moment

**Files:** Modify `Features/Social/ChatView.swift`, `Features/Sessions/GroupSessionLiveView.swift`.

Contract (canvas "the PR moment" treatment):
- ChatView: `system_pr` messages get the canvas celebration card (accent border/fill, 🔥 kicker, bigger type) replacing the current modest styling.
- GroupSessionLiveView: when an incoming `onSetLogged` set is followed by a system_pr for that user... simpler reliable trigger: subscribe nothing new — when the live feed inserts a set and the existing PR toast logic (solo path parity — READ how WorkoutSessionView triggers its PR celebration via `is_pr`) — for group: on MY set log, reuse the same `is_pr` check the solo flow uses to fire an in-session overlay (canvas moment: full-width accent flash + "NEW PR — {exercise}" card, ~2.5s, plus SoundboardPlayer.play("ding")). Others' PRs: render a feed-row flair (🔥 PR tag) when a system_pr chat message referencing that set arrives — SKIP if plumbing absent; list as deferred if the correlation isn't cheaply available.
- Commit `feat: PR celebration moment — in-session overlay + chat card`.

---

### Task 8: Hygiene + ship

- [ ] 3b follow-ups: (a) `editDuration` gains a completed-state guard (fetch already present — add `guard existing.state == "completed"` → .validation); (b) HealthKit re-write on duration edit (after successful editDuration in CompletedSessionView, re-export via HealthKitBridge with updated interval — READ the solo export call; note: naive re-export duplicates the workout entry; if HealthKitBridge lacks delete/update, ADD export with the edited dates only when no prior export is detectable — pragmatic: document limitation, implement the re-export, accept possible duplicate with a code comment; QA verifies).
- [ ] `node scripts/run_pgtap.js` ALL PASSED; CI green.
- [ ] PR `--base master` "Phase 3c: Soundboard, voice messages & the PR moment"; merge per user; TestFlight.
- [ ] Device QA (user + scripted ci_test_user_2 + browser LiveKit N/A here): soundboard tap → plays locally + on second client (needs second live app instance — controller CANNOT broadcast-receive via REST; soundboard cross-device is user+friend QA or deferred observation via chat echoes); voice message record→send→playback both directions (controller can INSERT an audio message via script with an uploaded fixture); Spotify mixing matrix (spec §6.1): music keeps playing during soundboard, during voice PLAYBACK; music ducks only during RECORDING hold; PR moment fires on a new max.

---

## Self-Review Notes

- kind CHECK constraint name discovery via pg_constraint documented in Task 1 (constraint was inline/unnamed — actual name like chat_messages_kind_check).
- soundboard_echo client-insert is spec-mandated (unlike system_*) — policy change is deliberate and pgTAP'd.
- Broadcast API drift risk acknowledged (2.51 broadcastStream naming) — Task 3 adapts, behavior contract fixed.
- Voice fixture strategy has a documented fallback; playback fidelity is device-QA regardless.
- Audio category swap isolated to VoiceRecorder with defer-restore; two-test guard (existing untouched + new restore test).
- Canvas-authority + restyle-discipline rules carried from the design plan.
