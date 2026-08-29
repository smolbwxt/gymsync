import Foundation

// MARK: - ProgramToday
//
// ONE answer to "which routine is today's" for an athlete with an
// enrolled block. Owner 2026-08-28: "Home leads with today's booked
// session from the enrollment" and "everything should be provided by
// Coach so that someone under his Coaching does not have to do anything
// to manage their workouts."
//
// Resolution order:
//   1. The session's own routine, when it carries one.
//   2. The enrolled block's next "Coach · " day routine not yet completed
//      this week (the generator's own day order) — and when this resolves
//      a SESSION that arrived routine-less, the routine is attached to
//      the row (SessionRepository.setRoutine), so the lobby, the labels
//      and the watch all see it from then on. Coach-booked sessions from
//      before WeekBooker carried routines are healed at first touch.
//   3. nil — no block or no Coach routines; the caller keeps its own
//      fallback (Home offers the picker, the lobby stays untargeted).
//
// Group sessions are never resolved: the organizer owns that pick.
enum ProgramToday {

    static func resolveRoutine(session: WorkoutSession?,
                               ownerID: UUID) async -> (routine: Routine, exercises: [RoutineExercise])? {
        if let routineID = session?.routineID,
           let fetched = try? await RoutineRepository.fetch(id: routineID) {
            return fetched
        }
        if let session, session.groupID != nil { return nil }
        guard let active = try? await ProgramRepository.active(),
              active.endedAt == nil else { return nil }
        guard let all = try? await RoutineRepository.fetchAll(ownerID: ownerID) else { return nil }
        let coach = all
            .filter { $0.name.hasPrefix("Coach · ") && $0.prescribedBy == nil }
            .sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
        guard !coach.isEmpty else { return nil }

        // The week's remaining day: first Coach routine with no completed
        // session this calendar week. All done → wrap to day one.
        let calendar = Calendar.current
        let doneThisWeek: Set<UUID> = Set(
            ((try? await SessionRepository.history(userID: ownerID, limit: 30)) ?? [])
                .filter { s in
                    guard let done = s.completedAt else { return false }
                    return calendar.isDate(done, equalTo: Date(),
                                           toGranularity: .weekOfYear)
                }
                .compactMap(\.routineID))
        let pick = coach.first { !doneThisWeek.contains($0.id) } ?? coach[0]
        guard let fetched = try? await RoutineRepository.fetch(id: pick.id) else { return nil }

        if let session, session.routineID == nil {
            // Durable heal, best-effort: the athlete's own session
            // (organizer = them, RLS update policy covers it).
            try? await SessionRepository.setRoutine(sessionID: session.id,
                                                    routineID: pick.id)
        }
        return fetched
    }
}
