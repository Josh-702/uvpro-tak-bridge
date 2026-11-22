// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Original codec for the published Benshi radio command layout.
/// BLE uses a different GATT service from KISS, so both can stay up together.
/// The classic-Bluetooth form of the same commands is the documented GAIA frame
/// (0xFF 0x01, flags, length, command bytes). This type is the BLE message.
public enum BenshiLink {
    public static let serviceUUID = "00001100-D102-11E1-9B23-00025B00A5A5"
    public static let writeUUID = "00001101-D102-11E1-9B23-00025B00A5A5"
    public static let indicateUUID = "00001102-D102-11E1-9B23-00025B00A5A5"
}

public enum BenshiCommand {
    public static let groupBasic = 2
    public static let readStatus = 5
    public static let readChannel = 13
    public static let writeChannel = 14
    public static let readSettings = 10
    public static let writeSettings = 11
    public static let getStatus = 20
    public static let getVolume = 22
    public static let setVolume = 23
    public static let batteryPercentage = 4
}

public enum TXPower: String, Codable, Equatable {
    case low
    case medium
    case high
}

public struct BenshiMessage: Equatable {
    public var group: Int
    public var isReply: Bool
    public var command: Int
    public var body: Data

    public init(group: Int = BenshiCommand.groupBasic, isReply: Bool = false, command: Int, body: Data = Data()) {
        self.group = group
        self.isReply = isReply
        self.command = command
        self.body = body
    }

    public var bytes: Data {
        var buffer = BitBuffer()
        buffer.append(group, width: 16)
        buffer.append(isReply ? 1 : 0, width: 1)
        buffer.append(command, width: 15)
        buffer.append(body)
        return buffer.data
    }

    public init?(bytes: Data) {
        var buffer = BitBuffer(bytes)
        guard let group = buffer.read(16),
              let reply = buffer.read(1),
              let command = buffer.read(15)
        else { return nil }
        self.group = group
        self.isReply = reply == 1
        self.command = command
        self.body = buffer.remainingBytes()
    }
}

public struct RadioChannel: Equatable {
    public var id: Int
    public var name: String
    public var receiveMHz: Double
    public var power: TXPower

    public init(id: Int, name: String, receiveMHz: Double, power: TXPower) {
        self.id = id
        self.name = name
        self.receiveMHz = receiveMHz
        self.power = power
    }
}

public struct RadioStatus: Equatable {
    public var poweredOn: Bool
    public var transmitting: Bool
    public var receiving: Bool
    public var channelID: Int
    public var batteryPercent: Int?

    public init(poweredOn: Bool, transmitting: Bool, receiving: Bool, channelID: Int, batteryPercent: Int? = nil) {
        self.poweredOn = poweredOn
        self.transmitting = transmitting
        self.receiving = receiving
        self.channelID = channelID
        self.batteryPercent = batteryPercent
    }
}

public enum BenshiRadio {
    public static func getStatusRequest() -> BenshiMessage {
        BenshiMessage(command: BenshiCommand.getStatus)
    }

    public static func batteryRequest() -> BenshiMessage {
        var body = BitBuffer()
        body.append(BenshiCommand.batteryPercentage, width: 16)
        return BenshiMessage(command: BenshiCommand.readStatus, body: body.data)
    }

    public static func readChannelRequest(_ id: Int) -> BenshiMessage {
        var body = BitBuffer()
        body.append(id, width: 8)
        return BenshiMessage(command: BenshiCommand.readChannel, body: body.data)
    }

    public static func volumeRequest() -> BenshiMessage {
        BenshiMessage(command: BenshiCommand.getVolume)
    }

    public static func setVolumeRequest(_ level: Int) -> BenshiMessage {
        var body = BitBuffer()
        body.append(min(15, max(0, level)), width: 8)
        return BenshiMessage(command: BenshiCommand.setVolume, body: body.data)
    }

    public static func readSettingsRequest() -> BenshiMessage {
        BenshiMessage(command: BenshiCommand.readSettings)
    }

    public static func writeSettingsRequest(_ settings: Data) -> BenshiMessage {
        BenshiMessage(command: BenshiCommand.writeSettings, body: settings)
    }

    public static func writeChannelRequest(_ channelBody: Data) -> BenshiMessage {
        BenshiMessage(command: BenshiCommand.writeChannel, body: channelBody)
    }

    public static func status(from reply: BenshiMessage) -> RadioStatus? {
        guard reply.isReply, reply.command == BenshiCommand.getStatus else { return nil }
        var bits = BitBuffer(reply.body)
        guard let code = bits.read(8), code == 0 else { return nil }
        guard let on = bits.read(1), let tx = bits.read(1), bits.read(1) != nil, let rx = bits.read(1),
              bits.read(2) != nil, bits.read(1) != nil, bits.read(1) != nil,
              let lower = bits.read(4)
        else { return nil }
        var upper = 0
        // Basic status has 4 bits left. The extended form adds rssi, region, then the high channel nibble.
        if bits.read(4) != nil, bits.read(4) != nil, bits.read(6) != nil, let high = bits.read(4) {
            upper = high
        }
        let channel = ((upper & 0x0F) << 4) | (lower & 0x0F)
        return RadioStatus(poweredOn: on == 1, transmitting: tx == 1, receiving: rx == 1, channelID: channel)
    }

    public static func batteryPercent(from reply: BenshiMessage) -> Int? {
        guard reply.isReply, reply.command == BenshiCommand.readStatus else { return nil }
        var bits = BitBuffer(reply.body)
        guard let code = bits.read(8), code == 0, let kind = bits.read(16), kind == BenshiCommand.batteryPercentage else {
            return nil
        }
        return bits.read(8)
    }

    public static func volume(from reply: BenshiMessage) -> Int? {
        guard reply.isReply, reply.command == BenshiCommand.getVolume else { return nil }
        var bits = BitBuffer(reply.body)
        guard let code = bits.read(8), code == 0 else { return nil }
        return bits.read(8)
    }

    /// Channel memory after the reply-status byte.
    public static func channel(from reply: BenshiMessage) -> RadioChannel? {
        guard reply.isReply, reply.command == BenshiCommand.readChannel else { return nil }
        var bits = BitBuffer(reply.body)
        guard let code = bits.read(8), code == 0 else { return nil }
        return channel(fromBody: bits.remainingBytes())
    }

    public static func channel(fromBody body: Data) -> RadioChannel? {
        var bits = BitBuffer(body)
        guard let id = bits.read(8),
              bits.read(2) != nil,
              let tx = bits.read(30),
              bits.read(2) != nil,
              let rx = bits.read(30),
              bits.read(16) != nil,
              bits.read(16) != nil,
              bits.read(1) != nil,
              let maxPower = bits.read(1)
        else { return nil }
        _ = tx
        guard bits.read(1) != nil, bits.read(1) != nil, bits.read(1) != nil, bits.read(1) != nil,
              let medPower = bits.read(1)
        else { return nil }
        let power: TXPower = maxPower == 1 ? .high : (medPower == 1 ? .medium : .low)
        // Skip the remaining fixed flag bits (4 pad included) to land on the 10-byte name.
        // Flags consumed after sub-audio: scan, max, talk, bandwidth, pre, sign, med = 7.
        // Remaining before name: tx_disable, fixed_freq, fixed_bandwidth, fixed_tx_power, mute, pad4 = 9.
        guard bits.read(9) != nil else { return nil }
        let nameBytes = bits.remainingBytes().prefix(10)
        let name = String(bytes: nameBytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        return RadioChannel(id: id, name: name.trimmingCharacters(in: .whitespaces), receiveMHz: Double(rx) / 1_000_000, power: power)
    }

    public static func setPower(_ power: TXPower, inChannelBody body: Data) -> Data? {
        var bits = BitBuffer(body)
        guard bits.read(8 + 2 + 30 + 2 + 30 + 16 + 16 + 1) != nil else { return nil }
        let maxIndex = bits.cursor
        guard bits.read(1 + 1 + 1 + 1 + 1) != nil else { return nil }
        let medIndex = bits.cursor
        var patched = body
        patched = setBit(patched, index: maxIndex, value: power == .high)
        patched = setBit(patched, index: medIndex, value: power == .medium)
        return patched
    }

    /// Selected memory is split into a low nibble at bit 0 and a high nibble at bit 80.
    public static func selectedChannel(in settingsBody: Data) -> Int? {
        guard let lower = bitValue(settingsBody, at: 0, width: 4),
              let upper = bitValue(settingsBody, at: 80, width: 4)
        else { return nil }
        return (upper << 4) | lower
    }

    public static func settingSelectedChannel(_ id: Int, in settingsBody: Data) -> Data? {
        guard bitValue(settingsBody, at: 80, width: 4) != nil else { return nil }
        var patched = settingsBody
        patched = setBits(patched, at: 0, width: 4, value: id & 0x0F)
        patched = setBits(patched, at: 80, width: 4, value: (id >> 4) & 0x0F)
        return patched
    }

    private static func bitValue(_ data: Data, at index: Int, width: Int) -> Int? {
        var bits = BitBuffer(data)
        guard bits.read(index) != nil else { return nil }
        return bits.read(width)
    }

    private static func setBit(_ data: Data, index: Int, value: Bool) -> Data {
        setBits(data, at: index, width: 1, value: value ? 1 : 0)
    }

    private static func setBits(_ data: Data, at index: Int, width: Int, value: Int) -> Data {
        var bytes = [UInt8](data)
        for offset in 0..<width {
            let bitIndex = index + offset
            let byte = bitIndex / 8
            guard byte < bytes.count else { break }
            let mask = UInt8(1 << (7 - (bitIndex % 8)))
            let bit = ((value >> (width - 1 - offset)) & 1) == 1
            if bit { bytes[byte] |= mask } else { bytes[byte] &= ~mask }
        }
        return Data(bytes)
    }
}

struct BitBuffer {
    private var bytes: [UInt8]
    var cursor = 0

    init(_ data: Data = Data()) {
        bytes = [UInt8](data)
    }

    var data: Data { Data(bytes) }

    mutating func append(_ value: Int, width: Int) {
        for offset in 0..<width {
            let bit = ((value >> (width - 1 - offset)) & 1) == 1
            appendBit(bit)
        }
    }

    mutating func append(_ data: Data) {
        for byte in data { append(Int(byte), width: 8) }
    }

    mutating func read(_ width: Int) -> Int? {
        guard cursor + width <= bytes.count * 8 else { return nil }
        var value = 0
        for _ in 0..<width {
            let bit = (bytes[cursor / 8] >> (7 - (cursor % 8))) & 1
            value = (value << 1) | Int(bit)
            cursor += 1
        }
        return value
    }

    func remainingBytes() -> Data {
        var copy = self
        var out = Data()
        while let byte = copy.read(8) {
            out.append(UInt8(byte))
        }
        return out
    }

    private mutating func appendBit(_ one: Bool) {
        let byte = cursor / 8
        if bytes.count == byte { bytes.append(0) }
        if one { bytes[byte] |= 1 << (7 - (cursor % 8)) }
        cursor += 1
    }
}
