import Foundation
import Supabase

// ============================================================
// Phase C / Task 2: campaigns UI — models + repository.
// ============================================================
// Backend contract (Task 1): supabase/migrations/20260728000001_campaigns_
// schema.sql (tables, RLS, community-aggregate RPC), 20260728000002_
// campaign_progress_trigger.sql (progress accrual + completion chat
// message), 20260728000004_campaign_participants_draft_join_fix_v2.sql
// (draft-join RLS close) — task-1-report.md / task-1 review in
// .superpowers/sdd/progress.md. Decode structs use snake_case CodingKeys
// per this codebase's convention (Friendship.swift, GymGroup.swift,
// ChatMessage.swift). Repository shape follows the small-repo idiom (model
// + `enum XRepository` colocated in one file) established by Streak.swift /
// Moderation.swift, per the task brief.

/// `campaigns.global_target` jsonb shape (spec :592 / migration :149):
/// `{"metric":"total_volume","target":100000000}`. Decoded as a dedicated
/// struct (not a flexible-JSON type) since the shape is fully known and
/// fixed — same "typed over flexible" preference this codebase already
/// shows for `GroupStats`/`BurpeeLedgerMath` rather than reaching for
/// `AnyJSON` when a concrete shape is available.
struct CampaignTarget: Decodable, Sendable, Equatable {
    let metric: String?
    let target: Double?
}

/// `campaigns.individual_target` jsonb shape (spec :592 / migration :150):
/// `{"sessions":12}` OR `{"workouts_completed":4}` — a campaign picks ONE
/// key, never both (the progress trigger's own header, 20260728000002:294-
/// 309, "picks whichever key... NULL individual_target or an unrecognized
/// key is a silent no-op"). Both kept optional here for the same reason.
struct CampaignIndividualTarget: Decodable, Sendable, Equatable {
    let sessions: Int?
    let workoutsCompleted: Int?

    enum CodingKeys: String, CodingKey {
        case sessions
        case workoutsCompleted = "workouts_completed"
    }

    /// The campaign's target count regardless of which key it uses, plus a
    /// display unit label — mirrors the trigger's own `v_target_n`/
    /// `v_unit_label` derivation (20260728000002_campaign_progress_
    /// trigger.sql:298-309) so the client's "12/12 sessions" style copy
    /// matches the server's own completion-message wording exactly.
    var resolvedTarget: (count: Int, unitLabel: String)? {
        if let sessions { return (sessions, "sessions") }
        if let workoutsCompleted { return (workoutsCompleted, "workouts") }
        return nil
    }
}

/// A row of `campaigns` (20260728000001_campaigns_schema.sql:142-156).
struct Campaign: Decodable, Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let startsAt: Date
    let endsAt: Date
    let bannerURL: String?
    let globalTarget: CampaignTarget?
    let individualTarget: CampaignIndividualTarget?
    let curatedRoutineIDs: [UUID]
    let isFeatured: Bool
    let isDraft: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case bannerURL = "banner_url"
        case globalTarget = "global_target"
        case individualTarget = "individual_target"
        case curatedRoutineIDs = "curated_routine_ids"
        case isFeatured = "is_featured"
        case isDraft = "is_draft"
        case createdAt = "created_at"
    }

    /// Date-window state machine (hermetic, pure — GymSyncTests exercises
    /// this directly). `.ended` exists for completeness/testability even
    /// though every current caller only ever fetches non-ended campaigns
    /// (`CampaignRepository.activeAndUpcoming`) — a campaign row the user
    /// already navigated into stays valid to describe even if its window
    /// lapses while the detail screen is open, rather than mis-labeling it
    /// "upcoming" or crashing an exhaustive `switch`.
    enum WindowState: Equatable {
        case upcoming
        case active
        case ended
    }

    func windowState(now: Date = .now) -> WindowState {
        if now < startsAt { return .upcoming }
        if now > endsAt { return .ended }
        return .active
    }

    /// Days until `startsAt` — used for the sub-tab's upcoming-campaign
    /// countdown (Flow 8 spec :865, "a countdown to upcoming ones"). `0`
    /// when `startsAt` is today or in the past (never negative — a caller
    /// only shows this for `.upcoming` campaigns in practice).
    func daysUntilStart(now: Date = .now) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: now, to: startsAt).day ?? 0)
    }
}

/// A row of `campaign_participants` (20260728000001_campaigns_schema.sql:
/// 170-175).
struct CampaignParticipant: Decodable, Sendable, Equatable {
    let campaignID: UUID
    let userID: UUID
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case campaignID = "campaign_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
    }
}

/// A row of `campaign_progress` (20260728000001_campaigns_schema.sql:200-
/// 208). `sessionsCompleted`/`workoutsCompleted` move in lockstep today —
/// the trigger's own header (20260728000002:95-106) calls this "deliberately
/// redundant in v1": both counters increment together for every qualifying
/// session regardless of which key a campaign's `individual_target` uses.
struct CampaignProgress: Decodable, Sendable, Equatable {
    let campaignID: UUID
    let userID: UUID
    let sessionsCompleted: Int
    let workoutsCompleted: Int
    let volumeLifted: Decimal
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case campaignID = "campaign_id"
        case userID = "user_id"
        case sessionsCompleted = "sessions_completed"
        case workoutsCompleted = "workouts_completed"
        case volumeLifted = "volume_lifted"
        case updatedAt = "updated_at"
    }
}

/// One row returned by `campaign_community_progress(p_campaign_id)`
/// (20260728000001_campaigns_schema.sql:344-367) — always exactly one row
/// once the function's own gate passes (campaign visible to the caller at
/// all), same "single-row RPC, `.first` with a zero fallback" idiom as
/// `GroupStats` (GymGroup.swift:239-248).
struct CampaignCommunityProgress: Decodable, Sendable, Equatable {
    let sessionsCompleted: Int
    let workoutsCompleted: Int
    let volumeLifted: Decimal

    enum CodingKeys: String, CodingKey {
        case sessionsCompleted = "sessions_completed"
        case workoutsCompleted = "workouts_completed"
        case volumeLifted = "volume_lifted"
    }
}

/// Client-composed per-campaign leaderboard row — `CampaignProgress` joined
/// against `Profile` client-side. See `CampaignRepository.leaderboard`'s doc
/// comment for why this is a plain client-side join, not a server RPC.
struct CampaignLeaderboardRow: Identifiable, Sendable, Equatable {
    var id: UUID { userID }
    let userID: UUID
    let username: String
    let avatarURL: URL?
    let sessionsCompleted: Int
    let workoutsCompleted: Int
    let volumeLifted: Decimal
}

// ============================================================
// Pure progress math — hermetically tested (GymSyncTests/CampaignTests.swift).
// No network, no RLS, no dates-as-now(); every input is a value type.
// ============================================================
enum CampaignProgressMath {
    /// The current user's count toward whichever key `target` uses
    /// (sessions vs. workouts) — `nil` target key (no `individual_target`,
    /// or an unrecognized key, mirroring the trigger's own silent-no-op
    /// posture, 20260728000002_campaign_progress_trigger.sql:294-309)
    /// yields `nil`, not 0 — there is nothing to count toward.
    static func achievedCount(progress: CampaignProgress?, target: CampaignIndividualTarget?) -> Int? {
        guard let resolved = target?.resolvedTarget else { return nil }
        switch resolved.unitLabel {
        case "sessions": return progress?.sessionsCompleted ?? 0
        case "workouts": return progress?.workoutsCompleted ?? 0
        default: return nil
        }
    }

    /// Fraction complete toward the individual target, clamped to `[0, 1]`.
    /// `nil` when the campaign has no recognized `individual_target` key —
    /// nothing to render a completion bar against (distinct from `0`, which
    /// would draw an empty-but-present bar for a campaign that has none).
    static func fractionComplete(progress: CampaignProgress?, target: CampaignIndividualTarget?) -> Double? {
        guard let resolved = target?.resolvedTarget, resolved.count > 0,
              let achieved = achievedCount(progress: progress, target: target) else { return nil }
        return min(1.0, max(0.0, Double(achieved) / Double(resolved.count)))
    }

    /// Whether the individual target has been met/crossed — mirrors the
    /// trigger's own crossing check (`v_new_count >= v_target_n`,
    /// 20260728000002_campaign_progress_trigger.sql:318) so the client's
    /// completion-badge state (Flow 8 :882-884) agrees with whichever
    /// session actually made the server fire the completion chat message.
    static func isComplete(progress: CampaignProgress?, target: CampaignIndividualTarget?) -> Bool {
        guard let resolved = target?.resolvedTarget,
              let achieved = achievedCount(progress: progress, target: target) else { return false }
        return achieved >= resolved.count
    }
}

enum CampaignRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    // MARK: - Discovery

    /// Campaigns whose window hasn't ended yet (`ends_at >= now`), split
    /// into active/upcoming. RLS ("campaigns are globally readable unless
    /// draft", 20260728000001_campaigns_schema.sql:243-248) already hides
    /// drafts from every non-participant server-side — no client-side
    /// `is_draft` filter needed (the server hides drafts; a participant of
    /// a draft campaign, e.g. Task 3's future seed, sees it here exactly
    /// like a real one). Flow 8 (spec :865): "Library -> Campaigns sub-tab
    /// shows all active campaigns + a countdown to upcoming ones" — an
    /// already-ended campaign is deliberately excluded from this list (it
    /// surfaced on the discovery list, which Flow 8's text never asks for.
    /// Ended campaigns the user PARTICIPATED IN remain reachable via
    /// `endedParticipated()` below + the Campaigns sub-tab's "Past" section.
    static func activeAndUpcoming() async throws -> (active: [Campaign], upcoming: [Campaign]) {
        do {
            let nowString = Date.now.ISO8601Format(
                .iso8601(timeZone: TimeZone(secondsFromGMT: 0)!, includingFractionalSeconds: true))
            let rows: [Campaign] = try await client
                .from("campaigns")
                .select()
                .gte("ends_at", value: nowString)
                .order("starts_at", ascending: true)
                .execute()
                .value
            let now = Date.now
            let active = rows.filter { $0.startsAt <= now }
            let upcoming = rows.filter { $0.startsAt > now }
            return (active, upcoming)
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Ended campaigns the current user joined — the "Past challenges"
    /// surface (Opus pre-GA closeout, 2026-07-20). Closes the gate's
    /// MINOR-2: an ended campaign dropped off `activeAndUpcoming` and had NO
    /// reachable path, so Flow 8 :884's "leaderboard is frozen; final
    /// community total is displayed as historical fact" was unreachable
    /// once a campaign ended — a participant lost their own frozen result.
    /// Scoped to PARTICIPANTS (an ended campaign is a memory only for those
    /// who ran it), which the `campaign_participants!inner(user_id)` embed
    /// enforces at the query layer AND the RLS backs (campaigns SELECT =
    /// `NOT is_draft OR participant`; a participant reads their ended row).
    /// `!inner` + dot-notation eq is the Phase L opt-in-embed idiom
    /// (`PublicWorkoutRepository.leaderboard`'s `workout_attempts!inner`).
    /// `CampaignDetailView` already renders the `.ended` window state (its
    /// frozen leaderboard + "Ended" tag) — this just gives it a door.
    static func endedParticipated() async throws -> [Campaign] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let nowString = Date.now.ISO8601Format(
                .iso8601(timeZone: TimeZone(secondsFromGMT: 0)!, includingFractionalSeconds: true))
            let rows: [Campaign] = try await client
                .from("campaigns")
                .select("*, campaign_participants!inner(user_id)")
                .eq("campaign_participants.user_id", value: me.uuidString)
                .lt("ends_at", value: nowString)
                .order("ends_at", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    // No single-campaign-by-id fetch: every caller of `CampaignDetailView`
    // (`CampaignsTabView`'s active/upcoming/past rows, `HomeView`'s carousel
    // card) already holds the full `Campaign` value from
    // `activeAndUpcoming()`/`endedParticipated()` and passes it directly —
    // no push/deep-link path exists that would need an id-only lookup
    // (Task 1's own header: "No push notification: NONE named, therefore
    // none built"). Adding an unused id-fetch method here would be dead
    // code with no caller to keep it honest against drift.

    // MARK: - Join / Leave
    //
    // Direct owner-scoped INSERT/DELETE, no RPC — Adjudication 2
    // (20260728000001_campaigns_schema.sql:76-89): Flow 8 names no
    // server-side check for either join or leave.

    /// Whether the current user has already joined — `nil` means not
    /// joined (PGRST116 on `.single()` with zero rows), same zero-state
    /// idiom as `StreakRepository.userStreak`.
    static func myParticipation(campaignID: UUID) async throws -> CampaignParticipant? {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let row: CampaignParticipant = try await client
                .from("campaign_participants")
                .select()
                .eq("campaign_id", value: campaignID.uuidString)
                .eq("user_id", value: me.uuidString)
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

    /// Join a campaign as the current user. A draft campaign's INSERT
    /// policy `WITH CHECK (user_id = auth.uid() AND NOT private.
    /// is_campaign_draft(campaign_id))`
    /// (20260728000004_campaign_participants_draft_join_fix_v2.sql:105-110)
    /// rejects the row with Postgres 42501 — surfaced through the same
    /// generic `ErrorMapping.map` -> `.validation(pg.message)` path every
    /// other RLS denial in this app already takes. Deliberately NOT
    /// special-cased into a "this campaign isn't open yet" message: doing
    /// so would let a caller distinguish "draft" from "any other reason
    /// this failed" purely from the error shape, the exact oracle class
    /// Task 1's own header warns about — per the brief's "surface as a
    /// generic failure" instruction.
    static func join(campaignID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("campaign_participants")
                .insert(["campaign_id": campaignID.uuidString, "user_id": me.uuidString])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Leave a campaign — owner-scoped DELETE ("user leaves a campaign they
    /// joined", 20260728000001_campaigns_schema.sql:271-273). Per Flow 8
    /// (spec :871, "No commitment beyond opt-in -- you can leave anytime")
    /// and the schema header's own reasoning (:191-199), leaving does NOT
    /// forfeit already-accrued `campaign_progress` — that table carries no
    /// FK to `campaign_participants`, deliberately, so progress survives a
    /// leave/rejoin.
    static func leave(campaignID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("campaign_participants")
                .delete()
                .eq("campaign_id", value: campaignID.uuidString)
                .eq("user_id", value: me.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Batched "which of these campaigns have I joined" lookup — Home's
    /// carousel card needs joined/unjoined state for potentially several
    /// active campaigns at once (spec :1375 notes "1-2 active seasonal
    /// campaigns at a time" as the expected scale) without one round trip
    /// per campaign. A single `campaign_participants` row can only ever
    /// pass this policy's `is_campaign_participant` check when `user_id =
    /// auth.uid()` IS the very row being evaluated (self-referential, not
    /// circular — see `20260728000001_campaigns_schema.sql`'s item 4), so
    /// filtering to `user_id = me` up front means every row the query CAN
    /// return already passes RLS; the `.in()` on `campaign_id` just narrows
    /// which of those rows come back.
    static func myParticipations(campaignIDs: [UUID]) async throws -> Set<UUID> {
        guard !campaignIDs.isEmpty else { return [] }
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [CampaignParticipant] = try await client
                .from("campaign_participants")
                .select()
                .eq("user_id", value: me.uuidString)
                .in("campaign_id", values: campaignIDs.map(\.uuidString))
                .execute()
                .value
            return Set(rows.map(\.campaignID))
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    // MARK: - Progress

    /// The current user's own progress row for a campaign — `nil` means
    /// zero (no qualifying session completed yet), same insert-on-first-
    /// touch idiom as `StreakRepository.userStreak`: the trigger's own
    /// `INSERT ... ON CONFLICT DO NOTHING`
    /// (20260728000002_campaign_progress_trigger.sql:272-274) only creates
    /// this row on a participant's FIRST qualifying session completion.
    static func myProgress(campaignID: UUID) async throws -> CampaignProgress? {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let row: CampaignProgress = try await client
                .from("campaign_progress")
                .select()
                .eq("campaign_id", value: campaignID.uuidString)
                .eq("user_id", value: me.uuidString)
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

    /// Community-aggregate totals for the campaign detail page's progress
    /// bar — `campaign_community_progress(p_campaign_id)` SECURITY DEFINER
    /// RPC (20260728000001_campaigns_schema.sql:344-367), same "single-row
    /// RPC, `.first` with a zero fallback" idiom as `GymGroup.
    /// stats(groupID:)` (GymGroup.swift:239-248). Named param `p_campaign_id`
    /// matches the function signature exactly — PostgREST rejects a
    /// mismatched RPC param name outright rather than silently coercing it.
    /// Callable by ANY authenticated user who can see the campaign at all
    /// (the RPC's own gate re-derives the campaigns SELECT predicate, Task
    /// 1's item 8 header) — unlike `leaderboard` below, this does NOT
    /// require the caller to already be a participant.
    static func communityProgress(campaignID: UUID) async throws -> CampaignCommunityProgress {
        do {
            let rows: [CampaignCommunityProgress] = try await client
                .rpc("campaign_community_progress", params: ["p_campaign_id": campaignID.uuidString])
                .execute()
                .value
            return rows.first ?? CampaignCommunityProgress(sessionsCompleted: 0, workoutsCompleted: 0, volumeLifted: 0)
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    // MARK: - Leaderboard

    /// Per-participant leaderboard for a campaign, ranked by `volumeLifted`
    /// DESC. Participants-only by construction — see the ADJUDICATION note
    /// below; callers must gate on `myParticipation(campaignID:)` and fall
    /// back to community-total-only for non-participants.
    ///
    /// ADJUDICATION (task brief: "check what RLS lets a participant see...
    /// if RLS blocks a per-user leaderboard for participants, the honest v1
    /// is community-total + my-progress ONLY... do NOT invent a new DEFINER
    /// surface"). Re-reading the SHIPPED RLS (not the hypothetical) settles
    /// this: the `campaign_progress` SELECT policy — "participants can read
    /// campaign progress" (20260728000001_campaigns_schema.sql:282-284) —
    /// reads `USING (private.is_campaign_participant(campaign_progress.
    /// campaign_id, auth.uid()))`. That gates on whether the CALLER is a
    /// participant of the ROW's campaign, not on whether the row belongs to
    /// the caller. A participant can therefore already read the FULL
    /// `campaign_progress` roster for any campaign they've joined — no new
    /// DEFINER surface needed; this is a plain client-side SELECT + join,
    /// same "fetch rows, then `ProfileRepository.fetchMany`, then re-sort to
    /// the original query order" shape as `ModerationRepository.
    /// blockedUsers()` (Moderation.swift:113-145). For a caller who hasn't
    /// joined, that SAME policy denies every row (RLS returns zero rows,
    /// not an error) — so this function is a real per-participant board for
    /// participants, and a silent empty board for anyone else; the UI layer
    /// (not this function) is responsible for not calling it, and for
    /// showing the community-total-only fallback, when the current user
    /// hasn't joined — matching the brief's fallback exactly, just scoped
    /// correctly to the RLS boundary that's actually shipped rather than
    /// the one that was hypothesized.
    ///
    /// Sort key: `volumeLifted`, not `sessionsCompleted`/`workoutsCompleted`
    /// — those two move in lockstep and are keyed to whichever
    /// `individual_target` type a given campaign happens to use (sessions
    /// vs. workouts), so neither is a stable cross-campaign ranking axis.
    /// `volumeLifted` is always tracked regardless of a campaign's
    /// individual-target shape, and is the same metric Flow 8's own
    /// community-bar example names ("Together we've moved 47.3M lbs...",
    /// spec :880) — the honest, non-invented reading of "per-campaign
    /// leaderboard" absent an explicit spec'd sort key.
    static func leaderboard(campaignID: UUID) async throws -> [CampaignLeaderboardRow] {
        do {
            let rows: [CampaignProgress] = try await client
                .from("campaign_progress")
                .select()
                .eq("campaign_id", value: campaignID.uuidString)
                .order("volume_lifted", ascending: false)
                .execute()
                .value
            guard !rows.isEmpty else { return [] }
            let profiles = try await ProfileRepository.fetchMany(ids: rows.map(\.userID))
            let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            // `ProfileRepository.fetchMany`'s `.in()` doesn't preserve input
            // order — same re-sort-to-query-order fix `ModerationRepository.
            // blockedUsers()` already applies, so the volume ranking from
            // the query above survives the join.
            return rows.compactMap { row in
                guard let profile = byID[row.userID] else { return nil }
                let name = (profile.displayName?.isEmpty == false) ? profile.displayName! : profile.username
                return CampaignLeaderboardRow(
                    userID: row.userID,
                    username: name,
                    avatarURL: profile.avatarURL,
                    sessionsCompleted: row.sessionsCompleted,
                    workoutsCompleted: row.workoutsCompleted,
                    volumeLifted: row.volumeLifted
                )
            }
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
