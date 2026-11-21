// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum LinkMode: String, Codable, Equatable {
    case offline
    case onlineLocalOnly
    case serverUnreachable
    case bridging

    /// iTAK is never pointed at a different server when this changes.
    public var keepsSingleITAKServer: Bool { true }

    public var summary: String {
        switch self {
        case .offline: return OperatorHint.offline
        case .onlineLocalOnly: return OperatorHint.onlineLocalOnly
        case .serverUnreachable: return OperatorHint.serverUnreachable
        case .bridging: return OperatorHint.bridging
        }
    }
}

public enum BeaconFormat: String, Codable, Equatable {
    case uncompressed
    case compressed
    case micE
}

public enum StationSource: String, Codable, Hashable {
    case rf
    case server
}

public struct UpstreamConfig: Codable, Equatable {
    public var host: String
    public var port: Int
    public var transport: TAKTransport
    public var hasClientIdentity: Bool

    public init(host: String, port: Int, transport: TAKTransport, hasClientIdentity: Bool = false) {
        self.host = host
        self.port = port
        self.transport = transport
        self.hasClientIdentity = hasClientIdentity
    }

    public var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && port > 0
    }
}

public struct PositionFix: Codable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var courseDegrees: Double?
    public var speedKnots: Double?
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, courseDegrees: Double? = nil, speedKnots: Double? = nil, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.courseDegrees = courseDegrees
        self.speedKnots = speedKnots
        self.timestamp = timestamp
    }
}

public struct BridgeConfig: Codable, Equatable {
    public var callsign: String
    public var ssid: Int
    public var symbolTable: String
    public var symbol: String
    public var path: String
    public var comment: String
    public var beaconEnabled: Bool
    public var beaconFormat: BeaconFormat
    public var smartBeacon: SmartBeaconConfig
    public var part97: Part97Policy
    public var upstream: UpstreamConfig?
    public var mirrorAllServerStations: Bool
    public var positionStale: TimeInterval
    public var objectStale: TimeInterval
    public var chatStale: TimeInterval
    public var localEndpoint: LocalTAKEndpoint

    public init(
        callsign: String = "",
        ssid: Int = 0,
        symbolTable: String = "/",
        symbol: String = "[",
        path: String = "WIDE1-1,WIDE2-1",
        comment: String = "",
        beaconEnabled: Bool = true,
        beaconFormat: BeaconFormat = .uncompressed,
        smartBeacon: SmartBeaconConfig = SmartBeaconConfig(),
        part97: Part97Policy = Part97Policy(),
        upstream: UpstreamConfig? = nil,
        mirrorAllServerStations: Bool = false,
        positionStale: TimeInterval = 30 * 60,
        objectStale: TimeInterval = 60 * 60,
        chatStale: TimeInterval = 24 * 60 * 60,
        localEndpoint: LocalTAKEndpoint = LocalTAKEndpoint()
    ) {
        self.callsign = callsign
        self.ssid = ssid
        self.symbolTable = symbolTable
        self.symbol = symbol
        self.path = path
        self.comment = comment
        self.beaconEnabled = beaconEnabled
        self.beaconFormat = beaconFormat
        self.smartBeacon = smartBeacon
        self.part97 = part97
        self.upstream = upstream
        self.mirrorAllServerStations = mirrorAllServerStations
        self.positionStale = positionStale
        self.objectStale = objectStale
        self.chatStale = chatStale
        self.localEndpoint = localEndpoint
    }
}

public struct Station: Codable, Equatable, Identifiable {
    public var id: String { uid }
    public var uid: String
    public var callsign: String
    public var latitude: Double?
    public var longitude: Double?
    public var comment: String
    public var cotType: String
    public var symbol: String
    public var courseDegrees: Double?
    public var speedKnots: Double?
    public var lastHeard: Date
    public var sources: Set<StationSource>

    public init(
        uid: String,
        callsign: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        comment: String = "",
        cotType: String = "a-f-G-U-C",
        symbol: String = "/[",
        courseDegrees: Double? = nil,
        speedKnots: Double? = nil,
        lastHeard: Date,
        sources: Set<StationSource>
    ) {
        self.uid = uid
        self.callsign = callsign
        self.latitude = latitude
        self.longitude = longitude
        self.comment = comment
        self.cotType = cotType
        self.symbol = symbol
        self.courseDegrees = courseDegrees
        self.speedKnots = speedKnots
        self.lastHeard = lastHeard
        self.sources = sources
    }
}

public struct PacketLogEntry: Codable, Equatable, Identifiable {
    public var id: UInt64
    public var time: Date
    public var direction: String
    public var summary: String

    public init(id: UInt64, time: Date, direction: String, summary: String) {
        self.id = id
        self.time = time
        self.direction = direction
        self.summary = summary
    }
}

public struct TXLogEntry: Codable, Equatable, Identifiable {
    public var id: UInt64
    public var time: Date
    public var summary: String
    public var hex: String
    public var monitor: String

    public init(id: UInt64, time: Date, summary: String, hex: String, monitor: String) {
        self.id = id
        self.time = time
        self.summary = summary
        self.hex = hex
        self.monitor = monitor
    }
}

public struct PersistedRadioFrame: Codable, Equatable {
    public var kiss: Data
    public var summary: String
    public var infoBytes: Int
    public var messageCharacters: Int?
    public var isThirdParty: Bool
    public var isOperatorTraffic: Bool
    public var isMicEEmergency: Bool
    public var notBefore: Date
    public var kind: String
    public var messageID: String?
    public var addressee: String?
    public var attempts: Int

    public init(
        kiss: Data,
        summary: String,
        infoBytes: Int,
        messageCharacters: Int? = nil,
        isThirdParty: Bool = false,
        isOperatorTraffic: Bool = true,
        isMicEEmergency: Bool = false,
        notBefore: Date,
        kind: String,
        messageID: String? = nil,
        addressee: String? = nil,
        attempts: Int = 0
    ) {
        self.kiss = kiss
        self.summary = summary
        self.infoBytes = infoBytes
        self.messageCharacters = messageCharacters
        self.isThirdParty = isThirdParty
        self.isOperatorTraffic = isOperatorTraffic
        self.isMicEEmergency = isMicEEmergency
        self.notBefore = notBefore
        self.kind = kind
        self.messageID = messageID
        self.addressee = addressee
        self.attempts = attempts
    }
}

public struct BridgeSnapshot: Codable, Equatable {
    public var stations: [Station]
    public var pendingUpstreamXML: [String]
    public var pendingLocalXML: [String]
    public var pendingRadio: [PersistedRadioFrame]
    public var packetLog: [PacketLogEntry]
    public var txLog: [TXLogEntry]

    public init(
        stations: [Station],
        pendingUpstreamXML: [String],
        pendingLocalXML: [String],
        pendingRadio: [PersistedRadioFrame],
        packetLog: [PacketLogEntry],
        txLog: [TXLogEntry]
    ) {
        self.stations = stations
        self.pendingUpstreamXML = pendingUpstreamXML
        self.pendingLocalXML = pendingLocalXML
        self.pendingRadio = pendingRadio
        self.packetLog = packetLog
        self.txLog = txLog
    }
}

public struct BridgeEffect: Equatable {
    public var localXML: [String]
    public var upstreamXML: [String]
    public var radioFrames: [Data]
    public var refusals: [TXRefusal]

    public init(localXML: [String] = [], upstreamXML: [String] = [], radioFrames: [Data] = [], refusals: [TXRefusal] = []) {
        self.localXML = localXML
        self.upstreamXML = upstreamXML
        self.radioFrames = radioFrames
        self.refusals = refusals
    }

    public static let empty = BridgeEffect()

    mutating func merge(_ other: BridgeEffect) {
        localXML.append(contentsOf: other.localXML)
        upstreamXML.append(contentsOf: other.upstreamXML)
        radioFrames.append(contentsOf: other.radioFrames)
        refusals.append(contentsOf: other.refusals)
    }
}

public final class BridgeEngine {
    private let lock = NSLock()
    private var storedConfig: BridgeConfig
    private var storedMode: LinkMode = .offline
    private var pathUp = false
    private var upstreamUp = false
    private var localClients = 0
    private var radioConnected = false
    private var failureCount = 0
    private var nextAttempt: Date?
    private var clock = Date(timeIntervalSince1970: 0)
    private var stationsByUID: [String: Station] = [:]
    private var upstreamQueue: [String] = []
    private var upstreamUID: [String?] = []
    private var localQueue: [String] = []
    private var localUID: [String?] = []
    private var radioQueue: [PersistedRadioFrame] = []
    private var packetEntries: [PacketLogEntry] = []
    private var txEntries: [TXLogEntry] = []
    private var nextEntryID: UInt64 = 1
    private var txTimes: [Date] = []
    private var kissDecoder = KISSStreamDecoder()
    private var localStream = COTByteStream()
    private var upstreamStream = COTByteStream()
    private var ownFix: PositionFix?
    private var lastBeacon: Date?
    private var lastCourse: Double?
    private var nextMessageNumber = 0
    private var seenChats: Set<String> = []
    private var recentTxids: Set<String> = []
    private var lastLocalSignature: [String: String] = [:]
    private var lastLocalEmit: [String: Date] = [:]
    private let backoffSteps = [1, 2, 4, 8, 16, 32, 60]

    public init(config: BridgeConfig = BridgeConfig()) {
        storedConfig = config
        recomputeModeLocked()
    }

    public var config: BridgeConfig {
        get { locked { storedConfig } }
        set { locked { storedConfig = newValue; recomputeModeLocked() } }
    }

    public var mode: LinkMode { locked { storedMode } }
    public var localEndpoint: LocalTAKEndpoint { locked { storedConfig.localEndpoint } }
    public var stations: [Station] {
        locked { stationsByUID.values.sorted { $0.callsign < $1.callsign } }
    }
    public var packetLog: [PacketLogEntry] { locked { packetEntries } }
    public var txLog: [TXLogEntry] { locked { txEntries } }
    public var pendingUpstream: Int { locked { upstreamQueue.count } }
    public var pendingLocal: Int { locked { localQueue.count } }
    public var pendingRadio: Int { locked { radioQueue.count } }
    public var wantsUpstreamSocket: Bool { locked { wantsUpstreamLocked() } }
    public var nextUpstreamAttempt: Date? { locked { nextAttempt } }

    public func setPath(satisfied: Bool, now: Date) -> BridgeEffect {
        locked {
            clock = now
            pathUp = satisfied
            if !satisfied { upstreamUp = false }
            recomputeModeLocked()
            return .empty
        }
    }

    public func noteUpstreamReady(now: Date) -> BridgeEffect {
        locked {
            clock = now
            guard pathUp, !upstreamUp else { return .empty }
            upstreamUp = true
            failureCount = 0
            nextAttempt = nil
            recomputeModeLocked()
            var effect = BridgeEffect()
            flushUpstreamLocked(now: now, into: &effect)
            return effect
        }
    }

    public func noteUpstreamFailed(now: Date) -> BridgeEffect {
        locked {
            clock = now
            upstreamUp = false
            let step = backoffSteps[min(failureCount, backoffSteps.count - 1)]
            failureCount += 1
            nextAttempt = now.addingTimeInterval(TimeInterval(step))
            recomputeModeLocked()
            return .empty
        }
    }

    public func noteUpstreamLost(now: Date) -> BridgeEffect {
        noteUpstreamFailed(now: now)
    }

    public func localClientDidConnect(now: Date) -> BridgeEffect {
        locked {
            clock = now
            localClients += 1
            var effect = BridgeEffect()
            if localClients == 1 { flushLocalLocked(into: &effect) }
            return effect
        }
    }

    public func localClientDidDisconnect(now: Date) -> BridgeEffect {
        locked {
            clock = now
            localClients = max(0, localClients - 1)
            return .empty
        }
    }

    public func radioDidConnect(now: Date) -> BridgeEffect {
        locked {
            clock = now
            radioConnected = true
            var effect = BridgeEffect()
            flushRadioLocked(now: now, into: &effect)
            return effect
        }
    }

    public func radioDidDisconnect(now: Date) -> BridgeEffect {
        locked {
            clock = now
            radioConnected = false
            return .empty
        }
    }

    public func ingestKISS(_ data: Data, now: Date) -> BridgeEffect {
        locked {
            clock = now
            var effect = BridgeEffect()
            for frame in kissDecoder.append(data) where frame.isData {
                guard let ax = AX25Frame.decode(frame.payload) else {
                    logLocked("rx", "Undecoded KISS payload \(frame.payload.count) bytes", now)
                    continue
                }
                ingestFrameLocked(ax, now: now, into: &effect)
            }
            return effect
        }
    }

    public func ingestAX25(_ frame: AX25Frame, now: Date) -> BridgeEffect {
        locked {
            clock = now
            var effect = BridgeEffect()
            ingestFrameLocked(frame, now: now, into: &effect)
            return effect
        }
    }

    public func ingestLocalXML(_ xml: String, now: Date) -> BridgeEffect {
        ingestLocalBytes(Data(xml.utf8), now: now)
    }

    public func ingestLocalBytes(_ data: Data, now: Date) -> BridgeEffect {
        locked {
            clock = now
            var effect = BridgeEffect()
            for item in localStream.append(data) {
                switch item {
                case .event(let event):
                    handleLocalEventLocked(event, now: now, into: &effect)
                case .protobuf(let length):
                    logLocked("note", "Ignored a \(length)-byte TAK protobuf frame. This bridge speaks CoT XML. If iTAK stays silent, run the TCP versus TLS check in docs/TESTING.md.", now)
                }
            }
            return effect
        }
    }

    public func ingestUpstreamBytes(_ data: Data, now: Date) -> BridgeEffect {
        locked {
            clock = now
            var effect = BridgeEffect()
            for item in upstreamStream.append(data) {
                if case .event(let event) = item {
                    handleUpstreamEventLocked(event, now: now, into: &effect)
                }
            }
            return effect
        }
    }

    public func updateOwnPosition(_ fix: PositionFix, now: Date) -> BridgeEffect {
        locked {
            clock = now
            ownFix = fix
            var effect = BridgeEffect()
            considerBeaconLocked(now: now, into: &effect)
            return effect
        }
    }

    public func tick(now: Date) -> BridgeEffect {
        locked {
            clock = now
            var effect = BridgeEffect()
            considerBeaconLocked(now: now, into: &effect)
            flushRadioLocked(now: now, into: &effect)
            return effect
        }
    }

    public func picture(now: Date) -> [COTEvent] {
        locked {
            stationsByUID.values.compactMap { station in
                guard let lat = station.latitude, let lon = station.longitude else { return nil }
                let sources = station.sources.map(\.rawValue).sorted().joined(separator: ",")
                return COTEvent(
                    uid: station.uid,
                    type: station.cotType,
                    time: station.lastHeard,
                    stale: station.lastHeard.addingTimeInterval(storedConfig.positionStale),
                    how: "m-g",
                    latitude: lat,
                    longitude: lon,
                    callsign: station.callsign,
                    remarks: station.comment,
                    courseDegrees: station.courseDegrees,
                    speedMetersPerSecond: station.speedKnots.map { $0 * 1852.0 / 3600.0 },
                    bridge: COTBridgeTag(origin: "picture", sources: sources, txid: nil)
                )
            }
            .sorted { $0.uid < $1.uid }
        }
    }

    public func snapshot() -> BridgeSnapshot {
        locked {
            BridgeSnapshot(
                stations: stationsByUID.values.sorted { $0.uid < $1.uid },
                pendingUpstreamXML: upstreamQueue,
                pendingLocalXML: localQueue,
                pendingRadio: radioQueue,
                packetLog: packetEntries,
                txLog: txEntries
            )
        }
    }

    public func restore(_ snapshot: BridgeSnapshot) {
        locked {
            stationsByUID = Dictionary(uniqueKeysWithValues: snapshot.stations.map { ($0.uid, $0) })
            upstreamQueue = snapshot.pendingUpstreamXML
            upstreamUID = snapshot.pendingUpstreamXML.map { uidFromXML($0) }
            localQueue = snapshot.pendingLocalXML
            localUID = snapshot.pendingLocalXML.map { uidFromXML($0) }
            radioQueue = snapshot.pendingRadio
            packetEntries = snapshot.packetLog
            txEntries = snapshot.txLog
            nextEntryID = (packetEntries.map(\.id).max() ?? 0) + (txEntries.map(\.id).max() ?? 0) + 1
        }
    }

    // MARK: - Locked work

    private func wantsUpstreamLocked() -> Bool {
        guard pathUp, storedConfig.upstream?.isConfigured == true, !upstreamUp else { return false }
        if let nextAttempt, clock < nextAttempt { return false }
        return true
    }

    private func recomputeModeLocked() {
        if !pathUp {
            storedMode = .offline
        } else if storedConfig.upstream?.isConfigured != true {
            storedMode = .onlineLocalOnly
        } else if upstreamUp {
            storedMode = .bridging
        } else {
            storedMode = .serverUnreachable
        }
    }

    private func ingestFrameLocked(_ frame: AX25Frame, now: Date, into effect: inout BridgeEffect) {
        guard frame.isUI else {
            logLocked("rx", "Ignored non-UI frame from \(frame.source.display)", now)
            return
        }
        let packet = APRS.parseHeard(frame: frame, now: now)
        logLocked("rx", packet.summary, now)
        if isOperatorLocked(base: packet.source.call, ssid: packet.source.ssid) && !packet.thirdParty {
            logLocked("note", "Ignored our own station \(packet.source.display)", now)
            return
        }
        switch packet.body {
        case .position(let position):
            let uid = APRSCOT.stationUID(base: packet.source.call, ssid: packet.source.ssid)
            publishPositionLocked(position, callsign: packet.source.display, uid: uid, stale: storedConfig.positionStale, now: now, into: &effect)
        case .object(let object):
            let uid = APRSCOT.objectUID(name: object.name, item: object.isItem)
            if !object.live {
                stationsByUID.removeValue(forKey: uid)
                let dead = object.position
                let event = APRSCOT.positionEvent(
                    position: dead,
                    callsign: object.name,
                    uid: uid,
                    now: now,
                    staleAfter: 0,
                    origin: "rf",
                    sources: "rf",
                    txid: makeTxidLocked(uid, now)
                )
                deliverLocalLocked(event.xml, uid: uid, coalesce: true, now: now, signature: nil, into: &effect)
            } else {
                publishPositionLocked(object.position, callsign: object.name, uid: uid, stale: storedConfig.objectStale, now: now, into: &effect)
            }
        case .message(let message):
            handleRFMessageLocked(packet: packet, message: message, now: now, into: &effect)
        case .status(let status):
            let uid = APRSCOT.stationUID(base: packet.source.call, ssid: packet.source.ssid)
            if var station = stationsByUID[uid] {
                station.comment = status.text
                station.lastHeard = now
                stationsByUID[uid] = station
                if let lat = station.latitude, let lon = station.longitude {
                    var position = APRSPosition(latitude: lat, longitude: lon, comment: status.text)
                    position.symbol = String(station.symbol.dropFirst())
                    position.symbolTable = String(station.symbol.prefix(1))
                    publishPositionLocked(position, callsign: station.callsign, uid: uid, stale: storedConfig.positionStale, now: now, into: &effect)
                }
            }
        case .raw:
            break
        }
    }

    private func publishPositionLocked(
        _ position: APRSPosition,
        callsign: String,
        uid: String,
        stale: TimeInterval,
        now: Date,
        into effect: inout BridgeEffect
    ) {
        var station = stationsByUID[uid] ?? Station(uid: uid, callsign: callsign, lastHeard: now, sources: [])
        station.callsign = callsign
        station.latitude = position.latitude
        station.longitude = position.longitude
        station.comment = position.comment
        station.cotType = SymbolMap.cotType(symbolTable: position.symbolTable, symbol: position.symbol)
        station.symbol = position.symbolTable + position.symbol
        station.courseDegrees = position.courseDegrees
        station.speedKnots = position.speedKnots
        station.lastHeard = now
        station.sources.insert(.rf)
        stationsByUID[uid] = station
        let txid = makeTxidLocked(uid, now)
        recentTxids.insert(txid)
        let event = APRSCOT.positionEvent(
            position: position,
            callsign: callsign,
            uid: uid,
            now: now,
            staleAfter: stale,
            origin: "rf",
            sources: station.sources.map(\.rawValue).sorted().joined(separator: ","),
            txid: txid
        )
        let signature = String(format: "%.5f,%.5f,%@", position.latitude, position.longitude, position.comment)
        deliverLocalLocked(event.xml, uid: uid, coalesce: true, now: now, signature: signature, into: &effect)
        sendUpstreamLocked(event.xml, uid: uid, coalesce: true, into: &effect)
    }

    private func handleRFMessageLocked(packet: APRSPacket, message: APRSMessage, now: Date, into effect: inout BridgeEffect) {
        switch message.kind {
        case .ack(let id), .reject(let id):
            radioQueue.removeAll { $0.messageID == id && $0.addressee == packet.source.display }
            logLocked("rx", "Ack \(id) from \(packet.source.display)", now)
        case .text(let text, let id):
            if message.isBulletin {
                deliverChatLocked(from: packet.source.display, to: "Bulletins", text: text, id: id ?? "bln", now: now, into: &effect)
                return
            }
            guard addressedToOperatorLocked(message.addressee) else { return }
            let key = "\(packet.source.display)|\(id ?? text)"
            if seenChats.insert(key).inserted {
                let known = stationsByUID[APRSCOT.stationUID(base: packet.source.call, ssid: packet.source.ssid)]
                deliverChatLocked(
                    from: packet.source.display,
                    to: operatorDisplayLocked(),
                    text: text,
                    id: id ?? "0",
                    latitude: known?.latitude ?? 0,
                    longitude: known?.longitude ?? 0,
                    now: now,
                    into: &effect
                )
            }
            if let id {
                queueFrameLocked(
                    infoText: APRSBuilder.ack(to: operatorDisplayLocked(), id: id),
                    summary: "ACK \(id) to \(packet.source.display)",
                    kind: "ack",
                    messageID: nil,
                    addressee: packet.source.display,
                    messageCharacters: nil,
                    thirdParty: false,
                    emergency: false,
                    now: now,
                    into: &effect
                )
            }
        }
    }

    private func deliverChatLocked(
        from: String,
        to: String,
        text: String,
        id: String,
        latitude: Double = 0,
        longitude: Double = 0,
        now: Date,
        into effect: inout BridgeEffect
    ) {
        let event = APRSCOT.chatEvent(
            from: from,
            fromUID: "APRS-\(from)",
            to: to,
            toUID: "APRS-\(to)",
            text: text,
            messageID: id,
            latitude: latitude,
            longitude: longitude,
            now: now,
            staleAfter: storedConfig.chatStale
        )
        deliverLocalLocked(event.xml, uid: event.uid, coalesce: false, now: now, signature: nil, into: &effect)
        sendUpstreamLocked(event.xml, uid: nil, coalesce: false, into: &effect)
    }

    private func handleLocalEventLocked(_ event: COTEvent, now: Date, into effect: inout BridgeEffect) {
        if event.isChat, let route = GeoChat.route(event) {
            let fromOperator = isOperatorCallsignLocked(route.senderCallsign)
            if route.allChat {
                if fromOperator {
                    effect.refusals.append(TXRefusal(time: now, reason: .notAddressedToRF, detail: "All Chat stays on TAK. Address an APRS station to send it over the radio."))
                    logLocked("note", "Refused All Chat on RF", now)
                }
                sendUpstreamLocked(event.xml, uid: nil, coalesce: false, into: &effect)
                return
            }
            guard let recipient = route.recipientCallsign else { return }
            if storedConfig.callsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                effect.refusals.append(TXRefusal(time: now, reason: .callsignNotSet, detail: "Set your callsign before Open UV Bridge can transmit."))
                return
            }
            if fromOperator {
                sendUpstreamLocked(event.xml, uid: nil, coalesce: false, into: &effect)
                queueOperatorMessageLocked(to: recipient, body: route.text, thirdParty: false, now: now, into: &effect)
            } else if storedConfig.part97.allowThirdPartyToRF {
                queueOperatorMessageLocked(to: recipient, body: route.text, thirdParty: true, now: now, into: &effect)
            } else {
                effect.refusals.append(TXRefusal(time: now, reason: .thirdParty, detail: "Only \(operatorDisplayLocked().isEmpty ? "your" : operatorDisplayLocked()) traffic goes to the radio."))
                logLocked("note", "Refused third-party chat from \(route.senderCallsign)", now)
            }
            return
        }
        if event.isAtom && isOperatorCallsignLocked(event.callsign) {
            if abs(event.latitude) > 0.0001 || abs(event.longitude) > 0.0001 {
                ownFix = PositionFix(
                    latitude: event.latitude,
                    longitude: event.longitude,
                    courseDegrees: event.courseDegrees,
                    speedKnots: event.speedMetersPerSecond.map { $0 * 3600.0 / 1852.0 },
                    timestamp: event.time
                )
                considerBeaconLocked(now: now, into: &effect)
            }
            sendUpstreamLocked(event.xml, uid: event.uid, coalesce: true, into: &effect)
        }
    }

    private func handleUpstreamEventLocked(_ event: COTEvent, now: Date, into effect: inout BridgeEffect) {
        if let txid = event.bridge?.txid, recentTxids.contains(txid) {
            if var station = stationsByUID[event.uid] {
                station.sources.insert(.server)
                station.lastHeard = now
                stationsByUID[event.uid] = station
            }
            return
        }
        if event.isChat, let route = GeoChat.route(event) {
            let mentionsOperator = isOperatorCallsignLocked(route.senderCallsign) || isOperatorCallsignLocked(route.recipientCallsign ?? "")
            let mentionsRF = stationsByUID.values.contains { station in
                station.sources.contains(.rf) && (station.callsign == route.senderCallsign || station.callsign == route.recipientCallsign)
            }
            if mentionsOperator || mentionsRF || route.allChat == false && storedConfig.mirrorAllServerStations {
                if mentionsOperator || mentionsRF {
                    deliverLocalLocked(event.xml, uid: event.uid, coalesce: false, now: now, signature: nil, into: &effect)
                }
            }
            return
        }
        guard event.isAtom else { return }
        if isOperatorCallsignLocked(event.callsign) { return }
        let alreadyRF = stationsByUID[event.uid]?.sources.contains(.rf) == true
        guard alreadyRF || storedConfig.mirrorAllServerStations else { return }
        var station = stationsByUID[event.uid] ?? Station(uid: event.uid, callsign: event.callsign, lastHeard: now, sources: [])
        station.callsign = event.callsign.isEmpty ? station.callsign : event.callsign
        station.latitude = event.latitude
        station.longitude = event.longitude
        if !event.remarks.isEmpty { station.comment = event.remarks }
        station.cotType = event.type
        station.lastHeard = now
        station.sources.insert(.server)
        stationsByUID[event.uid] = station
        let signature = String(format: "%.5f,%.5f,%@", event.latitude, event.longitude, event.remarks)
        deliverLocalLocked(event.xml, uid: event.uid, coalesce: true, now: now, signature: signature, into: &effect)
    }

    private func considerBeaconLocked(now: Date, into effect: inout BridgeEffect) {
        guard storedConfig.beaconEnabled, let fix = ownFix else { return }
        let decision = SmartBeacon.decide(
            config: storedConfig.smartBeacon,
            now: now,
            lastBeacon: lastBeacon,
            speedKnots: fix.speedKnots ?? 0,
            courseDegrees: fix.courseDegrees,
            lastCourseDegrees: lastCourse
        )
        guard decision.shouldBeacon else { return }
        guard !storedConfig.callsign.trimmingCharacters(in: .whitespaces).isEmpty else {
            effect.refusals.append(TXRefusal(time: now, reason: .callsignNotSet, detail: "Set your callsign before Open UV Bridge can transmit."))
            logLocked("note", "Refused beacon: callsign is blank", now)
            return
        }
        lastBeacon = now
        lastCourse = fix.courseDegrees
        guard let built = beaconPayloadLocked(fix) else {
            effect.refusals.append(TXRefusal(time: now, reason: .invalidPath, detail: "Beacon path or position could not be encoded."))
            return
        }
        radioQueue.removeAll { $0.kind == "beacon" }
        guard let kiss = kissLocked(destination: built.destination, info: built.info) else {
            effect.refusals.append(TXRefusal(time: now, reason: .invalidPath, detail: "The digipeater path is not valid AX.25."))
            return
        }
        radioQueue.append(PersistedRadioFrame(
            kiss: kiss,
            summary: "Beacon \(operatorDisplayLocked())",
            infoBytes: built.info.count,
            isThirdParty: false,
            isOperatorTraffic: true,
            isMicEEmergency: built.emergency,
            notBefore: now,
            kind: "beacon",
            attempts: 0
        ))
        flushRadioLocked(now: now, into: &effect)
    }

    private func beaconPayloadLocked(_ fix: PositionFix) -> (destination: AX25Address, info: Data, emergency: Bool)? {
        let table = storedConfig.symbolTable.first ?? "/"
        let symbol = storedConfig.symbol.first ?? "["
        switch storedConfig.beaconFormat {
        case .uncompressed:
            guard let text = APRSBuilder.uncompressedPosition(
                latitude: fix.latitude,
                longitude: fix.longitude,
                symbolTable: table,
                symbol: symbol,
                comment: storedConfig.comment,
                courseDegrees: fix.courseDegrees.map { Int($0) },
                speedKnots: fix.speedKnots.map { Int($0) }
            ) else { return nil }
            return (AX25Address(call: APRSBuilder.defaultToCall), Data(text.utf8), false)
        case .compressed:
            guard let text = APRSBuilder.compressedPosition(
                latitude: fix.latitude,
                longitude: fix.longitude,
                symbolTable: table,
                symbol: symbol,
                comment: storedConfig.comment,
                courseDegrees: fix.courseDegrees,
                speedKnots: fix.speedKnots
            ) else { return nil }
            return (AX25Address(call: APRSBuilder.defaultToCall), Data(text.utf8), false)
        case .micE:
            guard let encoded = MicE.encode(
                latitude: fix.latitude,
                longitude: fix.longitude,
                symbolTable: table,
                symbol: symbol,
                comment: storedConfig.comment,
                courseDegrees: fix.courseDegrees ?? 0,
                speedKnots: fix.speedKnots ?? 0
            ) else { return nil }
            return (AX25Address(call: encoded.destination), encoded.info, false)
        }
    }

    private func queueOperatorMessageLocked(to: String, body: String, thirdParty: Bool, now: Date, into effect: inout BridgeEffect) {
        if storedConfig.callsign.trimmingCharacters(in: .whitespaces).isEmpty {
            effect.refusals.append(TXRefusal(time: now, reason: .callsignNotSet, detail: "Set your callsign before Open UV Bridge can transmit."))
            return
        }
        if body.count > storedConfig.part97.maxMessageCharacters {
            effect.refusals.append(TXRefusal(time: now, reason: .messageTooLong, detail: "APRS messages are limited to \(storedConfig.part97.maxMessageCharacters) characters."))
            return
        }
        let id = nextMessageIDLocked()
        queueFrameLocked(
            infoText: APRSBuilder.message(to: to, body: body, id: id),
            summary: "Message \(to): \(body)",
            kind: "message",
            messageID: id,
            addressee: to,
            messageCharacters: body.count,
            thirdParty: thirdParty,
            emergency: false,
            now: now,
            into: &effect
        )
    }

    private func queueFrameLocked(
        infoText: String?,
        summary: String,
        kind: String,
        messageID: String?,
        addressee: String?,
        messageCharacters: Int?,
        thirdParty: Bool,
        emergency: Bool,
        now: Date,
        into effect: inout BridgeEffect
    ) {
        guard let infoText else {
            effect.refusals.append(TXRefusal(time: now, reason: .messageTooLong, detail: "Could not build the APRS payload."))
            return
        }
        guard let kiss = kissLocked(destination: AX25Address(call: APRSBuilder.defaultToCall), info: Data(infoText.utf8)) else {
            effect.refusals.append(TXRefusal(time: now, reason: .invalidPath, detail: "The digipeater path is not valid AX.25."))
            return
        }
        radioQueue.append(PersistedRadioFrame(
            kiss: kiss,
            summary: summary,
            infoBytes: infoText.utf8.count,
            messageCharacters: messageCharacters,
            isThirdParty: thirdParty,
            isOperatorTraffic: !thirdParty,
            isMicEEmergency: emergency,
            notBefore: now,
            kind: kind,
            messageID: messageID,
            addressee: addressee,
            attempts: 0
        ))
        flushRadioLocked(now: now, into: &effect)
    }

    private func kissLocked(destination: AX25Address, info: Data) -> Data? {
        guard let digis = AX25Frame.digipeaters(fromPath: storedConfig.path) else { return nil }
        guard Callsign.isValidBase(storedConfig.callsign) else { return nil }
        let frame = AX25Frame(
            destination: destination,
            source: AX25Address(call: storedConfig.callsign.uppercased(), ssid: storedConfig.ssid),
            digipeaters: digis,
            info: info
        )
        guard let bytes = frame.encode() else { return nil }
        return KISS.encode(KISSFrame(payload: bytes))
    }

    private func flushRadioLocked(now: Date, into effect: inout BridgeEffect) {
        var index = 0
        while index < radioQueue.count {
            let job = radioQueue[index]
            if job.notBefore > now {
                index += 1
                continue
            }
            let decision = Part97Guard.evaluate(TXCandidate(
                callsign: storedConfig.callsign,
                ssid: storedConfig.ssid,
                payloadIsEncrypted: false,
                isThirdParty: job.isThirdParty,
                isOperatorTraffic: job.isOperatorTraffic,
                messageCharacters: job.messageCharacters,
                infoBytes: max(job.infoBytes, 1),
                isMicEEmergency: job.isMicEEmergency,
                recentTransmissions: txTimes,
                now: now
            ), policy: storedConfig.part97)
            switch decision {
            case .allow:
                guard radioConnected else {
                    logLocked("note", "Queued \(job.summary) until the radio is connected", now)
                    index += 1
                    continue
                }
                effect.radioFrames.append(job.kiss)
                txTimes.append(now)
                txTimes = txTimes.filter { now.timeIntervalSince($0) < 120 }
                let monitor = AX25Frame.decode(kissPayload(job.kiss))?.monitor ?? job.summary
                txEntries.append(TXLogEntry(id: nextIDLocked(), time: now, summary: job.summary, hex: Hex.encode(job.kiss, separator: " "), monitor: monitor))
                trimLogsLocked()
                radioQueue.remove(at: index)
                if job.kind == "message" {
                    var retry = job
                    retry.attempts += 1
                    if retry.attempts <= storedConfig.part97.maxMessageRetries {
                        retry.notBefore = now.addingTimeInterval(storedConfig.part97.retryInterval)
                        radioQueue.append(retry)
                    }
                }
            case .delay(let wait):
                radioQueue[index].notBefore = now.addingTimeInterval(wait)
                logLocked("note", "Held \(job.summary) for \(Int(wait.rounded()))s (rate limit)", now)
                index += 1
            case .refuse(let reason):
                effect.refusals.append(TXRefusal(time: now, reason: reason, detail: job.summary))
                logLocked("note", "Refused \(job.summary): \(reason.rawValue)", now)
                radioQueue.remove(at: index)
            }
        }
    }

    private func deliverLocalLocked(_ xml: String, uid: String?, coalesce: Bool, now: Date, signature: String?, into effect: inout BridgeEffect) {
        if coalesce, let uid {
            let kept = zip(localQueue, localUID).filter { $0.1 != uid }
            localQueue = kept.map(\.0)
            localUID = kept.map(\.1)
        }
        if let uid, let signature, let previous = lastLocalSignature[uid], previous == signature,
           let sent = lastLocalEmit[uid], now.timeIntervalSince(sent) < 15, localClients > 0 {
            return
        }
        if localClients > 0 {
            effect.localXML.append(xml)
            if let uid, let signature {
                lastLocalSignature[uid] = signature
                lastLocalEmit[uid] = now
            }
        } else {
            localQueue.append(xml)
            localUID.append(uid)
            capLocked(&localQueue, companions: &localUID)
        }
    }

    private func sendUpstreamLocked(_ xml: String, uid: String?, coalesce: Bool, into effect: inout BridgeEffect) {
        guard storedConfig.upstream?.isConfigured == true else { return }
        if coalesce, let uid {
            let kept = zip(upstreamQueue, upstreamUID).filter { $0.1 != uid }
            upstreamQueue = kept.map(\.0)
            upstreamUID = kept.map(\.1)
        }
        if upstreamUp && pathUp {
            effect.upstreamXML.append(xml)
        } else {
            upstreamQueue.append(xml)
            upstreamUID.append(uid)
            capLocked(&upstreamQueue, companions: &upstreamUID)
        }
    }

    private func flushUpstreamLocked(now _: Date, into effect: inout BridgeEffect) {
        effect.upstreamXML.append(contentsOf: upstreamQueue)
        upstreamQueue.removeAll()
        upstreamUID.removeAll()
    }

    private func flushLocalLocked(into effect: inout BridgeEffect) {
        effect.localXML.append(contentsOf: localQueue)
        localQueue.removeAll()
        localUID.removeAll()
    }

    private func capLocked(_ queue: inout [String], companions: inout [String?]) {
        let cap = 500
        if queue.count > cap {
            queue.removeFirst(queue.count - cap)
            companions.removeFirst(companions.count - cap)
        }
    }

    private func kissPayload(_ kiss: Data) -> Data {
        let frames = KISSStreamDecoder().append(kiss)
        return frames.first?.payload ?? Data()
    }

    private func makeTxidLocked(_ uid: String, _ now: Date) -> String {
        let id = "rf-\(uid)-\(Int(now.timeIntervalSince1970))-\(nextEntryID)"
        nextEntryID += 1
        return id
    }

    private func nextMessageIDLocked() -> String {
        let id = String(format: "%02d", nextMessageNumber % 100)
        nextMessageNumber += 1
        return id
    }

    private func nextIDLocked() -> UInt64 {
        let id = nextEntryID
        nextEntryID += 1
        return id
    }

    private func logLocked(_ direction: String, _ summary: String, _ now: Date) {
        packetEntries.append(PacketLogEntry(id: nextIDLocked(), time: now, direction: direction, summary: summary))
        trimLogsLocked()
    }

    private func trimLogsLocked() {
        if packetEntries.count > 400 { packetEntries.removeFirst(packetEntries.count - 400) }
        if txEntries.count > 400 { txEntries.removeFirst(txEntries.count - 400) }
    }

    private func operatorDisplayLocked() -> String {
        let base = storedConfig.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !base.isEmpty else { return "" }
        return Callsign.display(base: base, ssid: storedConfig.ssid)
    }

    private func isOperatorLocked(base: String, ssid: Int) -> Bool {
        let ours = storedConfig.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !ours.isEmpty, base.uppercased() == ours else { return false }
        if storedConfig.ssid == 0 { return ssid == 0 }
        return ssid == storedConfig.ssid
    }

    private func isOperatorCallsignLocked(_ raw: String) -> Bool {
        guard let parsed = Callsign.parse(raw) else { return false }
        let ours = storedConfig.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !ours.isEmpty, parsed.base == ours else { return false }
        if storedConfig.ssid == 0 { return parsed.ssid == 0 }
        return parsed.ssid == storedConfig.ssid || parsed.ssid == 0
    }

    private func addressedToOperatorLocked(_ raw: String) -> Bool {
        isOperatorCallsignLocked(raw)
    }

    private func uidFromXML(_ xml: String) -> String? {
        COTXML.parseEvents(in: xml).first?.uid
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
