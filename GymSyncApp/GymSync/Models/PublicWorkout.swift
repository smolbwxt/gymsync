import Foundation
import Supabase

// MARK: - PublicWorkout (Phase L Task 3 — Discover)
//
// Superset of `Routine` for the public-workout-repository surface: the base
// `routines` columns PLUS the four Phase L fields Task 1 added fix-forward
// (`is_featured`/`default_sort`/`scoring_metrics`/`scoring_top_set_exercise_id`
// — `supabase/migrations/20260723000001_public_workout_repository.sql:29-35`)
// plus the owner's username (same join shape `RoutineRepository.publicRoutines()`
// already uses, `Routine.swift:85-107`).
//
// Deliberately NOT added to `Routine` itself: `RoutineBuilderView.save()`
// (`Features/Library/RoutineBuilderView.swift:404-412`) constructs a brand
// new `Routine(...)` from scratch on every edit — giving `Routine` new
// stored properties (even defaulted ones, which keep the synthesized
// memberwise init source-compatible) would make every "Edit Routine" save,
// including a curator editing an already-published featured routine, reset
// `is_featured`/`default_sort`/`scoring_metrics`/`scoring_top_set_exercise_id`
// back to their defaults — a silent, live "unpublish" regression parallel to
// the one that file's own `publishAsFeatured` seeding comment already warns
// about. A separate decode-only wrapper (same "dual decode from the same
// decoder" idiom `Routine.publicRoutines()`'s `RowWithOwner` already
// established) reads every field Discover needs without touching
// `Routine`'s constructor surface at all. Task 4 (RoutineBuilder publish
// path) is the correct place to teach `RoutineBuilderView` about these
// fields, seeded from `editing` the same defensive way `publishAsFeatured`
// already is.
struct PublicWorkout: Decodable, Identifiable, Sendable {
    let routine: Routine
    let ownerUsername: String
    let isFeatured: Bool
    let defaultSort: String?
    let scoringMetrics: [String]?
    let scoringTopSetExerciseID: UUID?

    var id: UUID { routine.id }

    private enum ExtraKeys: String, CodingKey {
        case isFeatured = "is_featured"
        case defaultSort = "default_sort"
        case scoringMetrics = "scoring_metrics"
        case scoringTopSetExerciseID = "scoring_top_set_exercise_id"
    }
    private enum JoinKeys: String, CodingKey { case profiles }
    private struct OwnerRef: Decodable { let username: String }

    init(from decoder: Decoder) throws {
        routine = try Routine(from: decoder)

        let extra = try decoder.container(keyedBy: ExtraKeys.self)
        isFeatured = try extra.decodeIfPresent(Bool.self, forKey: .isFeatured) ?? false
        defaultSort = try extra.decodeIfPresent(String.self, forKey: .defaultSort)
        scoringMetrics = try extra.decodeIfPresent([String].self, forKey: .scoringMetrics)
        scoringTopSetExerciseID = try extra.decodeIfPresent(UUID.self, forKey: .scoringTopSetExerciseID)

        let join = try decoder.container(keyedBy: JoinKeys.self)
        let owner = try join.decode(OwnerRef.self, forKey: .profiles)
        ownerUsername = owner.username
    }
}

// MARK: - LeaderboardEntryRow
//
// `leaderboard_entries` row (spec-verbatim columns, `docs/superpowers/specs/
// 2026-06-28-gymsync-design.md:418-429`) joined with the attempting user's
// profile (username/avatar) for display — same dual-decode idiom as
// `PublicWorkout` above. `top_sets` is the spec's `{exercise_id: best_weight}`
// jsonb shape (`:424`) — decodes straight to `[String: Decimal]` since
// Postgres emits `numeric` values as JSON numbers via `jsonb_object_agg`
// (`leaderboard_attempt_volume`, `20260723000001_public_workout_repository.
// sql:228-237`), and `Decimal` is natively `Decodable` from a JSON number.
// `decodeIfPresent` throughout: the recompute trigger always writes a
// non-null (possibly empty `{}`) `top_sets` and a `time_seconds`/
// `total_volume` pair that's null exactly when that metric doesn't apply to
// this attempt (":422-423" — "if 'time' applies; else NULL").
//
// `isOptInLeaderboard` (review fix, Important finding 1): the spec
// deliberately never denormalizes `is_opt_in_leaderboard` onto
// `leaderboard_entries` (`20260723000001_public_workout_repository.sql:112-
// 125`) — it only lives on the parent `workout_attempts` row, one join away.
// `leaderboard_entries`' own SELECT RLS is `user_id = auth.uid() OR
// <attempt opted in>` (same migration:134-143) — that owner branch exists so
// a user can read their OWN history (e.g. a future "my attempts" surface),
// NOT so their opted-out row can render on the shared Discover board. RLS is
// a ceiling on what a query COULD return, not a filter on what a specific
// query SHOULD return, so `PublicWorkoutRepository.leaderboard()`/
// `attemptCounts()` must apply the opt-in restriction themselves — decoding
// the flag here (via the same `workout_attempts!inner(...)` embed those two
// functions now select) is what makes that restriction visible/verifiable
// at the model layer instead of trusting an unchecked join.
struct LeaderboardEntryRow: Decodable, Identifiable, Sendable {
    let attemptID: UUID
    let routineID: UUID?
    let userID: UUID
    let timeSeconds: Int?
    let totalVolume: Decimal?
    let topSets: [String: Decimal]?
    let isComplete: Bool
    let isEdited: Bool
    let computedAt: Date
    let username: String
    let avatarURL: URL?
    let isOptInLeaderboard: Bool

    var id: UUID { attemptID }

    private enum CodingKeys: String, CodingKey {
        case attemptID = "attempt_id"
        case routineID = "routine_id"
        case userID = "user_id"
        case timeSeconds = "time_seconds"
        case totalVolume = "total_volume"
        case topSets = "top_sets"
        case isComplete = "is_complete"
        case isEdited = "is_edited"
        case computedAt = "computed_at"
    }
    private enum JoinKeys: String, CodingKey {
        case profiles
        case workoutAttempts = "workout_attempts"
    }
    private struct OwnerRef: Decodable {
        let username: String
        let avatarURL: URL?
        enum CodingKeys: String, CodingKey {
            case username
            case avatarURL = "avatar_url"
        }
    }
    private struct AttemptRef: Decodable {
        let isOptInLeaderboard: Bool
        enum CodingKeys: String, CodingKey {
            case isOptInLeaderboard = "is_opt_in_leaderboard"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attemptID = try c.decode(UUID.self, forKey: .attemptID)
        routineID = try c.decodeIfPresent(UUID.self, forKey: .routineID)
        userID = try c.decode(UUID.self, forKey: .userID)
        timeSeconds = try c.decodeIfPresent(Int.self, forKey: .timeSeconds)
        totalVolume = try c.decodeIfPresent(Decimal.self, forKey: .totalVolume)
        topSets = try c.decodeIfPresent([String: Decimal].self, forKey: .topSets)
        isComplete = try c.decode(Bool.self, forKey: .isComplete)
        isEdited = try c.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        computedAt = try c.decode(Date.self, forKey: .computedAt)

        let join = try decoder.container(keyedBy: JoinKeys.self)
        let owner = try join.decode(OwnerRef.self, forKey: .profiles)
        username = owner.username
        avatarURL = owner.avatarURL
        let attempt = try join.decode(AttemptRef.self, forKey: .workoutAttempts)
        isOptInLeaderboard = attempt.isOptInLeaderboard
    }
}

// MARK: - PublicWorkoutRepository

enum PublicWorkoutRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Discover grid: every `visibility='public'` routine, is_featured first
    /// then newest — Phase L design §3 ("featured/public workout grid...
    /// is_featured first, then others", `docs/superpowers/specs/2026-07-18-
    /// discover-leaderboards-design.md:18`). Same join shape as
    /// `RoutineRepository.publicRoutines()` (`Routine.swift:98-104`), widened
    /// to `PublicWorkout` for the 4 extra columns that view doesn't need.
    static func publicWorkouts() async throws -> [PublicWorkout] {
        do {
            let rows: [PublicWorkout] = try await client
                .from("routines")
                .select("*, profiles!routines_owner_id_fkey(username)")
                .eq("visibility", value: "public")
                .order("is_featured", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// A routine's leaderboard — every `leaderboard_entries` row RLS lets the
    /// caller read (opt-in OR own row: `20260723000001_public_workout_
    /// repository.sql:134-143`) joined with the attempting user's profile.
    /// No PER-TAB server round trip here — Time/Volume/TopSet/Recent are
    /// re-sorted CLIENT-SIDE from this one fetch (`DiscoverWorkoutDetailView`'s
    /// `sortedEntries`), so switching the segmented control never re-hits the
    /// network. `is_complete=true` is a defensive filter, not a load-bearing
    /// one — the recompute trigger only ever inserts a row with
    /// `is_complete=true` (`leaderboard_recompute_on_session_completion`'s
    /// INSERT, same migration:281-285); kept explicit so a future write path
    /// can't silently leak an in-progress attempt's stale zeroes onto the
    /// board. `limit(200)` is the "sane LIMIT, no pagination" non-goal from
    /// the Phase L design (`discover-leaderboards-design.md:32`).
    ///
    /// Task 7 item 3 (pre-GA ledger, .superpowers/sdd/task-7-brief.md item 3)
    /// FIX — LIMIT axis: this used to ALWAYS `.order("computed_at",
    /// ascending: false)` before the LIMIT, regardless of the routine's own
    /// `default_sort`. That's correct only when Recent genuinely IS the
    /// routine's primary ranking (`default_sort == 'recent'`, or unset). For
    /// a routine whose `default_sort` is `'time'`/`'volume'`/`'top_set'` —
    /// i.e. an actual scored leaderboard — limiting along RECENCY before the
    /// client ever re-sorts by the METRIC silently truncates the real top-200
    /// once a routine passes 200 attempts: a genuinely #1 all-time fastest
    /// "Time" entry from outside the 200-most-recent window would never even
    /// reach the client to be re-sorted into place (.superpowers/sdd/
    /// progress.md's "PRE-GA LEDGER: ... (3) recency-vs-metric LIMIT before
    /// any routine passes 200 entries"). Fix: order/limit along the SAME axis
    /// the routine is actually judged by (this function's new `defaultSort`
    /// param, sourced from `routines.default_sort`), falling back to
    /// recency exactly when Recent genuinely is that axis — mirrors
    /// `DiscoverWorkoutDetailView.initialSort(for:)`'s own fallback rule
    /// (unset/invalid/offered-metric-missing `default_sort` → Recent) and the
    /// server-side rank computation's own per-metric ordering
    /// (`leaderboard_rank_and_passed`, `20260723000001_public_workout_
    /// repository.sql:160-205`: time ASC NULLS LAST / volume DESC NULLS LAST /
    /// top_set DESC NULLS LAST on the routine's chosen exercise) — same three
    /// metrics, same NULLS LAST placement, kept in lockstep with the ranking
    /// this leaderboard is FOR rather than an independently-invented order.
    /// `top_sets->>id` JSONB-path ordering verified live (read-only probe
    /// against `leaderboard_entries`, 2026-07-19: `?order=top_sets->>x.desc.
    /// nullslast` returns 200, PostgREST accepts JSON-path order expressions
    /// the same as `select`); `order()`'s signature (`nullsFirst: Bool =
    /// false`) confirmed against the pinned dependency source
    /// (`raw.githubusercontent.com/supabase/supabase-swift/2.5.0/Sources/
    /// PostgREST/PostgrestTransformBuilder.swift`, matching `project.yml`'s
    /// `Supabase` package pin — Swift compiles in CI only, so this couldn't
    /// be confirmed by a local build).
    ///
    /// Honest residual (documented, not silently accepted): this is still
    /// ONE fetch for ALL four tabs, so only the routine's OWN primary axis
    /// gets a true top-200 — a NON-default tab (e.g. viewing "Volume" on a
    /// `default_sort='time'` routine with 250+ attempts) still re-sorts
    /// within whatever 200 rows the TIME axis limited to, same shape of gap
    /// as before, just narrowed from "every tab, always" to "every
    /// non-default tab, only past 200 attempts." Fixing that fully would mean
    /// a fetch per tab, reintroducing the exact network cost `sortedEntries`'s
    /// own doc comment deliberately avoided — out of this item's scope; a
    /// routine with 200+ attempts on more than one scored axis is a real
    /// future-scale problem, not a pre-GA blocker today.
    ///
    /// `workout_attempts!inner(is_opt_in_leaderboard)` + the trailing
    /// `.eq("workout_attempts.is_opt_in_leaderboard", value: true)` (review
    /// fix, Important finding 1): the RLS policy's `user_id = auth.uid()`
    /// branch (see above) exists so a caller can read their OWN attempt rows
    /// on some future personal-history surface — it is NOT scoped to "public
    /// leaderboard," so without this filter a user who chose "keep private"
    /// would see THEMSELVES appear on this board every time they revisit it.
    /// This is the same "filter through an embedded resource via `!inner` +
    /// dot-notation `.eq(...)`" idiom `SessionRepository.upcoming()` already
    /// uses (`SessionRepository.swift:230-231`,
    /// `.select("*, session_participants!inner(user_id)")` +
    /// `.eq("session_participants.user_id", ...)`) — no schema change, no new
    /// denormalized column, the flag is read straight off `workout_attempts`
    /// through the FK `leaderboard_entries.attempt_id` already has.
    static func leaderboard(
        routineID: UUID, defaultSort: String? = nil, topSetExerciseID: UUID? = nil
    ) async throws -> [LeaderboardEntryRow] {
        do {
            let query = client
                .from("leaderboard_entries")
                .select("*, profiles!leaderboard_entries_user_id_fkey(username, avatar_url), workout_attempts!inner(is_opt_in_leaderboard)")
                .eq("routine_id", value: routineID)
                .eq("is_complete", value: true)
                .eq("workout_attempts.is_opt_in_leaderboard", value: true)

            let ordered: PostgrestTransformBuilder
            switch (defaultSort, topSetExerciseID) {
            case ("time", _):
                ordered = query.order("time_seconds", ascending: true, nullsFirst: false)
            case ("volume", _):
                ordered = query.order("total_volume", ascending: false, nullsFirst: false)
            case ("top_set", .some(let exerciseID)):
                ordered = query.order(
                    "top_sets->>\(exerciseID.uuidString.lowercased())",
                    ascending: false, nullsFirst: false)
            default:
                // 'recent', unset, or 'top_set' with no chosen exercise —
                // same fallback set `DiscoverWorkoutDetailView.initialSort`
                // already treats as Recent.
                ordered = query.order("computed_at", ascending: false)
            }

            let rows: [LeaderboardEntryRow] = try await ordered
                .limit(200)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// Bulk per-routine opt-in attempt counts for the Discover grid's "N
    /// attempts" chip — one round trip regardless of grid size, same bulk-
    /// `.in(routine_id)` idiom as `RoutineRepository.exercisesForRoutines`
    /// (`Routine.swift:138-150`). Judgment call (brief: "attempt count if
    /// cheap — judge"): a per-routine COUNT would be N round trips (no
    /// grouped-count RPC exists, and adding one is Task 4/out of scope per
    /// the brief's "no new public-schema relationship oracles" caution) — but
    /// a single bulk SELECT of `leaderboard_entries.routine_id` for the
    /// visible grid IDs, counted client-side, is exactly as cheap as the
    /// exercises-count precedent above and reuses the exact same RLS
    /// (opt-in-or-owner) that the leaderboard itself relies on, so the count
    /// only ever reflects rows Discover would show anyway.
    ///
    /// Same `workout_attempts!inner(...)` + dot-notation `.eq(...)` opt-in
    /// filter as `leaderboard()` above (review fix, Important finding 1 —
    /// "mildly inflates the grid's attempt counts from their own vantage"):
    /// without it, RLS's owner-branch would let a user's own opted-out
    /// attempt inflate the "N attempts" chip by one every time THEY view
    /// Discover, even though nobody else would ever see that count. `Row`
    /// only decodes `routine_id` — the embedded `workout_attempts` object is
    /// present in the response purely to drive the `!inner` filter and is
    /// safely ignored by this minimal decode (extra keys a `Decodable`
    /// container doesn't ask for are never an error).
    static func attemptCounts(routineIDs: [UUID]) async throws -> [UUID: Int] {
        guard !routineIDs.isEmpty else { return [:] }
        do {
            struct Row: Decodable {
                let routineID: UUID?
                enum CodingKeys: String, CodingKey { case routineID = "routine_id" }
            }
            let rows: [Row] = try await client
                .from("leaderboard_entries")
                .select("routine_id, workout_attempts!inner(is_opt_in_leaderboard)")
                .in("routine_id", values: routineIDs.map(\.uuidString))
                .eq("workout_attempts.is_opt_in_leaderboard", value: true)
                .execute()
                .value
            return Dictionary(grouping: rows.compactMap(\.routineID), by: { $0 })
                .mapValues(\.count)
        } catch { throw ErrorMapping.map(error) }
    }

    /// `start_attempt(p_routine_id, p_session_id, p_opt_in) returns uuid` —
    /// backend contract per `.superpowers/sdd/task-2-report.md`: call AFTER
    /// creating the session with that routine (Task 2's RPC gates on
    /// `sessions.routine_id` actually matching `p_routine_id` — Finding 1,
    /// same report). Params passed as `[String: AnyJSON]` rather than the
    /// `[String: String]` dictionary literal every OTHER single-string-param
    /// RPC in this codebase uses (`SessionRepository.swift:206,367,382,394`
    /// etc.) because this call has a genuine `boolean` parameter alongside
    /// the two uuid ones — a dictionary literal can't mix value types, and
    /// `AnyJSON` is already this codebase's established typed-JSON-payload
    /// vocabulary (`RoutineProposal.swift:68-72`), giving `p_opt_in` a real
    /// JSON boolean rather than a stringified "true"/"false" that would rely
    /// on PostgREST's parameter coercion.
    static func startAttempt(routineID: UUID, sessionID: UUID, optIn: Bool) async throws -> UUID {
        do {
            let attemptID: UUID = try await client
                .rpc("start_attempt", params: [
                    "p_routine_id": AnyJSON.string(routineID.uuidString),
                    "p_session_id": AnyJSON.string(sessionID.uuidString),
                    "p_opt_in": AnyJSON.bool(optIn)
                ])
                .execute()
                .value
            return attemptID
        } catch { throw ErrorMapping.map(error) }
    }
}
