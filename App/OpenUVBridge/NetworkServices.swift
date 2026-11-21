// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network
import UVBridgeCore

/// Loopback TAK endpoint. iTAK is always pointed here. The phone's upstream
/// TAK server is a separate socket that comes and goes with the network.
final class LocalTAKService {
    weak var owner: AppModel?
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    func start(port: Int) {
        let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 17747
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true
        do {
            listener = try NWListener(using: parameters)
        } catch {
            return
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener?.start(queue: .main)
    }

    func send(_ documents: [String]) {
        guard !documents.isEmpty else { return }
        let payload = Data(documents.joined().utf8)
        for connection in connections {
            connection.send(content: payload, completion: .idempotent)
        }
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.owner?.localClientCount(1)
            }
            if case .failed = state {
                self?.drop(connection)
            }
            if case .cancelled = state {
                self?.drop(connection)
            }
        }
        connection.start(queue: .main)
        receive(connection)
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            if let data, !data.isEmpty {
                self?.owner?.localBytes(data)
            }
            if complete || error != nil {
                self?.drop(connection)
            } else {
                self?.receive(connection)
            }
        }
    }

    private func drop(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        owner?.localClientCount(0)
        connection.cancel()
    }
}

final class UpstreamTAKClient {
    weak var owner: AppModel?
    private var connection: NWConnection?
    private var retry: DispatchWorkItem?

    func reconnectIfNeeded() {
        guard let owner else { return }
        if owner.engine.wantsUpstreamSocket {
            if connection == nil { connect() }
        } else if connection != nil, !owner.engine.mode.keepsSingleITAKServer || owner.engine.mode != .bridging {
            // Keep the socket only while the engine wants it.
            if !owner.engine.wantsUpstreamSocket && owner.engine.mode != .bridging {
                cancel()
            }
        }
    }

    func send(_ documents: [String]) {
        guard !documents.isEmpty, let connection else { return }
        connection.send(content: Data(documents.joined().utf8), completion: .idempotent)
    }

    private func connect() {
        guard let owner, let upstream = owner.engine.config.upstream, upstream.isConfigured else { return }
        let host = NWEndpoint.Host(upstream.host)
        guard let port = NWEndpoint.Port(rawValue: UInt16(upstream.port)) else { return }
        let parameters: NWParameters
        if upstream.transport == .tls {
            let tls = NWProtocolTLS.Options()
            parameters = NWParameters(tls: tls)
        } else {
            parameters = NWParameters.tcp
        }
        let connection = NWConnection(host: host, port: port, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.owner?.upstreamReady()
                self?.receive()
            case .failed, .cancelled:
                self?.connection = nil
                self?.owner?.upstreamFailed()
                self?.scheduleRetry()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            if let data, !data.isEmpty {
                self?.owner?.upstreamBytes(data)
            }
            if complete || error != nil {
                self?.cancel()
                self?.owner?.upstreamFailed()
                self?.scheduleRetry()
            } else {
                self?.receive()
            }
        }
    }

    private func scheduleRetry() {
        guard let owner, let when = owner.engine.nextUpstreamAttempt else { return }
        retry?.cancel()
        let delay = max(0.2, when.timeIntervalSinceNow)
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancel() {
        connection?.cancel()
        connection = nil
    }
}

final class PathWatcher {
    weak var owner: AppModel?
    private let monitor = NWPathMonitor()

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.owner?.pathChanged(path.status == .satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "net.wa7brm.openuvbridge.path"))
    }
}
