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

    /// Redesign foundation — user-selectable accent: a `GSAccents` preset id
    /// ('sky'|'violet'|'amber'|'lime'|'coral'|'rose'|'mono') or a '#rrggbb'
    /// custom hex (`supabase/migrations/20260728000007_user_settings_accent_and_onyx.sql`).
    /// Declared LAST with a default for the exact memberwise-init reason
    /// `shareHeartRate` documents above, and mirroring the column's own 'sky'
    /// default. A future 5th field extends this same trailing pattern.
    var accent: String = "sky"

    /// Display/entry unit — 'lbs' or 'kg'
    /// (`supabase/migrations/20260730000001_units_and_bar_inventory.sql`).
    /// STORED WEIGHTS REMAIN POUNDS everywhere; this only changes what the
    /// UI shows and how typed entry is parsed (see Models/Units.swift).
    /// Trailing default, for the exact memberwise-init reason the two
    /// properties above document.
    var unitSystem: String = "lbs"

    /// Bar weight in POUNDS regardless of `unitSystem` — same canonical
    /// storage rule as every other weight. Trailing default.
    var barWeightLbs: Decimal = 45

    /// Plate denominations in the USER'S unit; `nil` means "the standard
    /// set for my unit" (meaningfully different from an empty array, which
    /// would mean "I own no plates"). Trailing default.
    var plateInventory: [Decimal]? = nil

    /// Getting-started lift anchors (`20260812000002`): confident 5-rep
    /// weights by exercise SLUG (back-squat / bench-press / deadlift / ohp),
    /// in CANONICAL POUNDS. Seed starting-weight suggestions only —
    /// `WorkingWeight`'s `.seeded` rung, which any real logged set outranks;
    /// never set_logs, PR math, or volume. `nil` = the onboarding step was
    /// skipped or predates this column. Trailing default, per the
    /// memberwise-init trap the properties above document.
    var liftAnchors: [String: Decimal]? = nil

    /// Parsed `unitSystem`, falling back to lbs for any unexpected value —
    /// a bad string must never crash a weight display.
    var weightUnit: WeightUnit { WeightUnit(rawValue: unitSystem) ?? .lbs }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case defaultRestSeconds = "default_rest_seconds"
        case palette
        case updatedAt = "updated_at"
        case shareHeartRate = "share_heart_rate"
        case accent
        case unitSystem = "unit_system"
        case barWeightLbs = "bar_weight_lbs"
        case plateInventory = "plate_inventory"
        case liftAnchors = "lift_anchors"
    }

    /// Mirrors the table's own column defaults exactly (migrations:
    /// `default_rest_seconds int NOT NULL DEFAULT 120`; `palette text NOT NULL
    /// DEFAULT 'onyx'` and `accent text NOT NULL DEFAULT 'sky'` after
    /// 20260728000007; `share_heart_rate boolean NOT NULL DEFAULT false`) —
    /// used both by `UserSettingsRepository.get()` when no row exists yet, and
    /// as the in-memory fallback value the You tab and solo workout screen read
    /// before their own `.task` resolves.
    static func defaults(userID: UUID) -> UserSettings {
        UserSettings(userID: userID, defaultRestSeconds: 120, palette: "onyx", updatedAt: Date(), shareHeartRate: false, accent: "sky")
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
    /// Redesign foundation — MUST stay in lockstep with `UserSettings.accent`,
    /// same "any field absent here silently never persists" trap the
    /// `shareHeartRate` comment above documents.
    let accent: String
    /// Units + bar/plate inventory — same lockstep rule as every field
    /// above. Omitting any of these would make the You-tab unit toggle and
    /// the bar-loader settings look like they work (optimistic local flip,
    /// no error) while never persisting.
    let unitSystem: String
    let barWeightLbs: Decimal
    let plateInventory: [Decimal]?
    /// Lift anchors — same lockstep rule as every field above; omitting it
    /// would make the onboarding step look like it saved while never
    /// persisting.
    let liftAnchors: [String: Decimal]?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case defaultRestSeconds = "default_rest_seconds"
        case palette
        case shareHeartRate = "share_heart_rate"
        case accent
        case unitSystem = "unit_system"
        case barWeightLbs = "bar_weight_lbs"
        case plateInventory = "plate_inventory"
        case liftAnchors = "lift_anchors"
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
                    shareHeartRate: settings.shareHeartRate,
                    accent: settings.accent,
                    unitSystem: settings.unitSystem,
                    barWeightLbs: settings.barWeightLbs,
                    plateInventory: settings.plateInventory,
                    liftAnchors: settings.liftAnchors
                ))
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
