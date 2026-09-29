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

    public static let shared = AuthService(config: SupabaseConfig.load(), transport: URLSessionTransport(),
                                           store: KeychainStore(service: "com.spendrop.SpenDrop.auth"))

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

    public func signUp(email: String, password: String) async throws -> SignUpResult {
        let body = try JSONSerialization.data(withJSONObject: ["email": email.trimmingCharacters(in: .whitespaces), "password": password])
        let data = try await post(path: "/auth/v1/signup", body: body)
        if let session = try? parseSession(data) {
            save(session)
            return .signedIn
        }
        return .confirmationRequired
    }

    public func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email.trimmingCharacters(in: .whitespaces), "password": password])
        let data = try await post(path: "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")], body: body)
        save(try parseSession(data))
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

    public func signInWithGoogle(using launcher: WebAuthLauncher) async throws {
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
        save(try parseSession(data))
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
            session = try parseSession(data)
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

    public func signOut() async {
        if let token = session?.accessToken {
            _ = try? await request(method: "POST", path: "/auth/v1/logout", token: token, body: nil)
        }
        clearSession(message: "Signed out. Local data remains on this iPhone.")
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

    func parseSession(_ data: Data) throws -> AuthSession {
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
                            provider: (appMeta["provider"] as? String) == "google" ? "google" : "email")
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

