import Foundation

// MARK: - WeekBooker
//
// Turn a week's schedule into REAL sessions. Owner 2026-08-27, asked
// whether setting a week should book sessions or only record intent:
// "Book real sessions."
//
// Until now WeekScheduleSheet wrote a BlockWeekSchedule row and nothing
// else — the calendar drew planned dots over days that had no session on
// them, and the athlete's phone calendar never heard about it. The
// display-only override was the silent-discard shape again: an input
// accepted, a receipt shown ("SET WEEK 3"), nothing booked.
//
// Replace, don't accumulate: the solo sessions already sitting in the
// window are cleared before the new ones go in, so setting a week twice
// yields one set of sessions, not two. Group sessions (groupID != nil)
// are somebody else's plans and are never touched.
enum WeekBooker {

    /// Book one solo session per selected weekday inside `window`, at
    /// `hour:minute`, cycling through `routines` Monday-first so day 1
    /// of the block lands on the first training day of the week.
    /// Returns how many sessions were booked. Days already in the past
    /// are skipped — the past cannot be scheduled, only logged.
    @discardableResult
    static func book(window: (start: Date, end: Date),
                     weekdays: Set<Int>,
                     hour: Int, minute: Int,
                     routines: [Routine]) async -> Int {
        let calendar = Calendar.current

        // A booking without its routine is the owner-reported defect
        // ("sessions booked by coach don't carry a routine when checking
        // in") - if the caller's routine list is empty, fetch the block's
        // own day routines rather than booking blanks.
        var routines = routines
        if routines.isEmpty,
           let ownerID = await SupabaseService.shared.currentUserID(),
           let all = try? await RoutineRepository.fetchAll(ownerID: ownerID) {
            routines = all
                .filter { $0.name.hasPrefix("Coach · ") && $0.prescribedBy == nil }
                .sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
        }

        // 1. Clear what this week held before. Occurrences that came from
        //    a series are cancelled through the series (so the series
        //    stays consistent); plain sessions are deleted outright.
        //
        //    Explicit limit: this is the one caller that must see PAST the
        //    near horizon. `upcoming()`'s default of 200 is sized for what a
        //    screen renders, but this pass has to find every session already
        //    sitting inside `window` — and a long recurring series can put
        //    200+ rows ahead of it (a year of 4x/week is ~208). A target week
        //    beyond the default would silently not be cleared and would then
        //    be double-booked by step 2.
        if let upcoming = try? await SessionRepository.upcoming(limit: 1000) {
            for session in upcoming where session.groupID == nil {
                guard let when = session.scheduledFor,
                      when >= window.start, when < window.end else { continue }
                if session.seriesID != nil {
                    try? await SeriesRepository.cancelOccurrence(sessionID: session.id)
                } else {
                    try? await SessionRepository.deleteSession(id: session.id)
                }
            }
        }

        // 2. Book the new ones.
        let weekStart = calendar.startOfDay(for: window.start)
        let daysInWindow: [Date] = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
        // Monday-first, so the order the athlete reads the toggles in is
        // the order the block's days are handed out.
        let ordered = weekdays.sorted { displayIndex($0) < displayIndex($1) }
        let syncToCalendar = CalendarSyncPrefsStore.isEnabled()
        var booked = 0
        for (index, weekday) in ordered.enumerated() {
            guard let day = daysInWindow.first(where: {
                      calendar.component(.weekday, from: $0) == weekday }),
                  let when = calendar.date(bySettingHour: hour, minute: minute,
                                           second: 0, of: day),
                  when > Date()
            else { continue }
            let routine = routines.isEmpty ? nil : routines[index % routines.count]
            guard let session = try? await SessionRepository.schedule(
                groupID: nil, inviteeIDs: [], routineID: routine?.id,
                scheduledFor: when, generateRoomCode: false)
            else { continue }
            booked += 1
            // Same gate and bridge as ScheduleSessionView.
            if syncToCalendar {
                _ = await EventKitBridge.syncEvent(
                    session: session,
                    routineName: routine?.name ?? "Coach session",
                    exerciseCount: nil)
            }
        }
        return booked
    }

    /// Calendar weekday (1 = Sunday) → Monday-first position.
    private static func displayIndex(_ weekday: Int) -> Int {
        (weekday + 5) % 7
    }
}
