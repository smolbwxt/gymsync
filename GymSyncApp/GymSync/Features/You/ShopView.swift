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
    // Gym seat key redemption (trainer enrollment rails, 20260816000001).
    @State private var showRedeemSheet = false
    @State private var redeemCode = ""
    @State private var redeeming = false
    @State private var redeemErrorText: String?
    @State private var redeemedTick = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                proCard
                rackCard
                coachingSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await loadRack() }
        .sheet(isPresented: $showRedeemSheet) { redeemSheet }
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

    // MARK: - COACHING (three doors — enrollment design 2026-08-16; the
    // training opt-in also stays in Settings)

    @ViewBuilder
    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COACHING")
                .font(GSFont.bold(20, relativeTo: .title3))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            Text("Train with a personal trainer, or take on clients of your own — free to start.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
        }
        .padding(.top, 4)

        coachingDoor(icon: "person.badge.key",
                     title: "Train with a personal trainer",
                     subtitle: "Redeem your trainer's invite code") {
            AnyView(CoachingView()
                .background(theme.bg)
                .navigationTitle("Coaching")
                .navigationBarTitleDisplayMode(.inline))
        }

        coachingDoor(icon: "figure.strengthtraining.traditional",
                     title: "Become a trainer",
                     subtitle: "Mint invites, take on clients — capacity plans come with billing") {
            AnyView(CoachingView()
                .background(theme.bg)
                .navigationTitle("Coaching")
                .navigationBarTitleDisplayMode(.inline))
        }

        Button {
            redeemCode = ""
            redeemErrorText = nil
            redeemedTick = false
            showRedeemSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redeem a gym key")
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text("Your gym sponsors your coaching seat")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Redeem a gym key")
    }

    private func coachingDoor(icon: String, title: String, subtitle: String,
                              destination: @escaping () -> AnyView) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text(subtitle)
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    /// Code entry → the SECURITY DEFINER redeem RPC. Its P0001 messages
    /// are user-facing copy and surface verbatim.
    private var redeemSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your gym hands out seat keys to the trainers it employs. Redeeming one sponsors your coaching — your clients and prescriptions are always yours either way.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Key code", text: $redeemCode)
                    .font(GSFont.heading(18, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(12)
                    .background(theme.surface)
                    .cornerRadius(GSMetrics.radiusSm)

                if let redeemErrorText {
                    Text(redeemErrorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                }
                if redeemedTick {
                    Text("Key redeemed — your gym sponsors your coaching seat.")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.accent700)
                }

                Button {
                    Task { await redeem() }
                } label: {
                    Text(redeeming ? "Redeeming…" : "Redeem")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSPrimaryButtonStyle())
                .disabled(redeeming || redeemCode.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding(16)
            .background(theme.bg)
            .navigationTitle("Redeem a gym key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { showRedeemSheet = false }
                        .tint(theme.accent)
                }
            }
        }
    }

    @MainActor
    private func redeem() async {
        redeeming = true
        defer { redeeming = false }
        do {
            try await TrainerEntitlementRepository.redeemGymKey(
                code: redeemCode.trimmingCharacters(in: .whitespaces))
            redeemErrorText = nil
            redeemedTick = true
        } catch {
            redeemedTick = false
            redeemErrorText = ErrorMapping.map(error).errorDescription
        }
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
