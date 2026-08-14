import Foundation
import CoreBluetooth

/// Standalone Bluetooth attendance — a SEPARATE method from face recognition.
///
/// Teacher role  = scans for nearby student phones and gathers their register numbers.
/// Student role  = advertises "I'm here" as a Bluetooth peripheral.
/// Proximity is gated by signal strength (RSSI) so only in-room phones count.
///
/// Foreground only: iOS throttles background BLE hard, so both sides keep the screen
/// open for the ~20s check-in. Needs Info.plist NSBluetoothAlwaysUsageDescription.
final class ProximityService: NSObject, ObservableObject {
    /// App-specific service so we only see our own students, not every BLE device.
    static let serviceUUID = CBUUID(string: "A1B2C3D4-1111-2222-3333-444455556666")
    private static let prefix = "ATT:"          // advertised name = "ATT:<register>"

    struct Nearby: Identifiable {
        let register: String
        var rssi: Int
        var lastSeen: Date
        var id: String { register }
    }

    enum Mode { case idle, teacher, student }

    @Published var nearby: [Nearby] = []        // teacher: students detected (sorted, closest first)
    @Published var mode: Mode = .idle
    @Published var status = "Idle"

    /// Signal-strength gate for "in the room" (closer = higher / less negative).
    /// -80 ≈ same room; raise toward -60 to require sitting near the teacher.
    @Published var rssiThreshold = -80

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var advertiseName = ""
    private var seen: [String: Nearby] = [:]
    private var pruneTimer: Timer?

    /// Students currently in range (pass the RSSI gate) — the "present" set.
    var presentRegisters: Set<String> {
        Set(nearby.filter { $0.rssi >= rssiThreshold }.map { $0.register })
    }

    // MARK: teacher (scan)
    func startTeacher() {
        stop()
        mode = .teacher
        seen = [:]; nearby = []
        central = CBCentralManager(delegate: self, queue: .main)
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.prune()
        }
    }

    // MARK: student (advertise)
    func startStudent(register: String) {
        stop()
        mode = .student
        advertiseName = Self.prefix + register
        peripheral = CBPeripheralManager(delegate: self, queue: .main)
    }

    func stop() {
        central?.stopScan(); central = nil
        peripheral?.stopAdvertising(); peripheral = nil
        pruneTimer?.invalidate(); pruneTimer = nil
        mode = .idle
        status = "Idle"
    }

    /// Drop students not seen for a few seconds (they left the room / closed the app).
    private func prune() {
        let cutoff = Date().addingTimeInterval(-6)
        seen = seen.filter { $0.value.lastSeen > cutoff }
        nearby = seen.values.sorted { $0.rssi > $1.rssi }
    }
}

// MARK: - Teacher: scanning
extension ProximityService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            status = "Scanning for students…"
            c.scanForPeripherals(withServices: [Self.serviceUUID],
                                 options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        case .poweredOff:   status = "Turn Bluetooth on"
        case .unauthorized: status = "Allow Bluetooth in Settings → ClassAttendance"
        default:            status = "Bluetooth unavailable"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              name.hasPrefix(Self.prefix) else { return }
        let reg = String(name.dropFirst(Self.prefix.count))
        seen[reg] = Nearby(register: reg, rssi: RSSI.intValue, lastSeen: Date())
        nearby = seen.values.sorted { $0.rssi > $1.rssi }
    }
}

// MARK: - Student: advertising
extension ProximityService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        switch p.state {
        case .poweredOn:
            status = "Broadcasting your presence…"
            p.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
                CBAdvertisementDataLocalNameKey: advertiseName,
            ])
        case .poweredOff:   status = "Turn Bluetooth on"
        case .unauthorized: status = "Allow Bluetooth in Settings → ClassAttendance"
        default:            status = "Bluetooth unavailable"
        }
    }
}
