import SwiftUI

// MARK: - GymEquipmentView (You ▸ Settings ▸ Gym equipment)
//
// The bar-weight and plate-inventory editor — what makes the bar loader
// exact for THIS user's gym instead of assuming the standard set. Design:
// 2026-07-26-lifting-quality-design.md, Phase B items 3-4.
//
// Everything edits in the user's own unit. Bar weight persists as
// canonical pounds (like every stored weight); the plate inventory
// persists in the user's unit, because denominations are unit-native and
// don't convert (a 45 lb plate is not a 20.4 kg plate).

struct GymEquipmentView: View {
    @Environment(\.gsTheme) private var theme

    /// Seeded by the caller (YouTabView's already-loaded settings) and
    /// pushed back through `onSaved` — the RestTimerSettingView shape.
    let currentSettings: UserSettings
    let onSaved: (UserSettings) -> Void

    @State private var barText: String = ""
    /// Denomination -> included. Order comes from the unit's standard set
    /// plus any custom denominations already saved.
    @State private var included: [Decimal: Bool] = [:]
    @State private var saving = false
    @State private var errorText: String?
    @State private var savedTick = false

    private var unit: WeightUnit { currentSettings.weightUnit }

    /// Standard denominations for the unit, merged with anything unusual
    /// already in the saved inventory so a previously-saved odd plate
    /// doesn't vanish from the editor.
    private var allDenominations: [Decimal] {
        let saved = Set(currentSettings.plateInventory ?? [])
        let standard = Set(unit.standardPlates)
        return Array(saved.union(standard)).sorted(by: >)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                barSection
                platesSection
                previewSection
                saveButton
                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle("Gym equipment")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { seed() }
    }

    // MARK: Bar

    private var barSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Your bar")
            HStack(spacing: 8) {
                TextField("Bar weight", text: $barText)
                    .keyboardType(.decimalPad)
                    .font(GSFont.heading(18, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .monospacedDigit()
                Text(unit.label)
                    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            Text("Standard is \(GSBarLoader.plateLabel(unit.defaultBar)) \(unit.label). Women's bar 35 lb / 15 kg; safety-squat bars run heavier.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
    }

    // MARK: Plates

    private var platesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Plates your gym has")
            Text("The loader and warm-up ramp only suggest weights these can build.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
            FlowChipsDecimal(
                options: allDenominations,
                isOn: { included[$0] ?? false },
                toggle: { plate in included[plate] = !(included[plate] ?? false) },
                unit: unit
            )
        }
    }

    /// Live proof the selection works: the loader for a mid-range target
    /// re-renders as plates toggle, so "what did I just break" is visible
    /// before saving.
    private var previewSection: some View {
        let plates = selectedPlates
        let sampleTarget: Decimal = unit == .kg ? 100 : 225
        return VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Preview · \(GSBarLoader.plateLabel(sampleTarget)) \(unit.label)")
            GSBarLoader(
                target: sampleTarget,
                barWeight: Units.parseToPounds(barText, unit: unit)
                    .map { Units.fromPounds($0, to: unit) } ?? unit.defaultBar,
                plates: plates.isEmpty ? unit.standardPlates : plates,
                unit: unit
            )
            // gs3D pass (2026-09-03, P2): the live loader preview is a
            // static widget the user reads — extruded face/lip container in
            // place of the flat surface fill. The bar-weight TextField above
            // deliberately stays flat: form inputs are furniture.
            .padding(14)
            .gs3DCard(cornerRadius: GSMetrics.radiusMd)
        }
    }

    private var selectedPlates: [Decimal] {
        allDenominations.filter { included[$0] ?? false }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            // Emoji sweep (spec §7): the confirmation "✓" was functional
            // chrome, not content — it becomes the `checkmark` SF Symbol,
            // the same idiom SettingsView's QA Reset button uses. The
            // outer `.frame(maxWidth: .infinity)` stays put so the CTA
            // keeps its full-width footprint and centered label.
            HStack(spacing: 5) {
                if savedTick {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(savedTick ? "Saved" : "Save")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 13))
        .disabled(saving || Units.parseToPounds(barText, unit: unit) == nil || selectedPlates.isEmpty)
        .opacity((saving || Units.parseToPounds(barText, unit: unit) == nil || selectedPlates.isEmpty) ? 0.6 : 1)
    }

    // MARK: Data

    private func seed() {
        guard barText.isEmpty else { return }
        var barInUnit = Units.fromPounds(currentSettings.barWeightLbs, to: unit)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &barInUnit, 2, .plain)
        barText = GSBarLoader.plateLabel(rounded)

        let saved = currentSettings.plateInventory
        for plate in allDenominations {
            // No saved inventory = "standard set": everything standard on.
            included[plate] = saved.map { $0.contains(plate) } ?? unit.standardPlates.contains(plate)
        }
    }

    @MainActor
    private func save() async {
        guard let barPounds = Units.parseToPounds(barText, unit: unit) else { return }
        saving = true
        defer { saving = false }
        var updated = currentSettings
        updated.barWeightLbs = barPounds
        // Selecting exactly the standard set stores NULL ("standard for my
        // unit") rather than a copy — keeps the "no row means defaults"
        // convention meaningful and survives a future change to standards.
        let selection = selectedPlates
        updated.plateInventory = Set(selection) == Set(unit.standardPlates) ? nil : selection
        do {
            try await UserSettingsRepository.upsert(updated)
            ThemeStore.shared.noteExternalSettingsWrite(updated)
            onSaved(updated)
            errorText = nil
            savedTick = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                savedTick = false
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}

/// Decimal-keyed sibling of ProgramViews' FlowChips (that one is
/// String-keyed and private to its file).
private struct FlowChipsDecimal: View {
    @Environment(\.gsTheme) private var theme
    let options: [Decimal]
    let isOn: (Decimal) -> Bool
    let toggle: (Decimal) -> Void
    let unit: WeightUnit

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { plate in
                Button {
                    toggle(plate)
                } label: {
                    Text(GSBarLoader.plateLabel(plate))
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(isOn(plate) ? plateInk(plate) : theme.neutral700)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                // gs3D pass (2026-09-03, P2): a plate is a selectable chip,
                // so it sits proud and sinks (ExercisesListView filter-chip
                // precedent), and the flat fill + divider stroke retire.
                // The ON face keeps the COMPETITION PLATE COLOUR rather than
                // going accent: that hue is data ink — the same colour the
                // Preview loader draws directly below, and what `plateInk`
                // exists to stay readable against — so an accent face would
                // destroy the chip↔plate mapping. An explicit non-neutral
                // face derives its darker lip, the documented accent-face
                // path (GS3DButton.swift:100-102). OFF = the neutral raised
                // pair. Footprint held: 32pt face + 4pt lip = the old
                // 10 + 13pt line + 10 chip.
                .buttonStyle(isOn(plate)
                    ? .gs3D(face: GSBarLoader.plateColor(plate, unit: unit), cornerRadius: 10, lipHeight: 4)
                    : .gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: 10, lipHeight: 4))
                .accessibilityLabel("\(GSBarLoader.plateLabel(plate)) \(unit.label) plates \(isOn(plate) ? "available" : "not available")")
            }
        }
    }

    private func plateInk(_ plate: Decimal) -> Color {
        // Pale plates need dark ink — mirror GSBarLoader's denomination rule.
        let value = NSDecimalNumber(decimal: plate).doubleValue
        let pale: Set<Double> = unit == .kg ? [15, 5, 2.5, 1.25] : [35, 10, 5, 2.5]
        return pale.contains(value) ? Color.gsHex(0x14161A) : .white
    }
}
