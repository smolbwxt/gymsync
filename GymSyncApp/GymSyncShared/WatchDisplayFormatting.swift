import Foundation

// MARK: - WatchDisplayFormatting
//
// Phase W Task 3 (watch-hr design §2, "Whose-turn home": "current lifter
// (name/initials)"). SHARED file (`GymSyncShared/`, same target-membership
// mechanism as `WatchEnvelope.swift` — compiled into BOTH `GymSync` and
// `GymSyncWatch`, see `project.yml`'s comment on that folder).
//
// Pulled out as a pure, standalone function specifically so it's hermetically
// testable: the Watch target itself has no test bundle (`WatchSessionStore.
// swift`'s own header doc comment — "do NOT create one"), but code that
// lives in `GymSyncShared/` compiles into `GymSync` too, so `GymSyncTests`
// (`@testable import GymSync`) exercises the EXACT same implementation the
// watch-side views call, not a parallel reimplementation.
enum WatchDisplayFormatting {

    /// Derives up to 2 uppercase initials from a display name — the
    /// whose-turn home surface's "name/initials" fallback for the tiny
    /// watch face (design §2 explicitly names both as acceptable; a name
    /// alone can overflow the current-lifter line at watch text sizes,
    /// initials are the compact fallback). Splits on whitespace, takes the
    /// first character of the first two non-empty components. A single-
    /// word name (the common case here — this app's names are usernames,
    /// e.g. "tommy", not "Tommy Smith") yields ONE initial, not a fabricated
    /// second letter — two letters would imply information (a "last name")
    /// this app's `Profile.username` doesn't actually carry.
    /// Empty/whitespace-only input yields `""` (nothing to render — callers
    /// decide their own placeholder, this function never fabricates one).
    static func initials(from name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
