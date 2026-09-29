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

