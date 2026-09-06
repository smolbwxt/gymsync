import SwiftUI

// MARK: - Home v2 shared design constants
//
// Home v2 (plan: docs/superpowers/plans/2026-09-05-home-v2-catalog.md) is a
// CATALOG-ONLY build: two arrangements of the same pieces, rendered through
// `CatalogHostView` with fixture data so the owner can pick A, B, or a mix
// before anything is wired into production `HomeView`. Nothing in this folder
// is reachable from the running app.

/// Gold, and only gold's two jobs (design language rule 2): the week-streak
/// number, and "the window is open, act now" — the check-in state of the one
/// button. Values are the plan's (`0xF6C945 → 0xDCA426`, ink `0x2A1D02`).
///
/// Production keeps its own copy of this pair as three `private static let`s on
/// `HomeView` (`goldTop`/`goldBottom`/`goldInk`, HomeView.swift:632-634) whose
/// ink is a hair darker (`0x261A02`). This file deliberately re-declares the
/// plan's values rather than widening production's access: the build's own
/// constraint is that `HomeView.swift` is not edited, and a 4-value difference
/// in one ink is invisible at render.
enum HomeV2Gold {
    static let top = Color.gsHex(0xF6C945)
    static let bottom = Color.gsHex(0xDCA426)
    static let ink = Color.gsHex(0x2A1D02)
}

/// The few geometry numbers Home v2's pieces share. Radii come from
/// `GSMetrics` (cards 24 / small 16 / pill 999); the 14 pt strip radius is the
/// one radius the design language names (rule 1) that has no token yet, so it
/// lives here rather than as a literal in three files.
enum HomeV2Metrics {
    /// The one button's face height (plan: "Height 57 pt, lip 7 pt").
    static let oneButtonFace: CGFloat = 57
    /// Lip height for the one button and the solo pill beside it — 7 pt, the
    /// `GS3DButtonStyle` default, so face/lip seams line up across the row.
    static let lip: CGFloat = 7
    /// Strips are not cards (rule 1): `surface` fill, 14 pt radius.
    static let stripRadius: CGFloat = 14
    /// The quiet solo pill's face height (plan: 48 pt).
    static let soloPillFace: CGFloat = 48
}

// MARK: - The one button

/// Every state the one button can be in, with the exact copy the plan's table
/// specifies. The button READS the state and names the next physical act; it
/// NEVER starts a workout by itself (design language rule 5) — every state
/// lands on a screen where the lifter can still do something different. Each
/// case's doc comment names that destination; wiring one is out of scope for
/// this catalog build.
enum HomeOneButtonState {
    /// Tap → the start screen with this routine pre-populated.
    case startRoutine(String)
    /// Tap → the start screen with nothing pre-populated (routines /
    /// freestyle / build one).
    case startWorkout
    /// Quiet: the check-in window has not opened yet. Tap → the crew room,
    /// where committing lives.
    case checkInOpens(String)
    /// The window is open. Tap → the lobby, where checking in happens.
    case checkIn(crew: String, routine: String, time: String)
    /// It started without you. Tap → the lobby of the live session.
    case joinSession(startedAt: String)

    /// Which of the three faces this state wears (plan's table): accent for
    /// the ordinary primary, the theme's raised pair for the quiet countdown,
    /// gold for "act now".
    enum Face { case accent, raised, gold }

    var face: Face {
        switch self {
        case .startRoutine, .startWorkout, .joinSession: return .accent
        case .checkInOpens:                              return .raised
        case .checkIn:                                   return .gold
        }
    }

    /// True when the primary is about a session with other people. Rule 5:
    /// in those states the quiet `START SOLO WORKOUT` pill remains under it.
    var isCrewState: Bool {
        switch self {
        case .checkInOpens, .checkIn, .joinSession: return true
        case .startRoutine, .startWorkout:          return false
        }
    }

    var line1: String {
        switch self {
        case .startRoutine(let name):   return "START · \(name.uppercased())"
        case .startWorkout:             return "START A WORKOUT"
        case .checkInOpens(let time):   return "CHECK-IN OPENS \(time)"
        case .checkIn:                  return "CHECK IN"
        case .joinSession:              return "JOIN THE SESSION"
        }
    }

    var line2: String {
        switch self {
        case .startRoutine:
            return "LOCKED AND LOADED · OPENS THE START SCREEN"
        case .startWorkout:
            return "ROUTINES · FREESTYLE · BUILD ONE"
        case .checkInOpens:
            return "YOU'RE IN"
        case .checkIn(let crew, let routine, let time):
            return "\(crew.uppercased()) · \(routine.uppercased()) · \(time.uppercased()) · OPEN NOW"
        case .joinSession(let startedAt):
            return "STARTED \(startedAt) · YOU'RE LATE"
        }
    }
}

/// The glance-level commit status of the crew session the `.checkInOpens`
/// state is counting down to.
///
/// Production only. It exists because the Home inventory
/// (`.superpowers/sdd/2026-09-04-investigations/screen-inventory-2.md` §1d)
/// calls the commit chip "the only glance-level commit status" in the app —
/// committing itself lives on the crew room's board — and the countdown card
/// that used to carry it (`HomeView.countdownBody`) is gone. It rides the
/// one button's own navigation rather than being a nested `Button`, the same
/// call `HomeView.commitControl` made and for the same reason (a `Button`
/// inside a `Button`'s label is a gesture-conflict hazard).
enum HomeOneButtonCommitChip {
    /// You haven't said yet.
    case commit
    case committed
    case out
}

/// Home's one primary (design language rule 4: one primary per screen). A
/// sinking extruded control — `GS3DCardStyle` rather than `GS3DButtonStyle`
/// because the gold state paints a gradient over its own face and only the
/// card style clips the label to the rounded shape (the same reason
/// production's `goldCheckInCard` rides `.gs3DCardStyle(face: goldBottom)`).
struct HomeOneButton: View {
    @Environment(\.gsTheme) private var theme

    let state: HomeOneButtonState
    /// The commit chip on the trailing edge, or `nil` for no chip at all.
    ///
    /// ADDITIVE, defaulted to `nil`, exactly like
    /// `HomeCalendarCard.showsAppointments`: every catalog call site
    /// (`HomeV3Frame`, `HomeV2TilesView`, `HomeV2StripsView`) omits it and
    /// renders byte-identically to the frames the owner approved — the `nil`
    /// path adds a zero-width `.padding(.trailing, 0)` and an empty overlay,
    /// neither of which changes layout.
    var commitChip: HomeOneButtonCommitChip?
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) { buttonFace }
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd,
                                        lipHeight: HomeV2Metrics.lip,
                                        face: faceColor))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = "\(state.line1). \(state.line2)"
        switch commitChip {
        case nil:          return base
        case .commit:      return base + ". You haven't committed yet."
        case .committed:   return base + ". You're in."
        case .out:         return base + ". You're out."
        }
    }

    private var buttonFace: some View {
        VStack(spacing: 3) {
            Text(state.line1)
                .font(GSFont.heading(20, relativeTo: .title3))
                .tracking(0.6)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(state.line2)
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.2)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(secondaryInk)
        }
        .padding(.horizontal, 14)
        // Reserves the chip's lane so the centred copy never runs under it.
        // Zero — a layout no-op — whenever there is no chip.
        .padding(.trailing, commitChip == nil ? 0 : 96)
        .frame(maxWidth: .infinity)
        .frame(height: HomeV2Metrics.oneButtonFace)
        .foregroundStyle(primaryInk)
        .background(goldGradient)
        .overlay(alignment: .trailing) { commitChipView }
        .contentShape(Rectangle())
    }

    /// The chip itself — `HomeView.commitControl`'s three faces, character
    /// for character, sized to a trailing lane instead of the countdown
    /// card's full width.
    @ViewBuilder
    private var commitChipView: some View {
        switch commitChip {
        case .none:
            EmptyView()
        case .commit:
            Text("COMMIT ›")
                .font(GSFont.bold(11, relativeTo: .caption))
                .kerning(0.8)
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .gs3DCard(cornerRadius: 10, lipHeight: 4, face: theme.accent)
                .padding(.trailing, 12)
        case .committed:
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("YOU'RE IN")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .kerning(1.1)
            }
            .foregroundStyle(Color.gsHex(0x2FA45C))
            .padding(.trailing, 14)
        case .out:
            Text("YOU'RE OUT")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .kerning(1.1)
                .foregroundStyle(HomeV2Gold.top)
                .padding(.trailing, 14)
        }
    }

    /// `nil` = the theme's tuned neutral raised pair (`GS3DCardChrome`'s
    /// default); an explicit face derives its own darker lip.
    private var faceColor: Color? {
        switch state.face {
        case .accent: return theme.accent
        case .raised: return nil
        case .gold:   return HomeV2Gold.bottom
        }
    }

    private var primaryInk: Color {
        switch state.face {
        case .accent: return theme.bg
        case .raised: return theme.text
        case .gold:   return HomeV2Gold.ink
        }
    }

    private var secondaryInk: Color {
        switch state.face {
        // The raised face washes out neutral500 — production's own note on
        // `ctaCard`'s subtitle (HomeView.swift:388-391).
        case .accent: return theme.bg.opacity(0.72)
        case .raised: return theme.neutral700
        case .gold:   return HomeV2Gold.ink.opacity(0.75)
        }
    }

    /// The gold state's visible face: the gradient sits over the style's solid
    /// `goldBottom` plate, whose remaining jobs are the derived dark-amber lip
    /// and the sink. Every other state leaves the plate showing.
    @ViewBuilder
    private var goldGradient: some View {
        if case .gold = state.face {
            LinearGradient(colors: [HomeV2Gold.top, HomeV2Gold.bottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color.clear
        }
    }
}
