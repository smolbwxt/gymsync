import SwiftUI

// MARK: - RPESwipeTrack
// Live-session redesign (2026-07-30, final-proof.html): a horizontal snap
// scroller — the numbers slide under a fixed accent underline — with FAIL as
// a pinned end-cap OUTSIDE the scroller, past a dashed wall.
//
// Replaces RPESegmentBar at both call sites (LogSetSheet + the group screen's
// entry card). NOT forked: LogSetSheet.swift's own history records that the
// RPE control duplication was deliberately removed, so this stays one shared
// component with per-site flags.
//
// Design-review constraints this encodes (each was a fatal in an earlier
// draft — do not "simplify" them away):
//   • Content inset is DERIVED from measured width, never a literal.
//     Hardcoded (393-x)/2 insets mis-centred the selection by 8-23pt on
//     every iPhone that isn't the design device.
//   • The underline is drawn at the SAME derived centre expression as the
//     inset, so the snapped cell and the mark cannot disagree.
//   • No sibling spacers inside scrollTargetLayout — every direct child is a
//     snap target, and an un-id'd child makes scrollPosition report nil.
//   • A transient nil from scrollPosition is IGNORED, never written to the
//     non-optional binding.
//   • FAIL is OUTSIDE the momentum scroller: .viewAligned has no snap target
//     there, so a hard flick rubber-bands at 10 and stops. is_failed feeds an
//     AFTER-INSERT-ONLY lifetime-volume trigger and this screen has no edit
//     or delete — a destructive flag must not be reachable by inertia.
//   • Arming FAIL snaps the scroller to 10, because a fail IS an RPE 10
//     (the user's own ruling; storage writes isFailed = true AND rpe = 10).
//   • VoiceOver: one adjustable element, clamped 1...10 — an overshoot must
//     never arm FAIL. FAIL is a separate named action.
//   • Cell width is @ScaledMetric so an accessibility-size numeral gets a
//     wider cell instead of clipping in a hard frame (the defect that
//     condemned the old ten-segment bar).

struct RPESwipeTrack: View {
    @Binding var value: Double
    @Binding var isFailed: Bool
    let theme: GSTheme
    /// False on the penalty-burpee path, where a failed set has load-bearing
    /// burpee-debt semantics that the terminal cap would silently overload.
    var allowsFail: Bool = true

    @Environment(\.gsAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Scroller cell pitch. @ScaledMetric so large-text numerals get a wider
    /// cell; the TRACK height stays the fixed 56pt the page's arithmetic
    /// reserves (numerals are boldFixed — see GSFont.boldFixed's doc).
    @ScaledMetric(relativeTo: .title2) private var cellWidth: CGFloat = 45

    /// The scroller's snapped cell. Optional because scrollPosition reports
    /// nil mid-gesture; only non-nil values ever reach `value`.
    @State private var centred: Int?

    private static let steps = Array(1...10)

    var body: some View {
        HStack(spacing: 0) {
            scroller
            if allowsFail {
                Spacer(minLength: 8)
                dashedWall
                Spacer(minLength: 8)
                failCap
            }
        }
        .frame(height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("RPE")
        .accessibilityValue(isFailed
            ? "Failed set, effort 10, \(Self.label(for: 10))"
            : "\(Int(value)), \(Self.label(for: value))")
        .accessibilityAdjustableAction { direction in
            // Clamped at 10: a blind user overshooting by one swipe must not
            // mark the set failed. FAIL is the named action below.
            switch direction {
            case .increment: setValue(min(10, Int(value) + 1))
            case .decrement: setValue(max(1, Int(value) - 1))
            @unknown default: break
            }
        }
        .accessibilityAction(named: isFailed ? "Clear failed set" : "Mark set failed") {
            if allowsFail { toggleFail() }
        }
        .onAppear { centred = Int(value) }
        .onChange(of: value) { _, newValue in
            // External writes (turn-reset prefill) re-centre the scroller.
            if centred != Int(newValue) { centred = Int(newValue) }
        }
    }

    // MARK: scroller

    private var scroller: some View {
        GeometryReader { geo in
            // DERIVED inset — the one expression both the margin and the
            // underline are computed from, so they agree on every width.
            let inset = max(0, (geo.size.width - cellWidth) / 2)

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    // Uniform pitch, no spacers, every child .id()'d: each
                    // direct child of scrollTargetLayout IS a snap target.
                    ForEach(Self.steps, id: \.self) { step in
                        cell(step)
                            .frame(width: cellWidth, height: 56)
                            .id(step)
                            .contentShape(Rectangle())
                            .onTapGesture { setValue(step) }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, inset, for: .scrollContent)
            // limitBehavior .never — on-device feedback (2026-07-30, "25%
            // less friction"): the default clamps each flick to roughly one
            // cell, which reads as drag. .never lets momentum carry across
            // several numbers and still snap to one. FAIL stays unreachable
            // by momentum regardless — it has no snap target to land on.
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $centred)
            // Edge fade: a clean clip reads as a complete short list; the
            // fade says more numbers exist off-screen.
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                }
            )
            // The underline: 3pt accent bar at the derived centre — the same
            // mark that denotes the current set column and the active pager
            // tab. Neutral while FAIL is armed (the scale has run out).
            .overlay(alignment: .bottomLeading) {
                Capsule()
                    .fill(isFailed ? theme.neutral700 : accent.base)
                    .frame(width: cellWidth - 15, height: 3)
                    .offset(x: inset + 7.5, y: -2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: scrollerWidth, height: 56)
        .onChange(of: centred) { _, newValue in
            // Transient nil (mid-gesture) is ignored, never written through.
            guard let newValue, Double(newValue) != value else { return }
            value = Double(newValue)
            // Arming FAIL snapped us to 10; any manual re-scroll disarms.
            if isFailed && newValue != 10 { isFailed = false }
        }
        .sensoryFeedback(.selection, trigger: centred)
    }

    @ViewBuilder
    private func cell(_ step: Int) -> some View {
        let isSelected = !isFailed && Int(value) == step
        let distance = abs(Int(value) - step)
        Text("\(step)")
            .font(GSFont.boldFixed(isSelected ? 29 : (distance == 1 ? 23 : 18)))
            .monospacedDigit()
            .foregroundStyle(
                isSelected ? theme.text
                    : (isFailed && step == 10 ? theme.text : theme.neutral700)
            )
            .opacity(!isSelected && distance >= 2 && !(isFailed && step == 10) ? 0.5 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: value)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFailed)
    }

    // MARK: FAIL

    private var dashedWall: some View {
        // The wall you cross deliberately: a 2x40 dashed rule between the
        // numeric scale and the terminal cap.
        Path { p in
            p.move(to: CGPoint(x: 1, y: 0))
            p.addLine(to: CGPoint(x: 1, y: 40))
        }
        .stroke(style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        .foregroundStyle(theme.neutral700)
        .frame(width: 2, height: 40)
    }

    private var failCap: some View {
        Button(action: toggleFail) {
            ZStack {
                if isFailed {
                    // Armed: the only fill on the page that is neither accent
                    // nor surface — neutral inversion, the screen going cold.
                    RoundedRectangle(cornerRadius: 14).fill(theme.text)
                }
                Text("FAIL")
                    .font(GSFont.bold(isFailed ? 18 : 16, relativeTo: .subheadline))
                    .tracking(0.9)
                    .foregroundStyle(isFailed ? theme.bg : theme.neutral700)
            }
            .frame(minWidth: 64, maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Closure-form trigger: the heavy impact fires on ARMING only. The
        // Bool-form trigger fires on both transitions, which would thud on
        // disarm and invert the haptic's meaning.
        .sensoryFeedback(trigger: isFailed) { _, newValue in
            newValue ? .impact(weight: .heavy) : .selection
        }
        .accessibilityHidden(true) // covered by the named action on the track
    }

    /// Five cells visible at rest — selection, a neighbour each side, and a
    /// half-faded numeral at each edge saying more exist. Fixed relative to
    /// cellWidth so the GeometryReader can't fight the FAIL cap for width
    /// (two width-greedy children in one HStack would split it 50/50).
    private var scrollerWidth: CGFloat { cellWidth * 5 }

    private func toggleFail() {
        if isFailed {
            isFailed = false
        } else {
            isFailed = true
            // A fail IS an RPE 10 — the screen states what the database
            // stores (isFailed = true AND rpe = 10, no migration).
            setValue(10)
        }
    }

    private func setValue(_ step: Int) {
        value = Double(step)
        if centred != step {
            if reduceMotion {
                centred = step
            } else {
                withAnimation(.easeOut(duration: 0.18)) { centred = step }
            }
        }
    }

    // MARK: label table
    // ONE monotonic table driving both the visible text and the spoken value.
    // Replaces the three disagreeing tables (LogSetSheet had two, the group
    // screen a third, with 7 and 9 both reading "Very hard").
    static func label(for value: Double) -> String {
        switch Int(value) {
        case ...1: return "Very easy"
        case 2:    return "Easy"
        case 3:    return "Light"
        case 4:    return "Moderate"
        case 5:    return "Hard"
        case 6:    return "Harder"
        case 7:    return "Very hard"
        case 8:    return "Near limit"
        case 9:    return "Last rep"
        default:   return "Max effort"
        }
    }
}
