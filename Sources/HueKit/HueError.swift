import Foundation

/// Problems, described in plain language for the menu and window.
public enum HueError: Error, LocalizedError, Equatable, Sendable {
    case unreachable
    case localNetworkDenied
    case notAuthorized
    case certificateChanged
    case rateLimited
    case notABridge
    case linkButtonNotPressed
    case bridgeSaid(String)
    case unexpectedAnswer

    public var errorDescription: String? {
        switch self {
        case .unreachable: "Can't reach your Hue Bridge right now. Is this Mac on the same network?"
        case .localNetworkDenied: "Local Network access is turned off, so the app can't see your Hue Bridge."
        case .notAuthorized: "The bridge no longer recognises this Mac. Set it up again."
        case .certificateChanged: "Your bridge's security certificate changed. Set the bridge up again to trust it."
        case .rateLimited: "The bridge is busy. Trying again."
        case .notABridge: "No Hue Bridge answered at that address."
        case .linkButtonNotPressed: "The link button on the bridge wasn't pressed in time."
        case .bridgeSaid(let text): "The bridge said: \(text)"
        case .unexpectedAnswer: "The bridge gave an answer the app didn't understand."
        }
    }

    /// Maps network errors to the plain-language ones above. (A changed certificate is spotted by BridgeTrust,
    /// which HueClient checks before calling this.)
    public static func from(_ error: Error) -> HueError {
        if let hue = error as? HueError { return hue }
        return .unreachable
    }
}
