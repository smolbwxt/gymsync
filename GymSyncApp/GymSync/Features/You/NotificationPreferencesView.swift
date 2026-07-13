import SwiftUI
import UserNotifications

/// Per-category push notification opt-out screen (Designer brief Feature 2,
/// Dossier §A.7) — nav-pushed from `YouTabView`'s "Notifications" settings
/// row. Also serves as the "re-entry when denied" surface described in
/// Feature 1's brief: per task-6-brief.md, the You tab routes here directly
/// (not through `PushPrimingView`), and the system-denied banner below
/// covers that role via its own "Open Settings" deep link.
struct NotificationPreferencesView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    /// Optimistic-default map: every category starts `true` (matches the
    /// server's absence-means-enabled default — see
    /// NotificationPrefsRepository.isEnabled) and is corrected in place as
    /// each row's real value resolves. "Best-effort loads (no blocking
    /// spinner for the whole screen)" per the task brief — the screen
    /// renders immediately with the correct defaults rather than waiting.
    @State private var prefs: [String: Bool] = Dictionary(
        uniqueKeysWithValues: NotificationPrefsRepository.categories.map { ($0, true) }
    )
    @State private var errorText: String?

    private var pushReceiver: PushReceiver { PushReceiver.shared }

    /// Category key -> plain-English label, verbatim from the designer
    /// brief's Feature 2 table (2026-07-12-design-request-next-phases.md,
    /// lines 56-67), in the same order as
    /// `NotificationPrefsRepository.categories`. Not `private` so
    /// `PushRegistrationTests` can assert completeness (all 10, no dupes)
    /// without duplicating this list in the test target.
    static let categoryLabels: [(category: String, label: String)] = [
        ("friend_request", "Friend requests"),
        ("session_invite", "Session invites"),
        ("session_reminder_15min", "15-minute reminders"),
        ("session_lobby_open", "Lobby is open"),
        ("your_turn", "It's your turn"),
        ("partner_pr", "Crew PRs"),
        ("lateness_chirp", "Late-arrival pings"),
        ("session_idle", "Idle session nudges"),
        ("chat_mention", "Mentions in chat"),
        ("leaderboard_passed", "Leaderboard changes"),
    ]

    private var allOff: Bool {
        Self.categoryLabels.allSatisfy { !(prefs[$0.category] ?? true) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                deniedBanner

                GSSectionHeader("Notifications")
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 6)

                Text("All on by default — turn off any you don't need.")
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundColor(theme.neutral700)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                VStack(spacing: 0) {
                    ForEach(Self.categoryLabels, id: \.category) { entry in
                        toggleRow(category: entry.category, label: entry.label)
                    }
                }
                .padding(.horizontal, 16)

                if allOff {
                    Text("You won't receive any notifications.")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundColor(theme.neutral700)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(13, relativeTo: .footnote))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Spacer(minLength: 24)
            }
        }
        .background(theme.bg)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from YouTabView's Settings section — see GSComponents.swift's
        // GSHidesDock.
        .gsHidesDock()
        .task {
            await pushReceiver.refreshAuthorizationStatus()
            await loadPrefs()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await pushReceiver.refreshAuthorizationStatus() }
        }
    }

    // MARK: - System-denied banner

    @ViewBuilder
    private var deniedBanner: some View {
        if pushReceiver.authorizationStatus == .denied {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notifications are disabled in iOS Settings — per-category preferences are saved but won't apply until you re-enable them.")
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundColor(theme.text)

                Button {
                    openSettings()
                } label: {
                    Text("Open Settings")
                }
                .buttonStyle(GSSecondaryButtonStyle())
                .frame(minHeight: 44)
            }
            .padding(16)
            .background(theme.accent100)
            .overlay(Rectangle().strokeBorder(theme.accent300, lineWidth: 1))
        }
    }

    // MARK: - Toggle row

    private func toggleRow(category: String, label: String) -> some View {
        HStack {
            Text(label)
                .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                .foregroundColor(theme.text)
            Spacer()
            Toggle("", isOn: Binding(
                get: { prefs[category] ?? true },
                set: { setEnabled($0, category: category) }
            ))
            .labelsHidden()
            .tint(theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// DECISION (documented in task-6-report.md): toggling ON deletes the
    /// stored row (reverts to the server's absence-means-enabled default)
    /// rather than upserting `enabled=true` — keeps the table storing only
    /// exceptions to the default, matching `reset(category:)`'s own doc
    /// comment ("reverting it to the default (enabled)") and the schema's
    /// design intent (spec: "Defaults: all on for v1"). Toggling OFF has no
    /// such default to fall back to, so it upserts `enabled=false`
    /// explicitly — the only way to represent "off" given absence always
    /// means "on".
    private func setEnabled(_ enabled: Bool, category: String) {
        let previous = prefs[category] ?? true
        prefs[category] = enabled
        Task {
            do {
                if enabled {
                    try await NotificationPrefsRepository.reset(category: category)
                } else {
                    try await NotificationPrefsRepository.setEnabled(false, category: category)
                }
            } catch {
                await MainActor.run {
                    prefs[category] = previous
                    errorText = ErrorMapping.map(error).errorDescription
                }
            }
        }
    }

    // MARK: - Data loading

    @MainActor
    private func loadPrefs() async {
        await withTaskGroup(of: (String, Bool?).self) { group in
            for category in NotificationPrefsRepository.categories {
                group.addTask {
                    let value = try? await NotificationPrefsRepository.isEnabled(category: category)
                    return (category, value)
                }
            }
            for await (category, value) in group {
                if let value {
                    prefs[category] = value
                }
            }
        }
    }
}
