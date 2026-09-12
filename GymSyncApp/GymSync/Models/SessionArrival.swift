import Foundation

// MARK: - SessionArrival
//
// Plan task S3. **Everything from S4 to S11 types against this file.** It is
// pure values and pure functions: no view, no repository, no clock beyond an
// injected `Date`. The lobby's two hardest facts — who is where, and what
// counts as solo — are named here once so no screen has to re-derive either.

/// Spec §1: a lifter with the lobby open outside the gym's geofence is *on the
/// way*; inside it, *at the gym*; *checked in* once they tap (or the geofence
/// confirms). Owner decision 12 pins the first one.
enum ArrivalStage: String, CaseIterable, Sendable {
    case onTheWay, atTheGym, checkedIn

    /// The column's kicker (rule 3: caps, 10-11 pt, muted).
    var caps: String {
        switch self {
        case .onTheWay:  return "ON THE WAY"
        case .atTheGym:  return "AT THE GYM"
        case .checkedIn: return "CHECKED IN"
        }
    }

    /// SF Symbols only — no decorative emoji (rule 2).
    var glyph: String {
        switch self {
        case .onTheWay:  return "figure.walk"
        case .atTheGym:  return "mappin.and.ellipse"
        case .checkedIn: return "checkmark.circle.fill"
        }
    }
}

/// One lifter in the lobby, as the track draws them.
struct ArrivalRow: Identifiable, Equatable, Sendable {
    let id: UUID              // user id
    let name: String
    let avatarURL: URL?
    let stage: ArrivalStage
    /// Self-reported energy, 1-5. nil = has not answered (never 0).
    let energy: Int?
    let isYou: Bool
    let isLate: Bool          // check_in_state == "late" || "no_show"
}

enum ArrivalLaw {
    /// CHECKED IN is a DB fact; the other two are a presence fact.
    ///
    /// `check_in_state == "ready"` is checked in, full stop — spec §3.1's
    /// "checked in is ready; there is no separate roster and no separate ready
    /// tick" (owner decision 16's reversal of round 1's two signals).
    ///
    /// AT THE GYM requires knowing where somebody standing in the room is, and
    /// no column stores that: the geofence is evaluated on each device
    /// (CheckInService.distanceCheck). So it comes from the lobby's own
    /// presence payload, which each device publishes for ITSELF. A lifter
    /// whose device has published nothing reads ON THE WAY, which is the
    /// honest default — see this plan's "What this plan does not decide" 1.
    ///
    /// **THE DB FACT IS TESTED FIRST**, which is the case a naive
    /// `if let publishedStage` ordering gets wrong: a lifter who checked in
    /// and then walked out of the geofence, or whose device published
    /// `onTheWay` before the tap landed, is still checked in.
    static func stage(checkInState: String?, publishedStage: String?) -> ArrivalStage {
        if checkInState == "ready" { return .checkedIn }
        guard let published = publishedStage,
              let stage = ArrivalStage(rawValue: published) else { return .onTheWay }
        // A device may not publish itself INTO the DB fact. `checkedIn` is
        // `session_participants.check_in_state`'s to say and nothing else's.
        return stage == .checkedIn ? .onTheWay : stage
    }

    /// `check_in_state` values that mean the session started without this
    /// lifter — spec §3.1's late lane. `evaluate_lateness` / `mark_no_shows`
    /// write both and neither is this plan's to change (constraint 18).
    static func isLate(checkInState: String?) -> Bool {
        checkInState == "late" || checkInState == "no_show"
    }
}

enum SessionShape {
    /// Spec §2 / owner decision 3: a scheduled SOLO session has no lobby.
    ///
    /// NOT `group_id == nil`. `ScheduleSessionView`'s `.friends` and `.code`
    /// modes also leave group_id nil (ScheduleSessionView.swift:778-786), and
    /// the code's own comment already calls that condition "solo" — the F10
    /// heal reads it that way and the crash report's H4 is the consequence
    /// (context-map §6). A solo session is one participant and no room code.
    static func isSolo(participantCount: Int, roomCode: String?) -> Bool {
        participantCount <= 1 && roomCode == nil
    }
}

enum LobbyCopy {
    /// "2 of 4 checked in" — Start's caption, counting the CHECKED IN column
    /// and nothing else (spec §3.1).
    static func checkedInCaption(checkedIn: Int, total: Int) -> String {
        "\(checkedIn) of \(total) checked in"
    }

    /// "Everyone's here. Let's work." — owner decision 20, verbatim.
    static let everyoneHere = "Everyone's here. Let's work."

    /// The leader's caption on the accent widget.
    static let readyLeaderCaption = "Yours to start — or it starts on its own."

    /// Everyone else's, in the same slot on the same widget.
    ///
    /// It says exactly what will happen, which is why it is not decoration:
    /// the organizer's client fires Start on its own a few seconds after the
    /// last check-in (plan task S7's consensus Start), and a crewmate watching
    /// a screen that only said "Waiting for Alex" would think it had stalled.
    static func readyCrewmateCaption(leaderFirstName: String) -> String {
        "Waiting for \(leaderFirstName) — or it starts on its own"
    }

    /// Under the foot's neutral secondary, which is the same act.
    static let secondaryStartNote = "Same action, in the thumb zone"

    /// "3 OF 4 REPORTED" — the energy card's right-hand read.
    static func energyReported(reported: Int, total: Int) -> String {
        "\(reported) OF \(total) REPORTED"
    }
}
