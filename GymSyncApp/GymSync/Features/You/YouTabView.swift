import SwiftUI

/// Redesign Phase 1 (four-tab reorientation, 2026-08): the You tab is now a
/// widget grid — the hub that absorbed Library (Routines, the exercises
/// catalog) and Stats when the tab bar collapsed from five tabs to four.
/// Everything the old You tab held (account details, preferences, Sign Out,
/// the Build footer) moved wholesale into `SettingsView`, pushed from the
/// SETTINGS row — nothing was dropped in the move.
///
/// Three-tab restructure (owner-approved proposal, 2026-08-12): You absorbed
/// the Shop tab. The grid now reads: STATS hero (live lifetime volume — the
/// "Get Stronger" pillar promoted) → ROUTINES | EXERCISES → PROGRAMS |
/// DISCOVER (the community-workouts browse, resurrected from the orphaned
/// LibraryTabView) → THE RACK (dock + weekly-rotation countdown, one
/// soundboard home) → LOCKER | PRO → SETTINGS. The header avatar became
/// tappable (→ Edit Profile).
///
/// Widget card recipe (2026-08 3D pass): extruded `GS3DCard` chrome — the
/// theme's raised face on a 6pt darker lip (the RACK IT anatomy at card
/// scale). Tappable widgets sink on press (`.gs3DCardStyle`); LOCKER sits
/// still (`.gs3DCard`). Content recipe: k-label title, a middle content
/// line, and a quieter footer k-label.
struct YouTabView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var showMyRack = false
    @State private var showStats = false
    @State private var showRoutines = false
    @State private var showExercises = false
    @State private var showPrograms = false
    @State private var showDiscoverWorkouts = false
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showEditProfile = false

    /// THE RACK widget face — the user's soundboard favorites, falling back
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

                        statsHero
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        LazyVGrid(columns: columns, spacing: 12) {
                            routinesWidget
                            exercisesWidget
                            programsWidget
                            discoverWidget
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        theRackWidget
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        LazyVGrid(columns: columns, spacing: 12) {
                            lockerWidget
                            proWidget
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        settingsRow
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
            .toolbar(.hidden, for: .navigationBar)   // in-content title (tab-root idiom)
            .task { await loadRack() }
            .navigationDestination(isPresented: $showMyRack) {
                MyRackView()
            }
            .navigationDestination(isPresented: $showStats) {
                // Pushed in content form (embedsInOwnStack: false). The
                // build-445 field report ("If I click You, then Stats, I'm
                // stuck") was StatsTabView's own nested NavigationStack
                // swallowing this stack's bar — bare content keeps the
                // system bar, and Stats' internal pushes ride THIS stack.
                StatsTabView(embedsInOwnStack: false)
                    .background(theme.bg)
                    .navigationTitle("Stats")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(isPresented: $showRoutines) {
                // The routines list the Library tab used to host. The
                // first-visit tip (`.library`) moved with it.
                RoutinesListView()
                    .background(theme.bg)
                    .navigationTitle("Routines")
                    .navigationBarTitleDisplayMode(.inline)
                    .gsSpotlight(.library)
            }
            .navigationDestination(isPresented: $showExercises) {
                ExercisesListView()
                    .background(theme.bg)
                    .navigationTitle("Exercises")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(isPresented: $showPrograms) {
                // Programs (né Campaigns — owner 2026-08-12: "Programs" is
                // the word the industry uses). The browse screen keeps its
                // internal structure: active program on top, structured
                // plans, community campaigns as a program type.
                CampaignsTabView()
                    .background(theme.bg)
                    .navigationTitle("Programs")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(isPresented: $showDiscoverWorkouts) {
                // Resurrected (three-tab restructure): the community-workout
                // browse grid was orphaned inside the dead LibraryTabView
                // since the four-tab reorientation.
                DiscoverView()
                    .background(theme.bg)
                    .navigationTitle("Discover")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(isPresented: $showPaywall) {
                PaywallView()
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $showEditProfile) {
                EditProfileView(profile: appState.currentProfile) { updated in
                    appState.currentProfile = updated
                }
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
            // Tappable since the restructure (wiring audit: it was
            // decorative) — the fastest route to the most-wanted setting.
            Button {
                showEditProfile = true
            } label: {
                avatar
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile")
        }
    }

    /// Same 38pt circle-with-initials shape as HomeView's greeting-header
    /// avatar, photo via AsyncImage when one is set. Reads
    /// `appState.currentProfile` directly; profile fetching stayed with the
    /// profile row in `SettingsView`.
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

    // MARK: - Stats hero

    /// Full-width live hero — the "Get Stronger" pillar promoted from a
    /// static two-line widget to the tab's headline. Lifetime volume comes
    /// free from `appState.currentProfile` (server-maintained column) — no
    /// fetch on the tab root.
    private var statsHero: some View {
        Button {
            showStats = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                kLabel("LIFETIME VOLUME", color: theme.neutral700)
                Spacer(minLength: 8)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(lifetimeVolumeText)
                        .font(GSFont.heading(40, relativeTo: .largeTitle))
                        .foregroundStyle(theme.text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(ThemeStore.shared.weightUnit.label.uppercased())
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .kerning(1.0)
                        .foregroundStyle(theme.neutral500)
                }
                Spacer(minLength: 8)
                kLabel("STATS · VOLUME · PRS · BODY WEIGHT · HISTORY", color: theme.neutral500)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stats")
    }

    private var lifetimeVolumeText: String {
        let pounds = appState.currentProfile?.lifetimeVolumeLifted ?? 0
        return StatMath.compactNumber(Units.fromPounds(pounds, to: ThemeStore.shared.weightUnit))
    }

    // MARK: - Widgets

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

    private var exercisesWidget: some View {
        Button {
            showExercises = true
        } label: {
            widgetCard(title: "EXERCISES", footer: "CATALOG") {
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
        // Library's old Discover segment (same target, same storage key).
        .gsDiscovery(.libraryDiscover, cornerRadius: GSMetrics.radiusSm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exercises")
    }

    private var programsWidget: some View {
        Button {
            showPrograms = true
        } label: {
            widgetCard(title: "PROGRAMS", footer: "GUIDED") {
                Text("Multi-week plans + campaigns")
                    .font(GSFont.bodyMedium(17, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        // The campaigns discovery dot followed the move from Shop
        // (same target, same storage key — pressed stays pressed).
        .gsDiscovery(.libraryCampaigns, cornerRadius: GSMetrics.radiusSm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Programs")
    }

    private var discoverWidget: some View {
        Button {
            showDiscoverWorkouts = true
        } label: {
            widgetCard(title: "DISCOVER", footer: "COMMUNITY") {
                Text("Workouts & leaderboards")
                    .font(GSFont.bodyMedium(17, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Discover")
    }

    // MARK: - The Rack (Shop merge, 2026-08-12)

    /// One soundboard home: the dock plates up front, the weekly-rotation
    /// countdown riding the title row (the Shop tab's headline concept,
    /// carried over — `WeeklyRack.nextRotation()` is pure date math, no
    /// fetch). Pushes MyRackView, which owns browsing + dock management.
    private var theRackWidget: some View {
        Button {
            showMyRack = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    kLabel("THE RACK", color: theme.neutral700)
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
                kLabel("SOUNDBOARD · THIS WEEK'S RACK + YOUR DOCK", color: theme.neutral500)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Rack")
    }

    /// Static compute at render — day/hour precision doesn't need a
    /// TimelineView; the row re-renders on any tab revisit.
    private var rotationText: String {
        let interval = max(0, WeeklyRack.nextRotation().timeIntervalSinceNow)
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        return "↻ ROTATES IN \(days)D \(hours)H"
    }

    /// Up to four compact plate tokens (the session dock's own component,
    /// at widget scale); neutral placeholder rings until the catalog
    /// resolves. ViewThatFits steps down on narrow devices.
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

    /// The Shop tab's inert "GYMSYNC PRO" row, made honest: it now opens
    /// the real PaywallView (design-only, says "coming soon", CTA
    /// disabled — Monetization ships dormant). Gold title = the one gold
    /// moment on this tab (debt/goal/aspiration color).
    private var proWidget: some View {
        Button {
            showPaywall = true
        } label: {
            widgetCard(title: "PRO", titleColor: Color.gsHex(0xE8C33A), footer: "GYMSYNC PRO") {
                Text("See what's coming")
                    .font(GSFont.bodyMedium(17, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GymSync Pro")
    }

    private var settingsRow: some View {
        Button {
            showSettings = true
        } label: {
            HStack {
                kLabel("SETTINGS", color: theme.neutral700)
                Spacer(minLength: 0)
                Text("Account · preferences")
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral500)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Settings")
    }

    // MARK: - Widget card chrome
    //
    // 3D pass (2026-08): this builder is the CONTENT of the card only — the
    // extruded face/lip chrome comes from the call site (`.gs3DCardStyle`
    // for tappable widgets, `.gs3DCard` for LOCKER). minHeight 144 = the
    // prior 150 minus the 6pt lip, which lives INSIDE the composite's frame.

    private func widgetCard<Face: View>(
        title: String,
        titleColor: Color? = nil,
        footer: String,
        @ViewBuilder face: () -> Face
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            kLabel(title, color: titleColor ?? theme.neutral700)
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
