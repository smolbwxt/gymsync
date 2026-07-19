import Foundation
import Supabase

/// One row per user: default rest-timer duration + active palette
/// (`supabase/migrations/20260717000001_user_settings.sql`). Backs the You
/// tab's Settings Hub (Appearance / Default rest timer rows) and the solo
/// workout screen's rest-timer fallback.
struct UserSettings: Codable, Sendable, Equatable {
    let userID: UUID
    var defaultRestSeconds: Int
    var palette: String
    var updatedAt: Date
    /// Phase W Task 4 (watch-hr design §4) — opt-in HR broadcast toggle,
    /// `supabase/migrations/20260727000001_user_settings_share_heart_rate.sql`.
    /// Declared LAST with a default value deliberately: Swift's synthesized
    /// memberwise initializer gives a trailing defaulted property a
    /// defaulted PARAMETER too, so every pre-existing `UserSettings(userID:
    /// defaultRestSeconds:palette:updatedAt:)` call site in this codebase
    /// (`UserSettings.defaults(userID:)` below, `ThemeStoreMergeTests`,
    /// `UserSettingsRepositoryTests`) keeps compiling unchanged, with
    /// `shareHeartRate` defaulting to `false` — the same opt-out-safe
    /// default the column itself has. Inserting this property earlier in
    /// the list (or before an existing one) would break every positional-
    /// labeled call site above; this is the memberwise-init trap this
    /// comment exists to warn future edits away from.
    var shareHeartRate: Bool = false

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case defaultRestSeconds = "default_rest_seconds"
        case palette
        case updatedAt = "updated_at"
        case shareHeartRate = "share_heart_rate"
    }

    /// Mirrors the table's own column defaults exactly (migration:
    /// `default_rest_seconds int NOT NULL DEFAULT 120`, `palette text NOT
    /// NULL DEFAULT 'midnight'`, `share_heart_rate boolean NOT NULL DEFAULT
    /// false`) — used both by `UserSettingsRepository.get()`
    /// when no row exists yet, and as the in-memory fallback value the You
    /// tab and solo workout screen read before their own `.task` resolves.
    static func defaults(userID: UUID) -> UserSettings {
        UserSettings(userID: userID, defaultRestSeconds: 120, palette: "midnight", updatedAt: Date(), shareHeartRate: false)
    }

    /// "m:ss" — e.g. 125 -> "2:05". Shared by the Settings Hub's "Default rest
    /// timer" value preview and `RestTimerSettingView`'s preset row labels
    /// (kept as one formatter rather than duplicating the `%d:%02d` pattern
    /// across both call sites).
    static func formatRestSeconds(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct UserSettingsUpsert: Encodable {
    let userID: UUID
    let defaultRestSeconds: Int
    let palette: String
    /// Phase W Task 4 addition — MUST stay in lockstep with `UserSettings
    /// .shareHeartRate` above. This struct is the exact bug class
    /// `20260726000006_user_settings_touch_updated_at.sql`'s own header
    /// comment documents for `updated_at` ("the client write path... upserts
    /// a Row that encodes only {user_id, default_rest_seconds, palette}...
    /// so the upsert only ever touches those fields, never updated_at"): any
    /// field present on `UserSettings` but ABSENT from this struct silently
    /// never reaches the database on write, no matter what the in-memory
    /// value says. Omitting `shareHeartRate` here would make
    /// `heartRateShareRow`'s toggle in `YouTabView` a complete no-op that
    /// looks like it works (optimistic local flip succeeds, no error) but
    /// never actually persists.
    let shareHeartRate: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case defaultRestSeconds = "default_rest_seconds"
        case palette
        case shareHeartRate = "share_heart_rate"
    }
}

enum UserSettingsRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Absence of a row means the column defaults apply (same
    /// absence-means-default convention as `NotificationPrefsRepository
    /// .isEnabled`) — returns `UserSettings.defaults(userID:)` rather than
    /// throwing/nil, so every call site can treat this as "the effective
    /// settings" without a bootstrap-row-on-signup step.
    static func get() async throws -> UserSettings {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [UserSettings] = try await client
                .from("user_settings")
                .select()
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
            return rows.first ?? UserSettings.defaults(userID: userID)
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Upserts on the table's own primary key (`user_id`) — no explicit
    /// `onConflict` needed, same convention as `NotificationPrefsRepository
    /// .setEnabled`.
    static func upsert(_ settings: UserSettings) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("user_settings")
                .upsert(UserSettingsUpsert(
                    userID: userID,
                    defaultRestSeconds: settings.defaultRestSeconds,
                    palette: settings.palette,
                    shareHeartRate: settings.shareHeartRate
                ))
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
