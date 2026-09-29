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

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!
        let path = url.path
        let query = url.query ?? ""
        let method = request.httpMethod ?? "GET"

        if let index = failures.firstIndex(where: { (path + "?" + query).contains($0.match) && $0.remaining > 0 }) {
            failures[index].remaining -= 1
            guard let status = failures[index].status else { throw CloudError.offline }
            return respond(status, ["msg": "Injected failure", "code": status])
        }

        switch (method, path) {
        case ("POST", "/auth/v1/signup"):
            let (status, body) = authResponses["signup"] ?? (200, Self.sessionJSON())
            return respond(status, body)
        case ("POST", "/auth/v1/token"):
            let grant = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "grant_type" }?.value ?? ""
            let (status, body) = authResponses[grant] ?? (200, Self.sessionJSON())
            return respond(status, body)
        case ("POST", "/auth/v1/logout"):
            return respond(204, [:])
        case ("POST", "/rest/v1/rpc/delete_my_account"):
            deletedAccount = true
            return respond(204, [:])
        case ("POST", let p) where p.hasPrefix("/storage/v1/object/backups/"):
            let key = String(p.dropFirst("/storage/v1/object/backups/".count))
            guard objects[key] == nil else { return respond(409, ["message": "The resource already exists"]) }
            objects[key] = request.httpBody ?? Data()
            return respond(200, ["Key": "backups/" + key])
        case ("GET", let p) where p.hasPrefix("/storage/v1/object/authenticated/backups/"):
            let key = String(p.dropFirst("/storage/v1/object/authenticated/backups/".count))
            guard let data = objects[key] else { return respond(404, ["message": "Object not found"]) }
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        case ("DELETE", "/storage/v1/object/backups"):
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            for prefix in body?["prefixes"] as? [String] ?? [] { objects[prefix] = nil }
            return respond(200, [:])
        case ("POST", "/rest/v1/backups"):
            guard var row = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] else { return respond(400, [:]) }
            row["created_at"] = "2026-09-29T10:15:30.123456+00:00"
            rows.append(row)
            return respond(201, [:])
        case ("GET", "/rest/v1/backups"):
            var result = rows
            if query.contains("offset=") {
                let offset = Int(query.components(separatedBy: "offset=").last ?? "0") ?? 0
                result = Array(rows.reversed().dropFirst(offset))
            }
            return respondArray(result)
        case ("DELETE", "/rest/v1/backups"):
            if query.contains("not.is.null") {
                rows.removeAll()
            } else if let ids = query.components(separatedBy: "in.(").last?.dropLast() {
                let set = Set(ids.split(separator: ",").map(String.init))
                rows.removeAll { set.contains(($0["id"] as? String) ?? "") }
            }
            return respond(204, [:])
        default:
            return respond(404, ["message": "Unknown route \(method) \(path)"])
        }
    }

    private func respond(_ status: Int, _ body: [String: Any]) -> (Data, HTTPURLResponse) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return (data, HTTPURLResponse(url: URL(string: "https://fake.supabase.co")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func respondArray(_ body: [[String: Any]]) -> (Data, HTTPURLResponse) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return (data, HTTPURLResponse(url: URL(string: "https://fake.supabase.co")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// Opens nothing; returns a scripted callback URL (tests never launch a browser).
@MainActor
final class FakeWebAuthLauncher: WebAuthLauncher {
    var lastURL: URL?
    let callback: URL?
    init(callback: URL?) { self.callback = callback }
    func start(url: URL, callbackScheme: String) async throws -> URL {
        lastURL = url
        guard let callback else { throw CloudError.cancelled }
        return callback
    }
}

/// Authentication tests. `--run-auth-tests`
@MainActor
public struct AuthTests {
    static let config = SupabaseConfig(url: URL(string: "https://fake.supabase.co")!, anonKey: "public-anon-key")

