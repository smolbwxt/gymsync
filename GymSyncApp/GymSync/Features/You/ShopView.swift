import SwiftUI

// MARK: - ShopView (owner 2026-08-16: "The shop should be at the top.
// The shop houses Pro, the soundboard purchase page, and any other
// sellable that we come up with later. The opt in to training should be
// linked there too.")
//
// The storefront T2 behind the You tab's SHOP widget: PRO (paywall),
// THE RACK (soundboard — the plate face + weekly rotation moved here
// with it), and COACHING (the training opt-in, linked here AND kept in
// Settings). Future sellables slot in as more cards.
struct ShopView: View {
    @Environment(\.gsTheme) private var theme

    @State private var rackSounds: [SoundboardSound] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                proCard
                rackCard
                coachingCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await loadRack() }
    }

    // MARK: - PRO

    private var proCard: some View {
        NavigationLink {
            PaywallView()
        } label: {
            card(title: "PRO", titleColor: Color.gsHex(0xE8C33A), footer: "GYMSYNC PRO") {
                Text("Coach programs, unlimited routines, the full ledger — see what's coming.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GymSync Pro")
    }

    // MARK: - THE RACK (moved from the You grid with its whole face)

    private var rackCard: some View {
        NavigationLink {
            MyRackView()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("THE RACK")
                        .font(GSFont.bold(20, relativeTo: .title3))
                        .tracking(0.5)
                        .foregroundStyle(theme.text)
                    Spacer(minLength: 8)
                    Text(rotationText)
                        .font(GSFont.bold(9.5, relativeTo: .caption2))
                        .kerning(1.0)
                        .foregroundStyle(Color.gsHex(0xE8C33A))
                        .monospacedDigit()
                }
                Spacer(minLength: 10)
                rackFace
                Spacer(minLength: 10)
                Text("SOUNDBOARD · THIS WEEK'S RACK + YOUR DOCK")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Rack")
    }

    private var rotationText: String {
        let interval = max(0, WeeklyRack.nextRotation().timeIntervalSinceNow)
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        return "↻ ROTATES IN \(days)D \(hours)H"
    }

    @ViewBuilder
    private var rackFace: some View {
        ViewThatFits(in: .horizontal) {
            plateRow(size: 38)
            plateRow(size: 34)
            plateRow(size: 30)
        }
    }

    @ViewBuilder
    private func plateRow(size: CGFloat) -> some View {
        HStack(spacing: 4) {
            if rackSounds.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .strokeBorder(theme.neutral300, lineWidth: 2)
                        .frame(width: size, height: size)
                }
            } else {
                ForEach(rackSounds.prefix(4)) { sound in
                    GSPlateToken(
                        name: sound.plateName,
                        envelope: sound.envelope,
                        durationMs: sound.durationMs,
                        isClipped: sound.isClipped,
                        cooldownUntil: nil,
                        size: size,
                        compact: true
                    )
                }
            }
        }
    }

    // MARK: - COACHING (the training opt-in; also stays in Settings)

    private var coachingCard: some View {
        NavigationLink {
            CoachingView()
                .background(theme.bg)
                .navigationTitle("Coaching")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            card(title: "COACHING", footer: "TRAIN WITH A COACH · COACH CLIENTS") {
                Text("Redeem a trainer's invite, or mint codes and take on clients of your own.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coaching")
    }

    // MARK: - Card chrome (the You widget language)

    private func card<Face: View>(
        title: String,
        titleColor: Color? = nil,
        footer: String,
        @ViewBuilder face: () -> Face
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(GSFont.bold(20, relativeTo: .title3))
                .tracking(0.5)
                .foregroundStyle(titleColor ?? theme.text)
            Spacer(minLength: 8)
            face()
            Spacer(minLength: 10)
            Text(footer)
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral500)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Data

    @MainActor
    private func loadRack() async {
        guard let catalog = try? await SoundboardRepository.fetchCatalog(),
              !catalog.isEmpty else { return }
        let bySlug = Dictionary(catalog.map { ($0.slug, $0) },
                                uniquingKeysWith: { first, _ in first })
        let favoriteSlugs = (try? await SoundboardFavoritesRepository.get()) ?? []
        let favored = favoriteSlugs.compactMap { bySlug[$0] }
        let chosen = favored.isEmpty ? catalog.filter(\.isCurated) : favored
        rackSounds = Array(chosen.prefix(4))
    }
}
