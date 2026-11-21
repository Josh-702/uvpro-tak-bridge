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
    @Published var upstreamLink = UpstreamLink.noServer
    @Published var needsCertificatePassword = false
    @Published var certificatePassword = ""
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
        restoreCertificates()
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
                hasClientIdentity: upstream.hasIdentity
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
            forgetCertificateFiles()
            storePackage(imported)
            importNote = imported.redactedDescription
            if !applyStoredCertificates(
                clientPassword: imported.resolvedClientPassword,
                trustPassword: imported.resolvedTrustStorePassword
            ) {
                needsCertificatePassword = true
                upstreamLink = .passwordNeeded
                importNote = "The certificate password was not accepted. Enter the password from the data package."
            } else {
                needsCertificatePassword = false
                certificatePassword = ""
            }
            saveSettings()
        } catch {
            importNote = "That package did not contain a server address."
        }
    }

    func unlockCertificates() {
        let password = certificatePassword
        guard !password.isEmpty else { return }
        if applyStoredCertificates(clientPassword: password, trustPassword: password) {
            needsCertificatePassword = false
            certificatePassword = ""
            importNote = "Certificates unlocked. Password stored in the Keychain."
            saveSettings()
        } else {
            needsCertificatePassword = true
            upstreamLink = .passwordNeeded
            importNote = "That password did not unlock the certificates."
        }
    }

    nonisolated func noteUpstreamLink(_ link: UpstreamLink) {
        MainActor.assumeIsolated {
            self.upstreamLink = link
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            if manager.authorizationStatus == .authorizedAlways {
                manager.allowsBackgroundLocationUpdates = true
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        let speedKnots = fix.speed >= 0 ? fix.speed * 1.94384 : 0
        let course = fix.course >= 0 ? fix.course : nil
        let position = PositionFix(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            courseDegrees: course,
            speedKnots: speedKnots,
            timestamp: fix.timestamp
        )
        MainActor.assumeIsolated {
            self.apply(self.engine.updateOwnPosition(position, now: Date()))
        }
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

    private func restoreCertificates() {
        guard applyStoredCertificates(
            clientPassword: TAKCredentialStore.loadPassword(account: TAKCredentialStore.clientPassword) ?? "",
            trustPassword: TAKCredentialStore.loadPassword(account: TAKCredentialStore.trustStorePassword) ?? ""
        ) else {
            if TAKCredentialStore.load(account: TAKCredentialStore.clientCertificate) != nil {
                needsCertificatePassword = true
                upstreamLink = .passwordNeeded
            }
            return
        }
        needsCertificatePassword = false
    }

    private func storePackage(_ imported: ImportedTAKServer) {
        if let client = imported.clientCertificate {
            _ = TAKCredentialStore.save(account: TAKCredentialStore.clientCertificate, data: client)
        }
        if let trust = imported.trustStore {
            _ = TAKCredentialStore.save(account: TAKCredentialStore.trustStore, data: trust)
        }
    }

    @discardableResult
    private func applyStoredCertificates(clientPassword: String, trustPassword: String) -> Bool {
        let clientData = TAKCredentialStore.load(account: TAKCredentialStore.clientCertificate)
        let trustData = TAKCredentialStore.load(account: TAKCredentialStore.trustStore)
        guard clientData != nil || trustData != nil else {
            upstream.use(nil)
            return true
        }
        guard let clientData else {
            upstream.use(nil)
            return false
        }
        guard let unlockedClient = TAKPKCS12.unlock(clientData, password: clientPassword),
              let identity = unlockedClient.identity
        else {
            upstream.use(nil)
            return false
        }
        _ = TAKCredentialStore.savePassword(account: TAKCredentialStore.clientPassword, password: clientPassword)
        var anchors: [SecCertificate] = []
        if let trustData {
            guard let unlockedTrust = TAKPKCS12.unlock(trustData, password: trustPassword) else {
                upstream.use(nil)
                return false
            }
            anchors = unlockedTrust.certificates
            _ = TAKCredentialStore.savePassword(account: TAKCredentialStore.trustStorePassword, password: trustPassword)
        }
        if anchors.isEmpty {
            var certificate: SecCertificate?
            if SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate {
                anchors = [certificate]
            }
        }
        guard !anchors.isEmpty else {
            upstream.use(nil)
            return false
        }
        upstream.use(TAKTLSMaterial(identity: identity, anchors: anchors))
        return true
    }

    private func forgetCertificateFiles() {
        let directory = configURL.deletingLastPathComponent()
        for name in ["upstream-trust.p12", "upstream-client.p12"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
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
