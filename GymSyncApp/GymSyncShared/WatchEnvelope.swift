import Foundation

// MARK: - WatchEnvelope
//
// Phase W Task 2 (watch-hr design §3, "Explicit versioned message schema —
// a small Codable envelope — future-proof"). SHARED file — compiled into
// BOTH the `GymSync` (iOS) and `GymSyncWatch` (watchOS) targets via
// `GymSyncApp/project.yml`'s `GymSyncShared` sources entry on each target
// (see that file's comment for the shared-membership mechanism chosen).
// Since the same file compiles into two SEPARATE modules, everything here
// stays default `internal` access — no `public` needed, matching every
// other type in this codebase (GSWatchTheme.swift is the one file that
// uses `public`, but nothing here needs cross-module reach beyond "visible
// to the rest of its own compiling target," which internal already gives).
//
// SHAPE CHOICE (task brief's explicit judgment call — `{v, kind, payload}`
// shell vs. a `kind`-discriminated enum with associated Codable payloads):
// picked the SHELL. A Swift `enum WatchMessage { case logSet(WatchLogSetPayload), ... }`
// would be more idiomatic Swift, but it couples decoding to knowing every
// case up front — a message whose `kind` this build doesn't recognize
// (an OLDER phone talking to a NEWER watch that added a case, or vice
// versa, exactly the skew this phase's own CI reality invites: phone and
// watch ship in the SAME app bundle today, but nothing prevents that from
// changing, and even within one release, `updateApplicationContext`'s
// "latest wins" cache can hand a JUST-LAUNCHED watch a stored context from
// a prior version) would fail Decodable entirely, taking the WHOLE envelope
// down with it. The shell keeps `payload` as raw `Data`, decoded into a
// concrete per-kind struct only ON DEMAND (`decodePayload(as:)`) once the
// caller has already switched on a RECOGNIZED `kind` string — an unknown
// `kind` still decodes the shell fine (`decodedKind()` just returns `nil`),
// so the caller can log-and-ignore ONE malformed/future message instead of
// the whole channel throwing. This is the "unknown-kind tolerance" the
// brief asks for, and it's cheap: `WatchMessageKind` stays a plain
// `RawRepresentable` `String` enum, no custom `Decodable` witness needed.

/// The 4 message kinds this phase needs (design §3's plumbing + the T5 HR
/// broadcast this schema is defined ahead of — "define now, implement
/// senders progressively" per the task brief). `sessionState` is
/// phone→watch (pushed via `WCSession.updateApplicationContext`, latest-
/// wins); `logSet`/`soundboardTap` are watch→phone (`sendMessage`,
/// expects a `WatchActionReply`); `hrSample` is watch→phone (T5 — sender
/// not implemented until that task, per the design doc's HR broadcast
/// component).
enum WatchMessageKind: String, Codable, Sendable, Equatable {
    case sessionState
    case logSet
    case soundboardTap
    case hrSample
    /// Task 3 addition (watch-hr design §2, "Idle state"). phone→watch,
    /// `updateApplicationContext` — mutually exclusive with `sessionState`
    /// on the wire since `updateApplicationContext` replaces the ENTIRE
    /// current context on each call (Apple's documented "latest wins": one
    /// active context total, not one per kind). See `WatchIdleStatePayload`'s
    /// doc comment and `WatchSessionStore`'s `didReceiveApplicationContext`
    /// for how the watch keeps the two states from colliding.
    case idleState
}

/// Versioned envelope shell. `v` versions the SHELL itself (this struct's
/// own 3 fields), NOT the per-kind payload shape — a payload's own fields
/// can evolve additively (new optional field) without bumping `v` at all,
/// since `Decodable` already tolerates unknown/missing optional keys.
/// `v` only needs to move if the SHELL shape changes in a way an older
/// decoder couldn't parse structurally (e.g. `payload` stops being a
/// single `Data` blob). Kept deliberately unglamorous: no custom
/// `init(from:)`/`encode(to:)` — the synthesized Codable conformance over
/// `Int`/`String`/`Data` is exactly the wire format wanted.
struct WatchEnvelope: Codable, Sendable, Equatable {
    /// The shell version THIS type currently produces.
    static let currentVersion = 1
    /// The highest shell version THIS BUILD knows how to interpret safely.
    /// Deliberately a SEPARATE constant from `currentVersion` (even though
    /// they're equal today) — `currentVersion` is "what I emit,"
    /// `maxSupportedVersion` is "what I'll accept from a peer." A future
    /// shell change would bump `currentVersion` immediately but might keep
    /// `maxSupportedVersion` at the OLD value for a transition window
    /// (accept both), or vice versa (a build that can READ a newer shell
    /// before it's ready to WRITE one).
    static let maxSupportedVersion = 1

    let v: Int
    let kind: String
    let payload: Data

    init(kind: WatchMessageKind, payload: Data, v: Int = WatchEnvelope.currentVersion) {
        self.v = v
        self.kind = kind.rawValue
        self.payload = payload
    }

    /// Version gate (brief's explicit "version gate" test target). `true`
    /// when this build is willing to ACT on the envelope — a `v` above
    /// `maxSupportedVersion` still decodes structurally fine (the shell
    /// hasn't changed), it's a deliberate choice not to interpret it,
    /// because a higher `v` signals the SENDER knows something about the
    /// wire format this build doesn't.
    var isSupportedVersion: Bool { v <= Self.maxSupportedVersion }

    /// Unknown-kind tolerance: `nil` for any `kind` string this build's
    /// `WatchMessageKind` enum doesn't declare — never throws, so a caller
    /// can log-and-ignore a single unrecognized message kind instead of
    /// losing the whole decode.
    func decodedKind() -> WatchMessageKind? { WatchMessageKind(rawValue: kind) }

    /// Decodes `payload` as a concrete per-kind struct. Callers are
    /// expected to check `decodedKind()`/`isSupportedVersion` FIRST — this
    /// throws (rather than returning `nil`) because by the time a caller
    /// reaches here it already knows which concrete type to expect; a
    /// throw here means the payload bytes themselves are malformed for a
    /// KNOWN kind, a genuinely different failure than "unknown kind."
    func decodePayload<T: Decodable>(as type: T.Type) throws -> T {
        try WatchWire.decoder.decode(type, from: payload)
    }

    /// Builds an envelope from a Codable payload in one step — the
    /// production senders' normal entry point (`WatchConnectivityBridge`,
    /// the Watch-side counterpart).
    static func encode<T: Encodable>(kind: WatchMessageKind, payload: T, v: Int = currentVersion) throws -> WatchEnvelope {
        WatchEnvelope(kind: kind, payload: try WatchWire.encoder.encode(payload), v: v)
    }

    /// The `[String: Any]` dictionary key both `asMessage()`/`from(message:)`
    /// use — a single-key wrapper so WCSession's dictionary is never
    /// inspected field-by-field; see `WatchWire`'s doc comment for why.
    private static let wireKey = "envelope"

    /// Encodes this envelope into the `[String: Any]` shape
    /// `WCSession.sendMessage`/`updateApplicationContext` both require.
    func asMessage() throws -> [String: Any] { try WatchWire.message(self, key: Self.wireKey) }

    /// Decodes an envelope back out of a received `[String: Any]` message.
    /// `nil` (never throws) for a dictionary that doesn't carry this app's
    /// wire key at all, or whose bytes don't even parse as the SHELL
    /// (`v`/`kind`/`payload` are the only 3 fields — this is the coarsest,
    /// cheapest possible malformed-message tolerance, distinct from the
    /// finer-grained `isSupportedVersion`/`decodedKind()` gates above,
    /// which assume the shell itself parsed).
    static func from(message: [String: Any]) -> WatchEnvelope? {
        WatchWire.decode(WatchEnvelope.self, key: wireKey, from: message)
    }
}

// MARK: - WatchWire (shared JSON <-> [String: Any] bridge)
//
// WCSession's `sendMessage`/`updateApplicationContext` are Objective-C
// bridged APIs that accept only property-list-compatible value types
// (NSString/NSNumber/NSDate/NSArray/NSDictionary/NSData) — arbitrary
// Swift `Codable` structs can't cross that boundary directly. `Data`
// (bridges to `NSData`) IS one of the supported types, so every wire type
// in this file rides as one JSON-encoded `Data` blob under a single
// dictionary key — the WCSession dictionary is just a courier; the actual
// contract lives entirely in Codable/JSON, never in per-field dictionary
// keys. Centralized here so `WatchEnvelope` and `WatchActionReply` (below)
// share one encode/decode path instead of each reinventing it.
enum WatchWire {
    /// `.iso8601` so `Date` fields (`WatchSessionStatePayload.updatedAt`,
    /// `WatchHRSamplePayload.recordedAt`) round-trip exactly — the default
    /// `JSONEncoder`/`JSONDecoder` date strategy is `.deferredToDate`
    /// (raw `TimeInterval` since a reference date), which round-trips fine
    /// too, but `.iso8601` matches `SessionBroadcastService`'s own wire
    /// convention for timestamps sent over Realtime (`"ts": .double(...)`
    /// is the ONE exception there, epoch-millis for a different, non-
    /// Codable wire path) and is human-readable in logs/captures.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func message<T: Encodable>(_ value: T, key: String) throws -> [String: Any] {
        [key: try encoder.encode(value)]
    }

    static func decode<T: Decodable>(_ type: T.Type, key: String, from message: [String: Any]) -> T? {
        guard let data = message[key] as? Data else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

// MARK: - Per-kind payloads

/// phone→watch, pushed via `WCSession.updateApplicationContext` (latest-
/// wins — no queueing, no history; a watch that reconnects after missing
/// several pushes only ever sees the MOST RECENT one, which is exactly
/// what a "current session state" concept wants). Built by
/// `GroupSessionLiveView` from its own already-fetched models (`WorkoutSession`,
/// `SessionParticipant`/`Profile` — see that view's `pushWatchSessionState()`
/// for the exact derivation and citations), not re-derived inside the
/// bridge — this app has no OTHER service that independently computes
/// "current exercise + current lifter," so the bridge accepts an
/// already-built payload rather than reimplementing that derivation as a
/// second source of truth.
struct WatchSessionStatePayload: Codable, Sendable, Equatable {
    let sessionID: UUID
    /// `nil` for a solo/ad-hoc session with no group chat — mirrors
    /// `WorkoutSession.groupID`'s own optionality (`SessionBroadcastService.
    /// sendSound`'s `groupID` parameter is optional for the identical
    /// reason: no group means no chat echo / no group-scoped concept).
    let groupID: UUID?
    let sessionName: String
    /// `nil` before routine/exercise data has finished loading, or for a
    /// session with no resolvable current exercise.
    let currentExerciseName: String?
    /// Task 3 addition (watch-hr design §2, Component "Tap-to-log-set") —
    /// the SAME `Exercise`'s id whose `.name` fills `currentExerciseName`
    /// above (`GroupSessionLiveView.currentExerciseForSheet`,
    /// `GroupSessionLiveView.swift:1675`) — needed to fill
    /// `WatchLogSetPayload.exerciseID` when the watch submits a set. `nil`
    /// under the identical conditions `currentExerciseName` is nil.
    let currentExerciseID: UUID?
    /// Display name (username) of whoever currently holds the turn — `nil`
    /// once nobody has an active turn (e.g. session ending/no participants
    /// yet resolved).
    let currentLifterName: String?
    let isMyTurn: Bool
    /// NOTE (pre-existing, Task 2): despite the name, this carries
    /// `GroupSessionLiveView.burpeesRemaining` (owed minus already-paid-
    /// this-session), not the raw `myParticipant.burpeesOwed` total — see
    /// `pushWatchSessionState()`'s call site. Kept byte-identical here; an
    /// additive Task 3 extension is not the place to rename a shipped
    /// field. `burpeesPaid` below is the field that's actually new.
    let burpeesOwed: Int
    /// Task 3 addition (watch-hr design §2, "Ledger glance") — burpee reps
    /// already logged as a penalty THIS SESSION by the current user,
    /// mirrors `GroupSessionLiveView.penaltyLogged`
    /// (`GroupSessionLiveView.swift:130`) — the same counter `burpeesOwed`
    /// above is already net of (see that field's note). Together the two
    /// give the ledger glance its "owed / paid" pair without re-deriving
    /// anything phone-side.
    let burpeesPaid: Int
    /// Task 3 addition (watch-hr design §2, "Soundboard buttons") — up to 4
    /// favorite slugs, straight from `GroupSessionLiveView.soundFavorites`
    /// (`GroupSessionLiveView.swift:69`), itself sourced from
    /// `SoundboardFavoritesRepository.get()` (`Models/Soundboard.swift:60`)
    /// — the SAME favorites list the phone's own soundboard dock ribbon
    /// renders (`dockSounds`, `GroupSessionLiveView.swift:164-168`). Empty
    /// until favorites finish loading or none are chosen.
    let soundboardFavorites: [String]
    /// Task 3 fix wave 1 (reviewer finding, IMPORTANT 2) — additive alongside
    /// `soundboardFavorites` above, NOT a replacement: `soundboardFavorites`
    /// stays the slugs the watch's TAP path sends back for playback
    /// (`SoundboardView.soundTile` -> `WatchSessionStore.tapSoundboard(slug:)`
    /// -> `WatchConnectivityBridge.handleSoundboardTap`, which resolves
    /// `payload.slug` straight into `SoundboardBroadcasting.play(slug:)` —
    /// that contract is unchanged and must stay that way). This field is the
    /// human-readable label for each of those SAME slugs, in the SAME order
    /// (`SoundboardSound.label`, `Models/Soundboard.swift:16` —
    /// `displayName ?? slug`) so the watch can render a real name instead of
    /// a raw slug like "airhorn"/"crowd-cheer" (the file header comment in
    /// `GymSyncWatch/SoundboardView.swift` used to explain why labels were
    /// judged out of scope; that reasoning is now superseded). Parallel
    /// array rather than `[(slug: String, label: String)]` or a small struct
    /// — matches `soundboardFavorites`' own plain-`[String]` wire shape
    /// exactly, so this rides the identical Codable/JSON path with no new
    /// type to define.
    let soundboardFavoriteLabels: [String]
    /// Task 3 addition — the CARRIED-IN REQUIREMENT from T2's review: "no
    /// session-ended signal exists; a Watch shows stale 'live' state for up
    /// to 90s after a session ends while the phone stays reachable."
    /// `false` exactly once, pushed from `GroupSessionLiveView.endSession()`
    /// right after `SessionRepository.complete(sessionID:)` succeeds — see
    /// that function's own comment for why THAT moment (not `.onDisappear`)
    /// is the honest hook. Defaults `true` so every pre-Task-3 call site
    /// (unchanged, never passes this argument) keeps describing a live
    /// session exactly as it always did.
    let isActive: Bool
    let updatedAt: Date
    /// Task 4 addition (watch-hr design §4) — the live `user_settings
    /// .share_heart_rate` opt-in value for the CURRENT (phone) user, pushed
    /// alongside the rest of the session snapshot so the Watch knows
    /// whether to start its `HKAnchoredObjectQuery` HR sampler for this
    /// session (T5 scope — the query itself isn't built yet; this field is
    /// defined now so T5 has something to read). Additive, default `false`
    /// — same "don't start the HR query unless explicitly told" safe
    /// default the column itself has
    /// (`supabase/migrations/20260727000001_user_settings_share_heart_rate.sql`,
    /// `DEFAULT false`).
    let shareHeartRate: Bool
    /// The set index the NEXT wrist-logged set should take.
    ///
    /// The bridge hardcoded `setIndex: 1` on every set the watch sent, so
    /// a whole session logged from the wrist collapsed onto index 1 —
    /// which BlockProgression.summarize sorts by and WorkingWeight reads
    /// through. The phone is the only side that knows how many sets exist,
    /// so it says. Optional and defaulted, like every additive field here,
    /// so a watch build that predates it still decodes.
    /// Whether the Watch should SAMPLE heart rate for this session.
    ///
    /// Split from `shareHeartRate` because the two are different acts and
    /// were sharing one switch. `shareHeartRate` is a privacy control — it
    /// is labelled "Share heart rate in live sessions ... visible to
    /// session participants" — but the Watch's sampler was gated on it,
    /// so an athlete who declined to broadcast their heart rate to a crew
    /// also could not see their OWN heart rate in a solo workout, where
    /// there is nobody to share it with and nothing is broadcast.
    ///
    /// Sampling your own heart rate onto your own screen is not a sharing
    /// act. HealthKit still asks its own permission. Broadcast stays gated
    /// on `shareHeartRate`, phone-side, exactly as before.
    ///
    /// Optional so a Watch build predating this keeps its old behaviour.
    let sampleHeartRate: Bool?
    let nextSetIndex: Int?
    /// The lifter's body weight in CANONICAL POUNDS, for bodyweight-
    /// equipment exercises. Dropped entirely on the wrist path, so a set
    /// of pull-ups logged from the watch contributed no tonnage while the
    /// identical set logged on the phone did — see SetLog.bodyWeightLbs,
    /// which exists precisely because "last month's pull-ups were done at
    /// last month's body weight".
    let bodyWeightLbs: Decimal?

    init(
        sessionID: UUID,
        groupID: UUID?,
        sessionName: String,
        currentExerciseName: String?,
        currentExerciseID: UUID? = nil,
        currentLifterName: String?,
        isMyTurn: Bool,
        burpeesOwed: Int,
        burpeesPaid: Int = 0,
        soundboardFavorites: [String] = [],
        soundboardFavoriteLabels: [String] = [],
        isActive: Bool = true,
        shareHeartRate: Bool = false,
        sampleHeartRate: Bool? = nil,
        nextSetIndex: Int? = nil,
        bodyWeightLbs: Decimal? = nil,
        updatedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.groupID = groupID
        self.sessionName = sessionName
        self.currentExerciseName = currentExerciseName
        self.currentExerciseID = currentExerciseID
        self.currentLifterName = currentLifterName
        self.isMyTurn = isMyTurn
        self.burpeesOwed = burpeesOwed
        self.burpeesPaid = burpeesPaid
        self.soundboardFavorites = soundboardFavorites
        self.soundboardFavoriteLabels = soundboardFavoriteLabels
        self.isActive = isActive
        self.shareHeartRate = shareHeartRate
        self.sampleHeartRate = sampleHeartRate
        self.nextSetIndex = nextSetIndex
        self.bodyWeightLbs = bodyWeightLbs
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID, groupID, sessionName, currentExerciseName, currentExerciseID
        case currentLifterName, isMyTurn, burpeesOwed, burpeesPaid, soundboardFavorites
        case soundboardFavoriteLabels, isActive, shareHeartRate, updatedAt
        case nextSetIndex, bodyWeightLbs, sampleHeartRate
    }

    /// Custom decode (Task 3, extended fix wave 1) — same "schema-lag" shape
    /// as `WorkoutSession.init(from:)` (`Models/Session.swift:44-60`; that
    /// struct's own comment: "older rows always carry it... custom init
    /// guards against any schema-lag"). Here the lag isn't a DB migration,
    /// it's a Watch/phone version skew: `updateApplicationContext` is
    /// "latest wins" with no queueing (this file's own header doc comment),
    /// so a just-relaunched watch could be handed a stored context encoded
    /// by an OLDER build that predates this task's fields.
    /// `decodeIfPresent(...) ?? default` on each of them lets that decode
    /// succeed instead of throwing and losing the WHOLE payload — proven by
    /// `WatchEnvelopeTests.testSessionStatePayloadDecodesOldShapeMissingTask3Fields`.
    /// The 6 original Task-2 fields stay plain `decode` (required) —
    /// unchanged, no reason to weaken them. `encode(to:)` stays
    /// COMPILER-SYNTHESIZED (not written here) — only decode needs the
    /// leniency, matching `WorkoutSession`'s identical split.
    ///
    /// `soundboardFavoriteLabels` (fix wave 1, IMPORTANT 2) falls back to
    /// `soundboardFavorites` itself — not `[]` — when its own key is absent:
    /// a build one version behind this fix (Task-3-wave-0, which already
    /// sends `soundboardFavorites` but not yet this field) still gives the
    /// watch something readable to render rather than blank tiles; a build
    /// two versions behind (pre-Task-3, missing both) still degrades
    /// correctly since `soundboardFavorites` itself has already resolved to
    /// `[]` by the time this line runs.
    ///
    /// `shareHeartRate` (Task 4) follows the SAME `decodeIfPresent(...) ??
    /// default` shape as `isActive` immediately above it — falls back to
    /// `false`, the column's own safe default, for any pre-Task-4 stored
    /// context or older-build sender. Proven by
    /// `WatchEnvelopeTests.testSessionStatePayloadFallsBackToShareHeartRateFalseWhenKeyAbsent`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        sessionName = try c.decode(String.self, forKey: .sessionName)
        currentExerciseName = try c.decodeIfPresent(String.self, forKey: .currentExerciseName)
        currentExerciseID = try? c.decodeIfPresent(UUID.self, forKey: .currentExerciseID)
        currentLifterName = try c.decodeIfPresent(String.self, forKey: .currentLifterName)
        isMyTurn = try c.decode(Bool.self, forKey: .isMyTurn)
        burpeesOwed = try c.decode(Int.self, forKey: .burpeesOwed)
        burpeesPaid = (try? c.decodeIfPresent(Int.self, forKey: .burpeesPaid)) ?? 0
        soundboardFavorites = (try? c.decodeIfPresent([String].self, forKey: .soundboardFavorites)) ?? []
        soundboardFavoriteLabels = (try? c.decodeIfPresent([String].self, forKey: .soundboardFavoriteLabels)) ?? soundboardFavorites
        isActive = (try? c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? true
        shareHeartRate = (try? c.decodeIfPresent(Bool.self, forKey: .shareHeartRate)) ?? false
        // 2026-08-26 additions. Same decodeIfPresent shape as everything
        // above, and all three stay OPTIONAL rather than falling back to a
        // value: nil means "the sender predates this field", which each
        // reader handles for itself — the watch falls back to
        // shareHeartRate for sampling, and the bridge falls back to
        // setIndex 1. A default here would erase that distinction.
        sampleHeartRate = try? c.decodeIfPresent(Bool.self, forKey: .sampleHeartRate)
        nextSetIndex = try? c.decodeIfPresent(Int.self, forKey: .nextSetIndex)
        bodyWeightLbs = try? c.decodeIfPresent(Decimal.self, forKey: .bodyWeightLbs)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// phone→watch (Task 3, watch-hr design §2 "Idle state") — pushed via
/// `updateApplicationContext` the SAME way `WatchSessionStatePayload` is,
/// but only when NO live session exists to describe (see
/// `WatchConnectivityBridge.updateIdleState` / `HomeView`'s push site for
/// the honest, minimal trigger chosen — app foreground on the Home screen,
/// piggybacking that screen's own existing `upcoming()` fetch rather than
/// building a scheduling-sync subsystem). Mutually exclusive with
/// `WatchSessionStatePayload` on the wire — see `WatchMessageKind.idleState`'s
/// doc comment for why — and `WatchSessionStore` clears whichever one it
/// ISN'T currently holding on each new arrival.
struct WatchIdleStatePayload: Codable, Sendable, Equatable {
    /// `nil` when there's no upcoming session at all — the watch renders
    /// "No session" in that case. Always set together with `nextSessionAt`
    /// from the same `WorkoutSession` row (`HomeView`'s push site), so the
    /// two are never meaningfully out of sync with each other.
    let nextSessionName: String?
    let nextSessionAt: Date?
    let updatedAt: Date

    init(nextSessionName: String?, nextSessionAt: Date?, updatedAt: Date = Date()) {
        self.nextSessionName = nextSessionName
        self.nextSessionAt = nextSessionAt
        self.updatedAt = updatedAt
    }
}

/// watch→phone, `sendMessage` with a reply expected (`WatchActionReply`).
/// Deliberately NOT the full `SetLog` model (`GymSync/Models/SetLog.swift`)
/// — that type lives in the iOS-only `GymSync` target (Supabase-shaped
/// `CodingKeys`, not meant for cross-target/cross-platform reuse) and
/// carries fields (`id`, `userID`, `sessionID`, `setIndex`) that are the
/// PHONE's responsibility to fill in from context the watch doesn't have
/// (current signed-in user, current session) — see
/// `WatchConnectivityBridge.handleLogSet` for exactly how those get filled.
struct WatchLogSetPayload: Codable, Sendable, Equatable {
    let exerciseID: UUID
    let reps: Int?
    let weight: Decimal?
    let rpe: Decimal?
    let isFailed: Bool
    let note: String?

    init(exerciseID: UUID, reps: Int?, weight: Decimal?, rpe: Decimal?, isFailed: Bool, note: String?) {
        self.exerciseID = exerciseID
        self.reps = reps
        self.weight = weight
        self.rpe = rpe
        self.isFailed = isFailed
        self.note = note
    }
}

/// watch→phone, `sendMessage` with a reply expected.
struct WatchSoundboardTapPayload: Codable, Sendable, Equatable {
    let slug: String
    init(slug: String) { self.slug = slug }
}

/// watch→phone (T5 — HR broadcast). LIVE since 95dd7a3/f61a337: the sender
/// is `HeartRateSampler.send` (watch, fire-and-forget sendMessage) and the
/// phone-side handler is `WatchConnectivityBridge.handleHRSample` (relays
/// to `HeartRateBroadcastService.publish` behind the live opt-in gate).
/// `bpm`/`recordedAt` match the
/// design doc §6.5 wire shape's `{user_id, bpm, zone?}` Realtime payload
/// minus `user_id`/`zone` — those are added phone-side (the phone knows
/// the signed-in user; zone is a derived display concern computed from
/// bpm + the viewer's own age/max-HR, not carried over the wire per the
/// design doc's own phrasing, "zones per the spec's formula... record the
/// choice" — a T5 concern, not this one).
struct WatchHRSamplePayload: Codable, Sendable, Equatable {
    let bpm: Int
    let recordedAt: Date
    init(bpm: Int, recordedAt: Date) {
        self.bpm = bpm
        self.recordedAt = recordedAt
    }
}

// MARK: - WatchActionReply
//
// Reply shape for BOTH `logSet` and `soundboardTap` (`sendMessage`'s reply
// dictionary) — one shared type rather than a per-action reply struct,
// since both actions reduce to the same 3-outcome shape the task brief
// names verbatim ("reply with success/queued/failure"). `soundboardTap`
// never actually produces `.queued` (there's no offline queue for sounds —
// see `WatchConnectivityBridge.handleSoundboardTap`), but reusing one type
// costs nothing and keeps the watch-side reply-handling code (T3+) a
// single switch instead of two near-identical ones. Rides the SAME
// `WatchWire` single-key-`Data` bridge as `WatchEnvelope` — deliberately
// NOT wrapped in a `WatchEnvelope` itself: a reply is a synchronous,
// single-round-trip response tied 1:1 to the request that produced it, not
// a stored/forwarded/cross-version message that needs the envelope's own
// version-gate/unknown-kind tolerance.
struct WatchActionReply: Codable, Sendable, Equatable {
    enum Outcome: String, Codable, Sendable, Equatable {
        case success
        case queued
        case failure
    }

    let outcome: Outcome
    let message: String?

    init(outcome: Outcome, message: String? = nil) {
        self.outcome = outcome
        self.message = message
    }

    private static let wireKey = "reply"

    func asMessage() throws -> [String: Any] { try WatchWire.message(self, key: Self.wireKey) }

    static func from(message: [String: Any]) -> WatchActionReply? {
        WatchWire.decode(WatchActionReply.self, key: wireKey, from: message)
    }
}
