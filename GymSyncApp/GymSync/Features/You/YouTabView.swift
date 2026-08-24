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
/// "Get Stronger" pillar promoted) → ROUTINES & PROGRAMMING | COACH |
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

    @State private var showShop = false
    @State private var showStats = false
    @State private var showRoutines = false
    @State private var showCoach = false
    @State private var showSettings = false
    @State private var showEditProfile = false

    /// ROUTINES widget slot state ("3 OF 5 SLOTS FILLED") — best-effort
    /// count fetch; nil until it resolves (footer falls back to "HUB").
    @State private var routineCount: Int?

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
                            .gsSpotlightTarget(key: "tour.you.stats")

                        // Owner 2026-08-13: full-width widgets with real
                        // descriptions. Reorder 2026-08-16: SHOP leads (it
                        // houses PRO, the Rack, Coaching, and every future
                        // sellable); EXERCISES moved into the Routines hub;
                        // Settings became a full widget.
                        shopWidget
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .gsSpotlightTarget(key: "tour.you.rack")

                        routinesWidget
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .gsSpotlightTarget(key: "tour.you.routines")

                        coachWidget
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        lockerWidget
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        settingsWidget
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
            // Tour (owner 2026-08-14): stats → routines → the Rack.
            .gsSpotlightTour(GuidanceTours.you)
            .task {
                // Launch-readiness accounting (RootView's overlay hold).
                appState.beginLaunchFetch()
                // ROUTINES slot state — one light query, best-effort.
                if let ownerID = appState.currentProfile?.id {
                    routineCount = (try? await RoutineRepository.fetchAll(ownerID: ownerID))?.count
                }
                appState.endLaunchFetch()
            }
            .navigationDestination(isPresented: $showShop) {
                ShopView()
                    .navigationTitle("Shop")
                    .navigationBarTitleDisplayMode(.inline)
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
                // The Routines hub (owner 2026-08-13): slots + Coach +
                // Builder + Discover — the single home for routine-shaped
                // things. The first-visit tip (`.library`) rides along.
                RoutinesHubView()
                    .background(theme.bg)
                    .navigationTitle("Routines & Programming")
                    .navigationBarTitleDisplayMode(.inline)
                    .gsSpotlight(.library)
            }
            .navigationDestination(isPresented: $showCoach) {
                // Coach's home (owner 2026-08-24): the dedicated chat +
                // MY PROGRAM (the generator, one layer down) + research
                // deliveries. Programs browse moved into the Routines hub.
                CoachHomeView()
                    .background(theme.bg)
                    .navigationTitle("Coach")
                    .navigationBarTitleDisplayMode(.inline)
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
    /// Owner 2026-08-21: the door says STATS; the lifetime-volume metric
    /// moved to the top of the stats page itself (one number, one home).
    private var statsHero: some View {
        Button {
            showStats = true
        } label: {
            widgetCard(title: "STATS") {
                Text("Volume · PRs · body weight · history")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stats")
    }

    // MARK: - Widgets

    private var routinesWidget: some View {
        Button {
            showRoutines = true
        } label: {
            widgetCard(title: "ROUTINES & PROGRAMMING") {
                Text(routinesFaceText)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Routines and programming")
    }

    /// Slot fill-state rides the face line now that the caps footer is
    /// gone (owner 2026-08-21) — the 2026-08-13 "state from the outside"
    /// ruling survives, one line lower.
    private var routinesFaceText: String {
        guard let routineCount else { return "Programs · the builder · Discover" }
        let limit = Monetization.freeRoutineLimit
        let state = routineCount > limit
            ? "\(routineCount) routines"
            : "\(routineCount) of \(limit) slots filled"
        return "Programs · the builder · Discover · \(state)"
    }

    /// Coach's T1 slot (owner 2026-08-24: "the coach should replace
    /// the programs widget on the T1 of the You tab"). Programs browse
    /// moved into the Routines hub; the generator lives one layer down
    /// inside Coach.
    private var coachWidget: some View {
        Button {
            showCoach = true
        } label: {
            widgetCard(title: "COACH") {
                Text("Your ongoing chat, your program, the research")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach")
    }

    // MARK: - Shop (owner 2026-08-16: the storefront leads the page)

    /// SHOP houses every sellable: PRO, the Rack, Coaching, and whatever
    /// comes later. The Rack's plate face and rotation moved into
    /// ShopView with it.
    private var shopWidget: some View {
        Button {
            showShop = true
        } label: {
            widgetCard(title: "SHOP") {
                Text("Pro, the soundboard rack, and training with a personal trainer")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shop")
    }

    /// Inert this round — avatar, backdrops and effects come later.
    /// Static extrusion (no sink — nothing to tap); the whole face + lip
    /// dims to 0.6, the same treatment a disabled 3D button gets.
    private var lockerWidget: some View {
        widgetCard(title: "LOCKER") {
            Text("Avatar · backdrops · effects — soon")
                .font(GSFont.body(13, relativeTo: .subheadline))
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
            widgetCard(title: "SETTINGS") {
                Text("Account, appearance, notifications, home gym")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
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
    // for tappable widgets, `.gs3DCard` for LOCKER). minHeight 92: the
    // full-width stacked language (owner 2026-08-13) — kicker +
    // description + footer read comfortably without the grid era's square
    // proportions.

    private func widgetCard<Face: View>(
        title: String,
        titleColor: Color? = nil,
        @ViewBuilder face: () -> Face
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Owner 2026-08-21 (typography pass): bigger title, the face
            // sits low, and the bottom caps line is gone — two levels of
            // text per widget, not three.
            Text(title)
                .font(GSFont.bold(24, relativeTo: .title2))
                .tracking(0.5)
                .foregroundStyle(titleColor ?? theme.text)
            Spacer(minLength: 14)
            face()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    }


    // MARK: - Data

}
