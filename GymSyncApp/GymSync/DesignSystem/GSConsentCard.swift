import SwiftUI

// MARK: - GSConsentCard
//
// Plan task S2, spec §4: "It becomes a proposal card — 'Coach proposes a new
// ladder: …' — on Home and the ladder page, applied on accept", and "the
// consent-card pattern is the one Coach chat already uses for swaps and
// rules."

/// The copy every consent card in the app answers with.
///
/// Hoisted out of the view bodies so a later edit to one surface cannot
/// silently diverge from another: the warm-up screen's Coach suggestion (plan
/// task S4) uses the same two words, and `GSConsentCardCopyTests` asserts them
/// as strings.
enum GSConsentCopy {
    /// The ladder proposal's kicker (spec §4's own sentence, in caps).
    static let ladderKicker = "COACH PROPOSES A NEW LADDER"
    /// What "yes" says. A button says exactly what happens (rule 9).
    static let accept = "Accept"
    /// What "no" says — not "Dismiss": the proposal is a fact about the
    /// ladder, so declining it is about TODAY and not about the notice.
    static let decline = "Not today"
}

/// A consent card: Coach proposes, the athlete decides, nothing happens until
/// they do. The composition of ConsultCloseView.ruleCard and
/// CoachHomeView.threadRuleCard, lifted so the ladder proposal (plan task S2)
/// is the same object rather than a third drawing of it.
///
/// ACCENT: none. Rule 2 spends accent on the screen's one primary action, and
/// a proposal is not the primary act of Home or of the ladder page. Accept and
/// Not today are both raised faces (`.gs3DCardStyle`, radiusSm, lip 4) — the
/// same pair the warm-up screen's suggestion uses, so a suggestion answers the
/// same way everywhere in the app.
///
/// **THAT IS A DELIBERATE DEPARTURE FROM THE TWO CARDS IT LIFTS.** Both of
/// them put the accent on their accept, and both can: they are the only thing
/// on their own surface. This one lands beneath Home's goal strip and beneath
/// the ladder page's coach line, each of which already has a primary, and a
/// page never has two accent buttons.
struct GSConsentCard: View {
    /// Caps, 10 pt, tracking 1.2, muted (rule 3).
    let kicker: String
    /// One sentence, sentence case (rule 9).
    let sentence: String
    /// The consequence line. Absent entirely when nil — a blank line is not a
    /// state.
    var detail: String?
    let acceptTitle: String
    let declineTitle: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.gsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kicker)
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral500)
            Text(sentence)
                .font(GSFont.bodyMedium(13.5, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                pill(acceptTitle, action: onAccept)
                pill(declineTitle, action: onDecline)
                // The pills hug their labels rather than splitting the width:
                // two half-width faces read as a fork in the road, and this is
                // a suggestion with an obvious default.
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    /// Both pills are the same face. Which one is "yes" is carried by the
    /// word, not by the colour — an accent Accept beside a neutral Not today
    /// would be the page's second invitation (rule 2).
    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(GSFont.bold(12.5, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
    }
}
