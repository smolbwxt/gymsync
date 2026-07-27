import CoreLocation
import SwiftUI

// MARK: - Venue Hubs H1 UI (Social ▸ Local)
//
// Design: docs/superpowers/specs/2026-07-25-venue-hubs-design.md ("Screens").
// No canvas frame exists for venues (Phase V was benched before design) —
// system-designed in the Onyx language from existing components, with
// accepted-deviations entries filed alongside.
//
// Two screens + one gate:
//   * LocalHubsView       — nearby venues, claim CTA, the age gate
//   * VenueHubView        — one venue: presence toggle, who's here, board
//   * AgeGateView         — self-attested 18+ (spec §6.7)

// MARK: - Age gate

struct AgeGateView: View {
    @Environment(\.gsTheme) private var theme
    let onConfirm: () -> Void
    let onDecline: () -> Void

    @State private var busy = false

    var body: some View {
        // Top-anchored, not centered: this app's screens anchor content to
        // the top (the Social empty-state feedback, 2026-07-23) and a
        // vertically centered gate read as floating in the capture.
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(theme.accent)
            Text("Local hubs are 18+")
                .font(GSFont.heading(22, relativeTo: .title2))
                .foregroundStyle(theme.text)
            Text("Local hubs show you other lifters at your gym. By tapping Confirm you attest that you are 18 or older.")
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.neutral500)
            Text("You choose whether anyone can see you — nobody appears on a hub without opting in, and you can turn it off any time.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)

            Button {
                busy = true
                onConfirm()
            } label: {
                Text("Confirm — I'm 18 or older")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 13))
            .disabled(busy)
            .padding(.top, 6)

            Button("Not now") { onDecline() }
                .font(GSFont.bodyMedium(14, relativeTo: .body))
                .foregroundStyle(theme.neutral500)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(20)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg)
    }
}

// MARK: - Local hubs list

struct LocalHubsView: View {
    @Environment(\.gsTheme) private var theme

    @State private var venues: [Venue] = []
    @State private var here: CLLocationCoordinate2D?
    @State private var loading = true
    @State private var errorText: String?
    @State private var ageAttested: Bool?
    @State private var showClaim = false

    #if DEBUG
    var catalogSkipLoad = false

    /// Catalog seam. A dedicated init (not the synthesized memberwise one)
    /// because the `@State` properties above are `private` — which makes
    /// the memberwise init private too, unreachable from CatalogHostView.
    /// Same reasoning as `CampaignsTabView`'s own catalog init.
    init(catalogFixtureVenues venues: [Venue], catalogFixtureAttested attested: Bool = true) {
        _venues = State(initialValue: venues)
        _ageAttested = State(initialValue: attested)
        _loading = State(initialValue: false)
        catalogSkipLoad = true
    }
    #endif

    init() {}

    var body: some View {
        Group {
            if ageAttested == false {
                AgeGateView(
                    onConfirm: { Task { await attest() } },
                    onDecline: { ageAttested = nil }
                )
            } else {
                listBody
            }
        }
        .background(theme.bg)
        .navigationTitle("Local")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showClaim) {
            VenueClaimView { newVenue in
                venues.append(newVenue)
                showClaim = false
            }
        }
    }

    private var sortedVenues: [(venue: Venue, distance: Double?)] {
        venues
            .map { venue in
                (venue, here.map { VenueMath.distanceMeters(from: $0, to: venue.coordinate) })
            }
            .sorted { lhs, rhs in
                switch (lhs.1, rhs.1) {
                case let (l?, r?): return l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                default:           return lhs.0.name < rhs.0.name
                }
            }
    }

    @ViewBuilder
    private var listBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if loading {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.top, 60)
                } else {
                    Text("Gyms near you. Check in to see who else is training — you stay hidden until you say otherwise.")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    if venues.isEmpty {
                        GSEmptyState(
                            icon: "mappin.and.ellipse",
                            title: "No gyms yet",
                            message: "Add your gym to start a hub for it."
                        )
                        .padding(.top, 30)
                    } else {
                        GSSectionHeader("Gyms")
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 8)
                        ForEach(sortedVenues, id: \.venue.id) { item in
                            NavigationLink {
                                VenueHubView(venue: item.venue, here: here)
                            } label: {
                                venueRow(item.venue, distance: item.distance)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                        }
                    }

                    Button {
                        showClaim = true
                    } label: {
                        Text("Add your gym")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GSSecondaryButtonStyle(fontSize: 14, verticalPadding: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(.red)
                            .padding(16)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .contentMargins(.bottom, 88, for: .scrollContent)
    }

    private func venueRow(_ venue: Venue, distance: Double?) -> some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(venue.name)
                        .font(GSFont.heading(16, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    if venue.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.accent)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
                if let distance {
                    Text(VenueMath.distanceText(distance))
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @MainActor
    private func load() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        loading = true
        defer { loading = false }
        // Age gate first — the whole surface is 18+ (spec §6.7).
        let attested = await AgeGateRepository.hasAttested()
        ageAttested = attested
        guard attested else { return }
        do { venues = try await VenueRepository.all() }
        catch { errorText = ErrorMapping.map(error).errorDescription }
        // Location is best-effort: without it the list simply loses its
        // distance sort — never an error, never a blocker.
        here = (try? await CheckInService.requestLocation())?.coordinate
    }

    @MainActor
    private func attest() async {
        do {
            try await AgeGateRepository.attest18Plus()
            ageAttested = true
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}

// MARK: - One venue's hub

struct VenueHubView: View {
    @Environment(\.gsTheme) private var theme

    let venue: Venue
    let here: CLLocationCoordinate2D?

    @State private var members: [VenueMember] = []
    @State private var board: [VenueLeaderboardRow] = []
    @State private var myMembership: VenueMember?
    @State private var loading = true
    @State private var busy = false
    @State private var errorText: String?
    @State private var showAdvisory = false
    // Key from OneShotFlags — see that file; keeps the QA reset honest.
    @AppStorage(OneShotFlags.venueAdvisoryKey) private var hasSeenAdvisory = false

    #if DEBUG
    var catalogSkipLoad = false

    init(venue: Venue, here: CLLocationCoordinate2D?,
         catalogFixtureMembers: [VenueMember] = [],
         catalogFixtureBoard: [VenueLeaderboardRow] = [],
         catalogFixtureMine: VenueMember? = nil,
         catalogSkipLoad: Bool = false) {
        self.venue = venue
        self.here = here
        _members = State(initialValue: catalogFixtureMembers)
        _board = State(initialValue: catalogFixtureBoard)
        _myMembership = State(initialValue: catalogFixtureMine)
        _loading = State(initialValue: false)
        self.catalogSkipLoad = catalogSkipLoad
    }
    #else
    init(venue: Venue, here: CLLocationCoordinate2D?) {
        self.venue = venue
        self.here = here
    }
    #endif

    private var presentMembers: [VenueMember] {
        members.filter { VenueMath.isPresent($0) && $0.userID != myMembership?.userID }
    }
    private var isCheckedIn: Bool { myMembership != nil }
    private var isVisible: Bool { myMembership?.isVisibleOnHub == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if loading {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.top, 40)
                } else {
                    checkInSection
                    whosHereSection
                    leaderboardSection
                }
                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .background(theme.bg)
        .navigationTitle("Hub")
        .navigationBarTitleDisplayMode(.inline)
        .gsHidesDock()
        .task { await load() }
        .sheet(isPresented: $showAdvisory) {
            VenueAdvisoryView { showAdvisory = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(venue.name)
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                if venue.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.accent)
                }
            }
            // "others" is load-bearing: presentMembers excludes you, so a
            // bare "2 here right now" misreads as the total including you.
            Text(presentMembers.isEmpty
                 ? "Nobody's on the hub right now"
                 : "\(presentMembers.count) other\(presentMembers.count == 1 ? "" : "s") here right now")
                .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                .foregroundStyle(theme.accent700)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var checkInSection: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 10) {
                if isCheckedIn {
                    Toggle(isOn: Binding(
                        get: { isVisible },
                        set: { newValue in Task { await setVisible(newValue) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("I'm here — show me on the hub")
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                            Text("Others at this gym can see your name while you're checked in.")
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                    .tint(theme.accent)
                    .disabled(busy)
                } else {
                    Text("Check in to join this hub")
                        .font(GSFont.bodyMedium(14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    Text("You need to be at the gym — your location is checked once and never stored as history.")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    Button {
                        Task { await checkIn() }
                    } label: {
                        Text("Check in")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GSPrimaryButtonStyle(fontSize: 14, verticalPadding: 12))
                    .disabled(busy)
                    .opacity(busy ? 0.6 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var whosHereSection: some View {
        if isCheckedIn {
            VStack(alignment: .leading, spacing: 8) {
                GSSectionHeader("Who's here")
                    .padding(.horizontal, 16)
                if presentMembers.isEmpty {
                    Text(isVisible
                         ? "You're the only one on the hub right now."
                         : "Nobody's visible right now. Flip the toggle above to show up for others.")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                        .padding(.horizontal, 16)
                } else {
                    ForEach(presentMembers) { member in
                        HStack(spacing: 10) {
                            GSInitialsAvatar(name: usernameFor(member.userID), size: 32)
                            Text(usernameFor(member.userID))
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var leaderboardSection: some View {
        if isCheckedIn, !board.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                GSSectionHeader("This month at this gym")
                    .padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(Array(board.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral500)
                                .frame(width: 20, alignment: .leading)
                            GSInitialsAvatar(name: row.username, size: 28)
                            Text(row.username)
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                            Spacer(minLength: 0)
                            Text("\(StatMath.compactNumber(Units.fromPounds(row.volume, to: ThemeStore.shared.weightUnit))) \(ThemeStore.shared.weightUnit == .kg ? "kg" : "lb")")
                                .font(GSFont.body(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.accent700)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        if index < board.count - 1 { GSDivider() }
                    }
                }
                .background(theme.surface)
                .cornerRadius(GSMetrics.radiusSm)
                .padding(.horizontal, 16)
            }
        }
    }

    /// The hub shows usernames only for people the leaderboard already
    /// names; presence rows for users not on the board fall back to a
    /// neutral label rather than fetching profiles (H1 keeps the hub to
    /// two queries).
    private func usernameFor(_ userID: UUID) -> String {
        board.first { $0.userID == userID }?.username ?? "Lifter"
    }

    // MARK: Data

    @MainActor
    private func load() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        loading = true
        defer { loading = false }
        let me = await SupabaseService.shared.currentUserID()
        do {
            members = try await VenueRepository.members(venueID: venue.id)
            myMembership = members.first { $0.userID == me }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
        // Leaderboard is member-gated server-side — only ask once we know
        // we're a member, so a non-member never sees its P0001 as an error.
        if myMembership != nil {
            board = (try? await VenueRepository.leaderboard(venueID: venue.id)) ?? []
        }
    }

    @MainActor
    private func checkIn() async {
        busy = true; defer { busy = false }
        do {
            // Friendly local pre-check so the common "not at the gym" case
            // reads as guidance, not a server error. The RPC re-checks and
            // is the authority (client coordinates are user-editable).
            let coordinate: CLLocationCoordinate2D
            if let here {
                coordinate = here
            } else {
                coordinate = try await CheckInService.requestLocation().coordinate
            }
            let distance = VenueMath.distanceMeters(from: coordinate, to: venue.coordinate)
            guard distance <= Double(venue.radiusMeters) else {
                errorText = "You need to be at \(venue.name) to check in — you're \(VenueMath.distanceText(distance))."
                return
            }
            try await VenueRepository.checkIn(venueID: venue.id, coordinate: coordinate)
            errorText = nil
            if !hasSeenAdvisory {
                hasSeenAdvisory = true
                showAdvisory = true
            }
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func setVisible(_ visible: Bool) async {
        busy = true; defer { busy = false }
        do {
            try await VenueRepository.setVisible(venueID: venue.id, visible: visible)
            errorText = nil
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}

// MARK: - Safety advisory (spec §6.7 — shown before meeting anyone)

struct VenueAdvisoryView: View {
    @Environment(\.gsTheme) private var theme
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "hand.raised")
                .font(.system(size: 30))
                .foregroundStyle(theme.accent)
            Text("Meeting people here")
                .font(GSFont.heading(20, relativeTo: .title3))
                .foregroundStyle(theme.text)
            Text("Keep first meetups in the public areas of the gym. Don't share your address, schedule, or anything you wouldn't post publicly.")
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.neutral500)
            Text("You can block or report anyone from their profile — blocked people disappear from every hub surface for both of you.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
            Button {
                onDismiss()
            } label: {
                Text("Got it")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 13))
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
    }
}

// MARK: - Claim a venue (map search — the HomeGymSetupView pattern)

struct VenueClaimView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let onClaimed: (Venue) -> Void

    @State private var name = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add your gym")
                .font(GSFont.heading(20, relativeTo: .title3))
                .foregroundStyle(theme.text)
            Text("Creates a hub for this gym. You need to be standing at it — the location you're at now becomes its center.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)

            TextField("Gym name", text: $name)
                .font(GSFont.body(15, relativeTo: .body))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(theme.surface)
                .cornerRadius(GSMetrics.radiusSm)

            if let coordinate {
                Text(String(format: "Using your location: %.4f, %.4f", coordinate.latitude, coordinate.longitude))
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }

            Button {
                Task { await claim() }
            } label: {
                Text("Create hub")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 13))
            .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity((busy || name.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.6 : 1)

            if let errorText {
                Text(errorText)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
        .task {
            coordinate = (try? await CheckInService.requestLocation())?.coordinate
        }
    }

    @MainActor
    private func claim() async {
        busy = true; defer { busy = false }
        guard let coordinate else {
            errorText = "Location unavailable — a hub needs a location to check people in."
            return
        }
        do {
            let venue = try await VenueRepository.claim(
                name: name.trimmingCharacters(in: .whitespaces),
                coordinate: coordinate
            )
            onClaimed(venue)
            dismiss()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
