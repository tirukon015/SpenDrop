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

