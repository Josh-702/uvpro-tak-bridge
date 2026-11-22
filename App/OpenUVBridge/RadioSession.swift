// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import CoreBluetooth
import Foundation
import UVBridgeCore

/// BLE central for the open KISS GATT service. The same UUIDs are used by the
/// UV-PRO, Mobilinkd TNC3/TNC4, PicoAPRS, VR-N76, and GA-5WB.
final class RadioSession: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var owner: AppModel?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var tx: CBCharacteristic?
    private var controlTX: CBCharacteristic?
    private var pendingControl: [Data] = []
    private var connectedAt: Date?
    private var seen: [UUID: RadioAdvertisement] = [:]
    private let restoreID = "net.wa7brm.openuvbridge.central"

    func start() {
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreID]
        )
    }

    func connect(_ id: UUID) {
        guard let central else { return }
        let match = central.retrievePeripherals(withIdentifiers: [id]).first
        guard let match else {
            owner?.setRadioStatus("That radio is no longer advertising", hint: OperatorHint.radioBusy)
            return
        }
        peripheral = match
        match.delegate = self
        connectedAt = nil
        central.stopScan()
        central.connect(match, options: nil)
        owner?.setRadioStatus("Connecting to \(match.name ?? "radio")", hint: nil)
    }

    func write(_ frame: Data) {
        guard let peripheral, let tx else { return }
        let chunk = peripheral.maximumWriteValueLength(for: .withResponse)
        let size = max(20, chunk)
        var offset = 0
        let bytes = [UInt8](frame)
        while offset < bytes.count {
            let end = min(offset + size, bytes.count)
            peripheral.writeValue(Data(bytes[offset..<end]), for: tx, type: .withResponse)
            offset = end
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            owner?.setRadioStatus("Looking for a KISS TNC", hint: nil)
            restoreOrScan(central)
        case .poweredOff:
            owner?.setRadioStatus("Bluetooth is off", hint: nil)
        case .unauthorized:
            owner?.setRadioStatus("Bluetooth permission is off for Open UV Bridge", hint: nil)
        case .unsupported:
            owner?.setRadioStatus("This iPhone has no Bluetooth LE", hint: nil)
        default:
            owner?.setRadioStatus("Bluetooth is starting", hint: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        if let first = restored.first {
            peripheral = first
            first.delegate = self
            central.connect(first, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "KISS TNC"
        seen[peripheral.identifier] = RadioAdvertisement(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        owner?.setDiscovered(Array(seen.values).sorted { $0.name < $1.name })
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedAt = Date()
        owner?.setRadioStatus("Connected to \(peripheral.name ?? "radio")", hint: nil)
        owner?.radioLink(true)
        peripheral.discoverServices([
            CBUUID(string: BLEKISS.serviceUUID),
            CBUUID(string: BenshiLink.serviceUUID),
        ])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        owner?.radioLink(false)
        owner?.setRadioStatus("Could not connect", hint: OperatorHint.radioBusy)
        scan(central)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        owner?.radioLink(false)
        let quick = connectedAt.map { Date().timeIntervalSince($0) < 2 } ?? false
        owner?.setRadioStatus("Radio link dropped", hint: quick || error != nil ? OperatorHint.radioBusy : nil)
        tx = nil
        scan(central)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let kiss = peripheral.services?.first { $0.uuid == CBUUID(string: BLEKISS.serviceUUID) }
        let control = peripheral.services?.first { $0.uuid == CBUUID(string: BenshiLink.serviceUUID) }
        guard let kiss else {
            owner?.setRadioStatus("This radio did not offer the KISS service", hint: OperatorHint.radioBusy)
            return
        }
        peripheral.discoverCharacteristics(
            [CBUUID(string: BLEKISS.transmitCharacteristicUUID), CBUUID(string: BLEKISS.receiveCharacteristicUUID)],
            for: kiss
        )
        if let control {
            peripheral.discoverCharacteristics(
                [CBUUID(string: BenshiLink.writeUUID), CBUUID(string: BenshiLink.indicateUUID)],
                for: control
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == CBUUID(string: BLEKISS.receiveCharacteristicUUID) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.uuid == CBUUID(string: BLEKISS.transmitCharacteristicUUID) {
                tx = characteristic
            }
            if characteristic.uuid == CBUUID(string: BenshiLink.indicateUUID) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.uuid == CBUUID(string: BenshiLink.writeUUID) {
                controlTX = characteristic
            }
        }
        if service.uuid == CBUUID(string: BLEKISS.serviceUUID), tx == nil {
            owner?.setRadioStatus("KISS transmit characteristic missing", hint: OperatorHint.radioBusy)
        }
        if controlTX != nil {
            owner?.radioControlReady()
            send(BenshiRadio.getStatusRequest())
            send(BenshiRadio.batteryRequest())
            send(BenshiRadio.volumeRequest())
            for id in 0..<16 {
                send(BenshiRadio.readChannelRequest(id))
            }
        }
    }

    func send(_ message: BenshiMessage) {
        guard let peripheral, let controlTX else { return }
        peripheral.writeValue(message.bytes, for: controlTX, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, !value.isEmpty else { return }
        if characteristic.uuid == CBUUID(string: BenshiLink.indicateUUID) {
            if let message = BenshiMessage(bytes: value) {
                owner?.radioControl(message)
            }
            return
        }
        owner?.radioBytes(value)
    }

    private func restoreOrScan(_ central: CBCentralManager) {
        let known = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: BLEKISS.serviceUUID)])
        if let first = known.first {
            peripheral = first
            first.delegate = self
            central.connect(first, options: nil)
        }
        scan(central)
    }

    private func scan(_ central: CBCentralManager) {
        central.scanForPeripherals(
            withServices: [CBUUID(string: BLEKISS.serviceUUID)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}
