import SwiftUI

// MARK: - HeartRateMonitorView (You ▸ Settings ▸ Heart rate monitor)
//
// Pairing for any standard Bluetooth HR device (BLEHeartRateService's
// header covers what that includes). Once paired, live sessions pick the
// strap up automatically — this screen is setup, not a per-workout step.

struct HeartRateMonitorView: View {
    @Environment(\.gsTheme) private var theme

    @State private var ble = BLEHeartRateService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Connect a chest strap or a watch broadcasting heart rate. During live sessions it shares through the same toggle as the Apple Watch — nothing is shared unless you've turned sharing on.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)

                statusCard

                if case .connected = ble.state {} else {
                    scanSection
                }

                Text("Works with Polar, Garmin and Wahoo straps, and Garmin/Polar/Whoop watches in broadcast mode. Fitbit and Samsung watches can't broadcast — their workouts still sync through Apple Health afterward.")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle("Heart rate monitor")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { ble.stopScanning() }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch ble.state {
            case .connected(let name):
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(GSFont.bold(15, relativeTo: .headline))
                            .foregroundStyle(theme.text)
                        // Live preview proves the pairing works before a
                        // session ever depends on it.
                        Text(ble.latestBPM.map { "\($0) bpm" } ?? "waiting for signal…")
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.accent700)
                            .monospacedDigit()
                    }
                    Spacer()
                }
                Button("Forget this device") { ble.disconnect(forget: true) }
                    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                    .foregroundStyle(.red)
            case .connecting(let name):
                HStack(spacing: 8) {
                    ProgressView().tint(theme.accent)
                    Text("Connecting to \(name)…")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                }
            case .bluetoothOff:
                Text("Bluetooth is off — turn it on in Control Center to pair.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            case .unauthorized:
                Text("Bluetooth permission is off for GymSync — enable it in Settings to pair a monitor.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            case .idle, .scanning:
                Text(ble.hasRememberedDevice
                     ? "Your monitor reconnects automatically during sessions."
                     : "No monitor paired yet.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.surface)
        .cornerRadius(GSMetrics.radiusMd)
    }

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GSSectionHeader("Nearby devices")
                Spacer()
                if case .scanning = ble.state {
                    ProgressView().controlSize(.small).tint(theme.accent)
                }
            }

            ForEach(ble.discovered, id: \.id) { device in
                Button {
                    ble.connect(id: device.id)
                } label: {
                    HStack {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.accent)
                        Text(device.name)
                            .font(GSFont.bodyMedium(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.neutral500)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(theme.surface)
                    .cornerRadius(GSMetrics.radiusSm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                if case .scanning = ble.state { ble.stopScanning() }
                else { ble.startScanning() }
            } label: {
                Text({ if case .scanning = ble.state { return "Stop scanning" } else { return "Scan" } }())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSSecondaryButtonStyle(fontSize: 14, verticalPadding: 11))
        }
    }
}
