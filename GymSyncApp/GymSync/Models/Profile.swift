import Foundation
import Supabase

struct Profile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let username: String
    let displayName: String?
    let avatarURL: URL?
    let createdAt: Date
    let lifetimeVolumeLifted: Decimal
    let isCurator: Bool
    let showSoloWorkouts: Bool
    /// Pro entitlement expiry (20260730000004) — SERVER-written only (guard
    /// trigger, same posture as is_curator); nil = never entitled. Read
    /// through `Monetization.isPro(_:)`, never directly, so the dormant-
    /// paywall flag and grandfathering live in one place.
    let proUntil: Date?
    /// Personal weekly days goal (20260811000003) — the STANDING goal (what
    /// the user last set; in effect from next week on). Client-writable on
    /// the own row via `updateWeeklySessionGoal` only.
    let weeklySessionGoal: Int
    /// Anti-goalpost pair (20260812000001, owner 2026-08-12: goal edits
    /// apply NEXT week only). When `weeklySessionGoalChangedAt` falls inside
    /// the current calendar week, `weeklySessionGoalPrev` is the goal that
    /// was in effect when the week started and governs THIS week's widget;
    /// once the week rolls over the standing goal takes effect with no
    /// write needed. Written only by `updateWeeklySessionGoal`'s snapshot
    /// logic below.
    let weeklySessionGoalPrev: Int?
    let weeklySessionGoalChangedAt: Date?
    /// Generator demographics (20260814000009) — all optional/skippable.
    /// sex feeds PHYSIOLOGY deltas only (never selection); birth year
    /// retires the HR-max 190 placeholder.
    let sex: String?
    let birthYear: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case lifetimeVolumeLifted = "lifetime_volume_lifted"
        case isCurator = "is_curator"
        case showSoloWorkouts = "show_solo_workouts"
        case proUntil = "pro_until"
        case weeklySessionGoal = "weekly_session_goal"
        case weeklySessionGoalPrev = "weekly_session_goal_prev"
        case weeklySessionGoalChangedAt = "weekly_session_goal_changed_at"
        case sex
        case birthYear = "birth_year"
    }

    // Custom decode so any pre-migration cached JSON (no is_curator/
    // show_solo_workouts key yet) still decodes safely, defaulting to false
    // — same idiom for both (show_solo_workouts follows isCurator's own
    // precedent, added here Phase M Task 4). No callers construct
    // `Profile(...)` directly (verified via grep before this change), so the
    // synthesized memberwise init is not needed elsewhere.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarURL = try c.decodeIfPresent(URL.self, forKey: .avatarURL)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lifetimeVolumeLifted = try c.decode(Decimal.self, forKey: .lifetimeVolumeLifted)
        isCurator = try c.decodeIfPresent(Bool.self, forKey: .isCurator) ?? false
        showSoloWorkouts = try c.decodeIfPresent(Bool.self, forKey: .showSoloWorkouts) ?? false
        proUntil = try c.decodeIfPresent(Date.self, forKey: .proUntil)
        // Pre-migration cached JSON defaults to the column's own DEFAULT.
        weeklySessionGoal = try c.decodeIfPresent(Int.self, forKey: .weeklySessionGoal) ?? 3
        weeklySessionGoalPrev = try c.decodeIfPresent(Int.self, forKey: .weeklySessionGoalPrev)
        weeklySessionGoalChangedAt = try c.decodeIfPresent(Date.self, forKey: .weeklySessionGoalChangedAt)
        sex = try c.decodeIfPresent(String.self, forKey: .sex)
        birthYear = try c.decodeIfPresent(Int.self, forKey: .birthYear)
    }

    /// The goal governing the CURRENT calendar week (anti-goalpost rule,
    /// owner 2026-08-12): an edit made this week doesn't apply until next
    /// week, so mid-week the week-start snapshot governs.
    var effectiveWeeklyGoal: Int {
        if let changedAt = weeklySessionGoalChangedAt,
           Calendar.current.isDate(changedAt, equalTo: .now, toGranularity: .weekOfYear),
           let prev = weeklySessionGoalPrev {
            return prev
        }
        return weeklySessionGoal
    }
}

enum ProfileRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func fetch(userID: UUID) async throws -> Profile? {
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            return profile
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil  // not found
        } catch {
            AppLogger.db.error("fetch profile failed: \(error.localizedDescription, privacy: .public)")
            throw ErrorMapping.map(error)
        }
    }

    static func create(username: String) async throws -> Profile {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= AppConfig.usernameMinLength,
              trimmed.count <= AppConfig.usernameMaxLength else {
            throw GymSyncError.validation(
                "Username must be \(AppConfig.usernameMinLength)–\(AppConfig.usernameMaxLength) characters."
            )
        }
        let inserted: Profile = try await client
            .from("profiles")
            .insert(["id": userID.uuidString, "username": trimmed])
            .select()
            .single()
            .execute()
            .value
        return inserted
    }

    static func refresh(userID: UUID) async throws -> Profile? {
        try await fetch(userID: userID)
    }

    static func usernameAvailable(_ username: String) async throws -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        let existing: [Profile] = try await client
            .from("profiles")
            .select()
            .ilike("username", pattern: trimmed)
            .limit(1)
            .execute()
            .value
        return existing.isEmpty
    }

    static func fetchByUsername(_ username: String) async throws -> Profile? {
        do {
            let row: Profile = try await SupabaseService.shared.client
                .from("profiles")
                .select()
                .ilike("username", pattern: username
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_"))
                .single()
                .execute()
                .value
            return row
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    // MARK: - Phase L Task 4: Top Lifters (global cumulative-volume board)

    /// Global "Top Lifters" leaderboard — profiles ranked by
    /// `lifetime_volume_lifted` DESC, LIMIT-ed (Phase L design §3's own
    /// honest read: "Top Lifters ranks profiles by lifetime volume — public
    /// data per profiles RLS (anyone reads public fields) — no extra opt-in
    /// needed", `docs/superpowers/specs/2026-07-18-discover-leaderboards-
    /// design.md:19`). `profiles` SELECT RLS is `USING (true)` for any
    /// authenticated user (`20260709000001_create_profiles.sql:15-18`) — a
    /// plain ordered+limited read needs no new RLS, same shape as
    /// `RoutineRepository.publicRoutines()`'s `.order(...).execute()` idiom.
    static func topLifters(limit: Int = 50) async throws -> [Profile] {
        do {
            let rows: [Profile] = try await client
                .from("profiles")
                .select()
                .order("lifetime_volume_lifted", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func fetchMany(ids: [UUID]) async throws -> [Profile] {
        guard !ids.isEmpty else { return [] }
        do {
            let rows: [Profile] = try await SupabaseService.shared.client
                .from("profiles")
                .select()
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    // MARK: - Phase F Task 6: Edit Profile

    /// Full-row-authorized by "users can update their own profile"
    /// (`20260709000001_create_profiles.sql`: `USING/WITH CHECK (auth.uid()
    /// = id)`, no column restriction) — same owner-RLS shape `setAvatar`
    /// below relies on. Always sends the trimmed string, even if empty,
    /// rather than attempting to encode a column-clearing NULL through the
    /// `[String: String]` update dictionary: every existing display-name
    /// reader in this codebase (`YouTabView.displayName(for:)`,
    /// `GroupView`/`FriendsView`/`CreateGroupView`'s `nameBlock`) already
    /// treats an empty string exactly like `nil` (`!displayName.isEmpty`
    /// guards), so a blank field round-trips to the same "show username
    /// instead" behavior without needing an `Encodable` that can carry null.
    static func updateDisplayName(_ displayName: String) async throws -> Profile {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let updated: Profile = try await client
                .from("profiles")
                .update(["display_name": displayName.trimmingCharacters(in: .whitespaces)])
                .eq("id", value: userID.uuidString)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Generator demographics (skippable, wizard/onboarding). nil leaves
    /// a field untouched — never clears.
    static func updateDemographics(sex: String?, birthYear: Int?) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        var payload: [String: String] = [:]
        if let sex { payload["sex"] = sex }
        if let birthYear { payload["birth_year"] = "\(birthYear)" }
        guard !payload.isEmpty else { return }
        do {
            try await client
                .from("profiles")
                .update(payload)
                .eq("id", value: userID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    // MARK: - Phase M Task 4: solo-workout privacy toggle

    /// Full-row-authorized by the same owner-RLS shape as
    /// `updateDisplayName` above (`auth.uid() = id`, no column
    /// restriction). Backs the You-tab "Share Solo Workouts" toggle —
    /// writing this column is what the new set_logs SELECT policy
    /// (20260722000002_solo_workout_privacy.sql) reads to decide whether an
    /// accepted friend can see the owner's solo (single-participant)
    /// session set_logs; multi-participant sessions are unaffected either
    /// way (that policy's friend clause is gated on session-solo-ness, not
    /// just this flag).
    static func updateShowSoloWorkouts(_ enabled: Bool) async throws -> Profile {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let updated: Profile = try await client
                .from("profiles")
                .update(["show_solo_workouts": enabled])
                .eq("id", value: userID.uuidString)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Personal weekly days goal (20260811000003 + 20260812000001) — same
    /// own-row update shape as `updateShowSoloWorkouts` above, plus the
    /// anti-goalpost snapshot (owner 2026-08-12: edits apply NEXT week).
    /// The FIRST edit in a calendar week snapshots the in-effect goal into
    /// `_prev` and stamps `_changed_at`; later same-week edits keep the
    /// original snapshot so repeat editing can't walk the week's goal down.
    /// `Profile.effectiveWeeklyGoal` is the read side of this contract.
    static func updateWeeklySessionGoal(_ goal: Int) async throws -> Profile {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        struct WeeklyGoalUpdate: Encodable {
            let weeklySessionGoal: Int
            let weeklySessionGoalPrev: Int
            let weeklySessionGoalChangedAt: String
            enum CodingKeys: String, CodingKey {
                case weeklySessionGoal = "weekly_session_goal"
                case weeklySessionGoalPrev = "weekly_session_goal_prev"
                case weeklySessionGoalChangedAt = "weekly_session_goal_changed_at"
            }
        }
        do {
            // Read the row fresh (not a caller-supplied snapshot) so the
            // "was there already an edit this week?" decision can't be made
            // against stale state.
            guard let current = try await fetch(userID: userID) else {
                throw GymSyncError.unauthorized
            }
            let changedThisWeek = current.weeklySessionGoalChangedAt.map {
                Calendar.current.isDate($0, equalTo: .now, toGranularity: .weekOfYear)
            } ?? false
            let prev = changedThisWeek
                ? (current.weeklySessionGoalPrev ?? current.weeklySessionGoal)
                : current.weeklySessionGoal
            let updated: Profile = try await client
                .from("profiles")
                .update(WeeklyGoalUpdate(
                    weeklySessionGoal: min(max(goal, 1), 14),
                    weeklySessionGoalPrev: prev,
                    weeklySessionGoalChangedAt: ISO8601DateFormatter().string(from: .now)
                ))
                .eq("id", value: userID.uuidString)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch let error as GymSyncError {
            throw error
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Mirrors `GroupRepository.setAvatar`'s upload idiom exactly (same
    /// downscale/compress via `ImageProcessor.jpegForUpload`, same
    /// upload-then-write-URL shape) — the group-avatar flow from Phase 2.5
    /// is the precedent this task's brief names explicitly.
    /// `StorageService.uploadUserAvatar` carries the per-entity path
    /// convention (`users/{uid}.jpg` vs groups' `groups/{group_id}.jpg`);
    /// RLS in 20260720000005_user_avatar_storage.sql.
    ///
    /// Return type deliberately DIVERGES from `GroupRepository.setAvatar`
    /// (`Profile`, not bare `URL`): `Profile` has no memberwise init (only
    /// the custom `init(from decoder:)` — see this file's decode-only
    /// `init`, same trap `CatalogHostView.swift`'s `catalogFixtureUsername`
    /// init documents), so a caller that needs to refresh a shared
    /// `AppState.currentProfile` after an avatar-only change cannot hand-
    /// build an updated `Profile` locally the way `CreateGroupView.create()`
    /// can for `GymGroup` (which DOES have a synthesized memberwise init).
    /// Returning the full re-selected row here sidesteps that trap entirely
    /// — no call site ever needs to construct a `Profile` by hand.
    static func setAvatar(imageData: Data) async throws -> Profile {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        guard let jpeg = ImageProcessor.jpegForUpload(from: imageData, maxDimension: 512) else {
            throw GymSyncError.validation("That image couldn't be processed.")
        }
        let url = try await StorageService.uploadUserAvatar(userID: userID, jpegData: jpeg)
        do {
            let updated: Profile = try await client
                .from("profiles")
                .update(["avatar_url": url.absoluteString])
                .eq("id", value: userID.uuidString)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
