import SwiftUI

/// Default rest timer preset picker — pushed from the You tab's Settings Hub
/// "Default rest timer" row (new-canvas-section.diff's "Settings Hub" frame,
/// Canvas Completion Task 2). Five fixed presets (1:00–3:00); no custom
/// stepper — task-2-brief.md's spec line mentions "+ custom stepper" but the
/// task contract this was built against calls for presets only ("simple
/// preset list ... selection check treatment, persists via repository; 44pt
/// rows"), so the stepper is omitted here (recorded decision, task-2-report
/// .md) rather than guessed at.
///
/// Selecting a preset persists immediately via `UserSettingsRepository
/// .upsert` (optimistic — reverts + surfaces an error on failure) and calls
/// back so the caller (`YouTabView`) can refresh its cached `UserSettings`
/// without a full reload.
struct RestTimerSettingView: View {
    @Environment(\.gsTheme) private var theme

    let currentSettings: UserSettings
    let onSaved: (UserSettings) -> Void

    @State private var selectedSeconds: Int
    @State private var errorText: String?

    /// 1:00 / 1:30 / 2:00 / 2:30 / 3:00, per the brief.
    private static let presets = [60, 90, 120, 150, 180]

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
