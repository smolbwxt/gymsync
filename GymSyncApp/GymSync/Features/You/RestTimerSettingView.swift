import SwiftUI

/// Default rest timer preset picker — pushed from the You tab's Settings Hub
/// "Default rest timer" row (new-canvas-section.diff's "Settings Hub" frame,
/// Canvas Completion Task 2). Five fixed presets (1:00–3:00) plus a "Custom"
/// stepper section (±15s, clamped 15–900s to match `user_settings
/// .default_rest_seconds`'s own CHECK constraint). The stepper was owed from
/// task-2-brief.md's own spec line ("simple preset list ... + custom
/// stepper") — the original task-2 contract scoped it out (recorded as
/// deviation #4 in task-2-report.md); this fix round adds it.
///
/// Selecting a preset OR adjusting the stepper persists immediately via
/// `UserSettingsRepository.upsert` (optimistic — reverts + surfaces an error
/// on failure) and calls back so the caller (`YouTabView`) can refresh its
/// cached `UserSettings` without a full reload. Both controls share the same
/// `selectedSeconds` state var and the same `select(_:)` persist path — there
/// is no separate "custom mode" flag. Consequence (intentional, simplest
/// consistent behavior): if the stepper lands on a value that equals a
/// preset (e.g. stepped to exactly 120s), that preset's checkmark lights up
/// too, since "selected" just means "this is the current value" regardless
/// of which control last set it.
struct RestTimerSettingView: View {
    @Environment(\.gsTheme) private var theme

    let currentSettings: UserSettings
    let onSaved: (UserSettings) -> Void

    @State private var selectedSeconds: Int
    @State private var errorText: String?

    /// 1:00 / 1:30 / 2:00 / 2:30 / 3:00, per the brief.
    private static let presets = [60, 90, 120, 150, 180]

    /// Matches `user_settings.default_rest_seconds`'s CHECK constraint
    /// (`supabase/migrations/20260717000001_user_settings.sql`: BETWEEN 15
    /// AND 900).
    private static let minSeconds = 15
    private static let maxSeconds = 900
    private static let stepSeconds = 15

    init(currentSettings: UserSettings, onSaved: @escaping (UserSettings) -> Void) {
        self.currentSettings = currentSettings
        self.onSaved = onSaved
        _selectedSeconds = State(initialValue: currentSettings.defaultRestSeconds)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GSSectionHeader("Default rest timer")

                VStack(spacing: 0) {
                    ForEach(Array(Self.presets.enumerated()), id: \.element) { index, seconds in
                        presetRow(seconds: seconds, isLast: index == Self.presets.count - 1)
                    }
                }
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

                GSSectionHeader("Custom")
                customStepperRow()

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(13, relativeTo: .footnote))
                        .foregroundColor(.red)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        .background(theme.bg)
        .navigationTitle("Rest Timer")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from YouTabView's Settings Hub — see GSComponents.swift's GSHidesDock.
        .gsHidesDock()
    }

    private func presetRow(seconds: Int, isLast: Bool) -> some View {
        let isSelected = selectedSeconds == seconds
        return Button {
            select(seconds)
        } label: {
            HStack {
                Text(UserSettings.formatRestSeconds(seconds))
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundColor(theme.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(theme.surface)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Custom section — minus box / value / plus box, ±`stepSeconds` per tap,
    /// clamped to [`minSeconds`, `maxSeconds`]. Persists through the same
    /// `select(_:)` path as a preset tap (optimistic — reverts + surfaces
    /// `errorText` on failure), so a failed upsert here behaves identically
    /// to a failed preset selection.
    private func customStepperRow() -> some View {
        HStack(spacing: 12) {
            stepperBox(symbol: "−", color: theme.neutral700) {
                select(clamped(selectedSeconds - Self.stepSeconds))
            }

            Spacer(minLength: 0)

            Text(UserSettings.formatRestSeconds(selectedSeconds))
                .font(GSFont.bold(15, relativeTo: .subheadline))
                .foregroundColor(theme.text)
                .monospacedDigit()

            Spacer(minLength: 0)

            stepperBox(symbol: "+", color: theme.accent) {
                select(clamped(selectedSeconds + Self.stepSeconds))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    /// A single "small drawn box" stepper button — 44×44 bordered square
    /// (zero-radius, matches this screen's/`LogSetSheet`'s existing
    /// bordered-`Rectangle` treatment), full-frame `contentShape` so the
    /// whole 44pt square is tappable, not just the glyph.
    private func stepperBox(symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    private func clamped(_ seconds: Int) -> Int {
        min(Self.maxSeconds, max(Self.minSeconds, seconds))
    }

    private func select(_ seconds: Int) {
        guard seconds != selectedSeconds else { return }
        let previous = selectedSeconds
        selectedSeconds = seconds
        Task {
            do {
                var updated = currentSettings
                updated.defaultRestSeconds = seconds
                try await UserSettingsRepository.upsert(updated)
                await MainActor.run { onSaved(updated) }
            } catch {
                await MainActor.run {
                    selectedSeconds = previous
                    errorText = ErrorMapping.map(error).errorDescription
                }
            }
        }
    }
}
