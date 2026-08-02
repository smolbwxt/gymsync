import SwiftUI

/// Phase-1 stub for the personal soundboard rack, reached from the You
/// tab's MY RACK widget. The full builder — browsing the catalog and
/// choosing the four favorite plates — lands next round; this screen just
/// stakes out the destination in Onyx dress.
struct MyRackView: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your sounds live here — next round")
                        .font(GSFont.bodyMedium(15, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Text("Pick the four plates you carry into every session. The rack builder is on its way.")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                        .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer(minLength: 24)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("My Rack")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 88, for: .scrollContent)
    }
}
