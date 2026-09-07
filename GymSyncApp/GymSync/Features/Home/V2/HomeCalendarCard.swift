import SwiftUI

/// The training calendar, folded: the month dot fields with the next few
/// appointments underneath, in one card.
///
/// Design language rule 4: anything that lives on a timeline is visible on
/// Home, or one tap from the page where it is editable. So the WHOLE card is
/// one tap target onto the calendar & scheduling page — the `+` circle and the
/// per-row status chips are affordances riding that one navigation, not nested
/// buttons (the same call production's `commitControl` already makes,
/// HomeView.swift:856-862, and for the same reason: a `Button` inside a
/// `Button`'s label is a gesture-conflict hazard).
///
/// The dot field is `TrainingMonthField` (task D1), the ONE field production
/// and this card now share. This card used to carry its own copy of it,
/// rebuilt on the same constants because `TrainingCalendarWidget`'s field was
/// `private` and that build could not edit it; D1 removed that constraint and
/// deleted the copy. Nothing about what this card RENDERS changed: the shared
/// field is the copy, moved — same constants, same model, and `fieldWidth`
/// still defaults to 326 here (the production widget's own seed value, and the
/// exact inner width of this card at the page's 16 pt margins on a standard
/// iPhone), so no geometry observation is needed and a catalog capture stays
/// hermetic.
struct HomeCalendarCard: View {
    @Environment(\.gsTheme) private var theme

    /// One month of the field. Positions are fixture values, not dates.
    ///
    /// The type moved to `TrainingMonthField` in task D1 (production needs it
    /// too now). The alias keeps `HomeCalendarCard.Month(...)` compiling at
    /// every fixture call site — the name the catalog worlds were written
    /// against — without a rename sweep through frames the owner has already
    /// judged.
    typealias Month = TrainingMonthField.Month

    /// One folded appointment row: `Today 5:00 PM · PC · Push A · Push Crew ·
    /// IN ›`, 44 pt tall.
    struct Appointment: Identifiable {
        enum Status {
            /// You have checked in. Green means present (rule 2).
            case checkedIn
            /// You haven't said yet — committing happens on the crew board.
            case commit
        }

        let id: Int
        /// `Today`, `Sat`, `Tue` …
        let day: String
        let time: String
        /// Two-letter tile: a crew's initials, or `You` for a solo lift.
        let initials: String
        /// The tile's identity colour — a `GSGroupColor` for a crew. `nil` is
        /// your own solo session, which wears the accent on the page ground
        /// (`TrainingCalendarWidget.avatarTile`'s rule), resolved at render
        /// because a fixture cannot know the user's accent.
        let tint: Color?
        let ink: Color?
        let title: String
        let subtitle: String
        /// Repeats — the series glyph the production row also shows.
        let repeats: Bool
        let status: Status?
    }

    let months: [Month]
    let appointments: [Appointment]
    /// Whether the folded appointment rows render under the dot field.
    ///
    /// `true` — Home v2's card, unchanged, itinerary and all: the default
    /// exists so the four v2 captures keep rendering exactly what the owner
    /// already judged. `false` — Home v3: the owner asked for the detail
    /// sessions to be stripped from the bottom of the calendar and written
    /// out on the page the card opens instead (plan,
    /// `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`,
    /// "Fixed decisions"). The header's `{n} UPCOMING` pill stays either way
    /// — the count is still true, it is only the itinerary that moves.
    var showsAppointments: Bool = true
    /// Tap → the calendar & scheduling page.
    var action: () -> Void = {}

    /// The rows render only when this card is showing its itinerary AND it
    /// has one. Named once here because the header's chevron is its mirror
    /// image: the door needs a handle exactly when the rows are gone.
    private var listVisible: Bool { showsAppointments && !appointments.isEmpty }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                header
                monthField.padding(.top, 14)
                if listVisible {
                    appointmentList.padding(.top, 16)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            GSSectionHeader("Training calendar")
            if !appointments.isEmpty {
                Text("\(appointments.count) UPCOMING")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.2)
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.neutral300))
            }
            // Schedule affordance — rides the card's own navigation.
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(theme.neutral300))

            // The door's handle. With the itinerary folded away, the rows'
            // own trailing chevrons go with it and nothing on the card says
            // it opens anything — so the header grows one (plan, "Fixed
            // decisions": tap anywhere → the calendar & scheduling page,
            // where the itinerary is written out). Gated on the same
            // parameter rather than added unconditionally, so a v2 capture
            // stays pixel-identical to the frames already judged.
            if !showsAppointments {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
        }
    }

    // MARK: Month dot field
    //
    // The shared field at its hermetic default width (326) — see the type's
    // doc comment for why this card does not measure.

    private var monthField: some View {
        TrainingMonthField(months: months)
    }

    // MARK: Folded appointments

    private var appointmentList: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.divider).frame(height: 1)
            ForEach(Array(appointments.prefix(3).enumerated()), id: \.element.id) { index, appointment in
                row(appointment)
                if index < min(appointments.count, 3) - 1 {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
    }

    private func row(_ appointment: Appointment) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 1) {
                Text(appointment.day)
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(appointment.time)
                    .font(GSFont.body(10.5, relativeTo: .caption2))
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(1)
                    // A clock time is short; "No time set" — the block's own
                    // lift on a solo day — is not. Shrink rather than clip
                    // inside the fixed column.
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 58, alignment: .leading)

            RoundedRectangle(cornerRadius: 9)
                .fill(appointment.tint ?? theme.accent)
                .frame(width: 30, height: 30)
                .overlay(
                    Text(appointment.initials)
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .foregroundStyle(appointment.ink ?? theme.bg)
                )

            HStack(spacing: 5) {
                Text(appointment.title)
                    .font(GSFont.bold(13.5, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if appointment.repeats {
                    Image(systemName: "repeat")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
                Text(appointment.subtitle)
                    .font(GSFont.body(11.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }

            Spacer(minLength: 6)

            if let status = appointment.status {
                chip(status)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func chip(_ status: Appointment.Status) -> some View {
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
