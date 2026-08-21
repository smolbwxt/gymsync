import Foundation
import Supabase

// MARK: - Models

/// A recurring session series.
/// `until_date` is a DATE column (PostgREST returns "yyyy-MM-dd").
/// We decode it as a String and expose `untilDate: Date` parsed in the series' own timezone.
/// Tasks 5/6 must use `untilDate` (the computed Date property), not the raw string.
struct SessionSeries: Codable, Identifiable, Sendable {
    let id: UUID
    /// Nil for a SOLO series — a standing commitment with no crew
    /// (migration 20260803000006 made the column nullable).
    let groupID: UUID?
    let organizerID: UUID
    let timezone: String
    /// Raw DATE string from PostgREST ("yyyy-MM-dd"). Use `untilDate` for Calendar math.
    let untilDateString: String
    /// 1 = weekly (every pre-existing series), 2 = every other week
    /// (field report #9). Bounded 1-4 by a DB check.
    let intervalWeeks: Int
    /// Raw DATE string pinning which weeks fire for interval > 1 — the
    /// creation day. NULL on pre-interval rows, never consulted at 1.
    let anchorDateString: String?
    let endedAt: Date?
    let createdAt: Date

    // MARK: Public contract: Tasks 5/6 compile against this.
    /// Midnight of the until-day in the SERIES' OWN timezone — not UTC.
    /// A UTC-pinned parse shifted the day one earlier for any timezone west
    /// of UTC (e.g. "2026-07-27" → Jul 26 20:00 ET), which made
    /// materialization drop the final day's occurrence whenever until fell
    /// on a series weekday, and prefilled SeriesEditorView's picker a day
    /// early (CI run 29307177206 caught the count mismatch).
    var untilDate: Date {
        let parts = untilDateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantFuture }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezone) ?? .current
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            ?? .distantFuture
    }

    /// The anchor day at midnight in the series' own timezone — same
    /// round-trip law as `untilDate`. Falls back to createdAt for
    /// pre-interval rows (interval 1 never reads it).
    var anchorDate: Date {
        guard let str = anchorDateString else { return createdAt }
        let parts = str.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return createdAt }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezone) ?? .current
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            ?? createdAt
    }

    /// Formats `date`'s calendar day in `timezone` as the DATE-column string
    /// ("yyyy-MM-dd"). The mirror of `untilDate`: both directions of the
    /// round-trip must use the series timezone or the day shifts near
    /// midnight/timezone boundaries.
    static func dayString(for date: Date, in timezone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case organizerID = "organizer_id"
        case timezone
        case untilDateString = "until_date"
        case intervalWeeks = "interval_weeks"
        case anchorDateString = "anchor_date"
        case endedAt = "ended_at"
        case createdAt = "created_at"
    }
}

/// Input type for one recurrence rule (weekday + time).
struct SeriesDayInput: Sendable, Hashable {
    let weekday: Int    // 1=Sun … 7=Sat (matches DB and Swift Calendar.Weekday)
    let hour: Int
    let minute: Int
    let routineID: UUID?
}

/// A `session_series_days` row decoded from PostgREST.
/// `time_local` is a TIME column ("HH:mm:ss" from PostgREST).
struct SeriesDay: Codable, Sendable, Hashable {
    let seriesID: UUID
    let weekday: Int    // 1=Sun … 7=Sat
    let timeLocal: String  // "HH:mm:ss"
    let routineID: UUID?

    enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
        case weekday
        case timeLocal = "time_local"
        case routineID = "routine_id"
    }
}

// MARK: - WorkoutSession series extension
// seriesID is decoded in WorkoutSession.CodingKeys (see Session.swift).

// MARK: - Repository

enum SeriesRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    // MARK: - ISO8601 helpers

    private static let iso8601Frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func isoString(_ date: Date) -> String {
        iso8601Frac.string(from: date)
    }

    // MARK: - Pure materialization (unit-testable, no network)

    /// Returns every (date, input) pair in [from's calendar day … until's calendar day] (inclusive,
    /// in `timezone`) where the calendar weekday matches any rule in `days`, and the
    /// combined date+time in `timezone` is strictly after `from`. Sorted ascending.
    ///
    /// Swift `Calendar` handles DST automatically — combining a date with hour/minute
    /// in a DST-aware calendar produces the correct wall-clock time regardless of
    /// clock changes (e.g., US fall-back "fall-back" day).
    static func occurrenceDates(
        days: [SeriesDayInput],
        from: Date,
        until: Date,
        timezone: TimeZone,
        intervalWeeks: Int = 1,
        anchor: Date? = nil
    ) -> [(date: Date, input: SeriesDayInput)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        // Every-other-week (field report #9): keep only weeks whose
        // whole-week distance from the ANCHOR week divides by the
        // interval. Anchored to creation, not to `from` — an edit-forward
        // mid-cycle re-expands from "now" and must not flip which weeks
        // fire. Euclidean modulo so an anchor after `from` can't skip
        // everything.
        let interval = max(1, intervalWeeks)
        let anchorWeekStart = cal.dateInterval(of: .weekOfYear, for: anchor ?? from)?.start

        // Build a lookup: weekday → [SeriesDayInput]
        var rulesByWeekday: [Int: [SeriesDayInput]] = [:]
        for rule in days {
            rulesByWeekday[rule.weekday, default: []].append(rule)
        }

        var results: [(date: Date, input: SeriesDayInput)] = []

        // Iterate day-by-day from floor(from) through floor(until) in `timezone`.
        // Start at the calendar-day start of `from` in the target timezone.
        var cursor = cal.startOfDay(for: from)
        let lastDay = cal.startOfDay(for: until)

        while cursor <= lastDay {
            if interval > 1, let anchorWeekStart,
               let weekStart = cal.dateInterval(of: .weekOfYear, for: cursor)?.start {
                let weeks = cal.dateComponents([.weekOfYear],
                                               from: anchorWeekStart,
                                               to: weekStart).weekOfYear ?? 0
                if ((weeks % interval) + interval) % interval != 0 {
                    guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                    cursor = next
                    continue
                }
            }
            let wd = cal.component(.weekday, from: cursor) // 1=Sun…7=Sat
            if let rules = rulesByWeekday[wd] {
                for rule in rules {
                    // Combine calendar date of cursor + rule hour/minute in timezone.
                    var comps = cal.dateComponents([.year, .month, .day], from: cursor)
                    comps.hour = rule.hour
                    comps.minute = rule.minute
                    comps.second = 0
                    if let occurrence = cal.date(from: comps), occurrence > from {
                        results.append((date: occurrence, input: rule))
                    }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return results.sorted { $0.date < $1.date }
    }

    // MARK: - Private materialization helper

    /// Shared by `create` and `editSeriesForward`. Materializes sessions + participants
    /// for every occurrence returned by `occurrenceDates`. One bulk insert per table.
    private static func materializeOccurrences(
        series: SessionSeries,
        days: [SeriesDayInput],
        from: Date,
        until: Date,             // caller's own until — NOT series.untilDate, whose
                                 // DATE round-trip is day-granular (see untilDate doc)
        memberUserIDs: [UUID],   // ALL group members (organizer already included via members query)
        organizerID: UUID
    ) async throws {
        let tz = TimeZone(identifier: series.timezone) ?? .current
        let occurrences = occurrenceDates(days: days, from: from, until: until, timezone: tz,
                                          intervalWeeks: series.intervalWeeks,
                                          anchor: series.anchorDate)
        guard !occurrences.isEmpty else { return }

        // Build session rows
        var sessionRows: [[String: String]] = []
        var sessionIDs: [(id: UUID, routineID: UUID?)] = []
        for occ in occurrences {
            let sid = UUID()
            var row: [String: String] = [
                "id": sid.uuidString,
                "organizer_id": organizerID.uuidString,
                "series_id": series.id.uuidString,
                "state": "scheduled",
                "scheduled_for": isoString(occ.date)
            ]
            // Omitted for a solo series, so each occurrence is a groupless
            // session — the same shape `startSolo` produces.
            if let gid = series.groupID { row["group_id"] = gid.uuidString }
            if let rid = occ.input.routineID {
                row["routine_id"] = rid.uuidString
            }
            sessionRows.append(row)
            sessionIDs.append((id: sid, routineID: occ.input.routineID))
        }

        // Bulk-insert sessions
        _ = try await client
            .from("sessions")
            .insert(sessionRows)
            .execute()

        // Build participant rows: organizer (online) + every other member (invited)
        var participantRows: [[String: String]] = []
        for (sid, _) in sessionIDs {
            // Organizer
            participantRows.append([
                "session_id": sid.uuidString,
                "user_id": organizerID.uuidString,
                "check_in_state": "online"
            ])
            // All other members
            for memberID in memberUserIDs where memberID != organizerID {
                participantRows.append([
                    "session_id": sid.uuidString,
                    "user_id": memberID.uuidString,
                    "check_in_state": "invited"
                ])
            }
        }

        // Bulk-insert participants
        _ = try await client
            .from("session_participants")
            .insert(participantRows)
            .execute()
    }

    // MARK: - Public API

    /// Creates a series, materializes all occurrences, and calls `finalize_series`.
    //
    // Task 6 item 3 (reliability/debt roll-up — series ops transactionality
    // note, docs/superpowers/specs/2026-07-18-reliability-debt-design.md
    // §6): five sequential client-orchestrated writes (session_series
    // insert → session_series_days insert → group_members read →
    // materializeOccurrences' two bulk inserts → finalize_series RPC), NOT
    // wrapped in a single server-side transaction. A failure partway (e.g.
    // network drop after the series row lands but before day rules insert)
    // leaves a partially-created series behind — the caller sees the
    // thrown error (every call site maps it through `ErrorMapping`/
    // `GymSyncError` to a visible `errorText`, consistent with every other
    // repository call in this codebase; see ScheduleSessionView.swift and
    // LobbyView.swift's identical `catch let error as GymSyncError { ... }`
    // pattern at their `SeriesRepository.create`/`cancelSeriesForward`
    // call sites), but nothing here rolls the partial writes back. v1
    // scope is honest error surfacing, not a transactional rewrite — same
    // documented limitation `editSeriesForward` below already carries for
    // its own re-run hazard. A retry after a partial failure is NOT
    // guaranteed idempotent (a second `create` call makes a second series
    // row rather than resuming the first).
    /// `groupID` is optional (2026-08-02): nil creates a SOLO series — a
    /// standing commitment with no crew, whose sessions have no group and
    /// exactly one participant. See migration 20260803000006 for the
    /// matching RLS and the silent finalize.
    static func create(
        groupID: UUID?,
        days: [SeriesDayInput],
        untilDate: Date,
        timezone: TimeZone = .current,
        intervalWeeks: Int = 1
    ) async throws -> SessionSeries {
        guard let organizerID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let seriesID = UUID()
            let untilStr = SessionSeries.dayString(for: untilDate, in: timezone)

            // Build time_local strings ("HH:mm:ss") for each day rule
            func timeString(hour: Int, minute: Int) -> String {
                String(format: "%02d:%02d:00", hour, minute)
            }

            // Insert series row
            var seriesRow: [String: String] = [
                "id": seriesID.uuidString,
                "organizer_id": organizerID.uuidString,
                "timezone": timezone.identifier,
                "until_date": untilStr,
                "interval_weeks": String(max(1, intervalWeeks)),
                // The anchor is the creation day: "every other week"
                // means every other week FROM NOW.
                "anchor_date": SessionSeries.dayString(for: Date(), in: timezone)
            ]
            // Omitted entirely for a solo series — the column is nullable and
            // absent means NULL, which is what the solo RLS branch keys on.
            if let groupID { seriesRow["group_id"] = groupID.uuidString }
            let series: SessionSeries = try await client
                .from("session_series")
                .insert(seriesRow)
                .select()
                .single()
                .execute()
                .value

            // Insert day rules — one bulk insert
            let dayRows: [[String: String]] = days.map { input in
                var row: [String: String] = [
                    "series_id": seriesID.uuidString,
                    "weekday": String(input.weekday),
                    "time_local": timeString(hour: input.hour, minute: input.minute)
                ]
                if let rid = input.routineID { row["routine_id"] = rid.uuidString }
                return row
            }
            _ = try await client
                .from("session_series_days")
                .insert(dayRows)
                .execute()

            // Fetch all current group members for participant rows. A solo
            // series has no roster to fetch — `materializeOccurrences` still
            // adds the organizer, so each session lands with exactly one
            // participant, shaped like any other solo workout.
            var memberIDs: [UUID] = []
            if let groupID {
                let memberRows: [GroupMember] = try await client
                    .from("group_members")
                    .select()
                    .eq("group_id", value: groupID.uuidString)
                    .execute()
                    .value
                memberIDs = memberRows.map(\.userID)
            }

            // Materialize sessions + participants — pass the caller's
            // untilDate directly so the count is identical to the hermetic
            // occurrenceDates() computation on the same inputs.
            try await materializeOccurrences(
                series: series,
                days: days,
                from: Date(),
                until: untilDate,
                memberUserIDs: memberIDs,
                organizerID: organizerID
            )

            // Call finalize_series RPC (posts 🔁 summary message)
            _ = try await client
                .rpc("finalize_series", params: ["p_series_id": seriesID.uuidString])
                .execute()

            return series
        } catch { throw ErrorMapping.map(error) }
    }

    /// Fetch a single series row. Returns nil if not found (PGRST116).
    static func series(id: UUID) async throws -> SessionSeries? {
        do {
            let row: SessionSeries = try await client
                .from("session_series")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            return row
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil
        } catch { throw ErrorMapping.map(error) }
    }

    /// Fetch all day rules for a series, ordered by weekday ascending.
    static func seriesDays(seriesID: UUID) async throws -> [SeriesDay] {
        do {
            let rows: [SeriesDay] = try await client
                .from("session_series_days")
                .select()
                .eq("series_id", value: seriesID.uuidString)
                .order("weekday", ascending: true)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// All sessions belonging to a series, ordered by scheduled_for ascending.
    static func occurrences(seriesID: UUID) async throws -> [WorkoutSession] {
        do {
            let rows: [WorkoutSession] = try await client
                .from("sessions")
                .select()
                .eq("series_id", value: seriesID.uuidString)
                .order("scheduled_for", ascending: true)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// Delete a single occurrence (organizer-gated via DB policy).
    static func cancelOccurrence(sessionID: UUID) async throws {
        do {
            _ = try await client
                .from("sessions")
                .delete()
                .eq("id", value: sessionID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Mark series ended and delete all future scheduled occurrences.
    // Task 6 item 3: same non-transactional caveat as `create`/
    // `editSeriesForward` above — the `ended_at` update and the future-
    // occurrences delete are two separate round trips. A failure between
    // them leaves the series marked ended with its future occurrences
    // still scheduled (visible, cancellable individually via
    // `cancelOccurrence`, just not swept in bulk) rather than a torn
    // half-deleted state — the safer of the two orderings if this has to
    // be non-atomic, which is why `ended_at` is updated first. Error
    // surfacing is the same consistent `ErrorMapping`/`GymSyncError` →
    // `errorText` path as every other call site (LobbyView.swift).
    static func cancelSeriesForward(seriesID: UUID) async throws {
        do {
            let now = isoString(Date())
            // Update ended_at
            _ = try await client
                .from("session_series")
                .update(["ended_at": now])
                .eq("id", value: seriesID.uuidString)
                .execute()
            // Delete future scheduled occurrences
            _ = try await client
                .from("sessions")
                .delete()
                .eq("series_id", value: seriesID.uuidString)
                .eq("state", value: "scheduled")
                .gt("scheduled_for", value: now)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Replace day rules and future occurrences with new schedule, then finalize again.
    // NOTE: Non-transactional re-run hazard — retry after partial failure may duplicate
    // future occurrences (delete succeeds but re-insert runs twice). v1 documented limitation.
    static func editSeriesForward(
        seriesID: UUID,
        days: [SeriesDayInput],
        untilDate: Date
    ) async throws {
        guard let organizerID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let now = Date()
            let nowStr = isoString(now)

            // Fetch the series up front — its stored timezone drives the
            // DATE formatting, and its groupID scopes the member query for
            // re-materialization below.
            guard let existing = try await self.series(id: seriesID) else {
                throw GymSyncError.notFound
            }
            let seriesTZ = TimeZone(identifier: existing.timezone) ?? .current
            let untilStr = SessionSeries.dayString(for: untilDate, in: seriesTZ)

            // Update until_date on series
            _ = try await client
                .from("session_series")
                .update(["until_date": untilStr])
                .eq("id", value: seriesID.uuidString)
                .execute()

            // Replace day rows: delete all, then insert new
            _ = try await client
                .from("session_series_days")
                .delete()
                .eq("series_id", value: seriesID.uuidString)
                .execute()

            func timeString(hour: Int, minute: Int) -> String {
                String(format: "%02d:%02d:00", hour, minute)
            }
            let dayRows: [[String: String]] = days.map { input in
                var row: [String: String] = [
                    "series_id": seriesID.uuidString,
                    "weekday": String(input.weekday),
                    "time_local": timeString(hour: input.hour, minute: input.minute)
                ]
                if let rid = input.routineID { row["routine_id"] = rid.uuidString }
                return row
            }
            _ = try await client
                .from("session_series_days")
                .insert(dayRows)
                .execute()

            // Delete future scheduled occurrences
            _ = try await client
                .from("sessions")
                .delete()
                .eq("series_id", value: seriesID.uuidString)
                .eq("state", value: "scheduled")
                .gt("scheduled_for", value: nowStr)
                .execute()

            // Fetch group members — a solo series has no roster.
            var memberIDs: [UUID] = []
            if let gid = existing.groupID {
                let memberRows: [GroupMember] = try await client
                    .from("group_members")
                    .select()
                    .eq("group_id", value: gid.uuidString)
                    .execute()
                    .value
                memberIDs = memberRows.map(\.userID)
            }

            // Re-materialize from now forward. `existing` still carries the
            // OLD until_date string, which is why `until` is passed
            // explicitly — the caller's Date, not the row round-trip.
            try await materializeOccurrences(
                series: existing,
                days: days,
                from: now,
                until: untilDate,
                memberUserIDs: memberIDs,
                organizerID: organizerID
            )

            // finalize_series again (posts updated 🔁 summary)
            _ = try await client
                .rpc("finalize_series", params: ["p_series_id": seriesID.uuidString])
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
