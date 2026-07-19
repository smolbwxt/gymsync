import SwiftUI

// MARK: - WhoseTurnView
//
// Phase W Task 3 (watch-hr design §2, Component 1 "Whose-turn home") — the
// Watch's ROOT surface (first `TabView` page, see `ContentView.swift`).
// Renders exactly one of 3 states from `WatchSessionStore`, distinctly (no
// state is inferred from another — see the task brief's carried-in
// requirement on `isActive`):
//   1. LIVE  — `store.sessionState != nil && sessionState.isActive` —
//      session name, current exercise, current lifter (name + initials
//      circle), turn state ("Your turn" / "{name}'s turn"), plus the
//      pre-existing (Task 2) stale-phone indicator.
//   2. ENDED — `store.sessionState != nil && !sessionState.isActive` — the
//      carried-in T2-review fix: distinct "Session ended" + last-known
//      summary, rendered IMMEDIATELY (no staleness timeout involved).
//   3. IDLE  — `store.sessionState == nil` — `store.idleState`'s next-
//      scheduled-session name/time, or "No session" if there is none.
//
// Deliberately NOT a `ScrollView`: Apple's own watchOS 10 guidance for
// `.verticalPage` TabViews (WWDC23 "Update your app for watchOS 10") warns
// that scrollable content inside a vertically-paging tab competes with the
// page-swipe gesture — this surface's content is kept short enough (2-4
// lines) to need no scrolling, matching "tiny-screen honesty."
struct WhoseTurnView: View {
    @Environment(\.gsWatchTheme) private var theme
    let store: WatchSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let state = store.sessionState, state.isActive {
                liveContent(state)
            } else if let state = store.sessionState {
                endedContent(state)
            } else {
                idleContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.bg)
        .navigationTitle("Turn")
        .onAppear {
            // Age-based staleness can't self-trigger on the clock alone
            // (`WatchSessionStore.refreshStaleness`'s own doc comment) —
            // re-check whenever this page becomes visible, same idiom
            // Task 2's placeholder ContentView already established.
            store.refreshStaleness()
        }
    }

    // MARK: - Live

    @ViewBuilder
    private func liveContent(_ state: WatchSessionStatePayload) -> some View {
        Text(state.sessionName.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(theme.text.opacity(0.6))
            .lineLimit(1)

        Text(state.currentExerciseName ?? "Exercise")
            .font(.headline)
            .foregroundStyle(theme.text)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

        if let lifter = state.currentLifterName {
            HStack(spacing: 6) {
                initialsBadge(lifter)
                Text(state.isMyTurn ? "Your turn" : "\(lifter)'s turn")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(state.isMyTurn ? theme.accent : theme.text)
                    .lineLimit(1)
            }
        }

        Spacer(minLength: 0)

        if store.isStale {
            // "wifi.slash" — same long-established SF Symbol Task 2's
            // placeholder already picked (this file's predecessor,
            // `ContentView.swift`, pre-Task-3), for the identical reason:
            // no risk of an unverified symbol name.
            Label("Phone unreachable", systemImage: "wifi.slash")
                .font(.caption2)
                .foregroundStyle(theme.text.opacity(0.6))
        }
    }

    private func initialsBadge(_ name: String) -> some View {
        Text(WatchDisplayFormatting.initials(from: name))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(theme.bg)
            .frame(width: 22, height: 22)
            .background(Circle().fill(theme.accent))
    }

    // MARK: - Ended (Task 3 — carried-in T2-review fix)

    @ViewBuilder
    private func endedContent(_ state: WatchSessionStatePayload) -> some View {
        Label("Session ended", systemImage: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.text)
        Text(state.sessionName)
            .font(.caption)
            .foregroundStyle(theme.text.opacity(0.7))
            .lineLimit(1)
        if let exercise = state.currentExerciseName {
            Text("Last: \(exercise)")
                .font(.caption2)
                .foregroundStyle(theme.text.opacity(0.55))
                .lineLimit(1)
        }
        Spacer(minLength: 0)
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleContent: some View {
        if let idle = store.idleState, let name = idle.nextSessionName {
            Text("NEXT SESSION")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(theme.text.opacity(0.5))
            Text(name)
                .font(.headline)
                .foregroundStyle(theme.text)
                .lineLimit(2)
            if let at = idle.nextSessionAt {
                Text(at, style: .relative)
                    .font(.caption)
                    .foregroundStyle(theme.accent)
            }
            Spacer(minLength: 0)
        } else {
            Spacer(minLength: 0)
            Text("No session")
                .font(.subheadline)
                .foregroundStyle(theme.text.opacity(0.6))
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    WhoseTurnView(store: .shared)
}
