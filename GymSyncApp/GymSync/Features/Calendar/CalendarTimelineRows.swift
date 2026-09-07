import SwiftUI

// MARK: - The other things on the timeline
//
// Design §C: "Timeline items beyond sessions: the block's days and campaign
// deadlines." They are the reason this page is the home of design rule 4 —
// anything on a timeline is editable from here — because they are the two
// dated commitments that have never had a place on Home to be changed from.
//
// Both rows carry their destination as an OPTIONAL model object. Production
// fills it and the row becomes a `NavigationLink`; the catalog leaves it nil
// and the row renders identically with nowhere to go, which is what keeps
// `calendar-scheduling` hermetic. No new data model — every value below is
// read from `ProgramRepository.active()` / `CampaignRepository`, the same two
// calls `HomeView` already makes.

/// `Coach block · week 2 of 6 · Tue, Thu, Sat` with a `CHANGE DAYS ›` pill.
/// Absent entirely when there is no active enrollment.
struct CalendarBlockRow {
    let text: String
    /// `nil` in the catalog — the row then has no `BlockCalendarView` to open.
    let enrollment: ProgramEnrollment?
    let weeks: [ProgramWeek]
}

/// `Fall Volume campaign · ends Sep 30 · you're at 61%`. One row per JOINED
/// active campaign — unjoined discovery stays on Home's carousel, which is
/// the only discovery surface (screen inventory §1d).
struct CalendarCampaignRow: Identifiable {
    let id: UUID
    let text: String
    /// `nil` in the catalog.
    let campaign: Campaign?
}

// MARK: - CalendarBlockRowView

struct CalendarBlockRowView: View {
    @Environment(\.gsTheme) private var theme

    let row: CalendarBlockRow

    var body: some View {
        if let enrollment = row.enrollment {
            NavigationLink {
                BlockCalendarView(enrollment: enrollment, weeks: row.weeks)
            } label: {
                face
            }
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        } else {
            face.gs3DCard(cornerRadius: GSMetrics.radiusMd)
        }
    }

    private var face: some View {
        HStack(spacing: 12) {
            Text(row.text)
                .font(GSFont.bodyMedium(13.5, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // The block's days are edited in `BlockCalendarView`, so the pill
            // names that act rather than repeating the row's own chevron.
            Text("CHANGE DAYS ›")
                .font(GSFont.bold(10.5, relativeTo: .caption2))
                .kerning(1.1)
                .foregroundStyle(theme.neutral800)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(theme.neutral300))
                .layoutPriority(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - CalendarCampaignRowView

struct CalendarCampaignRowView: View {
    @Environment(\.gsTheme) private var theme

    let row: CalendarCampaignRow

    var body: some View {
        if let campaign = row.campaign {
            NavigationLink {
                CampaignDetailView(campaign: campaign)
            } label: {
                face
            }
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        } else {
            face.gs3DCard(cornerRadius: GSMetrics.radiusMd)
        }
    }

    private var face: some View {
        HStack(spacing: 12) {
            Text(row.text)
                .font(GSFont.bodyMedium(13.5, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
