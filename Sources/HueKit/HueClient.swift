import Foundation

/// Talks to one paired Hue Bridge over the local network (Hue API v2).
public final class HueClient: Sendable {
    public let host: String
    private let appKey: String
    private let trust: BridgeTrust
    private let session: URLSession
    private let streamSession: URLSession

    public init(host: String, appKey: String, certificateHash: String?) {
        self.host = host
        self.appKey = appKey
        self.trust = BridgeTrust(host: host, pinnedHash: certificateHash)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)
        // The live stream stays open for a long time with nothing to say, so it gets a long idle timeout.
        let streamConfig = URLSessionConfiguration.ephemeral
        streamConfig.timeoutIntervalForRequest = 60 * 60
        streamConfig.timeoutIntervalForResource = 24 * 60 * 60
        self.streamSession = URLSession(configuration: streamConfig, delegate: trust, delegateQueue: nil)
    }

    /// The certificate fingerprint seen (saved if none was remembered yet).
    public var seenCertificateHash: String? { trust.seenHash }

    /// Stops all traffic. The client can't be used afterwards.
    public func close() {
        session.invalidateAndCancel()
        streamSession.invalidateAndCancel()
    }

    // MARK: Reading

    public func snapshot() async throws -> Snapshot {
        async let lights: [Light] = list("light")
        async let rooms: [Area] = list("room")
        async let zones: [Area] = list("zone")
        async let grouped: [GroupedLight] = list("grouped_light")
        async let scenes: [Scene] = list("scene")
        async let devices: [Device] = list("device")
        return try await Snapshot(lights: lights, rooms: rooms, zones: zones, groupedLights: grouped,
                                  scenes: scenes, devices: devices)
    }

    public func list<T: Decodable>(_ type: String) async throws -> [T] {
        let data = try await perform(try request(path: "/clip/v2/resource/\(type)"))
        do {
            return try JSON.decoder().decode(Envelope<T>.self, from: data).data
        } catch {
            throw HueError.unexpectedAnswer
        }
    }

    // MARK: Changing

    public func send(_ command: Command, to target: Target) async throws {
        var req = try request(path: "/clip/v2/resource/\(target.kind.rawValue)/\(target.id)")
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try command.json()
        _ = try await perform(req)
    }

    // MARK: Live updates

    /// Listens to the bridge's live event stream until it ends or fails. `onConnected` runs once the stream is open
    /// (a good moment to re-read everything, so nothing that happened while disconnected is missed).
    public func listen(onConnected: @Sendable () async -> Void,
                       onEvents: @Sendable ([HueEvent]) async -> Void) async throws {
        var req = try request(path: "/eventstream/clip/v2")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 60 * 60
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await streamSession.bytes(for: req)
        } catch {
            throw mapped(error)
        }
        try check(response, data: Data())
        await onConnected()

        var parser = EventStreamParser()
        var chunk: [UInt8] = []
        chunk.reserveCapacity(4096)
        do {
            for try await byte in bytes {
                chunk.append(byte)
                // Lines are handed over as soon as they're complete.
                guard byte == UInt8(ascii: "\n") else { continue }
                let messages = parser.feed(chunk)
                chunk.removeAll(keepingCapacity: true)
                let events = messages.flatMap(EventStreamParser.events(from:))
                if !events.isEmpty { await onEvents(events) }
            }
        } catch {
            throw mapped(error)
        }
    }

    // MARK: Plumbing

    private func request(path: String) throws -> URLRequest {
        // A bad address gives a clear message instead of a crash.
        guard let url = URL(string: "https://\(host)\(path)") else { throw HueError.notABridge }
        var req = URLRequest(url: url)
        req.setValue(appKey, forHTTPHeaderField: "hue-application-key")
        return req
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw mapped(error)
        }
        try check(response, data: data)
        return data
    }

    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw HueError.unexpectedAnswer }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw HueError.notAuthorized
        case 429, 503: throw HueError.rateLimited
        default:
            if let envelope = try? JSON.decoder().decode(Envelope<Never2>.self, from: data),
               let first = envelope.errors.first {
                throw HueError.bridgeSaid(first.description)
            }
            throw HueError.bridgeSaid("error \(http.statusCode)")
        }
    }

    private func mapped(_ error: Error) -> HueError {
        if trust.sawMismatch { return .certificateChanged }
        return HueError.from(error)
    }
}

/// Placeholder for answers where only the error list matters.
struct Never2: Decodable {}
