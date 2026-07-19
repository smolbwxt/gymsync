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
    /// Display name (username) of whoever currently holds the turn — `nil`
    /// once nobody has an active turn (e.g. session ending/no participants
    /// yet resolved).
    let currentLifterName: String?
    let isMyTurn: Bool
    let burpeesOwed: Int
    let updatedAt: Date

    init(
        sessionID: UUID,
        groupID: UUID?,
        sessionName: String,
        currentExerciseName: String?,
        currentLifterName: String?,
        isMyTurn: Bool,
        burpeesOwed: Int,
        updatedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.groupID = groupID
        self.sessionName = sessionName
        self.currentExerciseName = currentExerciseName
        self.currentLifterName = currentLifterName
        self.isMyTurn = isMyTurn
        self.burpeesOwed = burpeesOwed
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

/// watch→phone (T5 — HR broadcast). Defined now per the task brief ("define
/// now, implement senders progressively"); no sender or phone-side handler
/// exists yet — `WatchConnectivityBridge.handle(message:replyHandler:)`
/// replies `.failure` for this kind today (see that method), same
/// treatment as any other not-yet-wired kind. `bpm`/`recordedAt` match the
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
