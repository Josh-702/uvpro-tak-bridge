// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Identity of the project. The maintainer callsign is attribution only.
/// The transmit callsign defaults to blank so a fresh install cannot key a radio.
public enum UVBridgeCore {
    public static let version = "0.1.0"
    public static let name = "Open UV Bridge"
    public static let maintainer = "Josh Howard"
    public static let maintainerCallsign = "WA7BRM"
    public static let maintainerLicenseClass = "General"
    public static let maintainerQTH = "Las Vegas, Nevada"
    public static let license = "Apache-2.0"

    /// 47 CFR 97.113. There is no cipher on the RF path, and this cannot be turned on.
    public static let radioEncryptionAvailable = false
}

/// Copy the radio UI shows. Kept here so tests lock the operator-facing wording.
public enum OperatorHint {
    public static let radioBusy =
        "The radio is already on a Bluetooth link. Quit the BTECH, Radioddity, Vero, or other HT app that is using it, then connect again."

    public static let offline =
        "No network. iTAK stays on the on-phone server. APRS is radio to radio, and anything for your TAK server waits here until the link returns."

    public static let bridging =
        "Online. iTAK is still using only the on-phone server. RF stations are also bridged to your TAK server."

    public static let serverUnreachable =
        "The phone has a network path, but your TAK server is not answering. iTAK is unaffected. Server traffic stays queued and will be retried."

    public static let onlineLocalOnly =
        "The phone is online and no TAK server is configured. iTAK and the radio still work together on this phone."

    public static let addToITAKOnce =
        "Import this data package into iTAK once. Leave that server entry in place. Offline and online both use it, so you never reconfigure iTAK."

    public static let part97Clear =
        "Amateur radio is not encrypted here. Your callsign is sent in the clear on every transmission. 47 CFR 97.113."

    public static let emergencyEncryptionWarning =
        "Normal amateur operation prohibits encryption, 47 CFR 97.113(a)(4). In an emergency, 47 CFR 97.403 allows any means necessary for the immediate safety of life or property. You are responsible for that decision. The callsign stays in the clear. This switch does nothing in public APRS mode."
}

public enum Hex {
    public static func encode(_ data: Data, separator: String = "") -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: separator)
    }

    public static func decode(_ string: String) -> Data? {
        let cleaned = string.filter { !$0.isWhitespace && $0 != ":" }
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}

public enum Callsign {
    /// AX.25 base call: 3 to 6 characters, at least one letter and one digit.
    public static func isValidBase(_ raw: String) -> Bool {
        let value = raw.uppercased()
        guard (3...6).contains(value.count) else { return false }
        guard value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
        guard value.contains(where: \.isLetter), value.contains(where: \.isNumber) else { return false }
        return true
    }

    public static func parse(_ raw: String) -> (base: String, ssid: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let base = String(parts[0])
        guard isValidBase(base) else { return nil }
        if parts.count == 1 { return (base, 0) }
        guard let ssid = Int(parts[1]), (0...15).contains(ssid) else { return nil }
        return (base, ssid)
    }

    public static func display(base: String, ssid: Int) -> String {
        let call = base.uppercased()
        return ssid == 0 ? call : "\(call)-\(ssid)"
    }
}
