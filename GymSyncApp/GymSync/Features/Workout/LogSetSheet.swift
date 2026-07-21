import SwiftUI

// Canvas: Log Set card — bottom sheet with:
//   • Reps stepper  (−  value  +)  border: divider color
//   • Weight stepper (−  value  +)  border: accent color when PR candidate
//   • RPE segmented bar (10 cells, filled up to selection in accent200, active cell in accent)
//   • Fail + Save Set action row
// Slider is replaced by the segmented-bar per canvas design.
// All bindings, onLog callback, and isFailed toggle are UNCHANGED.
struct LogSetSheet: View {
    let exercise: Exercise
    let setIndex: Int
    let defaultReps: String?
    let defaultWeight: String?
    let onLog: (Int?, Decimal?, Decimal?, Bool, String?) -> Void
    // onLog(reps, weight, rpe, isFailed, note) — UNCHANGED

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    @State private var reps: String = ""
    @State private var weight: String = ""
    @State private var rpe: Double = 7.0
    @State private var isFailed = false
    @State private var note: String = ""

    // Phase H Task 4 — plate-math disclosure toggle. `private` + `@State`
    // with a default value, matching the shape of every other @State above:
    // Swift's synthesized memberwise init only includes non-private stored
    // properties (`exercise`/`setIndex`/`defaultReps`/`defaultWeight`/
    // `onLog`), so adding this does NOT change that init's signature — the
    // existing call sites (WorkoutSessionView.swift:224,
    // GroupSessionLiveView.swift:1399) keep compiling unchanged. Adding a
    // plain (non-@State, non-private) stored property here instead would
    // have been the memberwise-init trap.
    @State private var showPlateStack = false

    // Canvas RPE labels — "Very easy" .. "Max effort"
    private static let rpeLabels: [Double: String] = [
        1: "Very easy", 2: "Easy", 3: "Moderate", 4: "Somewhat hard",
        5: "Hard", 6: "Hard+", 7: "Very hard", 8: "Very hard+",
        9: "Very hard", 10: "Max effort"
    ]

    private var rpeLabel: String {
        Self.rpeLabels[rpe] ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Canvas: drag handle pill
                    HStack { Spacer()
                        Rectangle()
                            .fill(theme.neutral400)
                            .frame(width: 36, height: 4)
                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                    // Canvas: "Exercise name  |  Set N" header row
                    HStack(alignment: .firstTextBaseline) {
                        Text(exercise.name)
                            .font(GSFont.heading(22, relativeTo: .title2))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text("Set \(setIndex)")
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                    // Canvas: Reps + Weight stepper row side by side
                    HStack(spacing: 10) {
                        stepperCell(
                            theme: theme,
                            label: "Reps",
                            value: $reps,
                            borderColor: theme.divider,
                            valueColor: theme.text,
                            keyboard: .numberPad,
                            onDecrement: { decrementInt(&reps) },
                            onIncrement: { incrementInt(&reps) }
                        )

                        stepperCell(
                            theme: theme,
                            label: "Weight (\(exercise.defaultUnit))",
                            value: $weight,
                            borderColor: theme.accent,        // Canvas: accent border on weight
                            valueColor: theme.accent700,      // Canvas: accent700 for weight value
                            keyboard: .decimalPad,
                            onDecrement: { decrementDecimal(&weight) },
                            onIncrement: { incrementDecimal(&weight) }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Phase H Task 4 — "Plates" disclosure. No canvas frame
                    // depicts a plate-math affordance (see docs/design/
                    // accepted-deviations.json's "plate-math" entry).
                    // Live-updates with `weight` on every keystroke since it
                    // re-parses `weight` directly rather than caching a
                    // snapshot. Hidden entirely for empty/invalid weight —
                    // same parse idiom `commitLog()` below and
                    // `BodyWeightLogSheet.canSubmit`
                    // (Features/Stats/BodyWeightLogSheet.swift:82-85) already
                    // use for this exact TextField, so "invalid weight" is
                    // handled identically everywhere it's checked.
                    //
                    // Fix wave 1 (inline-card extension): the disclosure body
                    // itself is now `PlateStackDisclosure`, a free-standing
                    // `internal` view (bottom of this file) — promoted out of
                    // this struct the same way `stepperCell` (line ~317
                    // below) was, so GroupSessionLiveView's inline "LOG THIS
                    // SET" card can reuse it instead of copy-pasting the
                    // ~60-line body. This call site's rendering is unchanged.
                    //
                    // Phase O Task 2: `Decimal.parseUserInput(_:)` (Models/
                    // Decimal+ParseUserInput.swift) instead of the bare
                    // `Decimal(string:)` initializer — same locale-safe
                    // comma/period parse `commitLog()` below now uses for
                    // this exact field, so a comma-locale device's live
                    // "Plates" preview stays in sync with what actually
                    // submits.
                    if let targetWeight = Decimal.parseUserInput(weight), targetWeight > 0 {
                        PlateStackDisclosure(target: targetWeight, theme: theme, isExpanded: $showPlateStack)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    // Canvas: RPE row — "RPE · how hard" label  /  "9 · Very hard" value
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("RPE · how hard")
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                            Spacer()
                            Text("\(Int(rpe)) · \(rpeLabel)")
                                .font(GSFont.heading(12, relativeTo: .caption))
                                .foregroundStyle(theme.accent700)
                        }

                        // Canvas: 10-segment bar — filled in accent200 up to selection,
                        // selected segment in accent with white label, empty in surface+divider border
                        RPESegmentBar(value: $rpe, theme: theme)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Canvas: Failed set toggle row
                    HStack {
                        Text("Failed set")
                            .font(GSFont.body(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Toggle("", isOn: $isFailed)
                            .labelsHidden()
                            .tint(theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    GSDivider().padding(.horizontal, 16).padding(.bottom, 10)

                    // Canvas: Note field (optional)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOTE")
                            .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                            .tracking(1.0)
                            .foregroundStyle(theme.neutral500)
                        TextField("Anything to remember?", text: $note, axis: .vertical)
                            .lineLimit(1...3)
                            .font(GSFont.body(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Canvas: Fail + Save Set action row
                    HStack(spacing: 8) {
                        Button("Fail") {
                            isFailed = true
                            commitLog()
                        }
                        .buttonStyle(GSSecondaryButtonStyle())
                        .frame(width: 80)

                        Button("Save Set") {
                            commitLog()
                        }
                        .buttonStyle(GSPrimaryButtonStyle())
                        .disabled(Int(reps) == nil && !isFailed)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)
                }
            }
            .background(theme.bg)
            .navigationBarHidden(true)
            .onAppear {
                if reps.isEmpty { reps = defaultReps ?? "" }
                if weight.isEmpty { weight = defaultWeight ?? "" }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden) // using our own handle pill
    }

    // MARK: - Sub-views

    private func commitLog() {
        // Phase O Task 2: `Decimal.parseUserInput(_:)` — see the "Plates"
        // disclosure gate above for why the bare `Decimal(string:)`
        // initializer was locale-unsafe.
        onLog(
            Int(reps),
            Decimal.parseUserInput(weight),
            Decimal(rpe),
            isFailed,
            note.isEmpty ? nil : note
        )
        dismiss()
    }

    // Plate stack disclosure (Phase H Task 4) now lives as the free-standing
    // `PlateStackDisclosure` view + helpers at the bottom of this file (Fix
    // wave 1 — inline-card extension), same promotion `stepperCell` below
    // already received, so GroupSessionLiveView's inline "LOG THIS SET" card
    // can reuse it. See that section's doc comment for the full rationale.
}

#if DEBUG
extension LogSetSheet {
    /// Catalog-fixture convenience init (Phase H Task 4, `plate-math`
    /// catalog case): forces `showPlateStack` open so `CatalogHostView` can
    /// capture the disclosure already expanded, instead of requiring a
    /// simulated tap. Same same-file seam idiom as `HomeGymSetupView`'s
    /// `catalogSearchQuery:` convenience init (LogSetSheet.swift is the only
    /// file with access to `private` `_showPlateStack`) — delegates to the
    /// normal init first (satisfies the stored `let`s), then reassigns the
    /// backing `State` storage. Compiled out of release entirely.
    init(
        catalogFixtureExercise exercise: Exercise,
        setIndex: Int,
        defaultReps: String?,
        defaultWeight: String?,
        onLog: @escaping (Int?, Decimal?, Decimal?, Bool, String?) -> Void
    ) {
        self.init(
            exercise: exercise,
            setIndex: setIndex,
            defaultReps: defaultReps,
            defaultWeight: defaultWeight,
            onLog: onLog
        )
        _showPlateStack = State(initialValue: true)
    }
}
#endif

// MARK: - Shared stepper cell (Reps/Weight)
// Canvas: stepper cell — label kicker / "−  value  +" row with borders. Shared (internal,
// not file-private) so both LogSetSheet's own reps/weight row and GroupSessionLiveView's
// inline "LOG THIS SET" card can use the same implementation instead of copy-pasting it.

func stepperCell(
    theme: GSTheme,
    label: String,
    value: Binding<String>,
    borderColor: Color,
    valueColor: Color,
    keyboard: UIKeyboardType,
    onDecrement: @escaping () -> Void,
    onIncrement: @escaping () -> Void
) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(label)
            .font(GSFont.body(11, relativeTo: .caption))
            .foregroundStyle(theme.neutral500)

        // Canvas: bordered row — minus button | value | plus button, height 48
        HStack(spacing: 0) {
            Button(action: onDecrement) {
                Text("−")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 40, height: 48)
                    .contentShape(Rectangle())
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(borderColor.opacity(0.6)).frame(width: 1)
            }

            TextField("", text: value)
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .font(GSFont.heading(22, relativeTo: .title2))
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, minHeight: 48)

            Button(action: onIncrement) {
                Text("+")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 48)
                    .contentShape(Rectangle())
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(borderColor.opacity(0.6)).frame(width: 1)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(borderColor, lineWidth: 1))
    }
    .frame(maxWidth: .infinity)
}

// MARK: - Shared stepper arithmetic (integers & decimals)
// Shared (internal) so GroupSessionLiveView's inline log card doesn't need its own copies.

func decrementInt(_ s: inout String) {
    let v = max(0, (Int(s) ?? 0) - 1)
    s = "\(v)"
}
func incrementInt(_ s: inout String) {
    let v = (Int(s) ?? 0) + 1
    s = "\(v)"
}
func decrementDecimal(_ s: inout String) {
    let v = max(0, (Double(s) ?? 0) - 2.5)
    s = v.truncatingRemainder(dividingBy: 1) == 0
           ? "\(Int(v))" : String(format: "%.1f", v)
}
func incrementDecimal(_ s: inout String) {
    let v = (Double(s) ?? 0) + 2.5
    s = v.truncatingRemainder(dividingBy: 1) == 0
           ? "\(Int(v))" : String(format: "%.1f", v)
}

// MARK: - RPE Segment Bar
// Canvas: 10 horizontal equal segments — accent200 fill up to (not including) selected,
// accent fill on selected cell with bg-colored number label, surface+divider for unvisited.
// Shared (internal, not file-private) so GroupSessionLiveView's inline "LOG THIS SET" card
// reuses this instead of a copy-pasted InlineRPEBar.

struct RPESegmentBar: View {
    @Binding var value: Double
    let theme: GSTheme

    private let steps: [Double] = Array(stride(from: 1.0, through: 10.0, by: 1.0))

    var body: some View {
        HStack(spacing: 3) {
            ForEach(steps, id: \.self) { step in
                segment(for: step)
                    .onTapGesture { value = step }
            }
        }
        .frame(height: 30)
    }

    @ViewBuilder
    private func segment(for step: Double) -> some View {
        let isSelected = Int(step) == Int(value)
        let isFilled   = step < value

        ZStack {
            if isSelected {
                theme.accent
            } else if isFilled {
                theme.accent200
            } else {
                theme.surface
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
            }

            if isSelected {
                Text("\(Int(step))")
                    .font(GSFont.heading(13, relativeTo: .caption))
                    .foregroundStyle(theme.bg)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Shared plate stack disclosure (Phase H Task 4, Fix wave 1)
// Promoted out of `LogSetSheet` the same way `stepperCell` (line 317 above) and
// `RPESegmentBar` (line 340 above) were: shared (internal, not file-private) so
// GroupSessionLiveView's inline "LOG THIS SET" card can reuse the exact "Plates"
// disclosure instead of copy-pasting its ~60-line body — reviewer ruled the copy-paste
// approach out explicitly for this fix.
//
// `PlateMath` (Models/PlateMath.swift) is the pure helper — this only renders its
// result. `target` is bar+plates in lbs (this app is lbs-only in v1 — same finding
// `BodyWeightLogSheet.swift:23-28` recorded before hardcoding its own "lbs" unit).
// Callers own the empty/invalid/non-positive-weight gate — both LogSetSheet
// (LogSetSheet.swift:~130) and GroupSessionLiveView's `logThisSetCard` only
// construct this behind `if let targetWeight = Decimal.parseUserInput(...),
// targetWeight > 0` (Phase O Task 2 — was the bare `Decimal(string:...)`
// initializer), so this view assumes `target` is already a valid, positive
// weight.

struct PlateStackDisclosure: View {
    let target: Decimal
    let theme: GSTheme
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 12, weight: .regular))
                    Text("Plates")
                        .font(GSFont.bodyMedium(12, relativeTo: .caption))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .regular))
                }
                .foregroundStyle(theme.neutral500)
            }
            .buttonStyle(.plain)

            if isExpanded {
                let result = PlateMath.stack(for: target)
                let chips = plateChipLabels(result)

                if chips.isEmpty {
                    Text("Bar only (\(formattedPlateWeight(result.achievedWeight)) lbs)")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                } else {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            GSTag(text: chip, style: .outline)
                        }
                        Text("per side")
                            .font(GSFont.body(11, relativeTo: .caption2))
                            .foregroundStyle(theme.neutral500)
                    }
                }

                if let remainder = result.remainder {
                    let direction = result.achievedWeight < target ? "short" : "over target"
                    Text("Nearest: \(formattedPlateWeight(result.achievedWeight)) lbs (\(formattedPlateWeight(remainder)) \(direction))")
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                }
            }
        }
    }
}

/// "2×45" per non-zero denomination, index-aligned to `PlateMath.standardPlates`
/// (the same default `PlateStackDisclosure` calls `PlateMath.stack(for:)` with).
func plateChipLabels(_ result: PlateMath.Stack) -> [String] {
    zip(PlateMath.standardPlates, result.platesPerSide).compactMap { denomination, count in
        guard count > 0 else { return nil }
        return "\(formattedPlateWeight(count))×\(formattedPlateWeight(denomination))"
    }
}

/// Trims trailing zeros the same way `GroupSessionLiveView.weightText`
/// (GroupSessionLiveView.swift:1367) already formats logged weights.
func formattedPlateWeight(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}
