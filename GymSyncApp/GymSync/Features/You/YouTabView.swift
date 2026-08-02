import SwiftUI

/// Redesign Phase 1 (four-tab reorientation, 2026-08): the You tab is now a
/// widget grid — the hub that absorbed Library (Routines, the exercises
/// catalog) and Stats when the tab bar collapsed from five tabs to four
/// (Home · Social · Shop · You). Everything the old You tab held (account
/// details, preferences, Sign Out, the Build footer) moved wholesale into
/// `SettingsView`, pushed from the SETTINGS widget — nothing was dropped in
/// the move.
///
/// Widget card recipe (2026-08 3D pass): extruded `GS3DCard` chrome — the
/// theme's raised face on a 6pt darker lip (the RACK IT anatomy at card
/// scale) replacing the old flat `theme.surface` + 1pt neutral500 stroke.
/// Tappable widgets sink on press (`.gs3DCardStyle`); LOCKER sits still
/// (`.gs3DCard`). Content recipe unchanged: k-label title (11pt bold,
/// tracking 1.1, `theme.neutral700`, uppercase — bumped from 10 in the
/// 2026-08 bigger-widgets pass), a middle content line, and a quieter
/// footer k-label.
struct YouTabView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var showMyRack = false
    @State private var showStats = false
    @State private var showRoutines = false
    @State private var showDiscover = false
    @State private var showSettings = false

    /// MY RACK widget face — the user's soundboard favorites, falling back
    /// to the first four curated catalog sounds (the same fallback rule the
    /// live session's Rack Room applies when no favorites row exists). Pure
    /// catalog/favorites reads — deliberately NO live-session state here.
    /// Best-effort: a failed fetch leaves the placeholder circles.
    @State private var rackSounds: [SoundboardSound] = []

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                        LazyVGrid(columns: columns, spacing: 12) {
                            myRackWidget
                            statsWidget
                            routinesWidget
                            discoverWidget
                            lockerWidget
                            settingsWidget
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

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
            .toolbar(.hidden, for: .navigationBar)   // in-content title (tab-root idiom)
            .task { await loadRack() }
            .navigationDestination(isPresented: $showMyRack) {
                MyRackView()
            }
            .navigationDestination(isPresented: $showStats) {
                // Pushed in content form (embedsInOwnStack: false). The
                // build-445 field report ("If I click You, then Stats, I'm
                // stuck") was StatsTabView's own nested NavigationStack
                // swallowing this stack's bar — no back chevron, no
                // edge-swipe. Bare content keeps the system bar, and Stats'
                // internal pushes (Activity, per-exercise history) now ride
                // THIS stack — same presentation as the Campaigns push from
                // Shop and the Routines/Exercises destinations below.
                StatsTabView(embedsInOwnStack: false)
                    .background(theme.bg)
                    .navigationTitle("Stats")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(isPresented: $showRoutines) {
                // The routines list the Library tab used to host. The
                // first-visit tip (`.library` — "Your routines live here")
                // moves with it: its anchor lives inside RoutinesListView,
                // and the spotlight previously attached at LibraryTabView's
                // root now attaches to this destination.
                RoutinesListView()
                    .background(theme.bg)
                    .navigationTitle("Routines")
                    .navigationBarTitleDisplayMode(.inline)
                    .gsSpotlight(.library)
            }
            .navigationDestination(isPresented: $showDiscover) {
                ExercisesListView()
                    .background(theme.bg)
                    .navigationTitle("Exercises")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("You")
                .font(GSFont.heading(24, relativeTo: .title))
                .foregroundStyle(theme.text)
            Spacer(minLength: 0)
            avatar
        }
    }

    /// Decorative avatar — same 38pt circle-with-initials shape as
    /// HomeView's greeting-header avatar (`HomeView.greetingHeader`), photo
    /// via AsyncImage when one is set. Reads `appState.currentProfile`
    /// directly; profile fetching stayed with the profile row in
    /// `SettingsView`.
    @ViewBuilder
    private var avatar: some View {
        let profile = appState.currentProfile
        if let url = profile?.avatarURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                avatarInitials(profile)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            avatarInitials(profile)
        }
    }

    private func avatarInitials(_ profile: Profile?) -> some View {
        Circle()
            .fill(theme.surface)
            .frame(width: 38, height: 38)
            .overlay(Circle().strokeBorder(theme.divider, lineWidth: 1))
            .overlay(
                Text(initials(for: profile))
                    .font(GSFont.bold(13, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
            )
    }

    /// Same displayName-priority, 2-char-single-word algorithm the old
    /// profile row used (now in `SettingsView.initials(for:)`) — kept
    /// identical so the header and the Settings profile row can never show
    /// different initials for the same person.
    private func initials(for profile: Profile?) -> String {
        guard let profile else { return "?" }
        let trimmedDisplayName = profile.displayName?.trimmingCharacters(in: .whitespaces)
        let source = (trimmedDisplayName?.isEmpty == false ? trimmedDisplayName : nil) ?? profile.username
        let words = source.split(separator: " ")
        if words.count >= 2 {
            return String(words.prefix(2).compactMap(\.first)).uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }

    // MARK: - Widgets

    private var myRackWidget: some View {
        Button {
            showMyRack = true
        } label: {
            widgetCard(title: "MY RACK", footer: "SOUNDBOARD") {
                rackFace
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("My Rack")
    }

    /// Up to four compact plate tokens (the session dock's own component,
    /// at widget scale); neutral placeholder rings until the catalog
    /// resolves. 38pt preferred (2026-08 bigger-widgets pass) —
    /// ViewThatFits steps down on narrow devices so four plates never
    /// overflow the card.
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
                    Circle()
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

    private var statsWidget: some View {
        Button {
            showStats = true
        } label: {
            widgetCard(title: "STATS", footer: "TRENDS") {
                Text("Volume · PRs · history")
                    .font(GSFont.bodyMedium(17, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stats")
    }

    private var routinesWidget: some View {
        Button {
            showRoutines = true
        } label: {
            widgetCard(title: "ROUTINES", footer: "LIBRARY") {
                Text("Build & run your plans")
                    .font(GSFont.bodyMedium(17, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Routines")
    }

    private var discoverWidget: some View {
        Button {
            showDiscover = true
        } label: {
            widgetCard(title: "DISCOVER", footer: "EXERCISES") {
                // Non-interactive search-pill visual — search IS this
                // surface's identity (ExercisesListView opens with its own
                // live search field), so the widget face wears one.
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                    Text("Search exercises")
                        .font(GSFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        // The exercises catalog's discovery highlight rides along from
        // Library's old Discover segment (same target, same storage key —
        // anyone who already pressed it there stays pressed here).
        .gsDiscovery(.libraryDiscover, cornerRadius: GSMetrics.radiusSm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Discover exercises")
    }

    /// Inert this round — avatar, backdrops and effects come later.
    /// Static extrusion (no sink — nothing to tap); the whole face + lip
    /// dims to 0.6, the same treatment a disabled 3D button gets.
    private var lockerWidget: some View {
        widgetCard(title: "LOCKER", footer: "SOON") {
            Text("Avatar · backdrops · effects")
                .font(GSFont.bodyMedium(17, relativeTo: .body))
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
        .opacity(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locker — coming soon")
    }

    private var settingsWidget: some View {
        Button {
            showSettings = true
        } label: {
            widgetCard(title: "SETTINGS", footer: "APP") {
                Text("Account · preferences")
                    .font(GSFont.bodyMedium(17, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Settings")
    }

    // MARK: - Widget card chrome
    //
    // 3D pass (2026-08): this builder is the CONTENT of the card only — the
    // extruded face/lip chrome comes from the call site (`.gs3DCardStyle`
    // for tappable widgets, `.gs3DCard` for LOCKER), replacing the old flat
    // `theme.surface` + neutral500 stroke here. minHeight 144 = the prior
    // 150 minus the 6pt lip, which lives INSIDE the composite's frame — the
    // grid's footprint doesn't grow.

    private func widgetCard<Face: View>(
        title: String,
        footer: String,
        @ViewBuilder face: () -> Face
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            kLabel(title, color: theme.neutral700)
            Spacer(minLength: 10)
            face()
            Spacer(minLength: 10)
            kLabel(footer, color: theme.neutral500)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .leading)
    }

    private func kLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(GSFont.bold(11, relativeTo: .caption2))
            .tracking(1.1)
            .foregroundStyle(color)
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
