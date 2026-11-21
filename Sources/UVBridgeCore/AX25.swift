// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct AX25Address: Equatable, Codable {
    public var call: String
    public var ssid: Int
    public var repeated: Bool

    public init(call: String, ssid: Int = 0, repeated: Bool = false) {
        self.call = call.uppercased()
        self.ssid = min(15, max(0, ssid))
        self.repeated = repeated
    }

    public var display: String {
        ssid == 0 ? call : "\(call)-\(ssid)"
    }

    func encoded(isLast: Bool) -> [UInt8]? {
        guard (1...6).contains(call.count) else { return nil }
        guard call.allSatisfy({ $0.isASCII && $0.asciiValue! >= 0x20 && $0.asciiValue! < 0x7F }) else {
            return nil
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(7)
        for scalar in call.utf8 {
            bytes.append(scalar << 1)
        }
        while bytes.count < 6 {
            bytes.append(0x20 << 1)
        }
        var ssidByte: UInt8 = 0x60 | UInt8((ssid & 0x0F) << 1)
        if repeated { ssidByte |= 0x80 }
        if isLast { ssidByte |= 0x01 }
        bytes.append(ssidByte)
        return bytes
    }

    static func decode(_ bytes: ArraySlice<UInt8>) -> AX25Address? {
        guard bytes.count == 7 else { return nil }
        var chars: [UInt8] = []
        for offset in 0..<6 {
            let raw = bytes[bytes.startIndex + offset] >> 1
            if raw != 0x20 { chars.append(raw) }
        }
        guard let call = String(bytes: chars, encoding: .ascii), !call.isEmpty else { return nil }
        let ssidByte = bytes[bytes.startIndex + 6]
        let ssid = Int((ssidByte >> 1) & 0x0F)
        let repeated = (ssidByte & 0x80) != 0
        return AX25Address(call: call, ssid: ssid, repeated: repeated)
    }
}

public struct AX25Frame: Equatable {
    public var destination: AX25Address
    public var source: AX25Address
    public var digipeaters: [AX25Address]
    public var control: UInt8
    public var pid: UInt8
    public var info: Data

    public init(
        destination: AX25Address,
        source: AX25Address,
        digipeaters: [AX25Address] = [],
        control: UInt8 = 0x03,
        pid: UInt8 = 0xF0,
        info: Data
    ) {
        self.destination = destination
        self.source = source
        self.digipeaters = digipeaters
        self.control = control
        self.pid = pid
        self.info = info
    }

    /// UI frame, including the poll/final variant 0x13.
    public var isUI: Bool { (control & 0xEF) == 0x03 }

    public func encode() -> Data? {
        var addresses: [AX25Address] = [destination, source]
        addresses.append(contentsOf: digipeaters)
        guard addresses.count >= 2, addresses.count <= 10 else { return nil }
        var bytes: [UInt8] = []
        for (index, address) in addresses.enumerated() {
            guard let encoded = address.encoded(isLast: index == addresses.count - 1) else { return nil }
            bytes.append(contentsOf: encoded)
        }
        bytes.append(control)
        bytes.append(pid)
        bytes.append(contentsOf: info)
        return Data(bytes)
    }

    public static func decode(_ data: Data) -> AX25Frame? {
        let bytes = [UInt8](data)
        var index = 0
        var addresses: [AX25Address] = []
        var sawLast = false
        while addresses.count < 10, index + 7 <= bytes.count {
            let slice = bytes[index..<(index + 7)]
            guard let address = AX25Address.decode(slice) else { return nil }
            addresses.append(address)
            let last = (bytes[index + 6] & 0x01) != 0
            index += 7
            if last {
                sawLast = true
                break
            }
        }
        guard sawLast, addresses.count >= 2, index + 2 <= bytes.count else { return nil }
        let control = bytes[index]
        let pid = bytes[index + 1]
        let info = Data(bytes[(index + 2)...])
        return AX25Frame(
            destination: addresses[0],
            source: addresses[1],
            digipeaters: Array(addresses.dropFirst(2)),
            control: control,
            pid: pid,
            info: info
        )
    }

    public var monitor: String {
        let via = digipeaters.map { $0.repeated ? "\($0.display)*" : $0.display }
        let path = ([destination.display] + via).joined(separator: ",")
        let text = String(info.map { byte in
            if byte >= 0x20 && byte < 0x7F { return Character(UnicodeScalar(byte)) }
            return "·"
        })
        return "\(source.display)>\(path):\(text)"
    }

    /// `WIDE1-1,WIDE2-1` style. Empty is a direct path and is valid.
    public static func digipeaters(fromPath path: String) -> [AX25Address]? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        var result: [AX25Address] = []
        for raw in trimmed.split(separator: ",") {
            let piece = raw.trimmingCharacters(in: .whitespaces)
            guard let parsed = parseDigi(piece) else { return nil }
            result.append(parsed)
        }
        guard result.count <= 8 else { return nil }
        return result
    }

    private static func parseDigi(_ raw: String) -> AX25Address? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let call = String(parts[0]).uppercased()
        guard (1...6).contains(call.count) else { return nil }
        guard call.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        var ssid = 0
        if parts.count == 2 {
            guard let value = Int(parts[1]), (0...15).contains(value) else { return nil }
            ssid = value
        }
        return AX25Address(call: call, ssid: ssid)
    }
}
