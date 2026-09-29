import Foundation
import SwiftData

/// In-memory stand-in for the Supabase HTTP API (auth, storage, `backups` table). Records every request and can
/// inject failures. Used only by tests; the real server additionally enforces Row Level Security.
final class FakeSupabase: HTTPTransport, @unchecked Sendable {
    struct Failure {
        let match: String
        let status: Int?          // nil = network offline
        var remaining: Int
    }

    var requests: [URLRequest] = []
    var objects: [String: Data] = [:]
    var rows: [[String: Any]] = []
    var failures: [Failure] = []
    var authResponses: [String: (Int, [String: Any])] = [:]   // key: "signup", "password", "pkce", "refresh_token"
    var deletedAccount = false

    func fail(_ match: String, status: Int?, times: Int = 1) {
        failures.append(Failure(match: match, status: status, remaining: times))
    }

    static func sessionJSON(token: String = "access-1", refresh: String = "refresh-1", expiresIn: Double = 3600,
                            id: String = "user-123", email: String = "me@example.com", provider: String = "email") -> [String: Any] {
        ["access_token": token, "refresh_token": refresh, "expires_in": expiresIn, "token_type": "bearer",
         "user": ["id": id, "email": email, "app_metadata": ["provider": provider], "user_metadata": ["full_name": "Test User"]]]
    }

