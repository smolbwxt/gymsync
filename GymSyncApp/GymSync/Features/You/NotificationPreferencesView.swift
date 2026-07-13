import SwiftUI
import UserNotifications

/// Per-category push notification opt-out screen (Designer brief Feature 2,
/// Dossier §A.7; redrawn per new-canvas-section.diff's "Notif Preferences"
/// frame, Jul 2026 — Canvas Completion Task 1). Nav-pushed from
/// `YouTabView`'s "Notifications" settings row.
///
/// The system-denied banner below is this screen's own re-entry surface: its
/// "Open" action pushes `PushPrimingView(isOnboarding: false)`, whose denied
/// state carries the "Open Settings" deep link. That re-entry destination
/// previously had no production call site (task-6-report.md); this wiring
/// resolves that tracked question. The banner itself is kept — the canvas
/// designs both surfaces separately, each per its own frame.
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
    @State private var showPushPrimingReentry = false

    private var pushReceiver: PushReceiver { PushReceiver.shared }

    /// Category key -> plain-English label, grouped and ordered per the
    /// canvas's "Notif Preferences" frame (new-canvas-section.diff):
    /// "Sessions" then "Social & chat", each in the diff's row order.
    /// `categoryLabels` is the flat union of both (order-independent for
    /// callers that don't care about grouping, e.g. `loadPrefs()` and
    /// `PushRegistrationTests`'s completeness/label assertions). Not
    /// `private` so `PushRegistrationTests` can assert completeness (all
    /// 10, no dupes) without duplicating this list in the test target.
    static let sessionsCategories: [(category: String, label: String)] = [
        ("session_invite", "Session invites"),
        ("session_reminder_15min", "15-minute reminders"),
        ("session_lobby_open", "Lobby is open"),
        ("your_turn", "It's your turn"),
        ("session_idle", "Idle session nudges"),
    ]

    static let socialCategories: [(category: String, label: String)] = [
        ("friend_request", "Friend requests"),
        ("partner_pr", "Crew PRs"),
        ("lateness_chirp", "Late-arrival pings"),
        ("chat_mention", "Mentions in chat"),
        ("leaderboard_passed", "Leaderboard changes"),
    ]

    static let categoryLabels: [(category: String, label: String)] = sessionsCategories + socialCategories

    private var allOff: Bool {
        Self.categoryLabels.allSatisfy { !(prefs[$0.category] ?? true) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                deniedBanner

                groupSection(title: "Sessions", entries: Self.sessionsCategories)
                groupSection(title: "Social & chat", entries: Self.socialCategories)

                if allOff {
                    Text("You won't receive any notifications.")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundColor(theme.neutral700)
                }

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
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from YouTabView's Settings section — see GSComponents.swift's
        // GSHidesDock.
        .gsHidesDock()
        .navigationDestination(isPresented: $showPushPrimingReentry) {
            PushPrimingView(isOnboarding: false)
        }
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
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Disabled in iOS Settings")
                        .font(GSFont.bold(12, relativeTo: .footnote))
                        .foregroundColor(theme.text)
                    Text("Saved here, but won't apply until re-enabled.")
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundColor(theme.neutral700)
                }

                Spacer()

                Button {
                    showPushPrimingReentry = true
                } label: {
                    Text("Open")
                }
                .buttonStyle(GSSecondaryButtonStyle(fontSize: 11, horizontalPadding: 9, verticalPadding: 6))
                .frame(minHeight: 44)
            }
            .padding(12)
            .background(theme.surface)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 3)
            }
        }
    }

    // MARK: - Grouped sections

    private func groupSection(title: String, entries: [(category: String, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundColor(theme.text.opacity(0.6))

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.category) { index, entry in
                    toggleRow(category: entry.category, label: entry.label, isLast: index == entries.count - 1)
                }
            }
            .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
        }
    }

    // MARK: - Toggle row

    private func toggleRow(category: String, label: String, isLast: Bool) -> some View {
        let isOn = prefs[category] ?? true
        return HStack {
            Text(label)
                .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                .foregroundColor(theme.text.opacity(isOn ? 1.0 : 0.6))
            Spacer()
            GSToggle(isOn: Binding(
                get: { prefs[category] ?? true },
                set: { setEnabled($0, category: category) }
            ))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(theme.divider).frame(height: 1)
            }
        }
    }

    // MARK: - Actions

    /// DECISION (documented in task-6-report.md, preserved in
    /// task-1-report.md): toggling ON deletes the stored row (reverts to
    /// the server's absence-means-enabled default) rather than upserting
    /// `enabled=true` — keeps the table storing only exceptions to the
    /// default, matching `reset(category:)`'s own doc comment ("reverting
    /// it to the default (enabled)") and the schema's design intent (spec:
    /// "Defaults: all on for v1"). Toggling OFF has no such default to fall
    /// back to, so it upserts `enabled=false` explicitly — the only way to
    /// represent "off" given absence always means "on".
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
