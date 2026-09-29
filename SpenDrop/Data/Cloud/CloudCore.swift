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

