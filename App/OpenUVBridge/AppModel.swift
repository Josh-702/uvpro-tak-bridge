// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import CoreLocation
import Foundation
import SwiftUI
import UVBridgeCore

@MainActor
final class AppModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var modeSummary = OperatorHint.offline
    @Published var modeName = "Offline"
    @Published var stations: [Station] = []
    @Published var packetLog: [PacketLogEntry] = []
    @Published var txLog: [TXLogEntry] = []
    @Published var radioStatus = "Bluetooth is starting"
    @Published var radioHint: String?
    @Published var discovered: [RadioAdvertisement] = []
    @Published var callsign = ""
    @Published var ssid = 0
    @Published var path = "WIDE1-1,WIDE2-1"
    @Published var comment = ""
    @Published var symbol = "["
    @Published var beaconEnabled = true
    @Published var upstreamHost = ""
    @Published var upstreamPort = "8089"
    @Published var upstreamTLS = true
    @Published var mirrorServer = false
    @Published var allowThirdParty = false
    @Published var localConnect = LocalTAKEndpoint().connectString
    @Published var importNote = ""
    @Published var refusals: [String] = []

    let engine: BridgeEngine
    private let radio: RadioSession
    private let localServer: LocalTAKService
    private let upstream: UpstreamTAKClient
    private let paths: PathWatcher
    private let location = CLLocationManager()
    private var ticker: Timer?
    private let configURL: URL
    private let snapshotURL: URL

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        configURL = support.appendingPathComponent("bridge-config.json")
        snapshotURL = support.appendingPathComponent("bridge-snapshot.json")
        let restored = (try? Data(contentsOf: configURL)).flatMap { try? JSONDecoder().decode(BridgeConfig.self, from: $0) }
        engine = BridgeEngine(config: restored ?? BridgeConfig())
        radio = RadioSession()
        localServer = LocalTAKService()
        upstream = UpstreamTAKClient()
        paths = PathWatcher()
        super.init()
        pullFromEngine()
        if let snapshot = (try? Data(contentsOf: snapshotURL)).flatMap({ try? JSONDecoder().decode(BridgeSnapshot.self, from: $0) }) {
            engine.restore(snapshot)
            refreshLists()
        }
        radio.owner = self
        localServer.owner = self
        upstream.owner = self
        paths.owner = self
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        location.pausesLocationUpdatesAutomatically = false
        radio.start()
        localServer.start(port: engine.localEndpoint.port)
        paths.start()
        location.requestAlwaysAuthorization()
        location.startUpdatingLocation()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func refreshLists() {
        modeSummary = engine.mode.summary
        modeName = String(describing: engine.mode)
        stations = engine.stations
        packetLog = engine.packetLog.reversed()
        txLog = engine.txLog.reversed()
        localConnect = engine.localEndpoint.connectString
    }

    func saveSettings() {
        var config = engine.config
        config.callsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        config.ssid = ssid
        config.path = path
        config.comment = comment
        config.symbol = symbol.isEmpty ? "[" : symbol
        config.beaconEnabled = beaconEnabled
        config.mirrorAllServerStations = mirrorServer
        config.part97.allowThirdPartyToRF = allowThirdParty
        let host = upstreamHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            config.upstream = nil
        } else {
            config.upstream = UpstreamConfig(
                host: host,
                port: Int(upstreamPort) ?? 8089,
                transport: upstreamTLS ? .tls : .tcp,
                hasClientIdentity: engine.config.upstream?.hasClientIdentity ?? false
            )
        }
        engine.config = config
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
        persistSnapshot()
        refreshLists()
        upstream.reconnectIfNeeded()
    }

    func apply(_ effect: BridgeEffect) {
        localServer.send(effect.localXML)
        upstream.send(effect.upstreamXML)
        for frame in effect.radioFrames {
            radio.write(frame)
        }
        if !effect.refusals.isEmpty {
            refusals = effect.refusals.map { "\($0.reason.rawValue): \($0.detail)" } + refusals
            refusals = Array(refusals.prefix(8))
        }
        refreshLists()
        persistSnapshot()
        upstream.reconnectIfNeeded()
    }

    func tick() {
        apply(engine.tick(now: Date()))
    }

    func connectRadio(_ id: UUID) {
        radio.connect(id)
    }

    func packageFile() -> URL {
        let data = DataPackageBuilder.iTAKPackage(endpoint: engine.localEndpoint)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenUVBridge-iTAK.zip")
        try? data.write(to: url, options: .atomic)
        return url
    }

    func importServerPackage(_ data: Data) {
        do {
            let imported = try TAKPackageImport.load(data)
            upstreamHost = imported.host
            upstreamPort = String(imported.port)
            upstreamTLS = imported.transport == .tls
            if let trust = imported.trustStore {
                let url = configURL.deletingLastPathComponent().appendingPathComponent("upstream-trust.p12")
                try trust.write(to: url, options: .completeFileProtection)
            }
            if let client = imported.clientCertificate {
                let url = configURL.deletingLastPathComponent().appendingPathComponent("upstream-client.p12")
                try client.write(to: url, options: .completeFileProtection)
            }
            importNote = imported.redactedDescription
            saveSettings()
        } catch {
            importNote = "That package did not contain a server address."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        let speedKnots = fix.speed >= 0 ? fix.speed * 1.94384 : 0
        let course = fix.course >= 0 ? fix.course : nil
        apply(engine.updateOwnPosition(PositionFix(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            courseDegrees: course,
            speedKnots: speedKnots,
            timestamp: fix.timestamp
        ), now: Date()))
    }

    /// Bluetooth and Network callbacks are scheduled on the main queue, but those
    /// closures are not main-actor isolated. Enter the actor here so the UI update
    /// stays synchronous with the callback that produced it.
    nonisolated func setRadioStatus(_ text: String, hint: String?) {
        MainActor.assumeIsolated {
            self.radioStatus = text
            self.radioHint = hint
        }
    }

    nonisolated func setDiscovered(_ radios: [RadioAdvertisement]) {
        MainActor.assumeIsolated {
            self.discovered = radios
        }
    }

    nonisolated func radioBytes(_ data: Data) {
        MainActor.assumeIsolated {
            self.apply(self.engine.ingestKISS(data, now: Date()))
        }
    }

    nonisolated func radioLink(_ connected: Bool) {
        MainActor.assumeIsolated {
            self.apply(connected ? self.engine.radioDidConnect(now: Date()) : self.engine.radioDidDisconnect(now: Date()))
        }
    }

    nonisolated func localBytes(_ data: Data) {
        MainActor.assumeIsolated {
            self.apply(self.engine.ingestLocalBytes(data, now: Date()))
        }
    }

    nonisolated func localClientCount(_ count: Int) {
        MainActor.assumeIsolated {
            // The service reports transitions one client at a time.
            if count > 0 {
                self.apply(self.engine.localClientDidConnect(now: Date()))
            } else {
                self.apply(self.engine.localClientDidDisconnect(now: Date()))
            }
        }
    }

    nonisolated func pathChanged(_ satisfied: Bool) {
        MainActor.assumeIsolated {
            self.apply(self.engine.setPath(satisfied: satisfied, now: Date()))
        }
    }

    nonisolated func upstreamReady() {
        MainActor.assumeIsolated {
            self.apply(self.engine.noteUpstreamReady(now: Date()))
        }
    }

    nonisolated func upstreamFailed() {
        MainActor.assumeIsolated {
            self.apply(self.engine.noteUpstreamFailed(now: Date()))
        }
    }

    nonisolated func upstreamBytes(_ data: Data) {
        MainActor.assumeIsolated {
            self.apply(self.engine.ingestUpstreamBytes(data, now: Date()))
        }
    }

    private func pullFromEngine() {
        let config = engine.config
        callsign = config.callsign
        ssid = config.ssid
        path = config.path
        comment = config.comment
        symbol = config.symbol
        beaconEnabled = config.beaconEnabled
        mirrorServer = config.mirrorAllServerStations
        allowThirdParty = config.part97.allowThirdPartyToRF
        upstreamHost = config.upstream?.host ?? ""
        upstreamPort = String(config.upstream?.port ?? 8089)
        upstreamTLS = config.upstream?.transport != .tcp
        refreshLists()
    }

    private func persistSnapshot() {
        if let data = try? JSONEncoder().encode(engine.snapshot()) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
    }
}

struct RadioAdvertisement: Identifiable, Equatable {
    var id: UUID
    var name: String
    var rssi: Int
}
