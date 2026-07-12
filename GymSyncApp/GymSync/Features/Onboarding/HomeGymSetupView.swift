import CoreLocation
import MapKit
import SwiftUI

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
                    mapSection
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

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
        .task { await loadInitial() }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 10) {
            Text("STEP 3 OF 3")
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
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
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
            if isOnboarding {
                onAdvance?()
            } else {
                onSaved?()
                dismiss()
            }
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
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
            setCamera(center: location.coordinate)
        }
    }

    private func setCamera(center: CLLocationCoordinate2D) {
        mapCenter = center
        cameraPosition = .region(MKCoordinateRegion(center: center, span: Self.focusedSpan))
    }
}
