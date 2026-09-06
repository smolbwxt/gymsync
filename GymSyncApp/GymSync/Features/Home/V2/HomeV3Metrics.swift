import SwiftUI

// MARK: - Home v3 shared geometry
//
// Home v3 (plan: docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md)
// is the second CATALOG-ONLY round: ten compositions of the Home v2 pieces
// plus eight new ones, rendered through `CatalogHostView` with fixture data
// so the owner can pick a shape before anything is wired into production
// `HomeView`. Nothing in this folder is reachable from the running app.
//
// The v3 pieces live beside the v2 ones in `Features/Home/V2/` on purpose:
// v3 is not a fork, it is the same kit with more pieces in it, and eight of
// the ten compositions below are mostly v2 parts.

/// The three numbers the v3 tiles share, from the plan's own "New pieces"
/// note ("Tiles are 12 pt inner padding, min height 104 pt, paired in a
/// two-column row with 10 pt gap"). They live here rather than as literals
/// in six files, the same reason `HomeV2Metrics` exists.
///
/// These deliberately do NOT edit `HomeV2Metrics`: the v2 pieces are frozen
/// except for additive parameters, and a v2 tile keeps its own 15/13 padding
/// even when it stands beside a v3 tile in the same row (the row sizes to the
/// taller one, so the pair still reads level).
enum HomeV3Metrics {
    /// Inner padding on a v3 tile.
    static let tilePadding: CGFloat = 12
    /// A v3 tile is never shorter than this, so a two-line tile beside a
    /// four-line one still reads as a tile rather than a chip.
    static let tileMinHeight: CGFloat = 104
    /// Gap between the two tiles of a v3 row.
    static let tileGap: CGFloat = 10
}
