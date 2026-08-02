import SwiftUI

/// Redesign Phase 2 (2026-08): the Shop tab, now with the functional
/// THIS WEEK'S RACK — a deterministic weekly rotation of four soundboard
/// sounds (selection math in `WeeklyRack`; same week + same catalog =>
/// same four on every device). Slot 1 is the loaner: free to add to the
/// favorites dock ("RACK IT") while the dock has room — the dock holds 4
/// (`SoundLibrarySheet.toggleFavorite`'s cap; the repository itself is
/// uncapped, callers enforce it). Tapping any tile previews the sound via
/// `SoundboardPlayer` — the exact playback path the live session's dock
/// uses (soundboard bucket URL resolution + tmp cache + player pool).
///
/// Below the rack, the permanent shelves: CAMPAIGNS (the ONE live
/// destination — pushes the SAME `CampaignsTabView` Library presented,
/// unchanged, discovery marker intact) plus two inert SOON rows. NO
/// prices, balances, or purchase affordances anywhere — the economy
/// doesn't exist yet and the UI must not pretend it does.
///
/// Chrome follows the tab-root idiom every other tab root uses (in-content
/// title + hidden system bar, 88pt dock clearance) and the Onyx card recipe
/// (`theme.surface`, radius 16, 1pt `theme.neutral500.opacity(0.35)`
/// stroke, tracked 10pt k-labels in `theme.neutral700`).
struct ShopTabView: View {
    @Environment(\.gsTheme) private var theme

    @State private var showCampaigns = false

    /// Catalog fetch lifecycle for the rack.
    private enum RackLoad {
        case loading
        case loaded([SoundboardSound])
        case failed
    }
    @State private var rackLoad: RackLoad = .loading

    /// Local optimistic copy of the favorites dock (ordered slugs, max 4) —
    /// seeded once in `loadRack()`, mutated by `rackIt(_:)` which persists
    /// best-effort via `SoundboardFavoritesRepository.set(_:)` (the same
    /// fire-and-forget shape the live session's dock editing uses).
    @State private var favorites: [String] = []

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

                        rackHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 10)

                        rackContent
                            .padding(.horizontal, 16)

                        campaignsRow
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        inertShelfRow("GYMSYNC PRO")
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        inertShelfRow("FIND A COACH")
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

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
        .task {
            // Tabs stay mounted across switches in this app, so this fires
            // once per launch — the guard only matters for view-identity
            // resets (e.g. sign-out/in).
            if case .loaded = rackLoad { return }
            await loadRack()
        }
    }

    // MARK: - Rack header (k-label + rotation countdown)

    private var rackHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("THIS WEEK'S RACK")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            Spacer()
            // Minute cadence: the countdown never shows units under a
            // minute, so re-resolving faster would be wasted work.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text("↻ ROTATES IN \(Self.countdownText(from: context.date))")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
            }
        }
    }

    /// "3D 14H" while a day or more remains, "14H 32M" under 24 hours.
    private static func countdownText(from now: Date) -> String {
        let remaining = max(0, WeeklyRack.nextRotation(after: now).timeIntervalSince(now))
        let totalMinutes = Int(remaining) / 60
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        return days > 0 ? "\(days)D \(hours)H" : "\(hours)H \(minutes)M"
    }

    // MARK: - Rack content (loading / failed / empty / loaded)

    @ViewBuilder
    private var rackContent: some View {
        switch rackLoad {
        case .loading:
            rackGrid {
                ForEach(0..<4, id: \.self) { _ in placeholderTile }
            }
        case .failed:
            retryRow
        case .loaded(let catalog):
            if let selection = WeeklyRack.select(from: catalog) {
                rackGrid {
                    rackTile(selection.loaner, isLoaner: true)
                    ForEach(selection.others) { sound in
                        rackTile(sound, isLoaner: false)
                    }
                }
            } else {
                emptyCard
            }
        }
    }

    private func rackGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) { content() }
    }

    // MARK: - Rack tiles

    private func rackTile(_ sound: SoundboardSound, isLoaner: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The plate token already renders the waveform envelope,
            // duration, and clip scissors — no duplicate waveform strip.
            GSPlateToken(
                name: sound.plateName,
                envelope: sound.envelope,
                durationMs: sound.durationMs,
                isClipped: sound.isClipped,
                cooldownUntil: nil,
                size: 44
            )
            Text(sound.label)
                .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Text(durationFooter(sound))
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            if isLoaner {
                Text("FREE THIS WEEK · LOANER")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(theme.accent.opacity(0.12))
                    .clipShape(Capsule())
                loanerRackControl(for: sound.slug)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(
                    isLoaner ? theme.accent : theme.neutral500.opacity(0.35),
                    lineWidth: isLoaner ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        // Tap = preview. Same container-tap + inner-button shape the sound
        // library's rows use; the inner RACK IT Button wins its own taps.
        .onTapGesture {
            Task { await SoundboardPlayer.shared.play(slug: sound.slug) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sound.label), tap to preview")
    }

    /// Footer k-label: "3.2S", with the clip scissors when the 5-second
    /// cap ran ("✂ 3.2S"). Mirrors `GSPlateToken.durationText`'s rounding.
    private func durationFooter(_ sound: SoundboardSound) -> String {
        guard let ms = sound.durationMs else { return "—" }
        let s = (Double(ms) / 100).rounded() / 10
        let str = s == s.rounded() ? "\(Int(s))S" : "\(s)S"
        return sound.isClipped ? "✂ \(str)" : str
    }

    /// The loaner's add-to-dock affordance. Three states: already racked,
    /// dock full (4-cap — mirrors `SoundLibrarySheet`'s client-side cap,
    /// but deliberately does NOT drop-oldest here; managing a full dock
    /// belongs to My Rack), or room to rack.
    @ViewBuilder
    private func loanerRackControl(for slug: String) -> some View {
        if favorites.contains(slug) {
            Text("IN YOUR RACK")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
                .padding(.vertical, 6)
        } else if favorites.count >= 4 {
            Text("DOCK FULL — MANAGE IN MY RACK")
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
                .padding(.vertical, 6)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button {
                rackIt(slug)
            } label: {
                Text("RACK IT")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .tracking(1.1)
                    .foregroundStyle(theme.accent)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rack it, add to your dock")
        }
    }

    // MARK: - Loading / failure / empty states

    private var placeholderTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle()
                .fill(theme.neutral500.opacity(0.18))
                .frame(width: 44, height: 44)
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.neutral500.opacity(0.18))
                .frame(width: 92, height: 12)
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.neutral500.opacity(0.12))
                .frame(width: 44, height: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
        )
    }

    private var retryRow: some View {
        HStack(spacing: 8) {
            Text("RACK DIDN'T LOAD")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            Spacer()
            Button {
                Task { await loadRack() }
            } label: {
                Text("RETRY")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
        )
    }

    private var emptyCard: some View {
        Text("NOTHING ON THE RACK YET")
            .font(GSFont.bold(10, relativeTo: .caption2))
            .tracking(1.1)
            .foregroundStyle(theme.neutral700)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                    .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
            )
    }

    // MARK: - Data

    private func loadRack() async {
        rackLoad = .loading
        do {
            let catalog = try await SoundboardRepository.fetchCatalog()
            // Favorites are a soft dependency: unauthenticated or failed
            // reads degrade to an empty dock (the same `(try?) ?? []`
            // posture YouTabView takes) — the rack still renders.
            favorites = (try? await SoundboardFavoritesRepository.get()) ?? []
            rackLoad = .loaded(catalog)
        } catch {
            rackLoad = .failed
        }
    }

    private func rackIt(_ slug: String) {
        guard !favorites.contains(slug), favorites.count < 4 else { return }
        favorites.append(slug)
        let updated = favorites
        Task { try? await SoundboardFavoritesRepository.set(updated) }
    }

    // MARK: - Shelves

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

    /// The not-yet shelves — inert by design (no action, 0.6 opacity, SOON
    /// chip). They exist so the shelf structure reads as a place that will
    /// grow, without pretending anything is tappable or purchasable.
    private func inertShelfRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(GSFont.bold(11, relativeTo: .caption))
                .tracking(1.1)
                .foregroundStyle(theme.text)
            Spacer()
            Text("SOON")
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.neutral500.opacity(0.18))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
        )
        .opacity(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), coming soon")
    }
}
