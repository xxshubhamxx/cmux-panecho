import Foundation

/// Privacy-mode-only outbound egress guard.
///
/// When `PRIVACY_MODE` is enabled (Panecho), block all `URLSession` traffic to
/// non-loopback network destinations, regardless of feature flags or runtime
/// settings. This provides a fail-closed safety net in addition to per-feature
/// privacy checks.
enum PrivacyEgressGuard {
    private static let localhostNames: Set<String> = [
        "localhost",
        "127.0.0.1",
        "::1",
        "[::1]",
        "cmux-loopback.localtest.me",
    ]

    static func installIfNeeded() {
        guard PrivacyMode.isEnabled else { return }
        URLProtocol.registerClass(PrivacyModeURLProtocol.self)
    }

    static func isAllowedURL(_ url: URL) -> Bool {
        guard PrivacyMode.isEnabled else { return true }

        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "file", "data", "about", "blob":
            return true
        case "http", "https", "ws", "wss":
            guard let host = url.host?.lowercased() else { return false }
            if localhostNames.contains(host) { return true }
            if host.hasPrefix("127.") { return true }
            return false
        default:
            return false
        }
    }
}

private final class PrivacyModeURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard PrivacyMode.isEnabled else { return false }
        guard let url = request.url else { return false }
        return !PrivacyEgressGuard.isAllowedURL(url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorDataNotAllowed,
            userInfo: [
                NSLocalizedDescriptionKey: "Privacy mode blocks outbound network access.",
                NSURLErrorFailingURLErrorKey: request.url as Any,
            ]
        )
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}
