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

// MARK: - HTTP

public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                throw CloudError.offline
            case .cancelled:
                throw CloudError.cancelled
            default:
                throw CloudError.server(status: error.errorCode, message: error.localizedDescription)
            }
        }
    }
}

enum CloudJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = CloudJSON.parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Accepts Postgres timestamptz ("2026-09-29T10:00:00.123456+00:00") and plain ISO 8601.
    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        // Postgres may send more than 3 fractional digits; trim to milliseconds and retry.
        if let dot = text.firstIndex(of: "."), let zone = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let digits = text[text.index(after: dot)..<zone].prefix(3)
            return fractional.date(from: String(text[..<dot]) + "." + digits + String(text[zone...]))
        }
        return nil
    }

    /// Maps a Supabase error body to a user-facing error.
    static func error(status: Int, data: Data) -> CloudError {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (body["error_code"] as? String) ?? (body["error"] as? String) ?? (body["code"] as? String) ?? ""
        let message = (body["msg"] as? String) ?? (body["error_description"] as? String) ?? (body["message"] as? String) ?? ""
        let lower = (code + " " + message).lowercased()
        if lower.contains("invalid_credentials") || lower.contains("invalid login credentials") || (code == "invalid_grant" && lower.contains("credentials")) {
            return .invalidCredentials
        }
        if lower.contains("email_not_confirmed") || lower.contains("email not confirmed") { return .emailNotConfirmed }
        if lower.contains("user_already_exists") || lower.contains("already registered") || lower.contains("email_exists") { return .emailAlreadyRegistered }
        if lower.contains("weak_password") || lower.contains("password should") { return .weakPassword(message) }
        if lower.contains("refresh_token") || lower.contains("jwt expired") || status == 401 { return .sessionExpired }
        return .server(status: status, message: message)
    }
}

// MARK: - Secure storage (Keychain)

public protocol SecureStore: AnyObject {
    func read(_ key: String) -> Data?
    @discardableResult func write(_ data: Data, for key: String) -> Bool
    func delete(_ key: String)
}

/// Stores the auth session in the Keychain (this device only). Never in SwiftData or UserDefaults.
public final class KeychainStore: SecureStore {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

