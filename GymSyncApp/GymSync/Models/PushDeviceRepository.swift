import Foundation
import Supabase

// MARK: - PushDevice

struct PushDevice: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let apnsToken: String
    let lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case apnsToken = "apns_token"
        case lastSeenAt = "last_seen_at"
    }
}

enum PushDeviceRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Hex-encodes a raw APNs device token `Data` (the wire format
    /// UIApplicationDelegate hands back from
    /// `didRegisterForRemoteNotificationsWithDeviceToken`) — lowercase, no
    /// separators, Apple's own documented convention for turning the token
    /// into the string form APNs' server APIs expect.
    static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Registers (or reassigns) the current device's token, keyed on
    /// `apns_token` — a token rotation/reinstall naturally produces a fresh
    /// row rather than colliding with a stale one for the same physical
    /// device. `last_seen_at` refreshes on every call so push-dispatcher's
    /// dead-token cleanup (410/BadDeviceToken → delete) has a live signal to
    /// contrast against, though that cleanup doesn't currently read it.
    ///
    /// Delegates to the `register_push_device` RPC
    /// (20260716000007_register_push_device.sql) rather than a client-side
    /// `.upsert(onConflict:)` — a same-device, different-user re-registration
    /// (sign out, sign in as someone else) needs its `ON CONFLICT DO UPDATE`
    /// branch to reassign a row currently owned by someone ELSE, which the
    /// owner-only RLS policy silently blocks for a plain client upsert. The
    /// RPC is SECURITY DEFINER and pins `user_id = auth.uid()` on both
    /// branches, so it can reassign ownership regardless of who currently
    /// holds the row.
    static func upsert(token: Data) async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .rpc("register_push_device", params: ["p_token": hexEncode(token)])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Deletes every device row owned by the current user. Called from
    /// AuthService.signOut() BEFORE the Supabase session itself is torn down
    /// — `push_devices`' owner-only RLS policy needs an authenticated
    /// `auth.uid()` to match, which is gone the instant `client.auth.signOut()`
    /// completes.
    static func deleteOwnDevices() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else { return }
        do {
            try await client
                .from("push_devices")
                .delete()
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}

// MARK: - NotificationPref

struct NotificationPref: Codable, Sendable {
    let userID: UUID
    let category: String
    let enabled: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case category
        case enabled
        case updatedAt = "updated_at"
    }
}

private struct NotificationPrefUpsert: Encodable {
    let userID: UUID
    let category: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case category
        case enabled
    }
}

enum NotificationPrefsRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// The 10 per-category opt-out toggles, per `notification_prefs`' CHECK
    /// constraint (20260716000001_push_schema.sql) — mirrors the designer
    /// brief's Feature 2 list. `session_idle` covers both
    /// session_idle_30min and session_idle_60min (one toggle for the ladder,
    /// per push_event_category()'s server-side mapping).
    static let categories = [
        "friend_request", "session_invite", "session_reminder_15min",
        "session_lobby_open", "your_turn", "partner_pr", "lateness_chirp",
        "session_idle", "chat_mention", "leaderboard_passed",
    ]

    /// Absence of a row means enabled (spec: "Defaults: all on for v1") —
    /// mirrors enqueue_push's own absence-means-on gate server-side, so a
    /// client-side "is this on?" check never has to special-case the
    /// no-row state as anything other than `true`.
    static func isEnabled(category: String) async throws -> Bool {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [NotificationPref] = try await client
                .from("notification_prefs")
                .select()
                .eq("user_id", value: userID.uuidString)
                .eq("category", value: category)
                .execute()
                .value
            return rows.first?.enabled ?? true
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Upserts on the table's own primary key `(user_id, category)` — no
    /// explicit `onConflict` needed (PostgREST defaults to the primary key,
    /// same convention already used by `chat_read_state`'s upsert in
    /// ChatMessage.swift).
    static func setEnabled(_ enabled: Bool, category: String) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("notification_prefs")
                .upsert(NotificationPrefUpsert(userID: userID, category: category, enabled: enabled))
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Deletes the stored row for a category, reverting it to the default
    /// (enabled) — backs a "reset to default" action and proves the
    /// delete → default-true round trip in tests.
    static func reset(category: String) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("notification_prefs")
                .delete()
                .eq("user_id", value: userID.uuidString)
                .eq("category", value: category)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
