import SwiftUI

/// Redesign Phase 1 (four-tab reorientation, 2026-08): the Shop tab's
/// structural shell. The rotating weekly rack ("THIS WEEK'S RACK") is a
/// teaser card this round; the ONE live destination is the CAMPAIGNS row —
/// campaigns must not become unreachable now that the Library tab (whose
/// Campaigns sub-tab hosted them) left the tab bar. Pushes the SAME
/// `CampaignsTabView` Library presented, unchanged.
///
/// Chrome follows the tab-root idiom every other tab root uses (in-content
/// title + hidden system bar, 88pt dock clearance) and the Onyx card recipe
/// (`theme.surface`, radius 16, 1pt `theme.neutral500.opacity(0.35)`
/// stroke, tracked 10pt k-labels in `theme.neutral700`).
struct ShopTabView: View {
    @Environment(\.gsTheme) private var theme

    @State private var showCampaigns = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // In-content title (tab-root idiom).
                        Text("Pro Shop")
                            .font(GSFont.heading(24, relativeTo: .title))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                        Text("THIS WEEK'S RACK · SOON")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(1.1)
                            .foregroundStyle(theme.neutral700)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 10)

                        rackTeaserCard
                            .padding(.horizontal, 16)

                        campaignsRow
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        Spacer(minLength: 24)
                    }
                    // Top-pinned: a bare .frame(minHeight:) centers short
                    // content vertically (the Social center-snap bug class).
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                // Dock clearance (user bug report).
                .contentMargins(.bottom, 88, for: .scrollContent)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .toolbar(.hidden, for: .navigationBar)   // in-content title above
            .navigationDestination(isPresented: $showCampaigns) {
                // The exact view Library's Campaigns sub-tab hosted —
                // internals untouched; only the presentation frame (pushed
                // destination with a system bar) is new.
                CampaignsTabView()
                    .background(theme.bg)
                    .navigationTitle("Campaigns")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var rackTeaserCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The rotating rack is coming")
                .font(GSFont.bodyMedium(15, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
            Text("A small shelf of sounds and cosmetics that changes every week. First drop soon.")
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
    }

    private var campaignsRow: some View {
        Button {
            showCampaigns = true
        } label: {
            HStack(spacing: 8) {
                Text("CAMPAIGNS")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .tracking(1.1)
                    .foregroundStyle(theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .frame(minHeight: 44)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                    .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Campaigns' discovery highlight rides along from Library's old
        // Campaigns segment (same target, same storage key — anyone who
        // already pressed it there stays pressed here).
        .gsDiscovery(.libraryCampaigns, cornerRadius: GSMetrics.radiusSm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Campaigns")
    }
}
