import Foundation
import CoreBluetooth

// Exposes the phone-side GATT database the EKD01-BF probes while the app is
// connected as BLE central. No advertising is needed: the bike discovers these
// services after the app connects to its UART service.
class GattPeripheral: NSObject, CBPeripheralManagerDelegate {

    static let shared = GattPeripheral()

    private var pm: CBPeripheralManager!
    private var batteryChar: CBMutableCharacteristic?
    private var currentTimeChar: CBMutableCharacteristic?
    private var localTimeChar: CBMutableCharacteristic?
    private var readableValues: [String: Data] = [:]
    private var servicesAdded = 0

    private override init() {
        super.init()
        pm = CBPeripheralManager(delegate: self, queue: nil)
    }

    // MARK: – CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        addServices()
    }

    private func addServices() {
        guard servicesAdded == 0 else { return }

        addDeviceInformationService()
        addBikeGoCustomServices()

        // Battery Service 0x180F
        let batterySvc = CBMutableService(type: CBUUID(string: "180F"), primary: true)
        batteryChar = CBMutableCharacteristic(
            type: CBUUID(string: "2A19"),
            properties: [.read, .notify],
            value: nil,
            permissions: .readable
        )
        batterySvc.characteristics = [batteryChar!]
        pm.add(batterySvc)

        // Current Time Service 0x1805
        let ctsSvc = CBMutableService(type: CBUUID(string: "1805"), primary: true)
        currentTimeChar = CBMutableCharacteristic(
            type: CBUUID(string: "2A2B"),
            properties: [.read, .notify],
            value: nil,
            permissions: .readable
        )
        localTimeChar = CBMutableCharacteristic(
            type: CBUUID(string: "2A0F"),
            properties: .read,
            value: nil,
            permissions: .readable
        )
        ctsSvc.characteristics = [currentTimeChar!, localTimeChar!]
        pm.add(ctsSvc)
        servicesAdded += 3
    }

    private func addDeviceInformationService() {
        let disSvc = CBMutableService(type: CBUUID(string: "180A"), primary: true)
        let manufacturer = readableCharacteristic("2A29", value: "Bafang".data(using: .utf8)!)
        let model = readableCharacteristic("2A24", value: "EKD01-BF".data(using: .utf8)!)
        disSvc.characteristics = [manufacturer, model]
        pm.add(disSvc)
        servicesAdded += 1
    }

    private func addBikeGoCustomServices() {
        let specs: [(service: String, chars: [(uuid: String, props: CBCharacteristicProperties)])] = [
            (
                service: "d0611e78-bbb4-4591-a5f8-487910ae4366",
                chars: [
                    ("8667556c-9a37-4c91-84ed-54ee27d90049", [.write, .notify]),
                ]
            ),
            (
                service: "9fa480e0-4967-4542-9390-d343dc5d04ae",
                chars: [
                    ("af0badb1-5b99-43cd-917a-a77bc549e3cc", [.write, .notify]),
                ]
            ),
            (
                service: "7905f431-b5ce-4e99-a40f-4b1e122d00d0",
                chars: [
                    ("69d1d8f3-45e1-49a8-9821-9bbdfdaad9d9", [.write, .notify]),
                    ("9fbf120d-6301-42d9-8c58-25e699a21dbd", [.notify]),
                    ("22eac6e9-24d6-4bb5-be44-b36ace7c7bfb", [.notify]),
                ]
            ),
            (
                service: "89d3502b-0f36-433a-8ef4-c502ad55f8dc",
                chars: [
                    ("9b3c81d8-57b1-4a8a-b8df-0e56f7ca51c2", [.write, .notify]),
                    ("2f7cabce-808d-411f-9a0c-bb92ba96c102", [.write, .notify]),
                    ("c6b2f38c-23ab-46d8-a6ab-a3a870bbd5d7", [.read, .write, .notify]),
                ]
            ),
            (
                service: "410cd5ed-2f82-4f77-8916-ab5f5010368f",
                chars: [
                    ("f7da4085-bbe7-42f4-9727-6ca60fe3a1a5", [.writeWithoutResponse, .notify]),
                ]
            ),
        ]

        for spec in specs {
            let service = CBMutableService(type: CBUUID(string: spec.service), primary: true)
            service.characteristics = spec.chars.map { uuid, props in
                return CBMutableCharacteristic(
                    type: CBUUID(string: uuid),
                    properties: props,
                    value: nil,
                    permissions: permissions(for: props)
                )
            }
            pm.add(service)
            servicesAdded += 1
        }
    }

    private func permissions(for properties: CBCharacteristicProperties) -> CBAttributePermissions {
        var permissions = CBAttributePermissions()
        if properties.contains(.read) { permissions.insert(.readable) }
        if properties.contains(.write) || properties.contains(.writeWithoutResponse) {
            permissions.insert(.writeable)
        }
        return permissions
    }

    private func readableCharacteristic(_ uuid: String, value: Data) -> CBMutableCharacteristic {
        readableValues[uuid.uppercased()] = value
        return CBMutableCharacteristic(
            type: CBUUID(string: uuid),
            properties: .read,
            value: nil,
            permissions: .readable
        )
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        switch request.characteristic.uuid.uuidString.uppercased() {
        case "2A29", "2A24":
            request.value = readableValues[request.characteristic.uuid.uuidString.uppercased()]
            peripheral.respond(to: request, withResult: .success)
        case "2A19":
            request.value = Data([100])
            peripheral.respond(to: request, withResult: .success)
        case "2A2B":
            request.value = currentTimeValue()
            peripheral.respond(to: request, withResult: .success)
        case "2A0F":
            request.value = localTimeValue()
            peripheral.respond(to: request, withResult: .success)
        case "c6b2f38c-23ab-46d8-a6ab-a3a870bbd5d7".uppercased():
            request.value = Data([1])
            peripheral.respond(to: request, withResult: .success)
        default:
            peripheral.respond(to: request, withResult: .attributeNotFound)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests { peripheral.respond(to: req, withResult: .success) }
    }

    // MARK: – CTS payload helpers

    private func currentTimeValue() -> Data {
        let cal  = Calendar.current
        let now  = Date()
        let c    = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
        let year = UInt16(c.year ?? 2024)
        // CTS day-of-week: 1=Monday … 7=Sunday; Calendar: 1=Sunday, 2=Monday … 7=Saturday
        let dow  = c.weekday ?? 1
        let ctsDow = dow == 1 ? 7 : UInt8(dow - 1)
        return Data([
            UInt8(year & 0xFF), UInt8(year >> 8),
            UInt8(c.month  ?? 1),
            UInt8(c.day    ?? 1),
            UInt8(c.hour   ?? 0),
            UInt8(c.minute ?? 0),
            UInt8(c.second ?? 0),
            ctsDow,
            0,   // fractions256
            0,   // adjust reason
        ])
    }

    private func localTimeValue() -> Data {
        let secs    = TimeZone.current.secondsFromGMT()
        let offset  = Int8(exactly: secs / 900) ?? 0   // units of 15 min
        let dstSecs = TimeZone.current.daylightSavingTimeOffset()
        let dst: UInt8
        switch Int(dstSecs) {
        case  3600: dst = 4   // +1h
        case  7200: dst = 8   // +2h
        case  1800: dst = 2   // +0.5h
        default:    dst = 0
        }
        return Data([UInt8(bitPattern: offset), dst])
    }
}
