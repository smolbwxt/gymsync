import Foundation
import Supabase

// MARK: - Models

/// A recurring session series.
/// `until_date` is a DATE column (PostgREST returns "yyyy-MM-dd").
/// We decode it as a String and expose `untilDate: Date` via a static formatter.
/// Tasks 5/6 must use `untilDate` (the computed Date property), not the raw string.
struct SessionSeries: Codable, Identifiable, Sendable {
    let id: UUID
    let groupID: UUID
    let organizerID: UUID
    let timezone: String
    /// Raw DATE string from PostgREST ("yyyy-MM-dd"). Use `untilDate` for Calendar math.
    let untilDateString: String
    let endedAt: Date?
    let createdAt: Date

    // MARK: Public contract: Tasks 5/6 compile against this.
    var untilDate: Date { SessionSeries.untilDateFormatter.date(from: untilDateString) ?? Date.distantFuture }

    static let untilDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0) // DATE is timezone-agnostic
        return f
    }()

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case organizerID = "organizer_id"
        case timezone
        case untilDateString = "until_date"
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
        timezone: TimeZone
    ) -> [(date: Date, input: SeriesDayInput)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone

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
        memberUserIDs: [UUID],   // ALL group members (organizer already included via members query)
        organizerID: UUID
    ) async throws {
        let tz = TimeZone(identifier: series.timezone) ?? .current
        let occurrences = occurrenceDates(days: days, from: from, until: series.untilDate, timezone: tz)
        guard !occurrences.isEmpty else { return }

        // Build session rows
        var sessionRows: [[String: String]] = []
        var sessionIDs: [(id: UUID, routineID: UUID?)] = []
        for occ in occurrences {
            let sid = UUID()
            var row: [String: String] = [
                "id": sid.uuidString,
                "organizer_id": organizerID.uuidString,
                "group_id": series.groupID.uuidString,
                "series_id": series.id.uuidString,
                "state": "scheduled",
                "scheduled_for": isoString(occ.date)
            ]
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
    static func create(
        groupID: UUID,
        days: [SeriesDayInput],
        untilDate: Date,
        timezone: TimeZone = .current
    ) async throws -> SessionSeries {
        guard let organizerID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let seriesID = UUID()
            let untilStr = SessionSeries.untilDateFormatter.string(from: untilDate)

            // Build time_local strings ("HH:mm:ss") for each day rule
            func timeString(hour: Int, minute: Int) -> String {
                String(format: "%02d:%02d:00", hour, minute)
            }

            // Insert series row
            let seriesRow: [String: String] = [
                "id": seriesID.uuidString,
                "group_id": groupID.uuidString,
                "organizer_id": organizerID.uuidString,
                "timezone": timezone.identifier,
                "until_date": untilStr
            ]
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

            // Fetch all current group members for participant rows
            let memberRows: [GroupMember] = try await client
                .from("group_members")
                .select()
                .eq("group_id", value: groupID.uuidString)
                .execute()
                .value
            let memberIDs = memberRows.map(\.userID)

            // Materialize sessions + participants
            try await materializeOccurrences(
                series: series,
                days: days,
                from: Date(),
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
            let untilStr = SessionSeries.untilDateFormatter.string(from: untilDate)

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

            // Refetch series to get groupID + timezone for re-materialization
            guard let updatedSeries = try await self.series(id: seriesID) else {
                throw GymSyncError.notFound
            }

            // Fetch group members
            let memberRows: [GroupMember] = try await client
                .from("group_members")
                .select()
                .eq("group_id", value: updatedSeries.groupID.uuidString)
                .execute()
                .value
            let memberIDs = memberRows.map(\.userID)

            // Re-materialize from now forward
            try await materializeOccurrences(
                series: updatedSeries,
                days: days,
                from: now,
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
