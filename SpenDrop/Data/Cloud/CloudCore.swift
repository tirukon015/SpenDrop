import Foundation
import Security

// MARK: - Configuration

/// Public client configuration for the Supabase project (URL + anon key). The anon key is designed to be public;
/// access is enforced by Row Level Security on the server. No service-role/admin key is ever shipped in the app.
/// Loaded from `CloudConfig/SupabaseConfig.plist` (git-ignored). Missing file = cloud features disabled.
public struct SupabaseConfig: Equatable {
    public let url: URL
    public let anonKey: String
    /// Custom URL scheme the OAuth redirect returns to (registered in Info.plist).
    public static let callbackScheme = "spendrop"
    public static let redirectURL = "spendrop://auth-callback"

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    public static func load(bundle: Bundle = .main) -> SupabaseConfig? {
        guard let fileURL = bundle.url(forResource: "SupabaseConfig", withExtension: "plist", subdirectory: "CloudConfig"),
              let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urlString = (plist["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let key = (plist["SUPABASE_ANON_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString), url.scheme == "https", !key.isEmpty, !key.hasPrefix("YOUR_") else {
            return nil
        }
        return SupabaseConfig(url: url, anonKey: key)
    }
}

// MARK: - Errors

public enum CloudError: LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    case offline
    case invalidCredentials
    case emailNotConfirmed
    case emailAlreadyRegistered
    case weakPassword(String)
    case sessionExpired
    case cancelled
    case unsupportedBackup(Int)
    case invalidResponse
    case server(status: Int, message: String)
    case safetyBackupFailed

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Cloud backup isn't set up in this version of SpenDrop."
        case .notSignedIn: return "Sign in to enable cloud backup."
        case .offline: return "You're offline. Your data is safe on this iPhone; cloud backup will run when you're back online."
        case .invalidCredentials: return "Incorrect email or password."
        case .emailNotConfirmed: return "Please confirm your email address first, then sign in."
        case .emailAlreadyRegistered: return "An account with this email already exists. Sign in instead."
        case .weakPassword(let message): return message.isEmpty ? "Please choose a stronger password." : message
        case .sessionExpired: return "Your session has expired. Please sign in again. Local data remains on this iPhone."
        case .cancelled: return "Sign-in was cancelled."
        case .unsupportedBackup(let version): return "This backup was made by a newer version of SpenDrop (format \(version)). Update the app to restore it."
        case .invalidResponse: return "The server sent an unexpected response. Please try again."
        case .server(let status, let message): return message.isEmpty ? "Server error (\(status)). Please try again." : message
        case .safetyBackupFailed: return "Couldn't save a safety copy of your current data, so nothing was restored."
        }
    }
}

