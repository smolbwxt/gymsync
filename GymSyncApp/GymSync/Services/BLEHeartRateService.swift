import CoreBluetooth
import Foundation

// MARK: - BLEHeartRateService
//
// Live heart rate from ANY standard Bluetooth monitor (user direction
// 2026-07-27: "the goal is that everyone has the option to have live HR").
// Speaks the open BLE Heart Rate Profile — service 0x180D, measurement
// characteristic 0x2A37 — the same standard Peloton/Zwift build on. Covers
// every chest strap (Polar H10, Garmin HRM, Wahoo), Garmin and Polar
// watches in "broadcast heart rate" mode, and Whoop's broadcast mode.
// (Fitbit and Samsung watches cannot broadcast standard BLE HR — their
// users are covered by the post-workout HealthKit backfill instead.)
//
// This is a SOURCE, not a relay: it publishes nothing itself. Live-session
// screens set `onSample` and route readings through the EXACT gate the
// Apple Watch path uses (share toggle -> zone -> HeartRateBroadcastService
// .publish) — one policy, two sources, no second code path to drift.
//
// @Observable @MainActor singleton per the ConnectivityMonitor idiom.
// CoreBluetooth delivers callbacks on its own queue; every state mutation
// hops to the main actor.
@Observable
@MainActor
final class BLEHeartRateService: NSObject {
    static let shared = BLEHeartRateService()

    enum State: Equatable {
        case idle
        case bluetoothOff
        case unauthorized
        case scanning
        case connecting(name: String)
        case connected(name: String)
    }

    private(set) var state: State = .idle
    /// Peripherals seen while scanning — (identifier, display name).
    private(set) var discovered: [(id: UUID, name: String)] = []
    /// Most recent reading, for the pairing screen's live preview.
    private(set) var latestBPM: Int?
    private(set) var latestAt: Date?

    /// Live-session relay hook — set on session appear, cleared on
    /// disappear. Fires on the main actor for every measurement.
    var onSample: ((Int) -> Void)?

    /// The remembered monitor (auto-reconnect target). Device-local.
    static let rememberedKey = "ble.hr.peripheral.v1"

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    private static let hrService = CBUUID(string: "180D")
    private static let hrMeasurement = CBUUID(string: "2A37")

    // MARK: Public surface

    /// Starts Bluetooth (first call triggers the system permission prompt)
    /// and scans for heart-rate devices.
    func startScanning() {
        ensureCentral()
        discovered = []
        guard central?.state == .poweredOn else { return }
        state = .scanning
        central?.scanForPeripherals(withServices: [Self.hrService])
    }

    func stopScanning() {
        central?.stopScan()
        if case .scanning = state { state = .idle }
    }

    func connect(id: UUID) {
        ensureCentral()
        guard let central, central.state == .poweredOn,
              let target = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        central.stopScan()
        peripheral = target
        target.delegate = self
        state = .connecting(name: target.name ?? "Heart rate monitor")
        UserDefaults.standard.set(id.uuidString, forKey: Self.rememberedKey)
        central.connect(target)
    }

    /// Reconnects to the remembered monitor, if any — called when a live
    /// session starts so a paired strap just works.
    func connectRememberedIfAny() {
        guard peripheral == nil,
              let stored = UserDefaults.standard.string(forKey: Self.rememberedKey),
              let id = UUID(uuidString: stored) else { return }
        ensureCentral()
        // If Bluetooth isn't up yet, centralManagerDidUpdateState retries.
        if central?.state == .poweredOn { connect(id: id) }
    }

    func disconnect(forget: Bool) {
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        latestBPM = nil
        latestAt = nil
        state = .idle
        if forget { UserDefaults.standard.removeObject(forKey: Self.rememberedKey) }
    }

    var hasRememberedDevice: Bool {
        UserDefaults.standard.string(forKey: Self.rememberedKey) != nil
    }

    // MARK: Internals

    private func ensureCentral() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Standard HR Measurement parse: flags bit 0 selects uint8 vs uint16
    /// little-endian bpm. Everything after (energy, RR intervals) is
    /// irrelevant here.
    nonisolated static func parseHeartRate(_ data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        let flags = data[0]
        if flags & 0x01 == 0 {
            return Int(data[1])
        }
        guard data.count >= 3 else { return nil }
        return Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
    }

    fileprivate func handleMeasurement(_ data: Data) {
        guard let bpm = Self.parseHeartRate(data), bpm > 0, bpm < 250 else { return }
        latestBPM = bpm
        latestAt = .now
        onSample?(bpm)
    }
}

// MARK: - CoreBluetooth delegates (nonisolated; hop to main actor)

extension BLEHeartRateService: CBCentralManagerDelegate, CBPeripheralDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let poweredOn = central.state == .poweredOn
        let unauthorized = central.state == .unauthorized
        Task { @MainActor in
            if poweredOn {
                // Resume whatever was waiting on Bluetooth: an in-flight
                // scan request or the remembered auto-reconnect.
                if case .scanning = self.state {
                    self.central?.scanForPeripherals(withServices: [Self.hrService])
                } else {
                    self.connectRememberedIfAny()
                }
            } else {
                self.state = unauthorized ? .unauthorized : .bluetoothOff
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Heart rate monitor"
        Task { @MainActor in
            guard !self.discovered.contains(where: { $0.id == id }) else { return }
            self.discovered.append((id: id, name: name))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "Heart rate monitor"
        Task { @MainActor in
            self.state = .connected(name: name)
        }
        peripheral.discoverServices([Self.hrService])
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.latestBPM = nil
            self.state = .idle
            // A strap dropping mid-session (range, battery) should come
            // back on its own — CoreBluetooth connect requests don't
            // expire, so re-issue one for the remembered device.
            self.connectRememberedIfAny()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.hrService }) else { return }
        peripheral.discoverCharacteristics([Self.hrMeasurement], for: service)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.hrMeasurement }) else { return }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard characteristic.uuid == Self.hrMeasurement, let data = characteristic.value else { return }
        Task { @MainActor in
            self.handleMeasurement(data)
        }
    }
}
