#if DEBUG
import SwiftUI

// MARK: - Together, second pass
//
// Freestyle is approved as rendered and gets no v2. Together gets one
// change, and it is a rule rather than a composition: the owner's ruling
// that a heart rate is neutral ink with the zone as a word, because the
// language reserves red and gold. `together-clock` and `freestyle-rail` are
// untouched.

// MARK: - 126 · one clock, four neutral hearts

/// `together-clock-v2` — **the same clock, with the zone ramp taken off the
/// heart rates.**
///
/// Round 1 tinted the timeline's bars and its four `GSHeartRatePill`s by
/// zone — blue, green, orange, red — on rule 2's data-colour exemption and
/// on the pill's own precedent. The owner's ruling for this pass overrides
/// that here: *"replace the gold/red/green BPM ink with neutral ink and the
/// zone as a word ('Z4') — the language reserves those colours."*
///
/// So the composition is byte-for-byte round 1's and only the ink moves:
///
///  * The bars are `neutral700`, and the LIVE round's bar is `text`. Effort
///    is still legible across the four lanes, as HEIGHT — which is what the
///    bars were always measuring — instead of as hue.
///  * The pill becomes a plain readout: the number in `text`, `BPM` in
///    `neutral500`, and the zone spelled `Z1`…`Z4` in `neutral700`. Same
///    source of truth as the pill's tint (`HeartRateZone.zone(bpm:)`), so a
///    reading that says Z4 here is the one the pill would have painted red.
///  * A side effect worth having: `GSHeartRatePill` carries a repeating
///    beat animation, so round 1's `together-clock` is the one frame in this
///    round that is not perfectly still. This frame has no animation at all.
///
/// ACCENT: the interval ring, unchanged — the current item (rule 2), and now
/// the only colour on the page.
struct TogetherClockV2View: View {
    var body: some View {
        SVScrollScreen(kicker: "\(SVFixtures.crewName.uppercased()) · TOGETHER",
                       title: SVFixtures.togetherTitle) {
            SVIntervalClock()
            SVTogetherTimelineV2()
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi", "Lee Vance"])
        }
    }
}

/// The timeline, neutral. Four lanes on one twelve-round axis, the columns
/// fixed so the names, the traces, the numbers and the zone words each form
/// one straight edge — this pass's alignment rule applied to a table.
struct SVTogetherTimelineV2: View {
    @Environment(\.gsTheme) private var theme

    /// Round 6 is the live one; the trace's zero slots are the rounds that
    /// have not happened.
    private static let liveRound = 6

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
                ForEach(Array(trace.enumerated()), id: \.offset) { index, value in
                    bar(value, isLive: index + 1 == Self.liveRound)
                }
            }
            .frame(height: 26)

            Text("\(bpm)")
                .font(GSFont.bold(14, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: 32, alignment: .trailing)

            Text(SVZoneWord.of(bpm))
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(0.4)
                .foregroundStyle(theme.neutral700)
                .frame(width: 20, alignment: .trailing)
        }
        .frame(height: 30)
    }

    /// Height still carries the effort; the ink no longer does. A round with
    /// no reading yet keeps its slot on the axis so the four lanes line up.
    private func bar(_ value: Int, isLive: Bool) -> some View {
        let height: CGFloat = value <= 0 ? 4 : max(6, CGFloat(value - 90) * 0.24)
        let ink: Color = value <= 0 ? theme.neutral300 : (isLive ? theme.text : theme.neutral700)
        return RoundedRectangle(cornerRadius: 2)
            .fill(ink)
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
            Spacer(minLength: 0).frame(width: 62)
        }
    }
}
#endif
