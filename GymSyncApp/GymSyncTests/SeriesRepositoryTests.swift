import XCTest
@testable import GymSync

/// Tests for `SeriesRepository` — split into hermetic (pure logic, no network)
/// and live-DB sections.
final class SeriesRepositoryTests: XCTestCase {

    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    // MARK: - Hermetic: occurrenceDates

    func testOccurrenceDatesMonFriTwoWeeks() throws {
        // Anchor: 2026-07-15 (Wednesday) 12:00 America/New_York
        let tz = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 15
        comps.hour = 12; comps.minute = 0; comps.second = 0
        let anchor = try XCTUnwrap(cal.date(from: comps))

        // Rule: Mon (2) + Fri (6) at 19:00 local
        let days: [SeriesDayInput] = [
            SeriesDayInput(weekday: 2, hour: 19, minute: 0, routineID: nil),
            SeriesDayInput(weekday: 6, hour: 19, minute: 0, routineID: nil)
        ]

        // until = anchor + 14 days = 2026-07-29
        let until = try XCTUnwrap(cal.date(byAdding: .day, value: 14, to: anchor))

        let results = SeriesRepository.occurrenceDates(days: days, from: anchor, until: until, timezone: tz)

        // 2026-07-15 Wed (anchor)
        // Mon 2026-07-20 ✓, Fri 2026-07-24 ✓, Mon 2026-07-27 ✓, Fri 2026-07-31 — but until=07-29!
        // Wait: anchor+14 = 2026-07-29 (Tue). So dates in window:
        //   Mon 07-20 ✓, Fri 07-24 ✓, Mon 07-27 ✓  (Fri 07-31 > until)
        // That's 3 dates, not 4. Let me recalculate per spec:
        // spec says "Mon+Fri rule for 2 weeks → exactly 4 dates"
        // 2026-07-15 (Wed anchor). Going forward:
        //   Fri 07-17 > anchor ✓, Mon 07-20 ✓, Fri 07-24 ✓, Mon 07-27 ✓ (within anchor+14=07-29)
        //   Fri 07-31 is beyond 07-29 ✗
        // Yes: 4 occurrences: 07-17(Fri), 07-20(Mon), 07-24(Fri), 07-27(Mon)
        XCTAssertEqual(results.count, 4, "Expected exactly 4 occurrences for Mon+Fri over 14 days from a Wednesday")

        // All strictly after anchor
        for occ in results {
            XCTAssertGreaterThan(occ.date, anchor, "All occurrences must be strictly after 'from'")
        }

        // All weekdays are Mon(2) or Fri(6)
        for occ in results {
            let wd = cal.component(.weekday, from: occ.date)
            XCTAssertTrue(wd == 2 || wd == 6, "Occurrence weekday \(wd) not in {Mon(2), Fri(6)}")
        }

        // All at 19:00 local
        for occ in results {
            let h = cal.component(.hour, from: occ.date)
            let m = cal.component(.minute, from: occ.date)
            XCTAssertEqual(h, 19, "Hour must be 19")
            XCTAssertEqual(m, 0, "Minute must be 0")
        }
    }

    func testOccurrenceDatesDSTFallback() throws {
        // DST case: US fall-back is 2026-11-01 (clocks go back at 2am).
        // Anchor: 2026-10-28 (Wednesday) 12:00 local America/New_York.
        // Rule: Sun (1) at 19:00 local, until anchor+14d = 2026-11-11.
        // Sundays in window: 2026-11-01 (fall-back day!) and 2026-11-08.
        // Both must render as 19:00 local (Calendar handles DST automatically).
        let tz = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 28
        comps.hour = 12; comps.minute = 0; comps.second = 0
        let anchor = try XCTUnwrap(cal.date(from: comps))

        let days: [SeriesDayInput] = [
            SeriesDayInput(weekday: 1, hour: 19, minute: 0, routineID: nil) // Sun
        ]
        let until = try XCTUnwrap(cal.date(byAdding: .day, value: 14, to: anchor))

        let results = SeriesRepository.occurrenceDates(days: days, from: anchor, until: until, timezone: tz)

        XCTAssertEqual(results.count, 2, "Expected 2 Sundays (Nov 1 fall-back + Nov 8)")

        for occ in results {
            let h = cal.component(.hour, from: occ.date)
            let m = cal.component(.minute, from: occ.date)
            XCTAssertEqual(h, 19, "Fall-back Sunday must still be 19:00 local — got \(h):\(m)")
            XCTAssertEqual(m, 0)
            XCTAssertEqual(cal.component(.weekday, from: occ.date), 1) // Sunday
        }
    }

    // MARK: - Hermetic: until-day boundary (regression, CI run 29307177206)

    /// Pinned-date lock on the until-boundary semantics: an occurrence ON the
    /// until-day counts even when its time-of-day is later than until's clock
    /// time (day-inclusive, Teams-style). First caught live on 2026-07-14,
    /// when the live test's now+13d anchor landed on a series Monday for the
    /// first time since the test was written.
    func testOccurrenceDatesIncludesOccurrenceOnUntilDay() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        // from: Tue 2026-07-14 01:00 ET; until: Mon 2026-07-27 01:00 ET.
        // Mon(2)+Wed(4) 18:00 → Wed 15, Mon 20, Wed 22, and Mon 27 18:00 —
        // the last is AFTER until's 01:00 clock time but ON the until day.
        let from = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 1)))
        let until = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: 1)))
        let days: [SeriesDayInput] = [
            SeriesDayInput(weekday: 2, hour: 18, minute: 0, routineID: nil),
            SeriesDayInput(weekday: 4, hour: 18, minute: 0, routineID: nil)
        ]

        let dates = SeriesRepository.occurrenceDates(days: days, from: from, until: until, timezone: tz).map(\.date)

        XCTAssertEqual(dates.count, 4, "the until-day occurrence must be included (day-inclusive)")
        let last = try XCTUnwrap(dates.last)
        XCTAssertEqual(cal.component(.month, from: last), 7)
        XCTAssertEqual(cal.component(.day, from: last), 27)
        XCTAssertEqual(cal.component(.hour, from: last), 18)
    }

    /// The DATE column round-trip must reproduce the same calendar day in the
    /// series' own timezone. A UTC-pinned parse turned "2026-07-27" into
    /// Jul 26 20:00 ET — materialization then dropped the final Monday and
    /// SeriesEditorView prefilled its picker a day early.
    func testUntilDateRoundTripPreservesDayInSeriesTimezone() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        let series = SessionSeries(
            id: UUID(), groupID: UUID(), organizerID: UUID(),
            timezone: "America/New_York",
            untilDateString: "2026-07-27",
            endedAt: nil, createdAt: Date()
        )
        XCTAssertEqual(cal.component(.year, from: series.untilDate), 2026)
        XCTAssertEqual(cal.component(.month, from: series.untilDate), 7)
        XCTAssertEqual(cal.component(.day, from: series.untilDate), 27,
                       "untilDate must land on the stored day in the series timezone, not UTC")

        // Write path mirrors: any moment within the day formats to that day.
        let lateEvening = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: 21)))
        XCTAssertEqual(SessionSeries.dayString(for: lateEvening, in: tz), "2026-07-27",
                       "21:00 ET must not format as the next UTC day")
    }

    // MARK: - Live DB tests

    func testCreateSeriesAndCancelForward() async throws {
        // Create group (creator is sole member — no counterpart needed for this test)
        let group = try await GroupRepository.create(name: "CI Series Group")

        do {
            // Mon(2) + Wed(4) at 18:00. Anchor = now. Until = +13 days.
            let tz = TimeZone(identifier: "America/New_York") ?? .current
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            let until = try XCTUnwrap(cal.date(byAdding: .day, value: 13, to: Date()))

            let days: [SeriesDayInput] = [
                SeriesDayInput(weekday: 2, hour: 18, minute: 0, routineID: nil), // Mon
                SeriesDayInput(weekday: 4, hour: 18, minute: 0, routineID: nil)  // Wed
            ]

            let series = try await SeriesRepository.create(
                groupID: group.id,
                days: days,
                untilDate: until,
                timezone: tz
            )
            XCTAssertEqual(series.groupID, group.id)

            // 1. Occurrence count matches hermetic computation
            let expected = SeriesRepository.occurrenceDates(days: days, from: Date(), until: until, timezone: tz)
            let occurrences = try await SeriesRepository.occurrences(seriesID: series.id)
            XCTAssertEqual(
                occurrences.count, expected.count,
                "Live occurrence count \(occurrences.count) must match hermetic computation \(expected.count)"
            )

            // 2. Every occurrence has seriesID pointing back to this series
            for occ in occurrences {
                XCTAssertEqual(
                    occ.seriesID, series.id,
                    "session.series_id must equal series.id"
                )
            }

            // 3. Exactly ONE system_session chat message with 🔁 in body
            let msgs = try await SupabaseService.shared.client
                .from("chat_messages")
                .select()
                .eq("group_id", value: group.id.uuidString)
                .eq("kind", value: "system_session")
                .execute()
                .value as [ChatMessage]
            let seriesMessages = msgs.filter { ($0.body ?? "").contains("🔁") }
            XCTAssertEqual(seriesMessages.count, 1, "finalize_series must post exactly one 🔁 system message")

            // 4. cancelSeriesForward empties future scheduled occurrences
            try await SeriesRepository.cancelSeriesForward(seriesID: series.id)
            let afterCancel = try await SeriesRepository.occurrences(seriesID: series.id)
            XCTAssertEqual(
                afterCancel.filter { $0.state == "scheduled" }.count,
                0,
                "cancelSeriesForward must delete all future scheduled occurrences"
            )

            // Cleanup
            try await GroupRepository.deleteGroup(groupID: group.id)

        } catch {
            // Always clean up even on failure
            try? await GroupRepository.deleteGroup(groupID: group.id)
            throw error
        }
    }
}
