import SwiftUI

// MARK: - Together
//
// One interval clock for the whole crew, and no turns (spec §3.3, owner
// decisions 1 and 13; plan task S9). The production twin of `together-clock`
// (frame 117 — the v1 render, whose zone colours owner decision 17 restored),
// captured as `session-together-clock` (frame 140).
//
// THE INTERVALS ARE THE ROUTINE'S OWN. `routine_exercises.cardio_minutes` and
// `.cardio_zone` (`20260814000009:11-12`) are the only interval data this app
// has; nothing else in the schema describes a work/rest structure. A routine
// with none renders ONE OPEN INTERVAL and says so, rather than inventing a
// structure nobody prescribed.

// MARK: - The plan

/// The routine's cardio rows as a run of intervals — a pure function, so the
/// view is value-in over it and the law is tested rather than inspected.
enum TogetherIntervals {

    /// One interval. `minutes == nil` is an OPEN interval: it runs until the
    /// crew stops, and its clock counts UP.
    struct Interval: Identifiable, Equatable {
        let id: UUID
        /// The exercise's own name, or `Work` for the open interval.
        let name: String
        /// `cardio_zone`, 1-5. Nil when the row prescribes none.
        let zone: Int?
        /// `cardio_minutes`. Nil only on the open interval.
        let minutes: Int?

        /// `Z3 · 4 min`, `4 min`, `Z3`, or nothing.
        var detail: String {
            var parts: [String] = []
            if let zone { parts.append("Z\(zone)") }
            if let minutes { parts.append("\(minutes) min") }
            return parts.joined(separator: " · ")
        }
    }

    /// The one open interval, for a routine with nothing prescribed. A fixed
    /// id so a re-render is the same interval and not a new one.
    static let openIntervalID = UUID(uuidString: "00000000-0000-0000-0000-0000000009f1") ?? UUID()

    /// `Work` — the open interval's name. Sentence case: it is a word, not a
    /// kicker (rule 9); the clock's own phase label is what shouts.
    static let openIntervalName = "Work"

    /// Rows in, intervals out.
    ///
    /// A ROW WITHOUT MINUTES IS NOT AN INTERVAL. `cardio_zone` alone
    /// prescribes an effort and no duration, and a clock cannot count down an
    /// effort — such a row is skipped rather than given a made-up length.
    /// When nothing survives, the crew gets ONE OPEN INTERVAL, which is the
    /// honest shape of "we are all working until somebody says stop".
    static func plan(
        from rows: [(id: UUID, name: String, cardioZone: Int?, cardioMinutes: Int?)]
    ) -> [Interval] {
        let intervals = rows.compactMap { row -> Interval? in
            guard let minutes = row.cardioMinutes, minutes > 0 else { return nil }
            return Interval(id: row.id, name: row.name,
                            zone: row.cardioZone, minutes: minutes)
        }
        guard intervals.isEmpty else { return intervals }
        return [Interval(id: openIntervalID, name: openIntervalName, zone: nil, minutes: nil)]
    }

    /// Where the crew is, from the time lifting began.
    struct Position: Equatable {
        /// Which interval, zero-based.
        let index: Int
        /// How far into it.
        let elapsedInInterval: TimeInterval
        /// Seconds left. NIL for an open interval, which counts up.
        let remaining: TimeInterval?
        /// 0...1 through the current interval; 0 for an open one, which has
        /// no end to be a fraction of.
        let progress: Double
    }

    /// Walk the run of intervals by their own prescribed lengths.
    ///
    /// PAST THE END, THE CREW IS ON THE LAST INTERVAL WITH NOTHING LEFT. A
    /// session that overruns its plan has not started a thirteenth round; it
    /// is over its twelfth, and the clock says zero rather than wrapping.
    static func position(in intervals: [Interval], elapsed: TimeInterval) -> Position? {
        guard !intervals.isEmpty else { return nil }
        var remainingElapsed = max(0, elapsed)

        for (index, interval) in intervals.enumerated() {
            guard let minutes = interval.minutes else {
                // An open interval swallows the rest of the clock.
                return Position(index: index,
                                elapsedInInterval: remainingElapsed,
                                remaining: nil,
                                progress: 0)
            }
            let length = TimeInterval(minutes) * 60
            if remainingElapsed < length {
                return Position(index: index,
                                elapsedInInterval: remainingElapsed,
                                remaining: length - remainingElapsed,
                                progress: length > 0 ? remainingElapsed / length : 0)
            }
            remainingElapsed -= length
        }

        let last = intervals.count - 1
        let length = TimeInterval(intervals[last].minutes ?? 0) * 60
        return Position(index: last, elapsedInInterval: length, remaining: 0, progress: 1)
    }
}

// MARK: - The crew's readings, per interval

/// Where the timeline's bars come from: the last reading seen from each
/// lifter in each interval.
///
/// SESSION-LOCAL, BOUNDED, AND IT DIES WITH THE VIEW — the same category as
/// `RecoveryBuffer`, which is what spec §6's "no new store" already blesses.
/// Nothing is persisted, no repository is touched, and the size is one
/// `Sample` per lifter per interval. It exists because the broadcast carries
/// readings as they happen and nothing else in the app remembers them:
/// without it the crew's timeline could only ever draw one column.
struct TogetherTrace: Equatable {
    /// One reading: the bpm AND the zone it arrived with — carried
    /// together (fix round 3 / F7) so a bar's colour and a bar's number
    /// can never disagree about which zone the reading was in.
    struct Sample: Equatable {
        let bpm: Int
        /// The BROADCAST zone, never recomputed from `bpm` here —
        /// `HeartRateZone`'s own header forbids exactly that: zone
        /// reflects the sharing lifter's own effort relative to THEIR OWN
        /// max HR, which only their own device can compute. `nil` when
        /// the broadcast carried no zone (an older sender, or a malformed
        /// payload) — an absent zone stays absent, it is never guessed at.
        let zone: HeartRateZone?

        static let empty = Sample(bpm: 0, zone: nil)
    }

    private(set) var byLifter: [UUID: [Int: Sample]] = [:]

    /// Last writer wins within an interval: the bar says where a lifter's
    /// heart was by the END of it, which is the number a reader compares.
    mutating func record(userID: UUID, bpm: Int, zone: HeartRateZone?, interval: Int) {
        guard bpm > 0, interval >= 0 else { return }
        byLifter[userID, default: [:]][interval] = Sample(bpm: bpm, zone: zone)
    }

    /// `count` slots, oldest first. A slot with no reading is `.empty`
    /// (`bpm == 0`), which the timeline draws as an empty slot rather than
    /// as a zero-height nothing — the axis has to keep its shape or the
    /// lanes stop lining up.
    func trace(for userID: UUID, count: Int) -> [Sample] {
        guard count > 0 else { return [] }
        let readings = byLifter[userID] ?? [:]
        return (0..<count).map { readings[$0] ?? .empty }
    }
}

// MARK: - The screen

/// One lifter's lane on the shared axis.
struct TogetherLane: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// The live reading. Nil when it is stale — `heartRateFor(_:)`'s 15 s
    /// gate — and a stale reading is an em dash, never a last-known number.
    let bpm: Int?
    let zone: HeartRateZone?
    /// One `TogetherTrace.Sample` per interval, `.empty` where nothing was
    /// recorded — each bar carries its OWN broadcast zone (fix round 3 /
    /// F7), not one recomputed from `bpm`.
    let trace: [TogetherTrace.Sample]
}

/// `session-together-clock` (frame 140).
///
/// The clock card leads and carries the hero number; the crew is ONE card
/// under it on ONE axis, because four separate readouts is four solo sessions
/// in a row. Heart rate is shared by default (owner decision 13), which the
/// timeline says out loud rather than leaving the lifter to discover.
///
/// ACCENT: the interval ring — the current item (rule 2). Everything else in
/// the readouts is heart-rate data colour, which §4a exempts, and every one of
/// them carries its zone word.
///
/// **KNOWN RULE-2 TENSION (fix round 3 / F6, ruling R-B17):** the log
/// control (`LogControlButton`, mounted below) also paints `theme.accent` —
/// it is `turnChrome`'s own button, unchanged, and the fix's whole point
/// was that Together needed the SAME control Rounds and Freestyle already
/// have, not a redrawn one. Before this fix Together had no way to log a
/// set at all, which rule 2 does not have an opinion on; a second accent
/// face is the smaller problem. Flagged for the controller, the same way
/// the round wait's ring/`SkipOfferLine` tension was (review finding 7) —
/// not resolved here.
struct TogetherClockView: View {
    @Environment(\.gsTheme) private var theme

    /// `PUSH CREW · TOGETHER`.
    let kicker: String
    /// The routine's own name.
    let title: String

    /// `INTERVAL 6 OF 12`.
    let intervalKicker: String
    /// The current interval's name, in caps — the phase word.
    let phase: String
    /// `Z3 · 4 min`, or empty.
    let phaseDetail: String
    /// The countdown, or the count-up on an open interval.
    let readout: String
    /// 0...1 around the ring.
    let progress: Double
    /// `Next: Z2 · 3 min`, `Last interval`, or empty.
    let nextLine: String

    let lanes: [TogetherLane]
    /// `ROUND 1` … `ROUND 12` — the axis's two ends.
    let axisStart: String
    let axisEnd: String

    var dockNames: [String] = []
    var voice: VoiceFoot = VoiceFoot()
    /// The reps/weight/RPE entry, mounted directly above the LOG button
    /// below (fix round 4 / finding 1, ruling R-B21). Fix round 3 gave
    /// Together the button; nothing gave it anything to enter reps INTO, so
    /// the button rendered permanently disabled — the same hole one style
    /// wider. `SessionLiveView` hands in the SAME `turnEntryCard` the
    /// my-turn page mounts, type-erased since this view takes no generic
    /// content parameter elsewhere — one view, one code path, regardless of
    /// which of the three styles is on screen. `nil` in the catalog and
    /// tests, which draw the clock alone.
    var entryCard: AnyView? = nil
    /// The live log control (fix round 3 / F6, ruling R-B17). Together has
    /// no turn to gate it on — `logControlIsMine` reads true for every
    /// participant here — so every lifter needs the SAME button
    /// `turnChrome` draws for Rounds/Freestyle, mounted above the dock
    /// rather than left unreachable (`bottomChrome` never renders
    /// `turnChrome` for `.together`).
    var logControl: LogControlFoot = LogControlFoot()

    var onEnd: () -> Void = {}

    var body: some View {
        RoundPage(kicker: kicker, title: title) {
            clockCard
            timelineCard
        } foot: {
            VoiceNotices(foot: voice)
            if let entryCard {
                entryCard
            }
            LogControlButton(
                title: logControl.title,
                readback: logControl.readback,
                isFailed: logControl.isFailed,
                isDisabled: logControl.isDisabled,
                onTap: logControl.onTap)
            PTTDockRow(otherParticipantNames: dockNames, compact: false)
            // The SHIPPED End control — the same confirmation the header's X
            // raises, reached from the foot because Together's page has no
            // pinned chrome of its own. Neutral, never accent: the ring is
            // this screen's one accent act, and ending is not what the crew
            // came to do.
            RoundDoor(glyph: "xmark", title: RoundCopy.endSession, onTap: onEnd)
        }
    }

    // MARK: The clock

    private var clockCard: some View {
        HStack(spacing: 18) {
            ring
            VStack(alignment: .leading, spacing: 6) {
                GSSectionHeader(intervalKicker)
                Text(phase)
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .tracking(1.4)
                    .foregroundStyle(theme.text)
                if !phaseDetail.isEmpty {
                    Text(phaseDetail)
                        .font(GSFont.body(12.5, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
                if !nextLine.isEmpty {
                    Text(nextLine)
                        .font(GSFont.body(12.5, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
                Text(RoundCopy.togetherNoTurn)
                    .font(GSFont.body(11.5, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    /// `boldFixed` for the numeral, which is what that helper exists for: a
    /// big number inside a hard-framed circle clips at large Dynamic Type,
    /// and the meaning is carried redundantly by the scaling labels beside it.
    private var ring: some View {
        ZStack {
            Circle()
                .strokeBorder(theme.neutral300, lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(readout)
                .font(GSFont.boldFixed(30))
                .monospacedDigit()
                .foregroundStyle(theme.text)
        }
        .frame(width: 116, height: 116)
    }

    // MARK: The timeline

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GSSectionHeader(RoundCopy.crewOneTimeline)
                Spacer(minLength: 8)
                Text(RoundCopy.sharedByDefault)
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral500)
                    .fixedSize()
            }
            ForEach(lanes) { lane in
                self.lane(lane)
            }
            axis
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private func lane(_ lane: TogetherLane) -> some View {
        HStack(spacing: 10) {
            Text(lane.name)
                .font(GSFont.bodyMedium(12, relativeTo: .caption))
                .foregroundStyle(theme.text)
                .frame(width: 40, alignment: .leading)
                .lineLimit(1)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(lane.trace.enumerated()), id: \.offset) { _, sample in
                    bar(sample)
                }
            }
            .frame(height: 26)

            Spacer(minLength: 4)

            reading(lane)
        }
    }

    /// The zone WORD travels with the pill's colour (§4a) — and a lifter with
    /// no fresh reading gets an em dash rather than a number nobody sent.
    @ViewBuilder
    private func reading(_ lane: TogetherLane) -> some View {
        if let bpm = lane.bpm {
            GSHeartRatePill(bpm: bpm, zone: lane.zone)
            Text(lane.zone.map { HeartRateZoneDisplay.word($0) } ?? "—")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(0.4)
                .foregroundStyle(theme.neutral700)
                .frame(width: 22, alignment: .trailing)
        } else {
            Text("—")
                .font(GSFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
            Text(" ")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .frame(width: 22, alignment: .trailing)
        }
    }

    /// An interval with no reading yet is an EMPTY SLOT on the axis, not a
    /// zero-height nothing — the axis has to keep its shape for the intervals
    /// still to come, or the lanes stop lining up.
    ///
    /// INKED FROM THE SAMPLE'S OWN ZONE (fix round 3 / F7), never
    /// recomputed from `bpm` against a fixed max-HR estimate — the same
    /// "never recompute another participant's zone" rule the live
    /// reading beside it already follows (`reading(_:)` above,
    /// `HeartRateZone`'s own header). A reading with no zone (an older
    /// sender, or a malformed payload) draws `neutral700` — present, but
    /// deliberately not colour-coded to a zone nobody sent.
    private func bar(_ sample: TogetherTrace.Sample) -> some View {
        let height: CGFloat = sample.bpm <= 0 ? 4 : max(6, CGFloat(sample.bpm - 90) * 0.24)
        let ink: Color
        if sample.bpm <= 0 {
            ink = theme.neutral300
        } else if let zone = sample.zone {
            ink = HeartRateZoneDisplay.ink(zone)
        } else {
            ink = theme.neutral700
        }
        return RoundedRectangle(cornerRadius: 2)
            .fill(ink)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    private var axis: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0).frame(width: 40)
            Text(axisStart)
                .font(GSFont.bold(8.5, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(theme.neutral500)
            Spacer(minLength: 0)
            Text(axisEnd)
                .font(GSFont.bold(8.5, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(theme.neutral500)
            Spacer(minLength: 0).frame(width: 92)
        }
    }
}
