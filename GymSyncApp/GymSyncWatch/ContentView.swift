import SwiftUI

// MARK: - ContentView
//
// Phase W Task 3 (watch-hr design §2) — replaces Task 1/2's single-screen
// placeholder ("No live session" / minimal live summary, both folded into
// `WhoseTurnView` now) with the real 4-surface companion: whose-turn
// (root), tap-to-log-set, soundboard, ledger glance.
//
// NAVIGATION (task brief's explicit judgment call — "TabView (vertical
// paging) or NavigationStack, judge per watchOS 10 idiom"): `TabView` +
// `.tabViewStyle(.verticalPage)`, watchOS 10's OWN tab-view redesign for a
// small set of SIBLING, non-hierarchical surfaces — Apple's WWDC23 "Update
// your app for watchOS 10" session demonstrates exactly this shape (a
// `TabView` of peer screens, each carrying its own `.navigationTitle`,
// `.tabViewStyle(.verticalPage)`) for a multi-glance companion app. A
// `NavigationStack` was rejected: it reads as parent/child drill-down
// (tap in, tap "back" out), which is the wrong mental model for 4 PEER
// glances a lifter flips between mid-set — vertical Digital-Crown/swipe
// paging is the faster, one-handed motion for that. "Whose-turn is the
// root" (brief) = first page below.
//
// Per Apple's own guidance for `.verticalPage` (cited above): scrollable
// content should live in the LAST tab if it must exist at all, since a
// ScrollView inside a vertically-paging TabView competes with the page-
// swipe gesture. None of these 4 surfaces scroll (each is deliberately kept
// to a handful of short lines — "tiny-screen honesty"), so this doesn't
// bite here, but it's why `WhoseTurnView`/`LogSetView`/`SoundboardView`/
// `LedgerView` all use plain `VStack`/`Group`, never `ScrollView`.
//
// `LogSetView`'s own Digital Crown usage (weight adjustment) is scoped to
// its own `.focusable` control, not a page-level gesture — see that file's
// header doc comment for the citation and the interaction nuance flagged
// as a device-QA item (crown-vs-page-swipe contention is a real-device
// question this session can't verify without a Watch/simulator).
struct ContentView: View {
    @State private var store = WatchSessionStore.shared

    var body: some View {
        TabView {
            WhoseTurnView(store: store)
            LogSetView(store: store)
            SoundboardView(store: store)
            LedgerView(store: store)
        }
        .tabViewStyle(.verticalPage)
        .task {
            #if DEBUG
            // CI marketing screenshots - see seedForScreenshots' doc.
            if CommandLine.arguments.contains("--marketing-demo") {
                store.seedForScreenshots()
            }
            #endif
        }
    }
}

#Preview {
    ContentView()
}
