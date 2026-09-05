import SwiftUI

/// Coach as a STRIP — arrangement B's form of the same idea.
///
/// Not everything is a card (design language rule 1): a line that belongs to
/// the card above it is a strip — `surface` fill, 14 pt radius, no extrusion.
/// One line, tappable, opening a seeded thread (rule 7), with Coach's voice in
/// the first person.
///
/// `CO` glyph tile rather than an icon: no decorative emoji (rule 2), and the
/// two-letter tile matches the group-avatar idiom the calendar rows use.
struct HomeCoachLine: View {
    @Environment(\.gsTheme) private var theme

    let sentence: String
    /// Tap → the Coach thread, seeded with this line.
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.neutral300)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text("CO")
                            .font(GSFont.bold(11, relativeTo: .caption2))
                            .tracking(0.6)
                            .foregroundStyle(theme.neutral700)
                    )

                (
                    Text("Coach: ")
                        .font(GSFont.bold(13.5, relativeTo: .subheadline))
                        .foregroundColor(theme.text)
                    + Text(sentence)
                        .font(GSFont.body(13.5, relativeTo: .subheadline))
                        .foregroundColor(theme.neutral700)
                )
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: HomeV2Metrics.stripRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach. \(sentence). Opens the thread.")
    }
}
