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

                // gs3D pass (2026-09-03, P2): a preset is a choice the user
                // taps, so each row sits proud and sinks on its own rather
                // than living inside one bordered group box. The box's
                // stroke and the internal hairlines retire — the lips
                // delineate — and `isLast` goes with them.
                VStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { seconds in
                        presetRow(seconds: seconds)
                    }
                }

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

    /// One sinking extruded preset row. The label sheds its own surface fill
    /// (it would paint over the face) and the selection reads as the 2pt
    /// accent ring plus the checkmark it always had — the HomeView pickCard
    /// anatomy. Footprint held: a 38pt face on a 6pt lip is the old 44pt
    /// row, and the style's `contentShape` covers both, so the tap target
    /// stays at Apple's 44pt floor (`GSPrimaryButtonStyle`'s own idiom).
    private func presetRow(seconds: Int) -> some View {
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
            .frame(minHeight: 38)
            .overlay(
                isSelected
                    ? RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                        .strokeBorder(theme.accent, lineWidth: 2)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Custom section — minus box / value / plus box, ±`stepSeconds` per tap,
    /// clamped to [`minSeconds`, `maxSeconds`]. Persists through the same
    /// `select(_:)` path as a preset tap (optimistic — reverts + surfaces
    /// `errorText` on failure), so a failed upsert here behaves identically
    /// to a failed preset selection.
    ///
    /// gs3D pass (2026-09-03, P2): deliberately still FLAT. A stepper is a
    /// numeric input, and inputs are furniture, not widgets — the same
    /// judgment that keeps ScheduleSessionView's DatePicker tiles and the
    /// bar-weight field flat while the tappable rows around them sit proud.
    private func customStepperRow() -> some View {
        HStack(spacing: 12) {
            stepperBox(symbol: "−") {
                select(clamped(selectedSeconds - Self.stepSeconds))
            }

            Spacer(minLength: 0)

            Text(UserSettings.formatRestSeconds(selectedSeconds))
                .font(GSFont.bold(15, relativeTo: .subheadline))
                .foregroundColor(theme.text)
                .monospacedDigit()

            Spacer(minLength: 0)

            stepperBox(symbol: "+") {
                select(clamped(selectedSeconds + Self.stepSeconds))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    /// A single "small drawn box" stepper button — 44×44 bordered square
    /// (zero-radius, matches this screen's/`LogSetSheet`'s existing
    /// bordered-`Rectangle` treatment), full-frame `contentShape` so the
    /// whole 44pt square is tappable, not just the glyph.
    ///
    /// The glyph colour was a `color:` parameter so the "+" box could carry
    /// an accent tint; the owner's default-text law (2026-08-13) retires
    /// accent on UI text, both glyphs read neutral700 now, and the knob went
    /// with the tint.
    private func stepperBox(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundColor(theme.neutral700)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    private func clamped(_ seconds: Int) -> Int {
        min(Self.maxSeconds, max(Self.minSeconds, seconds))
    }

    /// Fix round B1 (final review blocker): on success, also calls
    /// `ThemeStore.shared.noteExternalSettingsWrite(updated)` — this view's
    /// own full-row upsert (`currentSettings` + the new `defaultRestSeconds`)
    /// otherwise leaves `ThemeStore`'s `lastKnownSettings` cache holding a
    /// stale rest-seconds value, which the *next* palette `select(_:)` would
    /// then upsert right back over this save (clobbering it in the DB,
    /// invisible until relaunch). `updated` already carries the correct,
    /// live palette (see `YouTabView.effectiveUserSettings`), so this call
    /// is safe even though it also passes `.palette` along — see
    /// `noteExternalSettingsWrite`'s own doc for how it protects that field
    /// from an in-flight palette persist.
    private func select(_ seconds: Int) {
        guard seconds != selectedSeconds else { return }
        let previous = selectedSeconds
        selectedSeconds = seconds
        Task {
            do {
                var updated = currentSettings
                updated.defaultRestSeconds = seconds
                try await UserSettingsRepository.upsert(updated)
                await MainActor.run {
                    ThemeStore.shared.noteExternalSettingsWrite(updated)
                    onSaved(updated)
                }
            } catch {
                await MainActor.run {
                    selectedSeconds = previous
                    errorText = ErrorMapping.map(error).errorDescription
                }
            }
        }
    }
}
