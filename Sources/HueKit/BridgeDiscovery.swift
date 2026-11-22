import Foundation
import Network

public struct DiscoveredBridge: Hashable, Sendable, Identifiable {
    public var id: String       // the bridge's own id (lowercase hex), stable even if its address changes
    public var name: String
    public var host: String     // IPv4 address
    public init(id: String, name: String, host: String) { self.id = id; self.name = name; self.host = host }
}

public struct DiscoveryResult: Sendable, Equatable {
    public var bridges: [DiscoveredBridge]
    public var localNetworkDenied: Bool
}

/// Finds Hue Bridges on the local network (they announce themselves as "_hue._tcp"). Nothing goes to the internet.
/// Needs the macOS "Local Network" permission.
public final class BridgeDiscovery: Sendable {
    private let serviceType: String

    public init(serviceType: String = "_hue._tcp") { self.serviceType = serviceType }

    /// Always finishes: after the first bridge is found plus a short grace period, or after `maxWait` at the latest.
    public func discover(maxWait: TimeInterval = 5) async -> DiscoveryResult {
        await withCheckedContinuation { continuation in
            let session = Session(type: serviceType, maxWait: maxWait) { continuation.resume(returning: $0) }
            session.start()
        }
    }

    /// One search. Everything runs on one serial queue, so the mutable state needs no locks.
    ///
    /// Lesson from Mac Sonos Control: the timers below hold the session *strongly* on purpose. With [weak self] the
    /// session was freed before its timer fired and the search never finished.
    private final class Session: @unchecked Sendable {
        private let queue = DispatchQueue(label: "mac-hue-control.discovery")
        private let type: String
        private let maxWait: TimeInterval
        private let done: (DiscoveryResult) -> Void
        private var browser: NWBrowser?
        private var connections: [NWConnection] = []
        private var found: [DiscoveredBridge] = []
        private var denied = false
        private var finished = false
        private var graceScheduled = false

        init(type: String, maxWait: TimeInterval, done: @escaping (DiscoveryResult) -> Void) {
            self.type = type
            self.maxWait = maxWait
            self.done = done
        }

        func start() {
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: .tcp)
            self.browser = browser
            browser.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error), .failed(let error):
                    if case .dns(let code) = error, code == -65570 { // "policy denied": no Local Network access
                        self.denied = true
                        self.finish()
                    }
                default: break
                }
            }
            browser.browseResultsChangedHandler = { results, _ in
                for result in results { self.resolve(result) }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + maxWait) { self.finish() }
        }

        private func resolve(_ result: NWBrowser.Result) {
            guard case .service(let serviceName, _, _, _) = result.endpoint else { return }
            var txtID: String?
            if case .bonjour(let txt) = result.metadata, let id = txt["bridgeid"], !id.isEmpty { txtID = id.lowercased() }
            let bridgeID = txtID ?? serviceName.lowercased()
            guard !found.contains(where: { $0.id == bridgeID }) else { return }

            let parameters = NWParameters.tcp
            (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
            let connection = NWConnection(to: result.endpoint, using: parameters)
            connections.append(connection)
            connection.stateUpdateHandler = { [weak connection] state in
                guard let connection else { return }
                switch state {
                case .ready:
                    if case .hostPort(let host, _)? = connection.currentPath?.remoteEndpoint,
                       case .ipv4(let address) = host {
                        let ip = "\(address)".components(separatedBy: "%")[0]
                        if !self.found.contains(where: { $0.id == bridgeID }) {
                            self.found.append(DiscoveredBridge(id: bridgeID, name: serviceName, host: ip))
                        }
                        self.finishSoon()
                    }
                    connection.cancel()
                case .failed:
                    connection.cancel()
                default: break
                }
            }
            connection.start(queue: queue)
        }

        /// Once one bridge is found, wait a moment for any others, then stop.
        private func finishSoon() {
            guard !graceScheduled else { return }
            graceScheduled = true
            queue.asyncAfter(deadline: .now() + 0.6) { self.finish() }
        }

        private func finish() {
            guard !finished else { return }
            finished = true
            browser?.cancel()
            connections.forEach { $0.cancel() }
            done(DiscoveryResult(bridges: found, localNetworkDenied: denied && found.isEmpty))
        }
    }
}
