import Foundation
import Synchronization

/// A plain text log on this Mac, so a problem can be read back afterwards instead of guessed at.
///
/// `~/Library/Logs/Mac Hue Control/Mac Hue Control.log`, one line per event:
/// `2026-11-23 11:28:05 ERROR command light 3 failed: bridge unreachable (URLError -1001 timed out)`.
///
/// It never holds personal data: no addresses, bridge ids, light, room, zone or scene names or ids. Lights and rooms
/// are told apart by anonymous labels ("light 3", "room 1") numbered in the order first seen since the app started,
/// so they mean nothing outside one run. Errors are logged by kind and code, never by the system's message text
/// (some of those name the bridge's address).
///
/// Nothing is written until the app calls `start(...)`, so tests never touch the real log.
public enum Log {
    public static func error(_ area: String, _ text: String) { write("ERROR", area, text) }
    public static func warn(_ area: String, _ text: String) { write("WARN", area, text) }
    public static func info(_ area: String, _ text: String) { write("INFO", area, text) }
    /// Only written when the app was started with `--verbose` (a trace of every request, for chasing a rare fault).
    public static func debug(_ area: String, _ text: String) {
        if verbose { write("DEBUG", area, text) }
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/Mac Hue Control/Mac Hue Control.log")
    }

    /// Starts logging to `url` and writes the start line. Labels start again from 1.
    public static func start(url: URL = defaultURL, verbose: Bool = false, startLine: String) {
        state.withLock {
            $0.file = LogFile(url: url)
            $0.verbose = verbose
            $0.labels = [:]
        }
        info("app", startLine + "; labels below are numbered from here")
    }

    public static var verbose: Bool { state.withLock { $0.verbose } }

    /// An anonymous label for a light, room, zone or scene ("light 3"), the same for the same id within one run.
    public static func label(_ kind: String, _ id: String) -> String {
        state.withLock { s in
            let key = kind + "/" + id
            if let n = s.labels[key] { return "\(kind) \(n)" }
            let n = s.labels.keys.filter { $0.hasPrefix(kind + "/") }.count + 1
            s.labels[key] = n
            return "\(kind) \(n)"
        }
    }

    public static func label(_ target: Target) -> String {
        let kind = switch target.kind {
        case .light: "light"
        case .groupedLight: "room"
        case .scene: "scene"
        }
        return label(kind, target.id)
    }

    /// An error in words safe to log: its kind and code, never its message text.
    public static func describe(_ error: Error) -> String {
        if let hue = error as? HueError { return hue.logKind }
        if error is CancellationError { return "cancelled" }
        if let url = error as? URLError { return "URLError \(url.errorCode) \(urlErrorWords(url.code))" }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }

    /// Waits until every line so far is on disk (for tests).
    public static func flush() { state.withLock { $0.file }?.flush() }

    // MARK: Plumbing

    private struct State {
        var file: LogFile?
        var verbose = false
        var labels: [String: Int] = [:]
    }
    private static let state = Mutex(State())

    private static func write(_ level: String, _ area: String, _ text: String) {
        guard let file = state.withLock({ $0.file }) else { return }
        file.append(LogFile.line(level: level, area: area, text: text, date: Date()))
    }

    private static func urlErrorWords(_ code: URLError.Code) -> String {
        switch code {
        case .timedOut: "timed out"
        case .cannotConnectToHost: "cannot connect"
        case .cannotFindHost: "cannot find host"
        case .notConnectedToInternet: "no network"
        case .networkConnectionLost: "connection lost"
        case .secureConnectionFailed: "secure connection failed"
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .serverCertificateHasBadDate: "certificate refused"
        case .cancelled: "cancelled"
        case .badServerResponse: "bad answer"
        default: ""
        }
    }
}

/// One log file: lines are appended in order on a background queue, and the file is rotated past `maxBytes`
/// (renamed to `.log.1`, replacing the previous one). A failure to write is ignored: logging never breaks the app.
public final class LogFile: Sendable {
    public let url: URL
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "MacHueControl.log")

    public init(url: URL, maxBytes: Int = 1_000_000) {
        self.url = url
        self.maxBytes = maxBytes
    }

    public func append(_ line: String) {
        queue.async { [url, maxBytes] in
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
                let old = url.appendingPathExtension("1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    public func flush() { queue.sync {} }

    /// `2026-11-23 11:28:05 ERROR area text`, in the Mac's own time zone.
    public static func line(level: String, area: String, text: String, date: Date,
                            timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        return "\(stamp) \(level) \(area) \(oneLine)"
    }
}

extension Command {
    /// Which settings the command changes ("on, dimming"), without their values.
    public var fieldNames: String {
        var names: [String] = []
        if on != nil { names.append("on") }
        if dimming != nil { names.append("dimming") }
        if color != nil { names.append("color") }
        if colorTemperature != nil { names.append("white") }
        if gradient != nil { names.append("gradient") }
        if recall != nil { names.append("recall") }
        return names.joined(separator: ", ")
    }
}

extension HueError {
    /// The kind of problem, for the log. Never includes the bridge's own text.
    public var logKind: String {
        switch self {
        case .unreachable: "bridge unreachable"
        case .localNetworkDenied: "Local Network access denied"
        case .notAuthorized: "bridge no longer accepts the app key"
        case .certificateChanged: "bridge certificate changed"
        case .rateLimited: "bridge busy (rate limited)"
        case .notABridge: "no Hue Bridge answered"
        case .linkButtonNotPressed: "link button not pressed in time"
        case .bridgeSaid: "bridge refused the request"
        case .unexpectedAnswer: "bridge answer not understood"
        }
    }
}
