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

