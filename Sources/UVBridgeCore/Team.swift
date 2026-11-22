// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Team mode is the default. Public APRS is available and starts off.
public enum OperatingMode: String, Codable, Equatable {
    case team
    case publicAPRS
}

public enum TeamPolicy {
    /// 144.390 MHz is the North American APRS calling frequency.
    public static let nationalAPRSCallingMHz = 144.390
    public static let publicDigipeaterPath = "WIDE1-1,WIDE2-1"

    public static func defaultPath(for mode: OperatingMode) -> String {
        mode == .team ? "" : publicDigipeaterPath
    }

    public static func allowsBeacon(mode: OperatingMode, teamChannelSet: Bool) -> Bool {
        switch mode {
        case .publicAPRS: return true
        case .team: return teamChannelSet
        }
    }

    public static func isNationalAPRSCallingFrequency(megahertz: Double) -> Bool {
        abs(megahertz - nationalAPRSCallingMHz) < 0.0025
    }

    /// Roster entries are base callsigns. SSID is ignored.
    public static func baseCallsign(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Callsign.parse(trimmed)?.base
    }

    public static func rosterAllows(_ callsign: String, roster: some Sequence<String>) -> Bool {
        guard let base = baseCallsign(callsign) else { return false }
        let allowed = Set(roster.compactMap(baseCallsign))
        return allowed.contains(base)
    }
}

public struct EncryptionAudit: Codable, Equatable {
    public var time: Date
    public var enabled: Bool

    public init(time: Date, enabled: Bool) {
        self.time = time
        self.enabled = enabled
    }
}
