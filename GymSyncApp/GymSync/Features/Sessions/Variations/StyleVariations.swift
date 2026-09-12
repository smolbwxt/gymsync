#if DEBUG
import SwiftUI

// MARK: - The other two styles, one frame each
//
// Spec §3.3. **Freestyle**: own pace, with glue — a shared progress rail
// (sets done over total, per lifter) and an end-together nudge, because
// "freestyle without the rail recreates the detachment the owner described".
// **Together**: everyone runs the same interval clock, there is no turn, and
// the crew frame shows every lifter's readout on one timeline (owner
// decision 13 shares heart rate by default).
//
// These two are not a pair — they are different styles, and each gets one
// frame. What they share with Rounds is the frame: the same page scaffold,
// the same kicker/title, the same dock in the same place.

// MARK: - 11 · the shared rail

/// The rail: ONE track, four markers, the crew's spread visible as distance
/// rather than as four numbers. Sets done over total, per lifter (spec §3.3).
///
/// One track and not four rows, because the thing the rail exists to show is
/// the GAP — four separate meters make four private facts, which is the
/// detachment the style is built to fix.
struct SVFreestyleRail: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GSSectionHeader("THE CREW · SETS DONE")
                Spacer(minLength: 8)
                Text("OF \(SVFixtures.freestyleTotal)")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral700)
                    .fixedSize()
            }

            track

            HStack(spacing: 0) {
                ForEach(Array(SVFixtures.freestyleRail.enumerated()), id: \.offset) { _, row in
                    legend(name: row.name, done: row.done, isYou: row.isYou)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    /// The 6 pt track with a marker per lifter. `GeometryReader` rather than a
    /// fixed width for `GSGoalChip`'s reason: a catalog fixture may not assume
    /// the device's width.
    private var track: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.neutral300)
                    .frame(height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)
                ForEach(Array(SVFixtures.freestyleRail.enumerated()), id: \.offset) { _, row in
                    marker(isYou: row.isYou)
                        .offset(x: offset(row.done, width: proxy.size.width))
                }
            }
        }
        .frame(height: 26)
    }

    private func offset(_ done: Int, width: CGFloat) -> CGFloat {
        let fraction = min(max(Double(done) / Double(SVFixtures.freestyleTotal), 0), 1)
        return (width - 18) * CGFloat(fraction)
    }

    /// You are `text`, the crew is `neutral500`. NOT accent: this page spends
    /// its one accent on the primary, and a marker is a readout.
    private func marker(isYou: Bool) -> some View {
        Circle()
            .fill(isYou ? theme.text : theme.neutral500)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(theme.raised3DFace, lineWidth: 2))
    }

    private func legend(name: String, done: Int, isYou: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name.uppercased())
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.9)
                .foregroundStyle(isYou ? theme.text : theme.neutral500)
                .lineLimit(1)
            Text("\(done)")
                .font(GSFont.bold(15, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(isYou ? theme.text : theme.neutral700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `freestyle-rail` — **own pace, with the gap made visible and the nudge
/// made optional.**
///
/// The rail leads because it is the style's whole reason to exist. Under it,
/// your rest says out loud that it has been stretched and by how much — a
/// stretch a lifter cannot see is a bug report — and Coach offers the
/// accessory as a suggestion with two answers, never as an applied change
/// (owner decision 4, spec §4).
///
/// The primary stays LIVE. Freestyle is own pace: the nudge lengthens the
/// rest readout, it does not lock the button, and rendering it as a gate
/// would turn the style into Rounds with extra steps.
///
/// ACCENT: START SET 15. The rail markers are `text` (you) and `neutral500`
/// (the crew), Coach's answers are raised faces.
struct FreestyleRailView: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · FREESTYLE",
                 title: "Own pace") {
            SVFreestyleRail()

            restStrip

            SVSuggestionStrip(suggestion: SVFixtures.freestyleSuggestion,
                              isPrivate: true)
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi", "Lee Vance"])
            SVPrimary(title: "START SET 15",
                      note: "You're two sets ahead of Dana")
        }
    }

    private var restStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                GSSectionHeader("YOUR REST")
                Text(SVFixtures.freestyleRest)
                    .font(GSFont.bold(26, relativeTo: .title2))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
            }
            Text(SVFixtures.freestyleStretch)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .svStrip()
    }
}

// MARK: - 12 · one clock, four hearts

/// The heart-rate ramp, mirroring `GSHeartRatePill`'s own private mapping
/// (blue → green → orange → red over the four named zones). Heart-rate zone
/// colour is DATA COLOUR and is exempt from the accent/green/red rules —
/// design language rule 2 says so explicitly, and `GSHeartRatePill` is the
/// precedent. Spelled here because the pill's mapping is private and the
/// timeline draws bars, not pills; both read `HeartRateZone.zone(bpm:)`, so
/// the two cannot disagree about which zone a number is in.
enum SVZoneColor {
    static func of(_ bpm: Int) -> Color {
        switch HeartRateZone.zone(bpm: bpm) {
        case .warmup:   return .blue
        case .moderate: return .green
        case .hard:     return .orange
        case .max:      return .red
        }
    }
}

/// The interval clock: one ring, one hero number, one phase word.
///
/// `boldFixed` for the numeral, which is exactly what that font helper
/// exists for — a big number inside a hard-framed circle clips at large
/// Dynamic Type, and the meaning is carried redundantly by the scaling
/// WORK / ROUND 6 OF 12 labels beside it.
struct SVIntervalClock: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        HStack(spacing: 18) {
            ring
            VStack(alignment: .leading, spacing: 6) {
                GSSectionHeader(SVFixtures.togetherRound)
                Text(SVFixtures.togetherPhase)
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .tracking(1.4)
                    .foregroundStyle(theme.text)
                Text("40 s work · 20 s rest")
                    .font(GSFont.body(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                Text("Everyone runs this clock. There is no turn.")
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

    private var ring: some View {
        ZStack {
            Circle()
                .strokeBorder(theme.neutral300, lineWidth: 9)
            Circle()
                .trim(from: 0, to: SVFixtures.togetherProgress)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(SVFixtures.togetherRemaining)
                .font(GSFont.boldFixed(30))
                .monospacedDigit()
                .foregroundStyle(theme.text)
        }
        .frame(width: 116, height: 116)
    }
}

/// Four lifters on ONE timeline: the same twelve-round axis for everybody,
/// so a glance reads who is working hardest at the same moment — which is
/// what a Together session is for. Names left, the shared axis in the middle,
/// the live reading right.
struct SVTogetherTimeline: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GSSectionHeader("THE CREW · ONE TIMELINE")
                Spacer(minLength: 8)
                Text("SHARED BY DEFAULT")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral500)
                    .fixedSize()
            }
            ForEach(Array(SVFixtures.togetherTimeline.enumerated()), id: \.offset) { _, row in
                lane(name: row.name, bpm: row.bpm, trace: row.trace)
            }
            axis
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private func lane(name: String, bpm: Int, trace: [Int]) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(GSFont.bodyMedium(12, relativeTo: .caption))
                .foregroundStyle(theme.text)
                .frame(width: 40, alignment: .leading)
                .lineLimit(1)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(trace.enumerated()), id: \.offset) { _, value in
                    bar(value)
                }
            }
            .frame(height: 26)

            Spacer(minLength: 4)

            GSHeartRatePill(bpm: bpm, zone: HeartRateZone.zone(bpm: bpm))
        }
    }

    /// A round with no reading yet is an empty slot on the axis, not a
    /// zero-height nothing — the axis has to keep its shape for rounds 7-12
    /// or the four lanes stop lining up.
    private func bar(_ value: Int) -> some View {
        let height: CGFloat = value <= 0 ? 4 : max(6, CGFloat(value - 90) * 0.24)
        return RoundedRectangle(cornerRadius: 2)
            .fill(value <= 0 ? theme.neutral300 : SVZoneColor.of(value))
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    private var axis: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0).frame(width: 40)
            Text("ROUND 1")
                .font(GSFont.bold(8.5, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(theme.neutral500)
            Spacer(minLength: 0)
            Text("ROUND 12")
                .font(GSFont.bold(8.5, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(theme.neutral500)
            Spacer(minLength: 0).frame(width: 92)
        }
    }
}

/// `together-clock` — **one clock is the whole session, so it is the whole
/// page.**
///
/// The clock card leads and carries the hero number; the crew is one card
/// under it, on one axis, because four separate readouts is four solo
/// sessions in a row. Heart rate is shared by default (owner decision 13),
/// which the timeline says out loud rather than leaving the lifter to
/// discover.
///
/// NO PRIMARY, deliberately. A running interval clock has no next physical
/// act to name (rule 5's whole test), so the foot is the dock alone. If the
/// owner wants a control here, the honest one is a crew-wide pause — which
/// is a feature this spec does not have, and inventing it in a design frame
/// is how a mockup becomes a requirement.
///
/// ACCENT: the interval ring — the current item (rule 2). Everything else in
/// the readouts is heart-rate data colour, which rule 2 exempts.
struct TogetherClockView: View {
    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · TOGETHER",
                 title: SVFixtures.togetherTitle) {
            SVIntervalClock()
            SVTogetherTimeline()
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi", "Lee Vance"])
        }
    }
}
#endif
