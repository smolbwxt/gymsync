import SwiftUI

// MARK: - CalendarAgendaItem
//
// One thing on this week's timeline. Every field is already RESOLVED — the
// page does the reading (which routine, which crew, whether you have
// committed), the row does the drawing. That split is what lets the catalog
// hand the same row four fixture items and get the v7 proof's frame back
// without a repository in sight.

struct CalendarAgendaItem: Identifiable {
    enum Status {
        /// You have committed. Green means present (design language rule 2).
        case checkedIn
        /// You have not said yet — committing happens on the crew board.
        case commit
    }

    let id: UUID
    /// `5`
    let dayNumber: Int
    /// `FRI`
    let weekday: String
    /// `Push A · 5:00 PM`
    let title: String
    /// Shows the `↻` glyph — this occurrence belongs to a series.
    let repeats: Bool
    /// `Push Crew · Powerhouse · you're in`, or `Solo · from your block`.
    let subtitle: String
    let status: Status?
    /// The live session behind the row. `nil` in the catalog, which renders
    /// the row exactly the same and simply has nowhere to go — a fixture
    /// frame must not be able to open a lobby or delete anything.
    let session: WorkoutSession?
}

// MARK: - CalendarAgendaRowView
//
// The row itself: day number over weekday on the left, the session in the
// middle with its series glyph, the status pill, the chevron. FLAT (design
// language rule 1) — the card it sits in is the raised object; furniture
// inside it does not extrude.

struct CalendarAgendaRowView: View {
    @Environment(\.gsTheme) private var theme

    let item: CalendarAgendaItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .center, spacing: 1) {
                Text("\(item.dayNumber)")
                    .font(GSFont.bold(19, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                Text(item.weekday)
                    .font(GSFont.bold(9.5, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral500)
            }
            .frame(width: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(GSFont.bold(14.5, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if item.repeats {
                        Image(systemName: "repeat")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }
                }
                Text(item.subtitle)
                    .font(GSFont.body(11.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            if let status = item.status {
                pill(status)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
        // 9, not 12, and 2 pt between the two lines rather than 3: the
        // proof's agenda rows run about 52 pt, and a four-row week has to
        // read as a list rather than as four stacked cards.
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The same two chips `HomeCalendarCard.chip` draws, at the same values —
    /// the door and the room must not disagree about whether you are in.
    @ViewBuilder
    private func pill(_ status: CalendarAgendaItem.Status) -> some View {
        switch status {
        case .checkedIn:
            Text("IN")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .kerning(1.1)
                .foregroundStyle(Color.gsHex(0x2FA45C))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.gsHex(0x2FA45C).opacity(0.16)))
        case .commit:
            Text("COMMIT")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .kerning(1.1)
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(theme.accent.opacity(0.16)))
        }
    }
}

// MARK: - CalendarSwipeRow
//
// `MOVE` / `CANCEL` behind a row, revealed by dragging it left.
//
// Written rather than reached for: `.swipeActions` exists only inside a
// `List`, and this agenda is a `VStack` of flat rows inside one raised card
// (design language rule 1) sitting in the page's own `ScrollView`. Nesting a
// `List` there to buy one modifier would cost the card, its rounding, and a
// height this page cannot compute. The behaviour is the platform's: drag to
// reveal, tap an action, and a destructive action fires on that tap without
// a second confirmation — the same posture `FriendsView`'s own destructive
// `.swipeActions` Remove already takes (:256-263).
//
// At rest the offset is zero, so a catalog capture is deterministic.

struct CalendarSwipeRow<Content: View>: View {
    @Environment(\.gsTheme) private var theme

    /// Both `nil` for a row with nothing behind it (the catalog's rows, and
    /// any row the page cannot edit) — the drag is then not installed at all
    /// rather than opening onto two dead buttons.
    var onMove: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    /// Where the row rests between drags — 0 closed, `-actionsWidth` open.
    @State private var restingOffset: CGFloat = 0

    private var actionWidth: CGFloat { 84 }
    private var actionsWidth: CGFloat { actionWidth * 2 }
    private var editable: Bool { onMove != nil || onCancel != nil }

    var body: some View {
        row
            // A BACKGROUND, not a `ZStack` sibling. A background is proposed
            // the primary view's own size, so the actions come out exactly
            // the row's height; as a ZStack sibling they are proposed the
            // page's unspecified height instead and `maxHeight: .infinity`
            // collapses to the label's ideal height — two short buttons
            // floating in the middle of the row. It also fixes them in
            // place, which is the point: the row slides, the actions do not.
            .background(alignment: .trailing) {
                if editable {
                    HStack(spacing: 0) {
                        action("MOVE", tint: theme.neutral300) { onMove?() }
                        action("CANCEL", tint: theme.neutral400) { onCancel?() }
                    }
                    .frame(width: actionsWidth)
                }
            }
            .clipped()
    }

    /// Branching on `editable` rather than passing an optional gesture:
    /// `gesture(_:)` takes a `Gesture`, not an `Optional`, and
    /// `gesture(_:isEnabled:)` is iOS 18 (this app ships to 17).
    @ViewBuilder
    private var row: some View {
        if editable {
            // SIMULTANEOUS: a plain `.gesture` on a row inside a vertical
            // `ScrollView` can swallow the drag that should have scrolled
            // the page. `drag` ignores a mostly-vertical translation, so
            // sharing costs nothing and the page keeps scrolling under a
            // finger that happens to start on a row.
            face.simultaneousGesture(drag)
        } else {
            face
        }
    }

    /// The row itself — opaque, in the card's own face colour, because the
    /// actions live UNDER it and a translucent row would show them through
    /// at rest.
    private var face: some View {
        content()
            .background(theme.raised3DFace)
            .offset(x: offset)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Vertical intent belongs to the page's scroll view.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(0, max(-actionsWidth, restingOffset + value.translation.width))
            }
            .onEnded { value in
                let landed = restingOffset + value.translation.width
                let target: CGFloat = landed < -actionsWidth / 2 ? -actionsWidth : 0
                restingOffset = target
                withAnimation(.easeOut(duration: 0.18)) { offset = target }
            }
    }

    /// Raised-face neutrals, not accent and not red.
    ///
    /// Design language §2: "Red is for errors only", and accent is spent on
    /// "the one primary action per screen" — which on this page is
    /// `SCHEDULE A SESSION`. §4 states the rest plainly: "One button in
    /// accent (or gold), everything else the raised face." A revealed swipe
    /// action is not exempt from that just because it is usually off screen.
    /// `FriendsView`'s destructive red is a weaker precedent than it looks,
    /// because the platform draws it and this does not.
    ///
    /// CANCEL is told apart by its word and by sitting at the far edge —
    /// where a destructive swipe action always sits — rather than by a
    /// colour the language reserves for errors. It is a step lighter than
    /// MOVE so the pair reads as two things, not one wide button.
    private func action(_ label: String, tint: Color, run: @escaping () -> Void) -> some View {
        Button {
            close()
            run()
        } label: {
            Text(label)
                .font(GSFont.bold(11, relativeTo: .caption2))
                .kerning(1.1)
                .foregroundStyle(theme.text)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.capitalized)
    }

    private func close() {
        restingOffset = 0
        withAnimation(.easeOut(duration: 0.18)) { offset = 0 }
    }
}
