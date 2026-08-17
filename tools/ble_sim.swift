// Bluetooth test helper: makes your Mac act as a fake student (or teacher) so you
// can test the iPhone's Bluetooth attendance with just a Mac + one phone.
//
//   student mode (Mac pretends to be a student the iPhone teacher will detect):
//     swift tools/ble_sim.swift student RA2411026010074
//
//   teacher mode (Mac scans; open "Student check-in" on the iPhone to be seen):
//     swift tools/ble_sim.swift teacher
//
// First run: macOS asks to let Terminal use Bluetooth -> Allow. Ctrl-C to stop.
import Foundation
import CoreBluetooth

let serviceUUID = CBUUID(string: "A1B2C3D4-1111-2222-3333-444455556666")
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "student"
let register = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "RA2411026010074"

func stateHint(_ raw: Int) -> String {
    raw == 5 ? "poweredOn ✓"
        : "state \(raw) — if not 5, enable Bluetooth and allow Terminal in System Settings › Privacy & Security › Bluetooth"
}

final class Student: NSObject, CBPeripheralManagerDelegate {
    var pm: CBPeripheralManager!
    override init() { super.init(); pm = CBPeripheralManager(delegate: self, queue: nil) }
    func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        print("Bluetooth:", stateHint(p.state.rawValue))
        guard p.state == .poweredOn else { return }
        p.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
                            CBAdvertisementDataLocalNameKey: "ATT:\(register)"])
        print("📡 Advertising as ATT:\(register) — open 'Bluetooth Attendance' on the iPhone. Ctrl-C to stop.")
    }
}

final class Teacher: NSObject, CBCentralManagerDelegate {
    var cm: CBCentralManager!
    override init() { super.init(); cm = CBCentralManager(delegate: self, queue: nil) }
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        print("Bluetooth:", stateHint(c.state.rawValue))
        guard c.state == .poweredOn else { return }
        print("🔍 Scanning — open 'Settings › Student check-in' on the iPhone and tap Check in.")
        c.scanForPeripherals(withServices: [serviceUUID],
                             options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let n = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              n.hasPrefix("ATT:") else { return }
        print("✅ Detected \(n)   signal \(RSSI) dBm")
    }
}

let runner: AnyObject = (mode == "teacher") ? Teacher() : Student()
_ = runner
RunLoop.main.run()
