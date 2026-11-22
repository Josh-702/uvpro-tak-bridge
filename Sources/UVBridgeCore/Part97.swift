// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Part 97 guard for anything that would be radiated.
/// Internet TLS to a TAK server is not an RF emission and is not judged here.
public struct Part97Policy: Equatable, Codable {
    public var allowThirdPartyToRF: Bool
    public var minimumGap: TimeInterval
    public var maxFramesPerMinute: Int
    public var maxMessageCharacters: Int
    public var maxMessageRetries: Int
    public var retryInterval: TimeInterval
    public var allowMicEEmergency: Bool
    public var maxInfoBytes: Int

    public init(
        allowThirdPartyToRF: Bool = false,
        minimumGap: TimeInterval = 8,
        maxFramesPerMinute: Int = 8,
        maxMessageCharacters: Int = 67,
        maxMessageRetries: Int = 4,
        retryInterval: TimeInterval = 45,
        allowMicEEmergency: Bool = false,
        maxInfoBytes: Int = 256
    ) {
        self.allowThirdPartyToRF = allowThirdPartyToRF
        self.minimumGap = minimumGap
        self.maxFramesPerMinute = maxFramesPerMinute
        self.maxMessageCharacters = maxMessageCharacters
        self.maxMessageRetries = maxMessageRetries
        self.retryInterval = retryInterval
        self.allowMicEEmergency = allowMicEEmergency
        self.maxInfoBytes = maxInfoBytes
    }
}

public enum RefusalReason: String, Equatable, Codable {
    case callsignNotSet
    case invalidCallsign
    case encryptionNotAllowed
    case thirdParty
    case messageTooLong
    case frameTooLong
    case invalidPath
    case micEEmergency
    case notAddressedToRF
    case noPosition
    case beaconDisabled
}

public struct TXRefusal: Equatable, Codable {
    public var time: Date
    public var reason: RefusalReason
    public var detail: String

    public init(time: Date, reason: RefusalReason, detail: String) {
        self.time = time
        self.reason = reason
        self.detail = detail
    }
}

public struct TXCandidate: Equatable {
    public var callsign: String
    public var ssid: Int
    public var payloadIsEncrypted: Bool
    /// Set only for a team-mode transmission after the operator accepted the emergency warning.
    public var emergencyEncryptionAuthorized: Bool
    public var isThirdParty: Bool
    public var isOperatorTraffic: Bool
    public var messageCharacters: Int?
    public var infoBytes: Int
    public var isMicEEmergency: Bool
    public var recentTransmissions: [Date]
    public var now: Date

    public init(
        callsign: String,
        ssid: Int = 0,
        payloadIsEncrypted: Bool = false,
        emergencyEncryptionAuthorized: Bool = false,
        isThirdParty: Bool = false,
        isOperatorTraffic: Bool = true,
        messageCharacters: Int? = nil,
        infoBytes: Int,
        isMicEEmergency: Bool = false,
        recentTransmissions: [Date] = [],
        now: Date
    ) {
        self.callsign = callsign
        self.ssid = ssid
        self.payloadIsEncrypted = payloadIsEncrypted
        self.emergencyEncryptionAuthorized = emergencyEncryptionAuthorized
        self.isThirdParty = isThirdParty
        self.isOperatorTraffic = isOperatorTraffic
        self.messageCharacters = messageCharacters
        self.infoBytes = infoBytes
        self.isMicEEmergency = isMicEEmergency
        self.recentTransmissions = recentTransmissions
        self.now = now
    }
}

public enum Part97Decision: Equatable {
    case allow
    case delay(TimeInterval)
    case refuse(RefusalReason)
}

public enum Part97Guard {
    public static func evaluate(_ candidate: TXCandidate, policy: Part97Policy) -> Part97Decision {
        let trimmed = candidate.callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .refuse(.callsignNotSet) }
        guard Callsign.isValidBase(trimmed), (0...15).contains(candidate.ssid) else {
            return .refuse(.invalidCallsign)
        }
        // Ordinary amateur transmissions stay in the clear. The emergency flag is a
        // separate operator decision and is refused everywhere else.
        if candidate.payloadIsEncrypted && !candidate.emergencyEncryptionAuthorized {
            return .refuse(.encryptionNotAllowed)
        }
        if UVBridgeCore.radioEncryptionAvailable {
            return .refuse(.encryptionNotAllowed)
        }
        if candidate.isMicEEmergency && !policy.allowMicEEmergency {
            return .refuse(.micEEmergency)
        }
        if !candidate.isOperatorTraffic && !policy.allowThirdPartyToRF {
            return .refuse(.thirdParty)
        }
        if candidate.isThirdParty && !policy.allowThirdPartyToRF {
            return .refuse(.thirdParty)
        }
        if let count = candidate.messageCharacters, count > policy.maxMessageCharacters {
            return .refuse(.messageTooLong)
        }
        if candidate.infoBytes > policy.maxInfoBytes || candidate.infoBytes <= 0 {
            return .refuse(.frameTooLong)
        }
        let recent = candidate.recentTransmissions
            .filter { candidate.now.timeIntervalSince($0) < 60 }
            .sorted()
        if let last = recent.last {
            let since = candidate.now.timeIntervalSince(last)
            if since < policy.minimumGap {
                return .delay(policy.minimumGap - since)
            }
        }
        if recent.count >= policy.maxFramesPerMinute, let oldest = recent.first {
            let wait = 60 - candidate.now.timeIntervalSince(oldest)
            if wait > 0 { return .delay(wait) }
        }
        return .allow
    }
}
