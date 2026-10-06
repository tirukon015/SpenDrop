import Foundation
import AuthenticationServices
import CryptoKit
import Observation
import UIKit

public struct AuthUser: Codable, Equatable {
    public let id: String
    public let email: String?
    public let name: String?
    /// "google" or "email".
    public let provider: String

    public var providerDisplayName: String { provider == "google" ? "Google" : "Email" }
}

public struct AuthSession: Codable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var user: AuthUser
}

/// Opens the OAuth page and returns the callback URL. Abstracted so tests never open a browser.
@MainActor
public protocol WebAuthLauncher: AnyObject {
    func start(url: URL, callbackScheme: String) async throws -> URL
}

/// Apple's ASWebAuthenticationSession (the supported way to run OAuth from an iOS app).
@MainActor
public final class SystemWebAuthLauncher: NSObject, WebAuthLauncher, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    public func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CloudError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? CloudError.invalidResponse)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: CloudError.invalidResponse)
            }
        }
    }

    nonisolated public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

/// SpenDrop account sign-in using Supabase Auth's official HTTP API (the same endpoints the official SDKs call).
/// Local-first: signing in or out never touches the local SwiftData store.
@MainActor
@Observable
public final class AuthService {
    public enum State: Equatable {
        case notConfigured
        case signedOut(message: String?)
        case signedIn(AuthUser)
    }

    public enum SignUpResult: Equatable {
        case signedIn
        /// The project requires email confirmation; the user must tap the link, then sign in.
        case confirmationRequired
    }

    public static let shared: AuthService = {
        // UI tests never touch the real Keychain or the network. `--ui-testing-signed-in` shows a signed-in
        // Google user so the Account screen can be checked without a real Google login.
        if ExpenseDataContainer.isUITesting {
            let store = MemorySecureStore()
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-signed-in") {
                let user = AuthUser(id: "ui-test-user", email: "ui.test@gmail.com", name: "UI Test", provider: "google")
                let session = AuthSession(accessToken: "ui-test", refreshToken: "ui-test",
                                          expiresAt: Date().addingTimeInterval(86_400), user: user)
                if let data = try? JSONEncoder().encode(session) { store.write(data, for: sessionKey) }
            }
            return AuthService(config: SupabaseConfig.load(), transport: OfflineTransport(), store: store)
        }
        return AuthService(config: SupabaseConfig.load(), transport: URLSessionTransport(),
                           store: KeychainStore(service: "com.spendrop.SpenDrop.auth"))
    }()

    /// Used only by UI tests: every request fails as "offline".
    private struct OfflineTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw CloudError.offline }
    }

    public private(set) var state: State
    public let config: SupabaseConfig?
    @ObservationIgnored private let transport: HTTPTransport
    @ObservationIgnored private let store: SecureStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var session: AuthSession?
    @ObservationIgnored private static let sessionKey = "session"

    public init(config: SupabaseConfig?, transport: HTTPTransport, store: SecureStore, now: @escaping () -> Date = Date.init) {
        self.config = config
        self.transport = transport
        self.store = store
        self.now = now
        if config == nil {
            state = .notConfigured
        } else if let data = store.read(Self.sessionKey), let saved = try? JSONDecoder().decode(AuthSession.self, from: data) {
            session = saved
            state = .signedIn(saved.user)
        } else {
            state = .signedOut(message: nil)
        }
    }

    public var currentUser: AuthUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    // MARK: Email / password

    /// Creates the account. The confirmation email links back to `spendrop://auth-callback` (never the Site URL)
    /// with a PKCE code; opening it on this iPhone signs the user in (see `handleAuthCallback`).
    public func signUp(email: String, password: String) async throws -> SignUpResult {
        let pkce = PKCE.make()
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespaces), "password": password,
            "code_challenge": pkce.challenge, "code_challenge_method": "s256"])
        savePendingEmailFlow(.init(verifier: pkce.verifier, kind: .signup, createdAt: now()))
        let data = try await post(path: "/auth/v1/signup", query: [URLQueryItem(name: "redirect_to", value: SupabaseConfig.redirectURL)], body: body)
        if let session = try? parseSession(data, provider: "email") {
            clearPendingEmailFlow()
            save(session)
            return .signedIn
        }
        return .confirmationRequired
    }

    /// Sends a password-reset email whose link returns to `spendrop://auth-callback`. Supabase answers the same
    /// way whether or not the address has an account, so this never reveals who is registered.
    public func requestPasswordReset(email: String) async throws {
        let pkce = PKCE.make()
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespaces),
            "code_challenge": pkce.challenge, "code_challenge_method": "s256"])
        savePendingEmailFlow(.init(verifier: pkce.verifier, kind: .recovery, createdAt: now()))
        _ = try await post(path: "/auth/v1/recover", query: [URLQueryItem(name: "redirect_to", value: SupabaseConfig.redirectURL)], body: body)
    }

    // MARK: Email links (confirmation and password reset)

    public enum EmailLinkResult: Equatable {
        /// Confirmation link opened on this iPhone: the account is verified and signed in.
        case signedIn
        /// Verified, but the request came from another device or an older install: sign in with email and password.
        case verifiedSignInNeeded
        /// Password-reset link: signed in only to choose a new password.
        case passwordRecovery
        case failed(String)
    }

    struct PendingEmailFlow: Codable, Equatable {
        enum Kind: String, Codable { case signup, recovery }
        let verifier: String
        let kind: Kind
        let createdAt: Date
    }

    /// True after a password-reset link until a new password is saved (or the reset is cancelled).
    public private(set) var awaitingNewPassword = false
    @ObservationIgnored private static let pendingFlowKey = "pendingEmailFlow"

    /// Handles `spendrop://auth-callback` links from confirmation and password-reset emails. Returns nil for any
    /// other URL. (Google sign-in's callback is delivered to ASWebAuthenticationSession and never arrives here.)
    public func handleAuthCallback(_ url: URL) async -> EmailLinkResult? {
        guard url.scheme == SupabaseConfig.callbackScheme, url.host == "auth-callback", config != nil else { return nil }
        var items: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { items[item.name] = item.value ?? "" }
        if let fragment = url.fragment, let parsed = URLComponents(string: "x:/?" + fragment)?.queryItems {
            for item in parsed { items[item.name] = item.value ?? "" }
        }

        if let error = items["error_code"] ?? items["error"] {
            let expired = error.contains("otp_expired") || (items["error_description"] ?? "").lowercased().contains("expired")
            return .failed(expired ? CloudError.linkExpired.errorDescription! : (items["error_description"]?.replacingOccurrences(of: "+", with: " ") ?? "This link couldn't be used. Please request a new one."))
        }
        let pending = loadPendingEmailFlow()
        do {
            if let code = items["code"], !code.isEmpty {
                guard let pending else { return .verifiedSignInNeeded }
                let body = try JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": pending.verifier])
                let data = try await post(path: "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "pkce")], body: body)
                save(try parseSession(data, provider: "email"))
                clearPendingEmailFlow()
                if pending.kind == .recovery {
                    awaitingNewPassword = true
                    return .passwordRecovery
                }
                return .signedIn
            }
            if let access = items["access_token"], let refresh = items["refresh_token"] {
                // Implicit-flow link (older emails): read the user, then keep the session the same way.
                let userData = try await request(method: "GET", path: "/auth/v1/user", token: access, body: nil)
                let user = (try? JSONSerialization.jsonObject(with: userData)) ?? [:]
                let sessionJSON: [String: Any] = ["access_token": access, "refresh_token": refresh,
                                                  "expires_in": Double(items["expires_in"] ?? "") ?? 3600, "user": user]
                save(try parseSession(JSONSerialization.data(withJSONObject: sessionJSON), provider: "email"))
                clearPendingEmailFlow()
                if items["type"] == "recovery" {
                    awaitingNewPassword = true
                    return .passwordRecovery
                }
                return .signedIn
            }
            return .verifiedSignInNeeded
        } catch CloudError.offline {
            return .failed("You're offline. Connect to the internet and open the link again.")
        } catch let error as CloudError {
            if error == .linkExpired, pending?.kind == .signup { return .failed("This link has expired or belongs to an older request. If your email is already verified, sign in; otherwise create the account again to get a new link.") }
            return .failed(error.errorDescription ?? "This link couldn't be used. Please request a new one.")
        } catch {
            return .failed("This link couldn't be used. Please request a new one.")
        }
    }

    /// Saves the new password chosen after a reset link, then signs out so the user signs in with it.
    public func updatePassword(_ newPassword: String) async throws {
        let token = try await validAccessToken()
        let body = try JSONSerialization.data(withJSONObject: ["password": newPassword])
        try await request(method: "PUT", path: "/auth/v1/user", token: token, body: body)
        awaitingNewPassword = false
        await signOut(message: "Password updated. Sign in with your new password.")
    }

    /// Leaves the reset without changing the password (the temporary session is ended).
    public func cancelPasswordRecovery() async {
        awaitingNewPassword = false
        await signOut()
    }

    private func savePendingEmailFlow(_ flow: PendingEmailFlow) {
        if let data = try? JSONEncoder().encode(flow) { store.write(data, for: Self.pendingFlowKey) }
    }

    private func loadPendingEmailFlow() -> PendingEmailFlow? {
        store.read(Self.pendingFlowKey).flatMap { try? JSONDecoder().decode(PendingEmailFlow.self, from: $0) }
    }

    private func clearPendingEmailFlow() {
        store.delete(Self.pendingFlowKey)
    }

    public func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email.trimmingCharacters(in: .whitespaces), "password": password])
        let data = try await post(path: "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")], body: body)
        save(try parseSession(data, provider: "email"))
    }

    // MARK: Google (OAuth + PKCE)

    public struct PKCE: Equatable {
        public let verifier: String
        public let challenge: String

        public static func make() -> PKCE {
            var bytes = [UInt8](repeating: 0, count: 48)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let verifier = Data(bytes).base64URLEncoded()
            return PKCE(verifier: verifier, challenge: challenge(for: verifier))
        }

        public static func challenge(for verifier: String) -> String {
            Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        }
    }

    public func googleAuthorizeURL(pkce: PKCE) throws -> URL {
        guard let config else { throw CloudError.notConfigured }
        var components = URLComponents(url: config.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: SupabaseConfig.redirectURL),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        return components.url!
    }

    /// Signs in (or, for a Google account Supabase hasn't seen, creates the account). The same Google account
    /// always maps to the same Supabase user ID. Does nothing when someone is already signed in.
    public func signInWithGoogle(using launcher: WebAuthLauncher) async throws {
        guard currentUser == nil else { return }
        let pkce = PKCE.make()
        let callback = try await launcher.start(url: try googleAuthorizeURL(pkce: pkce), callbackScheme: SupabaseConfig.callbackScheme)
        try await completeGoogleSignIn(callbackURL: callback, verifier: pkce.verifier)
    }

    public func completeGoogleSignIn(callbackURL: URL, verifier: String) async throws {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let description = items.first(where: { $0.name == "error_description" || $0.name == "error" })?.value {
            throw CloudError.server(status: 400, message: description)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw CloudError.invalidResponse }
        let body = try JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": verifier])
        let data = try await post(path: "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "pkce")], body: body)
        save(try parseSession(data, provider: "google"))
    }

    // MARK: Session

    /// A valid access token, refreshed when it expires within a minute. An expired refresh token signs the
    /// user out of the cloud (local data untouched); being offline keeps the session.
    public func validAccessToken() async throws -> String {
        guard config != nil else { throw CloudError.notConfigured }
        guard var session else { throw CloudError.notSignedIn }
        if session.expiresAt.timeIntervalSince(now()) > 60 { return session.accessToken }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
            let data = try await post(path: "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: body)
            session = try parseSession(data, provider: session.user.provider)
            save(session)
            return session.accessToken
        } catch CloudError.offline {
            throw CloudError.offline
        } catch let error as CloudError {
            if case .server(let status, _) = error, status >= 500 { throw error }
            clearSession(message: CloudError.sessionExpired.errorDescription)
            throw CloudError.sessionExpired
        }
    }

    /// Called once at launch: the saved session is already restored from the Keychain; this refreshes it if it
    /// expired while the app was closed. A revoked session signs out of the cloud; offline keeps it.
    public func refreshSessionIfNeeded() async {
        guard session != nil else { return }
        _ = try? await validAccessToken()
    }

    public func signOut(message: String = "Signed out. Local data remains on this iPhone.") async {
        if let token = session?.accessToken {
            _ = try? await request(method: "POST", path: "/auth/v1/logout", token: token, body: nil)
        }
        awaitingNewPassword = false
        clearSession(message: message)
    }

    /// Deletes the cloud account through the server-side `delete_my_account` function (it can only delete the
    /// caller's own user). Cloud backups are removed first by `deleteCloudData`. Local data is NOT touched.
    public func deleteAccount(deleteCloudData: () async throws -> Void) async throws {
        let token = try await validAccessToken()
        try await deleteCloudData()
        _ = try await request(method: "POST", path: "/rest/v1/rpc/delete_my_account", token: token, body: Data("{}".utf8))
        clearSession(message: "Your cloud account was deleted. Local data remains on this iPhone.")
    }

    // MARK: Internals

    private func save(_ newSession: AuthSession) {
        session = newSession
        if let data = try? JSONEncoder().encode(newSession) {
            store.write(data, for: Self.sessionKey)
        }
        state = .signedIn(newSession.user)
    }

    private func clearSession(message: String?) {
        session = nil
        store.delete(Self.sessionKey)
        state = config == nil ? .notConfigured : .signedOut(message: message)
    }

    /// `provider` is how the user signed in this time; without it the account's first provider is used.
    func parseSession(_ data: Data, provider signInProvider: String? = nil) throws -> AuthSession {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let userJSON = json["user"] as? [String: Any],
              let id = userJSON["id"] as? String else {
            throw CloudError.invalidResponse
        }
        let expiresAt: Date
        if let at = json["expires_at"] as? Double {
            expiresAt = Date(timeIntervalSince1970: at)
        } else {
            expiresAt = now().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        }
        let appMeta = userJSON["app_metadata"] as? [String: Any] ?? [:]
        let userMeta = userJSON["user_metadata"] as? [String: Any] ?? [:]
        let user = AuthUser(id: id, email: userJSON["email"] as? String,
                            name: (userMeta["full_name"] as? String) ?? (userMeta["name"] as? String),
                            provider: signInProvider ?? ((appMeta["provider"] as? String) == "google" ? "google" : "email"))
        return AuthSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, user: user)
    }

    private func post(path: String, query: [URLQueryItem] = [], body: Data) async throws -> Data {
        try await request(method: "POST", path: path, query: query, token: nil, body: body)
    }

    @discardableResult
    func request(method: String, path: String, query: [URLQueryItem] = [], token: String?, body: Data?) async throws -> Data {
        guard let config else { throw CloudError.notConfigured }
        var components = URLComponents(url: config.url.appendingPathComponent(String(path.dropFirst())), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw CloudJSON.error(status: response.statusCode, data: data)
        }
        return data
    }
}

/// Form checks shown before any network call.
public enum AuthValidation {
    /// `confirm` is given when creating an account: then the password must also meet the project's rules.
    public static func problem(email: String, password: String, confirm: String?) -> String? {
        if let problem = emailProblem(email) { return problem }
        if password.isEmpty { return "Enter your password." }
        guard let confirm else { return nil }  // signing in: the server decides
        if let rule = passwordRuleProblem(password) { return rule }
        return confirm == password ? nil : "Passwords don't match."
    }

    /// Matches the Supabase project's password policy (lower- and uppercase letter and a number), plus
    /// SpenDrop's 8-character minimum.
    public static let passwordHint = "At least 8 characters, with an uppercase letter, a lowercase letter and a number."

    public static func passwordRuleProblem(_ password: String) -> String? {
        guard password.count >= 8 else { return "Password must be at least 8 characters." }
        guard password.contains(where: \.isLowercase), password.contains(where: \.isUppercase),
              password.contains(where: \.isNumber) else { return "Use an uppercase letter, a lowercase letter and a number." }
        return nil
    }

    public static func emailProblem(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !trimmed.contains(" ") else { return "Enter a valid email address." }
        return nil
    }

    public static func newPasswordProblem(_ password: String, confirm: String) -> String? {
        if let rule = passwordRuleProblem(password) { return rule }
        return confirm == password ? nil : "Passwords don't match."
    }
}

extension AuthService {
    /// Messages for people, not developers. Raw server text is only shown when it explains a password rule.
    public static func friendlyMessage(_ error: Error) -> String {
        switch error {
        case CloudError.offline: return "You're offline. Connect to the internet and try again."
        case CloudError.invalidCredentials: return "Incorrect email or password."
        case CloudError.emailNotConfirmed: return "Please verify your email first. Open the link we sent you, then sign in."
        case CloudError.emailAlreadyRegistered: return "An account with this email already exists. Sign in instead, or reset your password."
        case CloudError.weakPassword: return "Choose a stronger password. \(AuthValidation.passwordHint)"
        case CloudError.rateLimited: return CloudError.rateLimited.errorDescription!
        case CloudError.linkExpired: return CloudError.linkExpired.errorDescription!
        case CloudError.sessionExpired: return "Your session has expired. Please sign in again."
        case CloudError.notConfigured: return CloudError.notConfigured.errorDescription!
        default: return "Something went wrong. Please try again."
        }
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
