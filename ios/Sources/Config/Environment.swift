import Foundation
import CMUXAuthCore

enum Environment {
    case development
    case production

    private static let secureAPIBaseURL = "https://api.cmux.sh"
    private static let processEnvironment = ProcessInfo.processInfo.environment

    static var current: Environment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    // MARK: - Local Config Override

    /// Reads from LocalConfig.plist (gitignored) for per-developer overrides
    private static let localConfig: [String: Any]? = {
        guard let path = Bundle.main.path(forResource: "LocalConfig", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return nil
        }
        return dict
    }()

    private func localOverride(devKey: String, prodKey: String, legacyKey: String? = nil) -> String? {
        Self.stringOverride(
            devKey: devKey,
            prodKey: prodKey,
            legacyKey: legacyKey,
            environment: self,
            environmentVariables: Self.processEnvironment,
            localConfig: Self.localConfig
        )
    }

    // MARK: - Stack Auth

    var stackAuthConfig: CMUXAuthConfig {
        CMUXAuthConfig.resolve(
            environment: currentAuthEnvironment,
            overrides: localConfigStringOverrides,
            developmentProjectId: "1467bed0-8522-45ee-a8d8-055de324118c",
            productionProjectId: "8a877114-b905-47c5-8b64-3a2d90679577",
            developmentPublishableClientKey: "pck_pt4nwry6sdskews2pxk4g2fbe861ak2zvaf3mqendspa0",
            productionPublishableClientKey: "pck_8761mjjmyqc84e1e8ga3rn0k1nkggmggwa3pyzzgntv70"
        )
    }

    var stackAuthProjectId: String {
        stackAuthConfig.projectId
    }

    var stackAuthPublishableKey: String {
        stackAuthConfig.publishableClientKey
    }

    // MARK: - Convex

    var convexURL: String {
        if let override = localOverride(
            devKey: "CONVEX_URL_DEV",
            prodKey: "CONVEX_URL_PROD",
            legacyKey: "CONVEX_URL"
        ) {
            return override
        }

        switch self {
        case .development:
            return "https://polite-canary-804.convex.cloud"
        case .production:
            return "https://adorable-wombat-701.convex.cloud"
        }
    }

    // MARK: - API URLs

    var apiBaseURL: String {
        let configuredValue = localOverride(
            devKey: "API_BASE_URL_DEV",
            prodKey: "API_BASE_URL_PROD",
            legacyKey: "API_BASE_URL"
        ) ?? defaultAPIBaseURL

        return Self.resolvedAPIBaseURL(
            candidate: configuredValue,
            environment: self,
            allowInsecureLocalOverride: Self.allowsInsecureLocalAPIBaseURL
        )
    }

    // MARK: - Debug Info

    var name: String {
        switch self {
        case .development: return "Development"
        case .production: return "Production"
        }
    }

    private var currentAuthEnvironment: CMUXAuthEnvironment {
        switch self {
        case .development:
            return .development
        case .production:
            return .production
        }
    }

    private var localConfigStringOverrides: [String: String] {
        guard let localConfig = Self.localConfig else {
            return [:]
        }

        var overrides: [String: String] = [:]
        for (key, value) in localConfig {
            if let stringValue = value as? String, !stringValue.isEmpty {
                overrides[key] = stringValue
            }
        }
        return overrides
    }

    private var defaultAPIBaseURL: String {
        switch self {
        case .development:
            return "http://localhost:3000"
        case .production:
            return Self.secureAPIBaseURL
        }
    }

    private static var allowsInsecureLocalAPIBaseURL: Bool {
        #if targetEnvironment(simulator) && DEBUG
        return true
        #else
        return false
        #endif
    }

    static func resolvedAPIBaseURL(
        candidate: String,
        environment: Environment,
        allowInsecureLocalOverride: Bool
    ) -> String {
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased() else {
            return secureFallbackAPIBaseURL(for: environment)
        }

        if scheme == "https" || allowInsecureLocalOverride {
            return candidate
        }

        NSLog("📱 Environment: Ignoring insecure API base URL on device: %@", candidate)
        return secureFallbackAPIBaseURL(for: environment)
    }

    private static func secureFallbackAPIBaseURL(for environment: Environment) -> String {
        switch environment {
        case .development, .production:
            return secureAPIBaseURL
        }
    }

    static func stringOverride(
        devKey: String,
        prodKey: String,
        legacyKey: String? = nil,
        environment: Environment,
        environmentVariables: [String: String],
        localConfig: [String: Any]?
    ) -> String? {
        let environmentKey = environment == .development ? devKey : prodKey
        for key in [environmentKey, legacyKey].compactMap({ $0 }) {
            if let value = environmentVariables[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        for key in [environmentKey, legacyKey].compactMap({ $0 }) {
            if let value = (localConfig?[key] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
