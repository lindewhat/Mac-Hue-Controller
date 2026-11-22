import CryptoKit
import Foundation
import Synchronization

/// Decides whether to trust the bridge's security certificate.
///
/// Hue Bridges use their own certificate that the Mac doesn't know, so normal checks would refuse it. Instead this
/// remembers the exact certificate the bridge showed when it was paired (pressing the link button proves it's your
/// bridge) and from then on only accepts that one certificate, and only from the bridge's address. Other websites
/// get the normal checks.
public final class BridgeTrust: NSObject, URLSessionDelegate, Sendable {
    private struct State {
        var pinned: String?
        var seen: String?
        var mismatch = false
    }

    private let host: String
    private let state: Mutex<State>

    /// `pinnedHash` nil means "trust whatever the bridge shows now" (only while pairing).
    public init(host: String, pinnedHash: String?) {
        self.host = host
        self.state = Mutex(State(pinned: pinnedHash))
    }

    /// The certificate fingerprint the bridge showed (to remember after pairing).
    public var seenHash: String? { state.withLock { $0.seen } }

    /// True once the bridge showed a different certificate from the remembered one.
    public var sawMismatch: Bool { state.withLock { $0.mismatch } }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let hash = Self.fingerprint(of: leaf)
        let accept = state.withLock { s -> Bool in
            s.seen = hash
            if let pinned = s.pinned {
                if pinned == hash { return true }
                s.mismatch = true
                return false
            }
            return true
        }
        if accept {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    static func fingerprint(of certificate: SecCertificate) -> String {
        let data = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
