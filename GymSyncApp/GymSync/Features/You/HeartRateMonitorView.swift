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

                // Field #2 2026-08-24: the paired Apple Watch's honest
                // status - the diagnosable states, named. A paired watch
                // WITHOUT the GymSync watch app is the common trap.
                appleWatchRow

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
                        // Owner text law (2026-08-12): UI text carries no
                        // accent tint — the live readout reads in the
                        // secondary neutral, the same swap StatsTabView's
                        // month-trend line took in the P1 sweep. The
                        // heart icon above keeps the accent (icons and
                        // data ink may).
                        Text(ble.latestBPM.map { "\($0) bpm" } ?? "waiting for signal…")
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral700)
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
        // gs3D pass (P2): a status/reading card is a widget the athlete
        // READS, so it joins the extruded language and matches
        // `appleWatchRow` right above it. The surface fill + cornerRadius
        // retire — the face is the fill, the lip is the delineation.
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    @ViewBuilder
    private var appleWatchRow: some View {
        let status = WatchConnectivityBridge.shared.pairingStatus
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(status.paired && status.appInstalled
                                     ? theme.accent : theme.neutral500)
                Text("APPLE WATCH")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
                Spacer()
                // Owner text law: the READY state reads in the DEFAULT text
                // color, not accent — the accent lives on the watch glyph to
                // the left, which is where the color signal belongs.
                Text(!status.active ? "CHECKING…"
                     : !status.paired ? "NOT PAIRED"
                     : !status.appInstalled ? "APP NOT ON WATCH"
                     : "READY")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(status.paired && status.appInstalled
                                     ? theme.text : theme.neutral500)
            }
            Text(!status.active
                 ? "Talking to the watch — give it a second."
                 : !status.paired
                 ? "No Apple Watch is paired with this iPhone."
                 : !status.appInstalled
                 ? "Your watch is paired, but GymSync isn't installed on it. Open the Watch app on this iPhone → available apps → install GymSync, and heart rate flows automatically — no pairing needed here."
                 : "Paired with GymSync installed — heart rate flows automatically during workouts, no pairing needed here. This screen is for chest straps and broadcast-mode watches.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
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
                    .contentShape(Rectangle())
                }
                // A discovered device is a thing you TAP: it sits proud and
                // sinks. The label sheds its own surface fill and radius —
                // a fill here would paint over the face (StatsTabView's
                // navRow precedent, same intrinsic-height row shape).
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
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
