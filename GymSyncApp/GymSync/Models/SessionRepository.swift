import Foundation
import Supabase

enum SessionRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    // MARK: - Room-code alphabet (no ambiguous chars: 0/O, 1/I/L)
    private static let roomCodeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    private static func makeRoomCode() -> String {
        String((0..<6).map { _ in roomCodeAlphabet.randomElement()! })
    }

    // MARK: - ISO8601 with fractional seconds (matches existing pattern)
    private static func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Existing methods (unchanged)

    /// THE AD-HOC START. One row, one participant, no RPC (Phase C1
    /// decision 1) — and, from C1 on, `.freestyle`.
    ///
    /// WHY THE STYLE IS THE ONLY THING THAT CHANGED. The row this function
    /// has always written is already a row the one body accepts:
    /// `state: "in_progress"` with `lifting_started_at` never set is exactly
    /// `WarmUpGate.isWarmingUp` (`WarmUpScreen.swift:25-27`), so
    /// `SessionRouter.route` sends it to `.warmUp` → `SessionRunnerView` →
    /// `WarmUpScreen`, and the shipped `start_lifting`/`mark_warmup_ready`
    /// stamps the column that moves it to `.live`. No new start RPC exists
    /// and constraint 20 is not strained.
    ///
    /// `.rounds` is the one style whose body carries a rotation strip, a
    /// round wait and a server-owned round, and a lifter alone in a gym must
    /// never see any of them. `.freestyle` is the style
    /// `LogFollowUp.calls(for:)` maps to NEITHER `advanceTurn` NOR an offered
    /// round close (`RoundPieces.swift:1205-1207`), so the round engine is
    /// never walked for an ad-hoc row — no special case needed — and
    /// `private.session_round_guard` freezes it the moment lifting starts.
    /// A SCHEDULED solo session keeps whatever style scheduling chose; this
    /// changes the ad-hoc insert alone.
    ///
    /// NOT `SessionStyleDefault.style(forExercises:)`, although the file
    /// table names it. That function is the CREW LOBBY's default and never
    /// returns `.freestyle` at all (its own header says so) — it answers
    /// `.rounds` or `.together`, and `.together` would put a shared clock on
    /// a session with one lifter. Decision 1's whole argument is that an
    /// ad-hoc solo row is `.freestyle`; that is what is written.
    ///
    /// THE TRIGGERS, WALKED AGAINST THIS EXACT INSERT rather than assumed
    /// (each read in `supabase/migrations`, Phase C1 S3):
    ///   * `session_venue_insert_guard` (20260918000204, + the squad_swaps
    ///     clause from 20260919000103) raises on a non-NULL `venue_id` or a
    ///     non-NULL `squad_swaps` at INSERT. `WorkoutSession` carries no
    ///     `squad_swaps` at all — deliberately, see `SessionSwapRepository
    ///     .loadSquad` — and `venueID` is a nil Optional, which the
    ///     synthesized `Encodable` emits through `encodeIfPresent` and so
    ///     OMITS (the same fact `SetUpdate` below documents from the other
    ///     side). Both land NULL. PASSES.
    ///   * `private.session_round_guard` is BEFORE UPDATE; an INSERT never
    ///     reaches it.
    ///   * `session_lifecycle_announce` (20260712000002) returns immediately
    ///     when `group_id IS NULL`. No chat row, no raise.
    ///   * `zzpush_session_invite` (20260716000001) skips the organizer's own
    ///     participant row, and here organizer and participant are the same
    ///     person. No self-push.
    ///   * `checkin_window_guard` and `engine_guard` and
    ///     `late_joiner_to_rotation_end` are all BEFORE **UPDATE** on
    ///     `session_participants` — the participant row below is INSERTED at
    ///     `check_in_state: "ready"`, which no UPDATE trigger ever sees. On
    ///     the later `warmup_ready` UPDATE that `mark_warmup_ready` makes,
    ///     `checkin_window_guard` reads `scheduled_for`, finds it NULL and
    ///     FAILS OPEN by its own comment (`20260715000003:36-41`);
    ///     `engine_guard` raises only for `late_minutes`/`burpees_owed`/
    ///     `turn_order`, none of which move; `late_joiner_to_rotation_end` is
    ///     `UPDATE OF check_in_state` and that column is not in the SET list.
    ///   * `set_logs_reject_prelive` (20260803000002) denies a list of
    ///     PRE-LIVE states; `in_progress` is not among them, which is why a
    ///     set logged on this row is accepted from the first second.
    /// Nothing raises for a solo ad-hoc row.
    ///
    /// CHECK-IN IS NOTHING THE LIFTER HAS TO DO, and constraint 10 is the
    /// reason this is stated here: the participant row is inserted AT
    /// `"ready"`, exactly as it always has been. This adds no location read,
    /// no `CLLocationManager` and no call to `CheckInService`.
    static func startSolo(routineID: UUID?) async throws -> WorkoutSession {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let session = WorkoutSession(
                id: UUID(),
                routineID: routineID,
                organizerID: userID,
                state: "in_progress",
                startedAt: Date(),
                completedAt: nil,
                createdAt: Date(),
                groupID: nil,
                roomCode: nil,
                scheduledFor: nil,
                seriesID: nil,
                currentTurnUserID: nil,
                currentTurnStartedAt: nil,
                style: .freestyle
            )
            let inserted: WorkoutSession = try await client
                .from("sessions")
                .insert(session)
                .select().single().execute().value
            // Add self as sole participant (for RLS unification across phases)
            _ = try await client
                .from("session_participants")
                .insert([
                    "session_id": session.id.uuidString,
                    "user_id": userID.uuidString,
                    "turn_order": "1",
                    "check_in_state": "ready"
                ])
                .execute()
            return inserted
        } catch { throw ErrorMapping.map(error) }
    }

    /// THE AD-HOC ENTRY POINTS' ONE START (Phase C1 S3) — adopt the workout
    /// that is already running, or begin one.
    ///
    /// THIS IS NOT A NEW LAW; IT IS A MOVED ONE. Until C1 the four entry
    /// points all mounted `WorkoutSessionView`, whose `startIfNeeded()`
    /// adopted a live solo session for the same routine before minting a new
    /// row (`WorkoutSessionView.swift:3930-3951`). That branch exists because
    /// of the 2026-08-22 field report — Start Workout became a dismissible
    /// sheet, so swipe-down and Start again minted a BRAND-NEW session with
    /// an empty carry and a fragmented history. C1 moves the capability out
    /// of that view, so the law has to move with it or the report comes back
    /// through the new door.
    ///
    /// IT ADOPTS FROM THE DATABASE, NOT FROM `AppState`. The shipped branch
    /// read `appState.liveSoloSession`, a view-registered in-memory handle
    /// that a relaunch lost; `liveForCurrentUser()` is the durable answer to
    /// the same question.
    ///
    /// THE DECISION IS `AdHocSessionAdoption.decide`, which is pure and
    /// tested — see that file for the check fix round 1 restored (the row
    /// must be one this lifter ORGANIZES; the old law had that by
    /// construction, since it read a handle the view itself had written) and
    /// for why a STALE row is ignored rather than closed.
    ///
    /// IT WRITES NOTHING BUT THE NEW ROW (fix round 2 / B3). A brief version
    /// of this function `complete()`d stale ad-hoc rows on the way past;
    /// `complete()` is not a quiet write — three `AFTER UPDATE OF state`
    /// triggers publish a leaderboard entry, push a `leaderboard_passed`
    /// notification to another user, and can post a campaign message into
    /// every group the lifter belongs to. That ruling is withdrawn and the
    /// stale row is left exactly as master leaves it.
    ///
    /// THE AGE FLOOR IS DROPPED HERE ON PURPOSE (`since: nil`), and it is a
    /// placement decision rather than a behavioural one: the window the
    /// adoption law turns on belongs in the pure function beside the rest of
    /// the law, where a test can read it, not split between a SQL predicate
    /// and a Swift one. `limit: 20` still bounds the read.
    ///
    /// A FAILED READ SIMPLY STARTS ONE. The adopt is an optimisation over
    /// correctness-of-history, not a gate: a lifter standing in a gym with no
    /// connection must still be able to begin, and `startSolo`'s own error is
    /// the one worth surfacing.
    static func startOrAdoptSolo(routineID: UUID?) async throws -> WorkoutSession {
        if let userID = await SupabaseService.shared.currentUserID(),
           let live = try? await liveForCurrentUser(since: nil) {
            let decision = AdHocSessionAdoption.decide(
                rows: live.map {
                    AdHocSessionAdoption.Candidate(
                        id: $0.id, routineID: $0.routineID,
                        organizerID: $0.organizerID, groupID: $0.groupID,
                        roomCode: $0.roomCode, scheduledFor: $0.scheduledFor,
                        startedAt: $0.startedAt)
                },
                routineID: routineID, me: userID, now: Date())

            if case .adopt(let adoptID) = decision,
               let running = live.first(where: { $0.id == adoptID }) {
                return running
            }
        }
        return try await startSolo(routineID: routineID)
    }

    static func complete(sessionID: UUID) async throws -> WorkoutSession {
        do {
            let updated: WorkoutSession = try await client
                .from("sessions")
                .update([
                    "state": "completed",
                    "completed_at": iso8601Now()
                ])
                .eq("id", value: sessionID)
                .select().single().execute().value
            return updated
        } catch { throw ErrorMapping.map(error) }
    }

    static func logSet(_ set: SetLog) async throws {
        do {
            _ = try await client.from("set_logs").insert(set).execute()
        } catch { throw ErrorMapping.map(error) }
    }

    private struct SetUpdate: Encodable {
        let reps: Int?
        let weight: Decimal?
        let rpe: Decimal?
        let isFailed: Bool
        let note: String?
        enum CodingKeys: String, CodingKey {
            case reps, weight, rpe, note
            case isFailed = "is_failed"
        }
        // Explicit encode (the PublishFieldsUpdate precedent): synthesized
        // Encodable uses encodeIfPresent, which OMITS nils — so clearing a
        // note/RPE would silently leave the old value stuck. encode(_:)
        // writes JSON null and actually clears the column.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(reps, forKey: .reps)
            try c.encode(weight, forKey: .weight)
            try c.encode(rpe, forKey: .rpe)
            try c.encode(isFailed, forKey: .isFailed)
            try c.encode(note, forKey: .note)
        }
    }

    /// Edits one set in place (the owner UPDATE policy has existed all
    /// along — edit was a client gap, not a backend one). Encodes nils as
    /// explicit nulls so clearing a note/RPE actually clears it.
    static func updateSet(_ log: SetLog) async throws {
        do {
            _ = try await client
                .from("set_logs")
                .update(SetUpdate(reps: log.reps, weight: log.weight,
                                  rpe: log.rpe, isFailed: log.isFailed,
                                  note: log.note))
                .eq("id", value: log.id)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Deletes one mistyped set (owner-scoped RLS, 20260730000003). PR rows
    /// born from the deleted set are deliberately NOT touched — see the
    /// migration header.
    /// Delete a whole workout from the ledger (owner field report
    /// 2026-08-21): set logs first, then the session row — both behind
    /// owner-scoped RLS delete policies. A completed workout is the
    /// athlete's to remove; PRs derived from it are separate rows and
    /// deliberately survive (records are records).
    static func deleteSession(id: UUID) async throws {
        do {
            try await client.from("set_logs")
                .delete().eq("session_id", value: id).execute()
            try await client.from("sessions")
                .delete().eq("id", value: id).execute()
        } catch { throw ErrorMapping.map(error) }
    }

    static func deleteSet(id: UUID) async throws {
        do {
            _ = try await client.from("set_logs").delete().eq("id", value: id).execute()
        } catch { throw ErrorMapping.map(error) }
    }

    static func history(userID: UUID, limit: Int) async throws -> [WorkoutSession] {
        do {
            let rows: [WorkoutSession] = try await client
                .from("sessions")
                .select()
                .eq("organizer_id", value: userID)
                .eq("state", value: "completed")
                .order("completed_at", ascending: false)
                .limit(limit)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func setLogs(sessionID: UUID) async throws -> [SetLog] {
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("session_id", value: sessionID)
                .order("set_index", ascending: true)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// Family-aware history (field report 2026-08-21: face pulls logged
    /// under two duplicate catalog rows showed different "last time"s per
    /// routine). Callers pass the alias FAMILY so history reads as one
    /// lift regardless of which duplicate a routine referenced.
    static func exerciseHistory(userID: UUID, exerciseIDs: [UUID], limit: Int) async throws -> [SetLog] {
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("user_id", value: userID)
                .in("exercise_id", values: exerciseIDs.map(\.uuidString))
                .eq("is_penalty", value: "false")
                .order("logged_at", ascending: false)
                .limit(limit)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func exerciseHistory(userID: UUID, exerciseID: UUID, limit: Int) async throws -> [SetLog] {
        do {
            // Failed rows are INCLUDED (owner 2026-08-13) — history views
            // already render them (FAIL badge, "authoritative" RPE column)
            // and math consumers read `completedReps`, never raw reps.
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("user_id", value: userID)
                .eq("exercise_id", value: exerciseID)
                .eq("is_penalty", value: "false")
                .order("logged_at", ascending: false)
                .limit(limit)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// A weight/reps pair from history — the raw material for rep-aware PR
    /// comparisons and 1RM estimation. Carries `isFailed` so callers can
    /// apply the failure doctrine (`SetLog.completedReps`): failed rows
    /// count at n − 1 completed reps, failed singles not at all.
    struct SetBasis: Decodable, Sendable {
        let weight: Decimal?
        let reps: Int?
        let isFailed: Bool?

        enum CodingKeys: String, CodingKey {
            case weight, reps
            case isFailed = "is_failed"
        }

        /// The doctrine, applied — mirrors `SetLog.completedReps` exactly.
        var completedReps: Int? {
            guard let reps, reps > 0 else { return nil }
            guard isFailed == true else { return reps }
            return reps > 1 ? reps - 1 : nil
        }
    }

    /// Every qualifying (weight, reps) pair for one exercise, heaviest first —
    /// the basis for "have I ever lifted this much for this many reps?".
    ///
    /// Two columns, not whole rows: a lifter with a long history costs a few KB
    /// here, which is what lets the caller prefetch this ONCE per exercise and
    /// answer PR questions for any rep count locally, with no network on the
    /// log path (the 2026-08-02 latency work).
    ///
    /// Ordered by weight descending so that if a history ever exceeds the
    /// limit, what survives is the heaviest work — the part every PR
    /// comparison is measured against.
    static func prBasis(userID: UUID, exerciseID: UUID, limit: Int = 500) async throws -> [SetBasis] {
        do {
            // Failed rows are INCLUDED (owner 2026-08-13): a failed set's
            // completed reps are real achievements — the doctrine conversion
            // (n − 1, failed singles dropped) happens in SetBasis.completedReps.
            let rows: [SetBasis] = try await client
                .from("set_logs")
                .select("weight,reps,is_failed")
                .eq("user_id", value: userID)
                .eq("exercise_id", value: exerciseID)
                .eq("is_penalty", value: "false")
                .order("weight", ascending: false, nullsFirst: false)
                .limit(limit)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// The heaviest non-failed, non-penalty set a user has ever recorded for
    /// one exercise — the PR comparison baseline.
    ///
    /// Deliberately NOT `exerciseHistory(limit: 200).compactMap(\.weight).max()`,
    /// which is what both live views used to call. That pulled 200 FULL rows
    /// across the network on every single set log, sitting in front of the
    /// write, and was the dominant cost behind the "app hangs, so users hit
    /// log repeatedly" report (2026-08-02). Postgres does the ordering here
    /// and answers with one column of one row.
    ///
    /// `nullsFirst: false` matters: Postgres sorts NULLs FIRST on a DESC
    /// order, so without it a weightless set (bodyweight/time-only) would win
    /// the `limit(1)` and report a prior best of 0. Filters mirror
    /// `exerciseHistory`'s exclusions exactly, so both agree on what counts.
    static func bestWeight(userID: UUID, exerciseID: UUID) async throws -> Decimal {
        struct WeightRow: Decodable { let weight: Decimal? }
        do {
            let rows: [WeightRow] = try await client
                .from("set_logs")
                .select("weight")
                .eq("user_id", value: userID)
                .eq("exercise_id", value: exerciseID)
                .eq("is_failed", value: "false")
                .eq("is_penalty", value: "false")
                .order("weight", ascending: false, nullsFirst: false)
                .limit(1)
                .execute().value
            return rows.first?.weight ?? 0
        } catch { throw ErrorMapping.map(error) }
    }

    /// All of a user's set logs since `since`, excluding failed/penalty —
    /// backs the Stats weekly-volume chart. Mirrors `exerciseHistory`'s
    /// failed/penalty exclusion filters exactly.
    static func recentSetLogs(userID: UUID, since: Date) async throws -> [SetLog] {
        do {
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("user_id", value: userID)
                .gte("logged_at", value: isoFmt.string(from: since))
                .eq("is_failed", value: "false")
                .eq("is_penalty", value: "false")
                .order("logged_at", ascending: true)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// Sessions by id — the workout ledger's second hop (distinct session
    /// ids from the caller's own set logs → the session rows).
    static func byIDs(_ ids: [UUID]) async throws -> [WorkoutSession] {
        guard !ids.isEmpty else { return [] }
        do {
            let rows: [WorkoutSession] = try await client
                .from("sessions")
                .select()
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    // MARK: - Trainer arm T4: the client's calendar

    /// Upcoming scheduled sessions on a user's calendar. For a trainer
    /// reading a client this rides the calendar-scope SELECT policy —
    /// an ungranted scope returns empty rows, never an error.
    static func upcomingScheduled(organizerID: UUID, limit: Int = 10) async throws -> [WorkoutSession] {
        do {
            let rows: [WorkoutSession] = try await client
                .from("sessions")
                .select()
                .eq("organizer_id", value: organizerID)
                .eq("state", value: "scheduled")
                .gte("scheduled_for", value: ISO8601DateFormatter().string(from: .now))
                .order("scheduled_for", ascending: true)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// Trainer books ON the client's calendar (policy "trainer books for
    /// client", 20260814000008): organizer stays the CLIENT so every
    /// downstream surface treats it as their own booked lift. Session row
    /// only — participant rows are the client's own session-start
    /// machinery's job, and RLS wouldn't let the trainer write them anyway.
    static func scheduleForClient(clientID: UUID, routineID: UUID?,
                                  scheduledFor: Date) async throws -> WorkoutSession {
        do {
            var row: [String: String] = [
                "id": UUID().uuidString,
                "organizer_id": clientID.uuidString,
                "state": "scheduled",
                "scheduled_for": ISO8601DateFormatter().string(from: scheduledFor)
            ]
            if let rid = routineID { row["routine_id"] = rid.uuidString }
            let inserted: WorkoutSession = try await client
                .from("sessions")
                .insert(row)
                .select().single().execute().value
            return inserted
        } catch { throw ErrorMapping.map(error) }
    }

    // MARK: - Phase 3a: Scheduling

    /// Schedule a session (group or ad-hoc). Inserts organizer + invitee participant rows.
    static func schedule(
        groupID: UUID?,
        inviteeIDs: [UUID],
        routineID: UUID?,
        scheduledFor: Date,
        generateRoomCode: Bool
    ) async throws -> WorkoutSession {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let sessionID = UUID()
            var row: [String: String] = [
                "id": sessionID.uuidString,
                "organizer_id": userID.uuidString,
                "state": "scheduled",
                "scheduled_for": ISO8601DateFormatter().string(from: scheduledFor)
            ]
            if let gid = groupID { row["group_id"] = gid.uuidString }
            if let rid = routineID { row["routine_id"] = rid.uuidString }
            if generateRoomCode { row["room_code"] = makeRoomCode() }

            let inserted: WorkoutSession = try await client
                .from("sessions")
                .insert(row)
                .select().single().execute().value

            // Organizer participant
            _ = try await client
                .from("session_participants")
                .insert([
                    "session_id": sessionID.uuidString,
                    "user_id": userID.uuidString,
                    "check_in_state": "online"
                ])
                .execute()

            // Invitee participants
            if !inviteeIDs.isEmpty {
                let inviteeRows = inviteeIDs.map { id in
                    ["session_id": sessionID.uuidString,
                     "user_id": id.uuidString,
                     "check_in_state": "invited"]
                }
                _ = try await client
                    .from("session_participants")
                    .insert(inviteeRows)
                    .execute()
            }

            return inserted
        } catch { throw ErrorMapping.map(error) }
    }

    /// Join a session by room code. Calls the SECURITY DEFINER RPC then fetches the session row.
    static func joinByCode(_ code: String) async throws -> WorkoutSession {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            let normalized = code.uppercased()
            let sessionID: UUID = try await client
                .rpc("join_session_by_code", params: ["p_code": normalized])
                .execute().value
            let session: WorkoutSession = try await client
                .from("sessions")
                .select()
                .eq("id", value: sessionID)
                .single()
                .execute().value
            return session
        } catch { throw ErrorMapping.map(error) }
    }

    /// Sessions where I am a participant with an active (pre-workout) state, ordered by scheduled_for.
    ///
    /// Bounded on BOTH axes, like the sibling `upcomingScheduled(organizerID:limit:)`.
    /// This query had neither, and a pre-workout state is sticky: nothing ever
    /// moves a stale `scheduled` row out of it, so every one stayed "upcoming"
    /// forever and the result set only ever grew. That is not hypothetical — the
    /// shared CI account reached ~680 rows, and this is the FIRST `async let` of
    /// `HomeView.refresh()`, which runs inside the wave the launch overlay holds
    /// on, so the cost landed on every single app launch. A real user who
    /// accumulates a few hundred never-started sessions pays exactly the same.
    ///
    /// The floor is `now − 30 min`, not `now`: Home only treats a session as
    /// MISSED 30 minutes after its scheduled start (`HomeView.todaysSession`,
    /// `nextActionableSession`), so a hard `>= now` would pull the "Join …" hero
    /// out from under someone two minutes late to their own lobby. Every
    /// pre-workout insert path sets `scheduled_for` (`schedule`,
    /// `scheduleForClient`, `SessionSeries`), so no row is lost to a NULL.
    ///
    /// `limit` mirrors the sibling's signature and defaults high enough that no
    /// existing caller changes behaviour — all four pass nothing and none render
    /// more than a handful.
    static func upcoming(limit: Int = 200) async throws -> [WorkoutSession] {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            // Server-side inner join on my participant rows. The previous
            // two-step (fetch ALL participations, then sessions .in(ids))
            // fanned every historical session ID into the request URL and
            // returned 400 once a user accumulated a few hundred sessions.
            let floor = Date.now.addingTimeInterval(-30 * 60)
            let sessions: [WorkoutSession] = try await client
                .from("sessions")
                .select("*, session_participants!inner(user_id)")
                .eq("session_participants.user_id", value: userID.uuidString)
                // `editing`/`voting`/`locked` narrowed out (D7's five-state
                // CHECK, mechanical cleanup decision 6, plan task S13): the
                // states no longer exist, so a row can no longer carry one.
                .in("state", values: ["scheduled", "lobby_open"])
                .gte("scheduled_for", value: ISO8601DateFormatter().string(from: floor))
                .order("scheduled_for", ascending: true)
                .limit(limit)
                .execute().value
            return sessions
        } catch { throw ErrorMapping.map(error) }
    }

    /// The current user's sessions that are ACTUALLY LIVE (`in_progress`).
    ///
    /// `upcoming()` deliberately excludes `in_progress` — its state list is
    /// the PRE-workout states, and four callers rely on that. So nothing in
    /// the app could answer "is one of my sessions running right now?"
    /// without a group id, and Home's `JOIN THE SESSION` state was
    /// unreachable: a crew session vanished from Home the instant it went
    /// live (`AppState.swift:148-149` even records the opposite belief —
    /// "Home's 'Join' hero + check-in widget already re-enter an in_progress
    /// group session" — which the query never delivered).
    ///
    /// Same idiom as `upcoming()` and for the same reasons: a server-side
    /// inner join on my participant rows rather than a two-step id fan-out,
    /// and a bounded `limit`. NO `scheduled_for` floor — a live session may
    /// carry a NULL `scheduled_for` (`startSolo` sets none), and filtering on
    /// it would drop exactly the rows this exists to find.
    ///
    /// NEWEST FIRST, AND NOTHING OLDER THAN SIX HOURS. Both bounds exist
    /// because `in_progress` is a state nothing ever leaves on its own:
    /// there is no reaper, and `20260716000003_push_cron.sql:169-199` only
    /// NOTIFIES at 30 and 60 minutes idle — it never transitions the row. A
    /// session nobody ends stays live indefinitely, so without these two
    /// lines it would own Home's one button for days, which is the exact
    /// class of bug the 30-minute missed cutoff was introduced for (user
    /// feedback 2026-07-24, "the gold shimmer ran forever on missed
    /// events"). Descending order fixes the preference too: when two
    /// sessions are live, the one that just started is the one worth
    /// resuming, not the stalest.
    ///
    /// Six hours, per the controller's ruling: no real gym session outlasts
    /// it, and an abandoned one still has the lobby's own resume and end
    /// paths — this bound governs what Home OFFERS, not what exists.
    ///
    /// The floor also excludes an `in_progress` row whose `started_at` is
    /// NULL. That combination is a data anomaly rather than a live session
    /// (`startSolo` sets it at insert; the `start_session` RPC sets it
    /// server-side), and a row that cannot say when it began cannot be aged
    /// out — so leaving it out is the honest reading of "live right now".
    ///
    /// Returns solo sessions too, and it always has — the state filter is
    /// the honest boundary for a repository. Home USED to drop them on the
    /// way out (`HomeView.actionableSessions`, `$0.groupID != nil`) because a
    /// live solo session had its own recovery surface and no place in the
    /// lobby. Phase C1 removed that filter: an ad-hoc session now runs in the
    /// one body and is routed by `SessionEntryView` like any other live
    /// session, so nothing downstream excludes solo any more.
    ///
    /// Two other callers read this: `CalendarSchedulingView:737` (which wants
    /// every live row) and `startOrAdoptSolo` above.
    ///
    /// `since: nil` DROPS THE FLOOR, and exactly one caller asks for that
    /// (fix round 1 / N6). The bound governs what Home OFFERS; a start has
    /// the opposite obligation, because a row too old to offer is precisely
    /// the row that needs ENDING, and hiding it in SQL is what left it
    /// `in_progress` forever. The default is unchanged, so every existing
    /// caller reads exactly what it read before.
    static func liveForCurrentUser(
        limit: Int = 20,
        since floor: Date? = Date.now.addingTimeInterval(-6 * 3600)
    ) async throws -> [WorkoutSession] {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            var query = client
                .from("sessions")
                .select("*, session_participants!inner(user_id)")
                .eq("session_participants.user_id", value: userID.uuidString)
                .eq("state", value: "in_progress")
            if let floor {
                query = query.gte("started_at",
                                  value: ISO8601DateFormatter().string(from: floor))
            }
            let sessions: [WorkoutSession] = try await query
                .order("started_at", ascending: false)
                .limit(limit)
                .execute().value
            return sessions
        } catch { throw ErrorMapping.map(error) }
    }

    /// Participants for a session, joined with their profiles.
    static func participants(sessionID: UUID) async throws -> [(participant: SessionParticipant, profile: Profile)] {
        do {
            let rows: [SessionParticipant] = try await client
                .from("session_participants")
                .select()
                .eq("session_id", value: sessionID.uuidString)
                .execute().value
            let profiles = try await ProfileRepository.fetchMany(ids: rows.map(\.userID))
            let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            return rows.compactMap { row in
                byID[row.userID].map { (participant: row, profile: $0) }
            }
        } catch { throw ErrorMapping.map(error) }
    }

    /// Transition session from 'scheduled' → 'lobby_open'. Idempotent (0 rows updated if already open).
    static func openLobby(sessionID: UUID) async throws {
        do {
            _ = try await client
                .from("sessions")
                .update(["state": "lobby_open"])
                .eq("id", value: sessionID.uuidString)
                .eq("state", value: "scheduled")
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Self check-in: updates own participant row with ready state, timestamp, and method.
    /// Leave a live session without ending it (2026-07-31): own-row flip
    /// to 'left' — outside the presence trio, so advance_turn skips you;
    /// walking back in (left → online) rides the late-joiner trigger to
    /// the rotation's end like any other re-arrival.
    static func leave(sessionID: UUID) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .from("session_participants")
                .update(["check_in_state": "left"])
                .eq("session_id", value: sessionID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    static func checkIn(sessionID: UUID, method: String) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            _ = try await client
                .from("session_participants")
                .update([
                    "check_in_state": "ready",
                    "check_in_at": fmt.string(from: Date()),
                    "check_in_method": method
                ])
                .eq("session_id", value: sessionID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
        // Decision 2: the venue comes from the VENUE check-in (venue_checkins,
        // server-verified geofence), never from `gyms` — a gyms row is a private
        // per-user geofence and is not a venues.id. Best-effort and last: a session
        // with no venue is today's behaviour, and a failure here must never turn a
        // successful check-in into an error the lifter sees.
        _ = try? await client.rpc("claim_session_venue",
                                  params: ["p_session_id": sessionID.uuidString]).execute()
    }

    /// Write my own energy for this session (spec §6, owner decision 18).
    ///
    /// A direct UPDATE, not an RPC: "participant updates own check-in"
    /// (20260712000001:22-25) already scopes the write to my own row, and the
    /// column's CHECK (1-5) is the backstop — the same reasoning
    /// `setWarmupMinutes` records for the organizer's own column.
    ///
    /// Clamped to `1...5` client-side before the write. A UI that can only
    /// send 1-5 still should not be the only guard: the clamp turns a caller's
    /// bug into a wrong-but-legal number instead of a 23514 the lobby would
    /// have to render as an error.
    static func setEnergy(sessionID: UUID, value: Int) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let clamped = min(5, max(1, value))
        do {
            _ = try await client
                .from("session_participants")
                .update(["energy": clamped])
                .eq("session_id", value: sessionID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    private struct TodaysScaleUpdate: Encodable {
        let todaysScale: TodaysScale?
        enum CodingKeys: String, CodingKey { case todaysScale = "todays_scale" }
    }

    /// Write MY OWN accepted set reduction for this session (decision 3,
    /// owner 2026-09-18's "Yes").
    ///
    /// A direct UPDATE, not an RPC, and `setEnergy`'s reasoning applies
    /// verbatim: "participant updates own check-in" (`20260712000001:22-25`)
    /// is `USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid())`
    /// WITH NO COLUMN LIST, so the policy already scopes this write to my own
    /// row. A third policy would be permissive-ORed with the two that exist
    /// and would grant nothing while looking like it granted something —
    /// which is why `20260912000101`'s header says the same of `energy`.
    ///
    /// BOTH BEFORE UPDATE TRIGGERS PASS, and they were read rather than
    /// assumed: `engine_guard` raises only when `late_minutes`,
    /// `burpees_owed` or `turn_order` change, and this changes none of them;
    /// `checkin_window_guard` compares `now() < scheduled_for - 20 minutes`,
    /// and a warm-up Accept happens after check-in opened, so it returns
    /// `NEW`. Identical to what `energy` already does in production.
    ///
    /// Every caller treats this as best-effort: a failed write leaves the
    /// in-memory scale standing, which is exactly B2's shipped behaviour.
    ///
    /// `scale` is NOT optional: nothing clears this column today, and
    /// `TodaysScaleUpdate`'s synthesized `Encodable` uses `encodeIfPresent`,
    /// so a `nil` here would silently PATCH `{}` instead of writing
    /// `todays_scale: null` (F12) — a signature that invites the bug it
    /// would take to reach it.
    static func setTodaysScale(sessionID: UUID, scale: TodaysScale) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .from("session_participants")
                .update(TodaysScaleUpdate(todaysScale: scale))
                .eq("session_id", value: sessionID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// All sessions for a group (upcoming + past), server-side filtered by group_id.
    /// Participant-only RLS automatically scopes results.
    static func groupSessions(groupID: UUID, pastLimit: Int = 10) async throws -> [WorkoutSession] {
        do {
            let rows: [WorkoutSession] = try await client
                .from("sessions")
                .select()
                .eq("group_id", value: groupID.uuidString)
                .order("scheduled_for", ascending: false)
                .limit(pastLimit + 20)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Bulk session lookup — backs Exercise History's "· solo" / "· {group}"
    /// meta suffix (needs each logged set's session to know its `group_id`).
    static func sessions(ids: [UUID]) async throws -> [WorkoutSession] {
        guard !ids.isEmpty else { return [] }
        do {
            // Chunked: .in(ids) rides the request URL, which caps out around
            // a couple hundred UUIDs (see upcoming()'s 400 regression).
            var rows: [WorkoutSession] = []
            for chunk in stride(from: 0, to: ids.count, by: 100).map({ Array(ids[$0..<min($0 + 100, ids.count)]) }) {
                let batch: [WorkoutSession] = try await client
                    .from("sessions")
                    .select()
                    .in("id", values: chunk.map(\.uuidString))
                    .execute()
                    .value
                rows.append(contentsOf: batch)
            }
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// Fetch a single session row by ID. Returns nil if not found (PGRST116).
    static func session(id: UUID) async throws -> WorkoutSession? {
        do {
            let row: WorkoutSession = try await client
                .from("sessions")
                .select()
                .eq("id", value: id.uuidString)
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

    /// Reschedule a session by updating its `scheduled_for` timestamp.
    /// Organizer-only; enforced by DB policy.
    static func reschedule(sessionID: UUID, to newDate: Date) async throws {
        do {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            _ = try await client
                .from("sessions")
                .update(["scheduled_for": fmt.string(from: newDate)])
                .eq("id", value: sessionID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Start: atomically calls `start_session` RPC (lateness + turn-order + state flip).
    /// Signature unchanged — LobbyView untouched.
    static func start(sessionID: UUID) async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .rpc("start_session", params: ["p_session_id": sessionID.uuidString])
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Client foreground heartbeat — resets the idle-ladder's activity clock
    /// while any participant has the app open on a live session
    /// (push-dossier.md §A.4: "app foreground >5s" counts as activity; v1
    /// fires once per scenePhase → active transition, no polling timer).
    /// No-ops server-side (0 rows updated, no error) if the session isn't
    /// in_progress — a heartbeat arriving just after a session ends is a
    /// harmless straggler, not something callers need to special-case.
    static func touchActivity(sessionID: UUID) async throws {
        do {
            _ = try await client
                .rpc("touch_session_activity", params: ["p_session": sessionID.uuidString])
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Set (or clear) the routine a lobby session will run.
    ///
    /// User report 2026-07-29: the lobby let you PROPOSE one exercise at a
    /// time but gave you no way to just pick a routine you had already
    /// built. No migration was needed — `sessions`' UPDATE policy has always
    /// been "organizer OR participant" (20260709000006, repointed by
    /// 20260726000001), so anyone in the lobby can set it, which matches how
    /// the rest of the lobby works (anyone can propose, anyone can vote).
    static func setRoutine(sessionID: UUID, routineID: UUID?) async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            // Explicit AnyJSON so clearing the routine sends a real null
            // rather than omitting the key (a synthesized Encodable would
            // drop it and silently leave the old routine in place).
            _ = try await client
                .from("sessions")
                .update(["routine_id": routineID.map { AnyJSON.string($0.uuidString) } ?? .null])
                .eq("id", value: sessionID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Set the warm-up window (minutes) for a session — the organizer's
    /// lobby control (20260803000004). Same direct-UPDATE path as
    /// `setRoutine` above: `sessions`' UPDATE policy already covers the
    /// organizer, and the column's own CHECK (0–60) is the backstop.
    static func setWarmupMinutes(sessionID: UUID, minutes: Int) async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .from("sessions")
                .update(["warmup_minutes": minutes])
                .eq("id", value: sessionID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Record the caller's "I'm warm" vote (20260803000004). Returns `true`
    /// when lifting has (now or already) started — this vote completed the
    /// unanimous PRESENT-participant set, or lifting had already begun —
    /// and `false` while the room is still waiting on someone. Raises
    /// P0001 for non-participants (server-side membership probe).
    static func markWarmupReady(sessionID: UUID) async throws -> Bool {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            let started: Bool = try await client
                .rpc("mark_warmup_ready", params: ["p_session_id": sessionID.uuidString])
                .execute().value
            return started
        } catch { throw ErrorMapping.map(error) }
    }

    /// Organizer force-start of lifting — the AFK escape hatch
    /// (20260803000004). Returns `true` when THIS call started lifting,
    /// `false` when the session isn't in progress or lifting had already
    /// begun. Non-organizers are rejected with P0001, the engine's
    /// authorization idiom (start_session, advance_turn).
    static func startLifting(sessionID: UUID) async throws -> Bool {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            let started: Bool = try await client
                .rpc("start_lifting", params: ["p_session_id": sessionID.uuidString])
                .execute().value
            return started
        } catch { throw ErrorMapping.map(error) }
    }

    /// Advance the turn to the next participant (current-lifter or organizer gated).
    ///
    /// `expectedVersion` makes the call REPLAYABLE (20260801000001): pass the
    /// `turnVersion` observed when the set was logged and the RPC becomes a
    /// no-op if the rotation has since moved on — which is what lets a turn
    /// advance survive being queued through a dead connection without ever
    /// double-advancing. Live (online) calls pass nil and behave exactly as
    /// before.
    static func advanceTurn(sessionID: UUID, expectedVersion: Int? = nil) async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            if let expectedVersion {
                _ = try await client
                    .rpc("advance_turn", params: [
                        "p_session_id": AnyJSON.string(sessionID.uuidString),
                        "p_expected_version": AnyJSON.integer(expectedVersion),
                    ])
                    .execute()
            } else {
                _ = try await client
                    .rpc("advance_turn", params: ["p_session_id": sessionID.uuidString])
                    .execute()
            }
        } catch { throw ErrorMapping.map(error) }
    }

    // MARK: - Phase B1: style, round, stations (20260913000101/…102)

    /// Set how this session moves (plan task S1; written by the lobby card,
    /// plan task S2).
    ///
    /// A direct PATCH, the same path `setWarmupMinutes` above takes: the
    /// shipped "organizer or participant can update session" policy already
    /// grants the write to ANY participant, which is the point — the style is
    /// the crew's decision, not the organizer's (owner decision 1). Two
    /// backstops narrow it, both server-side: the column's own CHECK, and
    /// `private.session_round_guard`, which rejects a style change once
    /// `lifting_started_at` is set. The card stops rendering at that same
    /// moment, so the UI never offers a write the server will reject.
    static func setStyle(sessionID: UUID, style: SessionStyle) async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .from("sessions")
                .update(["style": style.rawValue])
                .eq("id", value: sessionID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Close the current round — the server decides whether it actually
    /// closes (`public.advance_round`, 20260913000102).
    ///
    /// Returns the round number in force AFTER the call, which is not always
    /// one more than before: the RPC returns the current round unchanged when
    /// the crew is not done (some present lifter has no non-penalty set since
    /// `round_started_at`), and when `expectedRound` no longer matches. Both
    /// are successes, not failures — a client cannot push the round forward
    /// early, and a client that crashes cannot hold it back, because anyone's
    /// call closes it once the condition is true.
    ///
    /// `expectedRound` makes the call REPLAYABLE in `advanceTurn`'s own idiom
    /// (see that function): pass the round observed when the set was logged
    /// and a queued replay becomes a no-op if the round has since moved. The
    /// round is monotonic — unlike the rotation, which wraps — so comparing
    /// it is safe.
    ///
    /// `advance_turn` is NOT replaced by this (plan constraint 20): the
    /// client that logs calls `advanceTurn` as it always has, then this. The
    /// second call is cheap, safe to repeat and safe to lose.
    ///
    /// `force` (ruling R-B13, fix-forward `20260913000107`): the crew's
    /// skip line's own escape. `public.advance_round`'s close predicate
    /// otherwise requires a non-penalty set from EVERY present lifter since
    /// the round opened — with one lifter out it just returns the current
    /// round unchanged, which is what left the crew's skip with nothing
    /// that could actually move them on. `p_force` bypasses that predicate
    /// once the open round is >= 90 s old (the server's own floor, not a
    /// client-chosen number); ANY participant may pass it, and nothing is
    /// recorded against the skipped lifter — their set stays in their plan
    /// and they rejoin at the top of the next round. `advance_round` is now
    /// a single 3-arg function (`DROP FUNCTION ... (uuid, integer)` ran
    /// first, so no 2-arg overload survives to be ambiguous with this one);
    /// `p_force` always rides the call, defaulting `false` for every
    /// existing caller's behaviour.
    @discardableResult
    static func advanceRound(sessionID: UUID, expectedRound: Int? = nil,
                             force: Bool = false) async throws -> Int {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            var params: [String: AnyJSON] = [
                "p_session_id": .string(sessionID.uuidString),
                "p_force": .bool(force),
            ]
            if let expectedRound {
                params["p_expected_round"] = .integer(expectedRound)
            }
            let round: Int = try await client
                .rpc("advance_round", params: params)
                .execute().value
            return round
        } catch { throw ErrorMapping.map(error) }
    }

    private struct SetStationsParams: Encodable {
        let sessionID: UUID
        let exercisePosition: Int
        let stations: [SessionStations.Station]
        enum CodingKeys: String, CodingKey {
            case sessionID = "p_session_id"
            case exercisePosition = "p_exercise_position"
            case stations = "p_stations"
        }
    }

    /// Write the station assignment for one exercise
    /// (`public.set_session_stations`, 20260913000102).
    ///
    /// Returns what is STORED, which is not always what was sent: the RPC is
    /// idempotent on `exercisePosition`, so a second call at the same
    /// exercise reads the first one back unchanged. Turn order is fixed
    /// within an exercise (owner decision 6) and this is what enforces it —
    /// two clients re-mixing at the same exercise change cannot disagree.
    ///
    /// Throws P0001 when a station is deeper than three or when the union of
    /// `lifterIDs` is not exactly the present participants; the caller keeps
    /// the previous assignment and logs, because a failed re-mix must never
    /// block a round.
    static func setStations(
        sessionID: UUID,
        exercisePosition: Int,
        stations: [SessionStations.Station]
    ) async throws -> SessionStations {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            let stored: SessionStations = try await client
                .rpc("set_session_stations", params: SetStationsParams(
                    sessionID: sessionID,
                    exercisePosition: exercisePosition,
                    stations: stations
                ))
                .execute().value
            return stored
        } catch { throw ErrorMapping.map(error) }
    }

    // MARK: - Phase 3b: Duration editing

    /// Edit a completed session's start/end timestamps.
    ///
    /// Validates:
    ///   - `newCompletedAt > newStartedAt`
    ///   - Both new values are within ±48 h of the ORIGINAL session times
    ///
    /// On success:
    ///   1. Inserts a `session_duration_edits` audit row (old + new values, edited_by me).
    ///   2. Updates `sessions` (started_at, completed_at, duration_was_edited = true, edited_by = me).
    ///
    /// HealthKit re-write on edit: this data-layer function stays HealthKit-
    /// agnostic (no platform-framework import here) — the caller re-writes
    /// the exported `HKWorkout` after a successful edit by calling
    /// `HealthKitBridge.replaceWorkout(session:setLogs:)`. See
    /// `CompletedSessionView.DurationEditSheet.save()` (Phase H), the one
    /// client-side call site that invokes `editDuration`.
    static func editDuration(
        sessionID: UUID,
        newStartedAt: Date,
        newCompletedAt: Date,
        reason: String?
    ) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }

        // Client-side validation: order must be correct.
        guard newCompletedAt > newStartedAt else {
            throw GymSyncError.validation("End time must be after start time.")
        }

        do {
            // Fetch the current session to obtain current stored values (used for the audit row).
            guard let existing = try await session(id: sessionID) else {
                throw GymSyncError.notFound
            }
            guard existing.state == "completed" else {
                throw GymSyncError.validation("Only completed sessions can be edited.")
            }

            // ±48 h anchor rule: always measure against the ORIGINAL times, not the current
            // stored values. The earliest audit row preserves the old_* values from the very
            // first edit (which recorded the session's as-completed times). If no audit row
            // exists this is the first edit, so fall back to the current stored values.
            struct EarliestAuditRow: Decodable {
                let old_started_at: String?
                let old_completed_at: String?
            }
            let earliestRows: [EarliestAuditRow] = try await client
                .from("session_duration_edits")
                .select("old_started_at,old_completed_at")
                .eq("session_id", value: sessionID.uuidString)
                .order("edited_at", ascending: true)
                .limit(1)
                .execute().value

            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // Derive anchor dates from the earliest audit row when available.
            let anchorStart: Date?
            let anchorEnd: Date?
            if let earliest = earliestRows.first {
                anchorStart = earliest.old_started_at.flatMap { isoFmt.date(from: $0) }
                    ?? existing.startedAt
                anchorEnd = earliest.old_completed_at.flatMap { isoFmt.date(from: $0) }
                    ?? existing.completedAt
            } else {
                anchorStart = existing.startedAt
                anchorEnd   = existing.completedAt
            }

            let fortyEightHours: TimeInterval = 48 * 3600

            if let anchor = anchorStart {
                guard abs(newStartedAt.timeIntervalSince(anchor)) <= fortyEightHours else {
                    throw GymSyncError.validation("New start time must be within 48 hours of the original start.")
                }
            }
            if let anchor = anchorEnd {
                guard abs(newCompletedAt.timeIntervalSince(anchor)) <= fortyEightHours else {
                    throw GymSyncError.validation("New end time must be within 48 hours of the original end.")
                }
            }

            // 1. Insert audit row (Codable struct for type safety).
            // old_* values always reflect the CURRENT stored values so the chain is auditable;
            // the anchor for ±48 h validation is handled separately above.
            struct DurationEditInsert: Encodable {
                let id: String
                let session_id: String
                let edited_by: String
                let old_started_at: String?
                let old_completed_at: String?
                let new_started_at: String
                let new_completed_at: String
                let reason: String?
            }
            let auditRow = DurationEditInsert(
                id:               UUID().uuidString,
                session_id:       sessionID.uuidString,
                edited_by:        userID.uuidString,
                old_started_at:   existing.startedAt.map   { isoFmt.string(from: $0) },
                old_completed_at: existing.completedAt.map { isoFmt.string(from: $0) },
                new_started_at:   isoFmt.string(from: newStartedAt),
                new_completed_at: isoFmt.string(from: newCompletedAt),
                reason:           reason
            )

            _ = try await client
                .from("session_duration_edits")
                .insert(auditRow)
                .execute()

            // 2. Update session row.
            _ = try await client
                .from("sessions")
                .update([
                    "started_at":          isoFmt.string(from: newStartedAt),
                    "completed_at":        isoFmt.string(from: newCompletedAt),
                    "duration_was_edited": "true",
                    "edited_by":           userID.uuidString
                ])
                .eq("id", value: sessionID.uuidString)
                .execute()

        } catch let e as GymSyncError {
            throw e
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Old start/end timestamps from the most recent duration-edit audit row —
    /// backs the "Duration edited by X · was Y" audit line on Session Detail.
    static func latestDurationEdit(sessionID: UUID) async throws -> (oldStartedAt: Date?, oldCompletedAt: Date?)? {
        struct AuditRow: Decodable {
            let old_started_at: String?
            let old_completed_at: String?
        }
        do {
            let rows: [AuditRow] = try await client
                .from("session_duration_edits")
                .select("old_started_at,old_completed_at")
                .eq("session_id", value: sessionID.uuidString)
                .order("edited_at", ascending: false)
                .limit(1)
                .execute().value
            guard let row = rows.first else { return nil }
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return (
                oldStartedAt: row.old_started_at.flatMap { isoFmt.date(from: $0) },
                oldCompletedAt: row.old_completed_at.flatMap { isoFmt.date(from: $0) }
            )
        } catch { throw ErrorMapping.map(error) }
    }

    // MARK: - Phase 3b/Canvas Task 3: Burpee Ledger

    /// Group-wide crew debts (Fix round 1 — task-3-report.md). Calls the
    /// `group_burpee_ledger` SECURITY DEFINER RPC instead of querying
    /// `session_participants` directly: the direct query was gated by
    /// "readable by other participants" RLS, so a member who joined the
    /// group after some of its sessions had already run was never invited to
    /// those sessions and couldn't see their `session_participants` rows —
    /// silently undercounting EVERY crew member's total, not just their own.
    /// The RPC instead gates on current group membership and sums across
    /// every session the group has run, regardless of who was invited to
    /// which one (see `burpee_ledger_rpc_test.sql`).
    static func burpeeLedger(groupID: UUID) async throws -> [BurpeeLedgerMath.CrewDebt] {
        do {
            let aggregates: [GroupBurpeeLedgerAggregate] = try await client
                .rpc("group_burpee_ledger", params: ["p_group": groupID.uuidString])
                .execute().value
            return BurpeeLedgerMath.crewDebts(aggregates: aggregates)
        } catch { throw ErrorMapping.map(error) }
    }

    /// The current user's OWN `session_participants` rows for the group,
    /// joined with the session fields the "YOU OWE" banner's detail line
    /// needs (late minutes, per-minute rate, date, live-session id). Kept as
    /// a direct query (not the RPC above): a user's own rows are always RLS
    /// -visible via "user_id = auth.uid()" regardless of current group
    /// membership timing, so there's no undercount risk here to fix — see
    /// `BurpeeLedgerMath.youOweSummary`.
    static func myBurpeeLedgerRows(groupID: UUID) async throws -> [BurpeeLedgerRow] {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [BurpeeLedgerRow] = try await client
                .from("session_participants")
                .select("user_id, check_in_state, late_minutes, burpees_owed, sessions!inner(id, state, scheduled_for, started_at, late_penalty)")
                .eq("sessions.group_id", value: groupID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    // MARK: - Canvas Task 3: Activity Feed (frame 45)

    /// The calling user's completed sessions, month-groupable client-side
    /// from `completed_at` — powers `ActivityFeedView`. Calls the
    /// `activity_feed` SECURITY DEFINER RPC (same precedent as
    /// `burpeeLedger` above, `20260719000002_activity_feed_rpc.sql`) instead
    /// of a direct `sessions` query: the RPC aggregates each row's set count,
    /// volume, and PR count server-side via lateral joins against
    /// `set_logs`/`personal_records`, which a client-side fetch would
    /// otherwise need an extra round-trip per session for.
    static func activityFeed(limit: Int = 50) async throws -> [ActivityFeedRow] {
        do {
            let rows: [ActivityFeedRow] = try await client
                .rpc("activity_feed", params: ["p_limit": limit])
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// All set_logs for a session ordered by logged_at ascending.
    static func sessionSets(sessionID: UUID) async throws -> [SetLog] {
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("session_id", value: sessionID.uuidString)
                .order("logged_at", ascending: true)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }
}
