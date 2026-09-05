import SwiftUI

/// The join-with-code card, at the foot of both arrangements.
///
/// A re-creation of production's `HomeView.joinWithCodeSection` (:1255) —
/// section header, static extruded card, six-character field, `Join` button
/// disabled until the code is complete. Production's version is `private` and
/// its `Join` calls `SessionRepository.joinByCode`; this one keeps the
/// geometry, copy and states and does nothing on tap (the catalog makes no
/// network call). The card itself stays STATIC (`.gs3DCard`): the Join button
/// is the tappable, not the card.
struct HomeV2JoinCodeCard: View {
    @Environment(\.gsTheme) private var theme

    /// Seeded empty, matching the state every capture should show.
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Join with Code")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            Group {
                HStack(spacing: 8) {
                    TextField("6-character code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .font(GSFont.bodyMedium(16, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    Button("Join") {}
                        .buttonStyle(GSPrimaryButtonStyle())
                        .frame(width: 72)
                        .disabled(code.count != 6)
                        .opacity(code.count != 6 ? 0.4 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .gs3DCard(cornerRadius: GSMetrics.radiusMd)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}
