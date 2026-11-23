import Foundation

public struct PairedCredentials: Sendable, Equatable {
    public var appKey: String
    public var certificateHash: String?
}

/// Checking an address and pairing with the bridge (the "press the link button" step).
public enum BridgePairing {
    /// Asks the bridge at `host` for its name and id. Doesn't need pairing. Throws `.notABridge` if nothing answers.
    public static func probe(host: String) async throws -> DiscoveredBridge {
        let (session, _) = makeSession(host: host)
        defer { session.finishTasksAndInvalidate() }
        guard let url = URL(string: "https://\(host)/api/0/config") else { throw HueError.notABridge }
        do {
            let (data, _) = try await session.data(from: url)
            let config = try JSONDecoder().decode(Config.self, from: data)
            return DiscoveredBridge(id: config.bridgeid.lowercased(), name: config.name, host: host)
        } catch {
            Log.warn("setup", "checking an address found no bridge: \(Log.describe(error))")
            throw HueError.notABridge
        }
    }

    /// Asks the bridge for an app key every 2 seconds until someone presses its link button, or until `seconds` pass.
    /// `secondsLeft` is called once a second so the window can show a countdown.
    public static func pair(host: String, seconds: Int = 180,
                            secondsLeft: @escaping @Sendable (Int) async -> Void = { _ in }) async throws -> PairedCredentials {
        let (session, trust) = makeSession(host: host)
        defer { session.finishTasksAndInvalidate() }
        guard let url = URL(string: "https://\(host)/api") else { throw HueError.notABridge }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(#"{"devicetype":"mac_hue_control#mac","generateclientkey":true}"#.utf8)

        let deadline = ContinuousClock.now + .seconds(seconds)
        var lastAsk = ContinuousClock.now - .seconds(10)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let left = Int((deadline - ContinuousClock.now).components.seconds)
            await secondsLeft(max(left, 0))
            if ContinuousClock.now - lastAsk >= .seconds(2) {
                lastAsk = .now
                if let key = try await ask(session, req) {
                    return PairedCredentials(appKey: key, certificateHash: trust.seenHash)
                }
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw HueError.linkButtonNotPressed
    }

    /// Returns the key once the button was pressed, nil while it hasn't been.
    static func ask(_ session: URLSession, _ req: URLRequest) async throws -> String? {
        let data: Data
        do {
            (data, _) = try await session.data(for: req)
        } catch {
            Log.warn("setup", "pairing request failed: \(Log.describe(error))")
            throw HueError.unreachable
        }
        return try parsePairingAnswer(data)
    }

    static func parsePairingAnswer(_ data: Data) throws -> String? {
        guard let items = try? JSONDecoder().decode([PairAnswer].self, from: data), let first = items.first else {
            throw HueError.unexpectedAnswer
        }
        if let key = first.success?.username { return key }
        if let error = first.error {
            if error.type == 101 { return nil } // link button not pressed yet
            Log.warn("setup", "pairing refused by the bridge: Hue error type \(error.type)")
            throw HueError.bridgeSaid(error.description)
        }
        throw HueError.unexpectedAnswer
    }

    private static func makeSession(host: String) -> (URLSession, BridgeTrust) {
        let trust = BridgeTrust(host: host, pinnedHash: nil)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        return (URLSession(configuration: config, delegate: trust, delegateQueue: nil), trust)
    }

    private struct Config: Decodable { var name: String; var bridgeid: String }

    struct PairAnswer: Decodable {
        struct Success: Decodable { var username: String }
        struct Failure: Decodable { var type: Int; var description: String }
        var success: Success?
        var error: Failure?
    }
}
