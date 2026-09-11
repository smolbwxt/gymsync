import XCTest
@testable import GymSync

/// The goal screen's copy table.
///
/// A SwiftUI body is not unit-testable in this target, so the CAPTURE is the
/// proof of the screen (`goal-screen`, plan task C5). What is testable is the
/// table the screen reads — and a copy table is exactly the thing that rots
/// quietly: a preset added without a line renders a tile with a name and a
/// blank, and nothing fails until someone looks at a frame.
///
/// So the tests below are about the GRID being scannable rather than about
/// any one sentence: ten tiles, every one with a glyph and a line, no line
/// trailing off without a full stop, and no two tiles wearing the same
/// symbol — a grid where two tiles share a glyph is a grid nobody can scan.
final class GoalScreenCopyTests: XCTestCase {

    // MARK: - The grid

    /// TEN TILES, ELEVEN PRESETS. `repStrength` is the eleventh preset and
    /// the spec is explicit that it is not an eleventh tile (§2.3: "Rep
    /// strength appears as a second lever on the Strength card"), so this
    /// pins both halves: the count, and the one absence that makes it true.
    func testTenTilesAndRepStrengthIsNotOneOfThem() {
        XCTAssertEqual(GoalPreset.tiles.count, 10)
        XCTAssertEqual(GoalPreset.allCases.count, 11)
        XCTAssertFalse(GoalPreset.tiles.contains(.repStrength),
                       "rep strength is Strength's second lever, not a tile")
    }

    func testEveryTileHasAGlyphAndALine() {
        for preset in GoalPreset.tiles {
            guard let copy = GoalScreenView.copy[preset] else {
                XCTFail("no copy for \(preset.rawValue)")
                continue
            }
            XCTAssertFalse(copy.glyph.isEmpty, "\(preset.rawValue) has no glyph")
            XCTAssertFalse(copy.line.isEmpty, "\(preset.rawValue) has no line")
        }
    }

    /// Sentence case for sentences (design rule 9), and a sentence ends.
    func testEveryLineEndsInAFullStop() {
        for preset in GoalPreset.tiles {
            let line = GoalScreenView.copy[preset]?.line ?? ""
            XCTAssertTrue(line.hasSuffix("."),
                          "\(preset.rawValue): \(line)")
        }
    }

    func testNoTwoTilesShareAGlyph() {
        let glyphs = GoalPreset.tiles.compactMap { GoalScreenView.copy[$0]?.glyph }
        XCTAssertEqual(glyphs.count, GoalPreset.tiles.count,
                       "a tile with no glyph would hide here")
        XCTAssertEqual(Set(glyphs).count, glyphs.count,
                       "two tiles wearing one symbol is a grid nobody can scan")
    }

    /// Every preset — including the one that is not a tile — is nameable, so
    /// the Strength card's `REPS AT A LOAD` branch and the milestone card's
    /// title have a word to print.
    func testEveryPresetHasAName() {
        for preset in GoalPreset.allCases {
            XCTAssertFalse(GoalScreenView.name(preset).isEmpty, preset.rawValue)
        }
    }

    // MARK: - The Pro door

    /// PHASE 1 RENDERS IT DISABLED, AND SAYS WHY. The reason is that the
    /// Coach-guided consult is not built yet (spec §10 puts it in phase 2) —
    /// NOT entitlement: `Entitlements.hasPro` is `true` today
    /// (`Models/CoachObservations.swift:11-13`). Naming the gate now and
    /// disabling for a stated reason is the honest shape; silently routing to
    /// a screen that cannot bind a goal is not.
    func testTheProDoorIsRenderedDisabledAndSaysWhy() {
        XCTAssertFalse(GoalScreenView.proDoorEnabled,
                       "phase 1 renders the Pro door disabled (plan task C1)")
        XCTAssertEqual(GoalScreenView.proDoorTitle, "Talk it through with Coach")
        XCTAssertEqual(GoalScreenView.proDoorFooter,
                       "PRO · ARRIVING WITH THE WATCH METRICS")
        XCTAssertFalse(GoalScreenView.proDoorLine.isEmpty)
        XCTAssertTrue(GoalScreenView.proDoorLine.hasSuffix("."))
    }

    // MARK: - What a tap hands over

    /// The tile hands over a draft that NAMES ITS PRESET and nothing more:
    /// the numbers are the milestone card's to seed (`GoalMilestoneCopy
    /// .draft`, task C2). What must be true here is that the metric and the
    /// preset agree, and that the athlete is recorded as the author — the
    /// door is the athlete choosing.
    func testATileHandsOverItsOwnPreset() {
        for preset in GoalPreset.tiles {
            let draft = GoalScreenView.chosen(preset)
            XCTAssertEqual(draft.preset, preset, preset.rawValue)
            XCTAssertEqual(draft.metric, preset.metric, preset.rawValue)
            XCTAssertEqual(draft.source, .user, "the door is the athlete choosing")
        }
    }
}
