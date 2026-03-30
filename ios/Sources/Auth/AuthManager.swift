import CMUXAuthCore
import Foundation
import StackAuth
import SwiftUI

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var currentUser: StackAuthUser?
    @Published var isLoading = false
    @Published var isRestoringSession = false

    private let stack = StackAuthApp.shared
    private let authUserCache = AuthUserCache.shared
    private let authSessionCache = AuthSessionCache.shared

    private init() {
        primeSessionState()
        Task {
            await checkExistingSession()
        }
    }

    private var clearAuthRequested: Bool {
        ProcessInfo.processInfo.environment["CMUX_UITEST_CLEAR_AUTH"] == "1"
    }

    private var autoLoginCredentials: AuthAutoLoginCredentials? {
        AuthLaunchConfig.autoLoginCredentials(
            from: ProcessInfo.processInfo.environment,
            clearAuth: clearAuthRequested,
            mockDataEnabled: UITestConfig.mockDataEnabled
        )
    }

    private var authFixtureUser: StackAuthUser? {
        AuthLaunchConfig.fixtureUser(
            from: ProcessInfo.processInfo.environment,
            clearAuth: clearAuthRequested,
            mockDataEnabled: UITestConfig.mockDataEnabled
        )
    }

    // MARK: - Session Management

    private func primeSessionState() {
        if clearAuthRequested {
            clearAuthState()
            Task {
                await clearPersistedAuthForUITest()
            }
            return
        }

        #if DEBUG
        if UITestConfig.mockDataEnabled {
            applyAuthState(
                CMUXAuthState.primed(
                    clearAuthRequested: false,
                    mockDataEnabled: true,
                    fixtureUser: nil,
                    autoLoginCredentials: nil,
                    cachedUser: nil,
                    hasTokens: false,
                    mockUser: uiTestMockUser
                )
            )
            return
        }

        if let authFixtureUser {
            print("🔐 AuthManager: Using auth fixture user")
            applyAuthState(
                CMUXAuthState.primed(
                    clearAuthRequested: false,
                    mockDataEnabled: false,
                    fixtureUser: authFixtureUser,
                    autoLoginCredentials: nil,
                    cachedUser: authFixtureUser,
                    hasTokens: true,
                    mockUser: uiTestMockUser
                )
            )
            return
        }

        if autoLoginCredentials != nil {
            print("🔐 AuthManager: Auto-login credentials detected")
            applyAuthState(
                CMUXAuthState.primed(
                    clearAuthRequested: false,
                    mockDataEnabled: false,
                    fixtureUser: nil,
                    autoLoginCredentials: autoLoginCredentials,
                    cachedUser: authUserCache.load(),
                    hasTokens: authSessionCache.hasTokens,
                    mockUser: uiTestMockUser
                )
            )
            return
        }
        #endif

        applyAuthState(
            CMUXAuthState.primed(
                clearAuthRequested: false,
                mockDataEnabled: false,
                fixtureUser: nil,
                autoLoginCredentials: nil,
                cachedUser: authUserCache.load(),
                hasTokens: authSessionCache.hasTokens,
                mockUser: uiTestMockUser
            )
        )
    }

    private func checkExistingSession() async {
        if clearAuthRequested {
            return
        }

        #if DEBUG
        if UITestConfig.mockDataEnabled {
            return
        }

        if let fixtureUser = authFixtureUser {
            print("🔐 AuthManager: Applying auth fixture user")
            authUserCache.save(fixtureUser)
            authSessionCache.setHasTokens(true)
            currentUser = fixtureUser
            isAuthenticated = true
            return
        }

        if let credentials = autoLoginCredentials, !authSessionCache.hasTokens {
            print("🔐 AuthManager: Starting auto-login for \(credentials.email)")
            await performAutoLogin(credentials)
            return
        }
        #endif

        let cachedUser = authUserCache.load()
        let hasAccessToken = await stack.getAccessToken() != nil
        let hasRefreshToken = await stack.getRefreshToken() != nil
        let hasStoredTokens = hasAccessToken || hasRefreshToken

        if hasStoredTokens {
            authSessionCache.setHasTokens(true)
            if currentUser == nil, let cachedUser {
                currentUser = cachedUser
            }
            await validateCachedSession(hasStoredTokens: hasStoredTokens)
            return
        }

        clearAuthState()
        await ConvexClientManager.shared.clearAuth()
    }

    private func performAutoLogin(_ credentials: AuthAutoLoginCredentials) async {
        do {
            try await signInWithPassword(email: credentials.email, password: credentials.password, setLoading: false)
        } catch {
            print("🔐 Auto-login failed: \(error)")
            clearAuthState()
        }
    }

    private func validateCachedSession(hasStoredTokens: Bool) async {
        do {
            if let user = try await stack.getUser(or: .returnNull) {
                await applySignedInUser(user)
                return
            }
        } catch {
            print("🔐 Session validation failed: \(error)")
        }

        if hasStoredTokens {
            authSessionCache.setHasTokens(true)
            isAuthenticated = true
            return
        }

        clearAuthState()
        await ConvexClientManager.shared.clearAuth()
    }

    private func applySignedInUser(_ user: CurrentUser) async {
        let mappedUser = await StackAuthUser(currentUser: user)
        currentUser = mappedUser
        isAuthenticated = true
        authUserCache.save(mappedUser)
        authSessionCache.setHasTokens(true)
        await ConvexClientManager.shared.syncAuth()
        await NotificationManager.shared.syncTokenIfPossible()
    }

    private func clearAuthState() {
        authUserCache.clear()
        authSessionCache.clear()
        applyAuthState(.cleared())
    }

    private func clearPersistedAuthForUITest() async {
        // UI tests only need deterministic local signed-out state at launch.
        // Clear persisted auth through the shared Convex logout path once,
        // instead of racing duplicate Stack Auth sign-out calls during init.
        await ConvexClientManager.shared.clearAuth()
    }

    // MARK: - Sign In Flow

    private var pendingNonce: String?

    #if DEBUG
    private struct DebugCredentials {
        let email: String
        let password: String
    }
    private var debugPasswordCredentials: DebugCredentials?
    #endif

    func sendCode(to email: String) async throws {
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        if email.trimmingCharacters(in: .whitespacesAndNewlines) == "42" {
            let creds = DebugCredentials(email: "l@l.com", password: "abc123")
            try await signInWithPassword(email: creds.email, password: creds.password, setLoading: false)
            debugPasswordCredentials = creds
            return
        }
        #endif

        let callbackUrl = Environment.current == .development
            ? "http://localhost:3000/auth/callback"
            : "https://cmux.dev/auth/callback"

        let nonce = try await stack.sendMagicLinkEmail(email: email, callbackUrl: callbackUrl)
        pendingNonce = nonce
    }

    func verifyCode(_ code: String) async throws {
        guard let nonce = pendingNonce else {
            throw AuthError.invalidCode
        }

        isLoading = true
        defer { isLoading = false }

        let fullCode = AuthMagicLinkCode.compose(code: code, nonce: nonce)
        try await stack.signInWithMagicLink(code: fullCode)
        try await completeSignIn()

        pendingNonce = nil
    }

    // MARK: - Password Sign In (Debug)

    func signInWithPassword(email: String, password: String, setLoading: Bool = true) async throws {
        if setLoading {
            isLoading = true
        }
        defer {
            if setLoading {
                isLoading = false
            }
        }

        try await stack.signInWithCredential(email: email, password: password)
        try await completeSignIn()
    }

    // MARK: - Apple Sign In

    func signInWithApple() async throws {
        isLoading = true
        defer { isLoading = false }

        try await stack.signInWithOAuth(
            provider: "apple",
            presentationContextProvider: AuthPresentationContextProvider.shared
        )
        try await completeSignIn()
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async throws {
        isLoading = true
        defer { isLoading = false }

        try await stack.signInWithOAuth(
            provider: "google",
            presentationContextProvider: AuthPresentationContextProvider.shared
        )
        try await completeSignIn()
    }

    private func completeSignIn() async throws {
        guard let user = try await stack.getUser(or: .throw) else {
            throw AuthError.unauthorized
        }
        await applySignedInUser(user)
    }

    func signOut() async {
        do {
            try await stack.signOut()
        } catch {
            print("🔐 Sign-out failed: \(error)")
        }

        clearAuthState()
        await NotificationManager.shared.unregisterFromServer()
        await ConvexClientManager.shared.clearAuth()
    }

    // MARK: - Access Token

    func getAccessToken() async throws -> String {
        if let accessToken = await stack.getAccessToken() {
            return accessToken
        }

        #if DEBUG
        if let credentials = debugPasswordCredentials {
            try? await signInWithPassword(
                email: credentials.email,
                password: credentials.password,
                setLoading: false
            )
            if let accessToken = await stack.getAccessToken() {
                return accessToken
            }
        }
        #endif

        throw AuthError.unauthorized
    }
}

private extension AuthManager {
    var uiTestMockUser: StackAuthUser {
        StackAuthUser(
            id: "uitest_user",
            primaryEmail: "uitest@cmux.local",
            displayName: "UI Test"
        )
    }

    func applyAuthState(_ state: CMUXAuthState) {
        currentUser = state.currentUser
        isAuthenticated = state.isAuthenticated
        isRestoringSession = state.isRestoringSession
    }
}

typealias AuthAutoLoginCredentials = CMUXAuthAutoLoginCredentials

enum AuthLaunchConfig {
    static func autoLoginCredentials(
        from environment: [String: String],
        clearAuth: Bool,
        mockDataEnabled: Bool
    ) -> AuthAutoLoginCredentials? {
        CMUXAuthLaunchConfig.autoLoginCredentials(
            from: environment,
            clearAuth: clearAuth,
            mockDataEnabled: mockDataEnabled
        )
    }

    static func fixtureUser(
        from environment: [String: String],
        clearAuth: Bool,
        mockDataEnabled: Bool
    ) -> StackAuthUser? {
        CMUXAuthLaunchConfig.fixtureUser(
            from: environment,
            clearAuth: clearAuth,
            mockDataEnabled: mockDataEnabled
        ).map { StackAuthUser(id: $0.id, primaryEmail: $0.primaryEmail, displayName: $0.displayName) }
    }
}

enum AuthMagicLinkCode {
    static func compose(code: String, nonce: String) -> String {
        CMUXAuthMagicLinkCode.compose(code: code, nonce: nonce)
    }
}

final class AuthSessionCache {
    static let shared = AuthSessionCache()
    private let cache = CMUXAuthSessionCache(
        keyValueStore: UserDefaults.standard,
        key: "auth_has_tokens"
    )

    private init() {}

    var hasTokens: Bool {
        cache.hasTokens
    }

    func setHasTokens(_ value: Bool) {
        cache.setHasTokens(value)
    }

    func clear() {
        cache.clear()
    }
}

final class AuthUserCache {
    static let shared = AuthUserCache()
    private let store = CMUXAuthIdentityStore(
        keyValueStore: UserDefaults.standard,
        key: "auth_cached_user"
    )

    private init() {}

    func save(_ user: StackAuthUser) {
        do {
            try store.save(user)
        } catch {
            print("🔐 Failed to cache user: \(error)")
        }
    }

    func load() -> StackAuthUser? {
        do {
            return try store.load()
        } catch {
            print("🔐 Failed to load cached user: \(error)")
            return nil
        }
    }

    func clear() {
        store.clear()
    }
}
