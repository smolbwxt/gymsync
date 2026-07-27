import SwiftUI

// MARK: - BarLoaderWidget
//
// The in-session "load the bar" surface (user direction 2026-07-26):
// a weight field, an lbs/kg toggle RIGHT ON THE WIDGET, the drawn
// GSBarLoader stack, and the warm-up ramp — reachable during any workout
// session, group or solo, whether it's your turn or not.
//
// UNIT TOGGLE SEMANTICS (deliberate): the toggle here is a LOCAL view
// override, seeded from the user's persisted preference. It changes what
// this widget displays and how its field parses — it does NOT rewrite the
// app-wide setting mid-set (that lives in You ▸ Settings) and it NEVER
// changes stored data, which stays canonical pounds everywhere.
//
// PLATE INVENTORY ACROSS UNITS: the persisted inventory is denominated in
// the user's own unit ("my gym's lbs plates"). Denominations don't convert
// — a 45 lb plate is not a 20.4 kg plate — so the custom inventory applies
// ONLY while the widget shows the user's persisted unit; flipping to the
// other unit falls back to that unit's standard set.

struct BarLoaderWidget: View {
    @Environment(\.gsTheme) private var theme

    /// Prefill in canonical pounds (a routine target or last logged set);
    /// nil starts the field empty.
    let initialPounds: Decimal?

    @State private var unit: WeightUnit = .lbs
    @State private var weightText: String = ""
    @State private var settings: UserSettings?
    @State private var showRamp = false
    @State private var seeded = false

    /// Canonical pounds for the current entry — the single value everything
    /// below derives from.
    private var enteredPounds: Decimal? {
        Units.parseToPounds(weightText, unit: unit)
    }

    private var persistedUnit: WeightUnit { settings?.weightUnit ?? .lbs }

    /// Custom inventory only in its own unit (see header).
    private var plates: [Decimal] {
        if unit == persistedUnit, let custom = settings?.plateInventory, !custom.isEmpty {
            return custom.sorted(by: >)
        }
        return unit.standardPlates
    }

    /// Bar in the DISPLAY unit, rounded to 2dp so a 45 lb bar reads
    /// "20.41 kg" rather than a 15-digit conversion.
    private var barInUnit: Decimal {
        var value = Units.fromPounds(settings?.barWeightLbs ?? 45, to: unit)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                weightField
                unitToggle
            }

            if let pounds = enteredPounds, pounds > 0 {
                GSBarLoader(
                    target: Units.fromPounds(pounds, to: unit),
                    barWeight: barInUnit,
                    plates: plates,
                    unit: unit
                )
                rampSection(workingPounds: pounds)
            } else {
                Text("Enter a weight to see the plates.")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .task { await seedIfNeeded() }
    }

    // MARK: Entry + toggle

    private var weightField: some View {
        HStack(spacing: 6) {
            TextField("Weight", text: $weightText)
                .keyboardType(.decimalPad)
                .font(GSFont.heading(18, relativeTo: .title3))
                .foregroundStyle(theme.text)
                .monospacedDigit()
            Text(unit.label)
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(theme.bg)
        .cornerRadius(GSMetrics.radiusSm)
    }

    /// lbs | kg — the segmented-pill idiom LibraryTabView's sub-tabs use.
    /// Flipping REFORMATS the field from the same canonical pounds, so 225
    /// lbs becomes 102.5 kg (loadable-snapped), not a stale "225 kg".
    private var unitToggle: some View {
        HStack(spacing: 3) {
            ForEach(WeightUnit.allCases, id: \.self) { candidate in
                Button {
                    switchUnit(to: candidate)
                } label: {
                    Text(candidate.label)
                        .font(GSFont.bold(12.5, relativeTo: .subheadline))
                        .foregroundStyle(unit == candidate ? theme.bg : theme.neutral700)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .frame(minHeight: 38)
                        .background(unit == candidate ? theme.accent : Color.clear)
                        .cornerRadius(9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(theme.bg)
        .cornerRadius(11)
    }

    private func switchUnit(to newUnit: WeightUnit) {
        guard newUnit != unit else { return }
        // Carry the VALUE across, snapped to what the new unit's plates can
        // build — never the digits (225 lbs is not 225 kg).
        let pounds = enteredPounds
        unit = newUnit
        if let pounds {
            let inUnit = Units.fromPounds(pounds, to: newUnit)
            let snapped = Units.nearestLoadable(inUnit, barWeight: barInUnit,
                                                plates: plates, unit: newUnit)
            weightText = GSBarLoader.plateLabel(snapped)
        }
    }

    // MARK: Warm-up ramp

    @ViewBuilder
    private func rampSection(workingPounds: Decimal) -> some View {
        let steps = WarmupMath.ramp(
            workingPounds: workingPounds,
            barPounds: settings?.barWeightLbs ?? 45,
            unit: unit,
            plates: plates
        )
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showRamp.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("WARM-UP")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(1.2)
                        Image(systemName: showRamp ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.neutral500)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showRamp {
                    ForEach(steps) { step in
                        rampRow(step)
                    }
                    Text("Warm-ups aren't logged — they never count toward volume or PRs.")
                        .font(GSFont.body(10.5, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral700)
                }
            }
        }
    }

    private func rampRow(_ step: WarmupMath.Step) -> some View {
        let inUnit = Units.fromPounds(step.pounds, to: unit)
        let stack = PlateMath.stack(for: inUnit, barWeight: barInUnit, plates: plates)
        let perSide = zip(plates, stack.platesPerSide)
            .compactMap { plate, count -> String? in
                let n = NSDecimalNumber(decimal: count).intValue
                return n > 0 ? "\(n)×\(GSBarLoader.plateLabel(plate))" : nil
            }
            .joined(separator: " ")

        return HStack(spacing: 10) {
            // Load label: one-decimal rule via displayWeight — the
            // pounds↔unit round-trip above can leave "22.909999…" and raw
            // Decimal interpolation printed every digit (user report
            // 2026-07-27).
            Text(step.isBar ? "Bar" : "\(Units.displayWeight(inUnit)) \(unit.label)")
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .frame(width: 92, alignment: .leading)
            Text("×\(step.reps)")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .frame(width: 30, alignment: .leading)
            Text(step.isBar || perSide.isEmpty ? "—" : perSide)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: Seeding

    @MainActor
    private func seedIfNeeded() async {
        guard !seeded else { return }
        seeded = true
        settings = try? await UserSettingsRepository.get()
        unit = persistedUnit
        if let initialPounds, initialPounds > 0 {
            let inUnit = Units.fromPounds(initialPounds, to: unit)
            let snapped = Units.nearestLoadable(inUnit, barWeight: barInUnit,
                                                plates: plates, unit: unit)
            weightText = GSBarLoader.plateLabel(snapped)
        }
    }
}

// MARK: - Sheet wrapper (group sessions — reachable whether it's your turn
// or not, from the always-present header bar)

struct BarLoaderSheet: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let initialPounds: Decimal?

    var body: some View {
        NavigationStack {
            ScrollView {
                BarLoaderWidget(initialPounds: initialPounds)
                    .padding(16)
                    .background(theme.surface)
                    .cornerRadius(GSMetrics.radiusMd)
                    .padding(16)
            }
            .background(theme.bg)
            .navigationTitle("Load the bar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
