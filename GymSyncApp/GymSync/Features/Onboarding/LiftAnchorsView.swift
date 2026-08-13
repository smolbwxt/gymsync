import SwiftUI

/// STEP 4 OF 4 — "Where are you starting?" (owner 2026-08-12, the
/// Hevy-inspired getting-started prompt): confident 5-rep weights for the
/// four primary barbell compounds, seeding starting-weight suggestions
/// (`LiftAnchorMath` → `WorkingWeight.Source.seeded`) until real sets exist.
///
/// Everything here is optional — whole-screen Skip, and any subset of the
/// four lifts counts. "Confident 5" on purpose: 5RM sits in the prediction
/// formulas' most accurate range, and confident self-reports skew safe (an
/// untested-1RM ask would skew heroic). The unit toggle doubles as the
/// lifter's unit_system choice — onboarding previously never asked, and
/// this is the first screen where the answer matters.
///
/// Weights convert to CANONICAL POUNDS at save (Units.swift edge rule).
/// Seeds never enter set_logs, PR math, or volume.
struct LiftAnchorsView: View {
    let onAdvance: () -> Void
    /// True in the onboarding coordinator (STEP 4 OF 4 chrome + "Skip for
    /// now"); false when pushed from Settings as the Starting-weights
    /// editor ("Cancel", no step pip).
    var isOnboarding: Bool = true

    @Environment(\.gsTheme) private var theme

    @State private var unit: WeightUnit = .lbs
    @State private var entries: [String: String] = [:]
    @State private var saving = false
    @State private var errorText: String?

    private static let lifts: [(slug: String, name: String)] = [
        ("back-squat", "Back Squat"),
        ("bench-press", "Bench Press"),
        ("deadlift", "Deadlift"),
        ("ohp", "Overhead Press"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isOnboarding {
                    HStack(spacing: 10) {
                        Text("STEP 4 OF 4")
                            .font(GSFont.bold(12, relativeTo: .caption2))
                            .tracking(0.6)
                            .foregroundColor(theme.neutral700)
                        Spacer()
                    }
                    .padding(.top, 24)
                }

                Text("Where are you starting?")
                    .font(GSFont.heading(26, relativeTo: .title))
                    .foregroundStyle(theme.text)
                    .padding(.top, 10)

                Text("A weight you could confidently lift for 5 reps. Any you know — skip the rest. Your first suggestions start here, and real sets take over immediately.")
                    .font(GSFont.body(14, relativeTo: .body))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                unitToggle
                    .padding(.top, 16)

                VStack(spacing: 10) {
                    ForEach(Self.lifts, id: \.slug) { lift in
                        liftRow(lift.slug, lift.name)
                    }
                }
                .padding(.top, 14)

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .padding(.top, 10)
                }

                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "SAVING…" : "SET MY STARTS")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSPrimaryButtonStyle())
                .disabled(saving)
                .padding(.top, 20)

                Button {
                    onAdvance()
                } label: {
                    Text(isOnboarding ? "Skip for now" : "Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSSecondaryButtonStyle())
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.bg)
        .task { await prefillExisting() }
    }

    /// Settings re-entry (and a resumed onboarding step): show what's
    /// already stored so an edit to one lift can never silently drop the
    /// others — `save()` builds the dict from the visible entries.
    @MainActor
    private func prefillExisting() async {
        guard entries.isEmpty,
              let existing = try? await UserSettingsRepository.get() else { return }
        unit = existing.weightUnit
        for (slug, pounds) in existing.liftAnchors ?? [:] {
            entries[slug] = Units.format(pounds: pounds, unit: existing.weightUnit,
                                         rounded: false, includeUnit: false)
        }
    }

    private var unitToggle: some View {
        HStack(spacing: 8) {
            ForEach(WeightUnit.allCases, id: \.self) { candidate in
                Button {
                    unit = candidate
                } label: {
                    Text(candidate.label.uppercased())
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .kerning(1.0)
                        .foregroundStyle(unit == candidate ? theme.bg : theme.neutral700)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(unit == candidate ? theme.accent : theme.surface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func liftRow(_ slug: String, _ name: String) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(GSFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
            Spacer(minLength: 8)
            TextField("—", text: Binding(
                get: { entries[slug] ?? "" },
                set: { entries[slug] = $0 }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(GSFont.bold(16, relativeTo: .body).monospacedDigit())
            .foregroundStyle(theme.text)
            .frame(width: 84)
            Text(unit.label)
                .font(GSFont.bold(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
        )
    }

    @MainActor
    private func save() async {
        var anchors: [String: Decimal] = [:]
        for (slug, raw) in entries {
            guard let typed = Decimal.parseUserInput(raw), typed > 0 else { continue }
            anchors[slug] = Units.toPounds(typed, from: unit)
        }
        // Nothing entered = an explicit skip — don't write an empty dict
        // over a NULL that means "never captured".
        guard !anchors.isEmpty else {
            onAdvance()
            return
        }
        saving = true
        defer { saving = false }
        do {
            // Get-then-upsert so the write carries every other settings
            // field (the Upsert struct persists the full row).
            var settings = try await UserSettingsRepository.get()
            settings.liftAnchors = anchors
            settings.unitSystem = unit.rawValue
            try await UserSettingsRepository.upsert(settings)
            ThemeStore.shared.noteExternalSettingsWrite(settings)
            onAdvance()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}