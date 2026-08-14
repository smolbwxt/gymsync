import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// "Set your home gym" — onboarding step 3 of 3 (Dossier §A.7, canvas lines
/// 1053-1129). Also reused as the You-tab's Home Gym editor
/// (`isOnboarding: false`) per Task 8's brief.
///
/// The map is a live MapKit view the user pans; the gym coordinate is always
/// the visible map's CENTER (a fixed crosshair overlay marks it — the pin +
/// geofence circle never move, the map moves underneath them).
struct HomeGymSetupView: View {
    /// When `true` (onboarding), the footer's left button reads "Skip" and
    /// both buttons advance the onboarding flow. When `false` (You-tab
    /// editor), the left button reads "Cancel" and dismisses the sheet;
    /// saving dismisses the sheet instead of advancing.
    var isOnboarding: Bool = true

    /// Onboarding only: called for both "Skip" and a successful "Set Home
    /// Gym" save, to advance to the next onboarding screen.
    var onAdvance: (() -> Void)?

    /// You-tab editor only: called after a successful save (before the
    /// sheet dismisses) so the caller can refresh its displayed gym name.
    var onSaved: (() -> Void)?

    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var mapCenter: CLLocationCoordinate2D = Self.defaultRegion.center
    @State private var gymName: String = ""
    @State private var isSaving = false
    @State private var errorText: String?

    // Gym / address search (canvas frame 42) — type a name or address and
    // pick from MapKit local-search results, instead of panning the map in
    // from space. Selecting a result drops the map onto it; the map stays for
    // confirmation and fine-tuning the exact spot.
    @State private var searchQuery = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var userLocation: CLLocation?

    // Hub join offer (owner 2026-08-14: "when someone sets their home gym
    // somewhere, they should be prompted to join that hub, if one is
    // available"). Set after a successful save when a hub sits within
    // HubMatch.matchRadiusMeters and the user isn't in it yet; the alert's
    // buttons own the advance/dismiss that normally follows saving.
    @State private var hubOffer: Venue?
    @State private var showHubOffer = false

    #if DEBUG
    /// Debug-only: when true (screen catalog only, via the fixture init
    /// below), `body`'s `.task` skips `loadInitial()`'s live CheckInService
    /// network call + CLLocationManager one-shot request (10s hard
    /// timeout), so the catalog's forced search fixture renders
    /// deterministically instead of being raced/overwritten by a real
    /// response. Always false in every other path (including normal debug
    /// builds); compiled out of release entirely.
    var catalogSkipLoadInitial = false
    #endif

    private static let defaultRegion = MKCoordinateRegion(
        // Continental-US fallback used when the one-shot location request is
        // denied or times out — the flow must remain completable either way.
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
    )

    private static let focusedSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isOnboarding {
                        stepIndicator
                    }

                    header

                    searchSection
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

                    if !searchResults.isEmpty {
                        searchResultsList
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    mapSection
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    gymCard
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(13, relativeTo: .footnote))
                            .foregroundColor(.red)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    Spacer().frame(height: 100)
                }
            }

            footer
        }
        .task {
            #if DEBUG
            if catalogSkipLoadInitial { return }
            #endif
            await loadInitial()
        }
        .alert("Join the \(hubOffer?.name ?? "gym") hub?", isPresented: $showHubOffer) {
            Button("Join Hub") { Task { await joinOfferedHub() } }
            Button("Not Now", role: .cancel) { finishAfterSave() }
        } message: {
            Text("Your home gym hosts a hub — who's training, the monthly board, and the equipment list Coach builds from. You can leave anytime.")
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 10) {
            Text("STEP 3 OF 4")
                .font(GSFont.bold(12, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundColor(theme.neutral700)

            Spacer()

            HStack(spacing: 4) {
                Rectangle().fill(theme.accent).frame(width: 22, height: 4)
                Rectangle().fill(theme.accent).frame(width: 22, height: 4)
                Rectangle().fill(theme.accent).frame(width: 22, height: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 52)
        .padding(.bottom, 10)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set your home gym")
                .font(GSFont.bold(28, relativeTo: .title))
                .foregroundColor(theme.text)

            Text("We use it to confirm you're in the room at check-in. You can skip this.")
                .font(GSFont.body(14, relativeTo: .subheadline))
                .foregroundColor(theme.neutral700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, isOnboarding ? 20 : 52)
    }

    // MARK: - Map

    private var mapSection: some View {
        ZStack {
            Map(position: $cameraPosition)
                .onMapCameraChange { context in
                    mapCenter = context.camera.centerCoordinate
                }
                .allowsHitTesting(true)

            // Static crosshair overlays — centered over the map, never move.
            // The map pans underneath them; the visible center is the gym
            // coordinate that gets saved.
            Circle()
                .fill(theme.accent.opacity(0.12))
                .overlay(Circle().strokeBorder(theme.accent, lineWidth: 2))
                .frame(width: 120, height: 120)
                .allowsHitTesting(false)

            Image(systemName: "mappin")
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(theme.accent)
                .allowsHitTesting(false)
        }
        .frame(height: 230)
        .clipped()
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Search (canvas frame 42)

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search for a gym or address")
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundColor(theme.neutral700)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(theme.neutral500)

                TextField("e.g. Powerhouse Gym, or 88 Market St", text: $searchQuery)
                    .font(GSFont.body(15, relativeTo: .body))
                    .foregroundColor(theme.text)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onChange(of: searchQuery) { _, q in scheduleSearch(q) }

                if isSearching {
                    ProgressView().controlSize(.small).tint(theme.accent)
                } else if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(theme.neutral400)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(
                    searchQuery.isEmpty ? theme.divider : theme.accent, lineWidth: 1
                )
            )
        }
    }

    private var searchResultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(searchResults.prefix(6).enumerated()), id: \.offset) { index, item in
                Button {
                    selectResult(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle")
                            .font(.system(size: 18))
                            .foregroundColor(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Unknown")
                                .font(GSFont.bold(14, relativeTo: .subheadline))
                                .foregroundColor(theme.text)
                            Text(resultDetail(item))
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundColor(theme.neutral500)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < min(searchResults.count, 6) - 1 {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
    }

    // MARK: - Gym card

    private var gymCard: some View {
        GSCard(bordered: true) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Gym name", text: $gymName)
                    .font(GSFont.bold(15, relativeTo: .body))
                    .foregroundColor(theme.text)

                Text("check-in radius 200 m")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundColor(theme.neutral700)
            }
            .padding(12)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            GSDivider()
            HStack(spacing: 10) {
                Button {
                    handleSkip()
                } label: {
                    Text(isOnboarding ? "Skip" : "Cancel")
                }
                .buttonStyle(GSGhostButtonStyle())
                .frame(minHeight: 44)

                Button {
                    Task { await handleSetHomeGym() }
                } label: {
                    if isSaving {
                        ProgressView().tint(theme.bg)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Set Home Gym")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(GSPrimaryButtonStyle())
                .frame(minHeight: 44)
                .disabled(gymName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.bottom, 22)
        }
        .background(theme.bg)
    }

    // MARK: - Actions

    private func handleSkip() {
        if isOnboarding {
            onAdvance?()
        } else {
            dismiss()
        }
    }

    @MainActor
    private func handleSetHomeGym() async {
        let trimmed = gymName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        errorText = nil
        do {
            _ = try await GymRepository.upsertPrimary(
                name: trimmed,
                latitude: mapCenter.latitude,
                longitude: mapCenter.longitude,
                radiusMeters: 200
            )
            // Hub match: a hub at this spot the user hasn't joined → offer
            // it, and let the alert's buttons finish the flow. Any lookup
            // failure just skips the offer — the gym IS saved either way.
            if let venues = try? await VenueRepository.all(),
               let hub = HubMatch.nearest(in: venues, of: mapCenter) {
                let alreadyMember = await VenueRepository.isMember(venueID: hub.id)
                if !alreadyMember {
                    hubOffer = hub
                    showHubOffer = true
                    return
                }
            }
            finishAfterSave()
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
    }

    /// The advance/dismiss that follows a successful save — factored out so
    /// the hub-offer alert's buttons can run it after the offer resolves.
    private func finishAfterSave() {
        if isOnboarding {
            onAdvance?()
        } else {
            onSaved?()
            dismiss()
        }
    }

    /// Best-effort by design: a failed join must never wedge onboarding on
    /// a bonus step — the hub screen's check-in remains the recovery path.
    @MainActor
    private func joinOfferedHub() async {
        if let hub = hubOffer {
            try? await VenueRepository.join(venueID: hub.id)
        }
        finishAfterSave()
    }

    // MARK: - Initial camera / prefill

    @MainActor
    private func loadInitial() async {
        // Editing an existing primary gym: prefill name + start the camera
        // there rather than requesting the device's current location.
        if let existing = try? await CheckInService.primaryGym() {
            gymName = existing.name ?? ""
            let coordinate = CLLocationCoordinate2D(latitude: existing.latitude, longitude: existing.longitude)
            setCamera(center: coordinate)
            return
        }

        // No gym yet: center on the user's current location via the
        // existing one-shot location helper. Denial/timeout falls back to
        // the continental-US default region already set — the flow stays
        // completable either way.
        if let location = try? await CheckInService.requestLocation() {
            userLocation = location
            setCamera(center: location.coordinate)
        }
    }

    private func setCamera(center: CLLocationCoordinate2D) {
        mapCenter = center
        cameraPosition = .region(MKCoordinateRegion(center: center, span: Self.focusedSpan))
    }

    // MARK: - Search actions

    /// Debounced: MapKit local search is rate-limited and every keystroke
    /// would otherwise fire a request. Waits 300 ms of quiet before searching.
    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await runSearch(q)
        }
    }

    @MainActor
    private func runSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // Bias toward the map's current area so nearby gyms rank first.
        request.region = MKCoordinateRegion(
            center: mapCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            if !Task.isCancelled { searchResults = response.mapItems }
        } catch {
            searchResults = []
        }
    }

    /// Picking a result drops the map onto it and prefills the name (only if
    /// the user hasn't typed their own), then clears the search.
    private func selectResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        if gymName.trimmingCharacters(in: .whitespaces).isEmpty, let name = item.name {
            gymName = name
        }
        setCamera(center: coordinate)
        searchResults = []
        searchQuery = ""
        // Dismiss the keyboard so the map + confirmation are fully visible.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    /// Address line + distance from the user (when location is available —
    /// otherwise name-only, matching the frame's "location is off" note).
    private func resultDetail(_ item: MKMapItem) -> String {
        let placemark = item.placemark
        var parts: [String] = []
        if let street = placemark.thoroughfare {
            parts.append(placemark.subThoroughfare.map { "\($0) \(street)" } ?? street)
        }
        if let city = placemark.locality {
            parts.append(city)
        }
        var line = parts.joined(separator: ", ")
        if let userLocation {
            let meters = userLocation.distance(from: CLLocation(
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude
            ))
            let miles = meters / 1609.34
            line += (line.isEmpty ? "" : " · ") + String(format: "%.1f mi", miles)
        }
        return line.isEmpty ? "Tap to use this location" : line
    }
}

#if DEBUG
extension HomeGymSetupView {
    /// Debug-only seam for the design-parity screen catalog (Task 4):
    /// force-seeds the map-search fixture (query + results + spinner) and
    /// skips `loadInitial()`'s live network/location calls (see
    /// `catalogSkipLoadInitial` above), so `CatalogHostView` can render both
    /// the plain and "searching" home-gym states deterministically. Added
    /// here (rather than in CatalogHostView.swift) because `_searchQuery`/
    /// `_searchResults`/`_isSearching` are `private` @State — this extension
    /// can assign them only because it lives in the SAME FILE as those
    /// declarations. Compiled out of release entirely.
    init(catalogSearchQuery: String, catalogSearchResults: [MKMapItem], catalogIsSearching: Bool) {
        self.init(isOnboarding: true)
        _searchQuery = State(initialValue: catalogSearchQuery)
        _searchResults = State(initialValue: catalogSearchResults)
        _isSearching = State(initialValue: catalogIsSearching)
        catalogSkipLoadInitial = true
    }
}
#endif
