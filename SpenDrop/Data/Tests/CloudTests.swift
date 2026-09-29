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

    public static func runAllTests() async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Authentication") { results.append($0) }

        // PKCE (RFC 7636 test vector) and the Google authorize URL
        do {
            let challenge = AuthService.PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
            let pkce = AuthService.PKCE.make()
            let auth = AuthService(config: config, transport: FakeSupabase(), store: MemorySecureStore())
            let url = try? auth.googleAuthorizeURL(pkce: pkce)
            let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            t.check("Google: PKCE S256 matches RFC 7636; authorize URL uses Supabase Google provider + app redirect",
                    challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" && pkce.verifier.count >= 43 &&
                    AuthService.PKCE.challenge(for: pkce.verifier) == pkce.challenge &&
                    url?.path == "/auth/v1/authorize" && items["provider"] == "google" && items["redirect_to"] == "spendrop://auth-callback" &&
                    items["code_challenge"] == pkce.challenge && items["code_challenge_method"] == "s256",
                    expected: "RFC vector + correct query", actual: "challenge=\(challenge) url=\(url?.absoluteString ?? "nil")")
        }

        // Google sign-in callback exchange
        do {
            let server = FakeSupabase()
            server.authResponses["pkce"] = (200, FakeSupabase.sessionJSON(provider: "google"))
            let store = MemorySecureStore()
            let auth = AuthService(config: config, transport: server, store: store)
            let launcher = FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=abc123"))
            var ok = true
            do { try await auth.signInWithGoogle(using: launcher) } catch { ok = false }
            let exchange = server.requests.last
            let body = (try? JSONSerialization.jsonObject(with: exchange?.httpBody ?? Data())) as? [String: String]
            t.check("Google sign-in: code exchanged with PKCE verifier; session saved in secure store; provider Google",
                    ok && exchange?.url?.query == "grant_type=pkce" && body?["auth_code"] == "abc123" && body?["code_verifier"]?.isEmpty == false &&
                    auth.currentUser?.provider == "google" && store.read("session") != nil,
                    expected: "signed in via pkce", actual: "ok=\(ok) query=\(exchange?.url?.query ?? "nil") provider=\(auth.currentUser?.provider ?? "nil")")

            let denied = AuthService(config: config, transport: FakeSupabase(), store: MemorySecureStore())
            var deniedError: Error?
            do { try await denied.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?error=access_denied&error_description=Denied"))) } catch { deniedError = error }
            var cancelled: CloudError?
            do { try await denied.signInWithGoogle(using: FakeWebAuthLauncher(callback: nil)) } catch { cancelled = error as? CloudError }
            t.check("Google sign-in: denied or cancelled leaves you signed out", deniedError != nil && cancelled == .cancelled && denied.currentUser == nil,
                    expected: "error, cancelled, signed out", actual: "denied=\(deniedError != nil) cancelled=\(String(describing: cancelled))")
        }

        // Email sign-in, wrong password, backend unavailable
        do {
            let server = FakeSupabase()
            let store = MemorySecureStore()
            let auth = AuthService(config: config, transport: server, store: store)
            try? await auth.signIn(email: " me@example.com ", password: "correct-horse")
            let req = server.requests.last
            let body = (try? JSONSerialization.jsonObject(with: req?.httpBody ?? Data())) as? [String: String]
            t.check("Email sign-in: public anon key only, password grant, session stored in Keychain-style store (not SwiftData)",
                    req?.url?.query == "grant_type=password" && req?.value(forHTTPHeaderField: "apikey") == "public-anon-key" &&
                    req?.value(forHTTPHeaderField: "Authorization") == "Bearer public-anon-key" && body?["email"] == "me@example.com" &&
                    auth.currentUser?.email == "me@example.com" && store.values.keys.sorted() == ["session"],
                    expected: "signed in", actual: "user=\(auth.currentUser?.email ?? "nil") keys=\(store.values.keys.sorted())")

            let wrong = FakeSupabase()
            wrong.authResponses["password"] = (400, ["code": 400, "error_code": "invalid_credentials", "msg": "Invalid login credentials"])
            let legacy = FakeSupabase()
            legacy.authResponses["password"] = (400, ["error": "invalid_grant", "error_description": "Invalid login credentials"])
            let down = FakeSupabase()
            down.fail("/auth/v1/token", status: 503)
            var errors: [CloudError?] = []
            for server in [wrong, legacy, down] {
                let a = AuthService(config: config, transport: server, store: MemorySecureStore())
                do { try await a.signIn(email: "me@example.com", password: "wrong-pass"); errors.append(nil) } catch { errors.append(error as? CloudError) }
                if a.currentUser != nil { errors.append(nil) }
            }
            t.check("Wrong password (new + legacy error formats) and backend unavailable are reported; still signed out",
                    errors.count == 3 && errors[0] == .invalidCredentials && errors[1] == .invalidCredentials &&
                    { if case .server(503, _)? = errors[2] { return true }; return false }(),
                    expected: "invalidCredentials x2, server 503", actual: "\(errors.map { String(describing: $0) })")
        }

        // Account creation
        do {
            let immediate = FakeSupabase()
            let confirmFirst = FakeSupabase()
            confirmFirst.authResponses["signup"] = (200, ["id": "user-9", "email": "new@example.com", "confirmation_sent_at": "2026-09-29T10:00:00Z"])
            let exists = FakeSupabase()
            exists.authResponses["signup"] = (422, ["code": 422, "error_code": "user_already_exists", "msg": "User already registered"])
            let a1 = AuthService(config: config, transport: immediate, store: MemorySecureStore())
            let a2 = AuthService(config: config, transport: confirmFirst, store: MemorySecureStore())
            let a3 = AuthService(config: config, transport: exists, store: MemorySecureStore())
            let r1 = try? await a1.signUp(email: "new@example.com", password: "long-enough")
            let r2 = try? await a2.signUp(email: "new@example.com", password: "long-enough")
            var r3: CloudError?
            do { _ = try await a3.signUp(email: "new@example.com", password: "long-enough") } catch { r3 = error as? CloudError }
            t.check("Create account: signed in immediately, or asked to confirm email; existing email reported",
                    r1 == .signedIn && a1.currentUser != nil && r2 == .confirmationRequired && a2.currentUser == nil && r3 == .emailAlreadyRegistered,
                    expected: "signedIn, confirmationRequired, alreadyRegistered", actual: "\(String(describing: r1)) \(String(describing: r2)) \(String(describing: r3))")
            let problems = [
                AuthValidation.problem(email: "bad", password: "12345678", confirm: nil),
                AuthValidation.problem(email: "a@b.co", password: "short", confirm: nil),
                AuthValidation.problem(email: "a@b.co", password: "12345678", confirm: "different"),
                AuthValidation.problem(email: "a@b.co", password: "12345678", confirm: "12345678")
            ]
            t.check("Create account form: email, 8+ character password, matching confirmation", problems.map { $0 != nil } == [true, true, true, false],
                    expected: "[true, true, true, false]", actual: "\(problems.map { $0 != nil })")
        }

        // Session persistence, expiry, offline, sign out, not configured
        do {
            let store = MemorySecureStore()
            let server = FakeSupabase()
            let first = AuthService(config: config, transport: server, store: store)
            try? await first.signIn(email: "me@example.com", password: "correct-horse")
            let second = AuthService(config: config, transport: FakeSupabase(), store: store)
            t.check("Signed-in session survives an app restart (restored from secure store, no network)",
                    second.currentUser?.id == "user-123", expected: "user-123", actual: second.currentUser?.id ?? "nil")

            var clock = Date()
            let expiring = FakeSupabase()
            expiring.authResponses["password"] = (200, FakeSupabase.sessionJSON(expiresIn: 30))
            expiring.authResponses["refresh_token"] = (200, FakeSupabase.sessionJSON(token: "access-2"))
            let a = AuthService(config: config, transport: expiring, store: MemorySecureStore(), now: { clock })
            try? await a.signIn(email: "me@example.com", password: "correct-horse")
            let refreshed = try? await a.validAccessToken()
            clock = clock.addingTimeInterval(10)
            let offlineServer = FakeSupabase()
            offlineServer.authResponses["password"] = (200, FakeSupabase.sessionJSON(expiresIn: 30))
            let b = AuthService(config: config, transport: offlineServer, store: MemorySecureStore())
            try? await b.signIn(email: "me@example.com", password: "correct-horse")
            offlineServer.fail("grant_type=refresh_token", status: nil)
            var offlineError: CloudError?
            do { _ = try await b.validAccessToken() } catch { offlineError = error as? CloudError }
            t.check("Expiring token is refreshed; offline refresh keeps you signed in",
                    refreshed == "access-2" && offlineError == .offline && b.currentUser != nil,
                    expected: "access-2; offline; still signed in", actual: "\(refreshed ?? "nil") \(String(describing: offlineError)) \(b.currentUser != nil)")

            let expiredServer = FakeSupabase()
            expiredServer.authResponses["password"] = (200, FakeSupabase.sessionJSON(expiresIn: 1))
            expiredServer.authResponses["refresh_token"] = (400, ["error_code": "refresh_token_not_found", "msg": "Invalid Refresh Token"])
            let expiredStore = MemorySecureStore()
            let c = AuthService(config: config, transport: expiredServer, store: expiredStore)
            try? await c.signIn(email: "me@example.com", password: "correct-horse")
            var expiredError: CloudError?
            do { _ = try await c.validAccessToken() } catch { expiredError = error as? CloudError }
            t.check("Expired session: signed out of the cloud with a clear message; secure store cleared",
                    expiredError == .sessionExpired && c.currentUser == nil && expiredStore.values.isEmpty &&
                    { if case .signedOut(let m) = c.state { return m?.contains("Local data remains") == true }; return false }(),
                    expected: "sessionExpired, signed out", actual: "\(String(describing: expiredError)) \(c.state)")

            let ctx = TestKit.context()
            ctx.insert(Expense(amount: 12, merchant: "Local"))
            try? ctx.save()
            let outServer = FakeSupabase()
            let outStore = MemorySecureStore()
            let d = AuthService(config: config, transport: outServer, store: outStore)
            try? await d.signIn(email: "me@example.com", password: "correct-horse")
            await d.signOut()
            t.check("Sign out: server logout called, session removed, local data untouched",
                    outServer.requests.last?.url?.path == "/auth/v1/logout" && d.currentUser == nil && outStore.values.isEmpty &&
                    TestKit.count(Expense.self, in: ctx) == 1,
                    expected: "logout, signed out, 1 local expense", actual: "last=\(outServer.requests.last?.url?.path ?? "nil") expenses=\(TestKit.count(Expense.self, in: ctx))")
            try? await d.signIn(email: "me@example.com", password: "correct-horse")
            t.check("Sign back in works after signing out", d.currentUser != nil, expected: "signed in", actual: "\(d.state)")

            let noServer = FakeSupabase()
            let unconfigured = AuthService(config: nil, transport: noServer, store: MemorySecureStore())
            var notConfigured: CloudError?
            do { try await unconfigured.signIn(email: "me@example.com", password: "correct-horse") } catch { notConfigured = error as? CloudError }
            t.check("Without Supabase config: no network calls, clear 'not set up' state", unconfigured.state == .notConfigured &&
                    notConfigured == .notConfigured && noServer.requests.isEmpty,
                    expected: "notConfigured, 0 requests", actual: "\(unconfigured.state) requests=\(noServer.requests.count)")
        }

        // Account deletion
        do {
            let server = FakeSupabase()
            let auth = AuthService(config: config, transport: server, store: MemorySecureStore())
            try? await auth.signIn(email: "me@example.com", password: "correct-horse")
            let ctx = TestKit.context()
            ctx.insert(Expense(amount: 5, merchant: "Stays local"))
            try? ctx.save()
            let cloud = CloudBackupTests.makeCloud(auth: auth, server: server, context: ctx)
            _ = await cloud.backupNow()
            let objectsBefore = server.objects.count
            var failed = false
            do { try await auth.deleteAccount { try await cloud.deleteAllCloudData() } } catch { failed = true }
            t.check("Delete cloud account: backups removed, then server-side delete_my_account; local data kept; signed out",
                    !failed && objectsBefore == 1 && server.objects.isEmpty && server.rows.isEmpty && server.deletedAccount &&
                    auth.currentUser == nil && TestKit.count(Expense.self, in: ctx) == 1,
                    expected: "cloud empty, account deleted, 1 local expense",
                    actual: "failed=\(failed) objects=\(server.objects.count) rows=\(server.rows.count) deleted=\(server.deletedAccount) local=\(TestKit.count(Expense.self, in: ctx))")
        }

        return results
    }
}

/// Cloud backup / restore tests. `--run-cloud-tests`
@MainActor
public struct CloudBackupTests {
    static func signedInAuth(_ server: FakeSupabase) async -> AuthService {
        let auth = AuthService(config: AuthTests.config, transport: server, store: MemorySecureStore())
        try? await auth.signIn(email: "me@example.com", password: "correct-horse")
        return auth
    }

    static func makeCloud(auth: AuthService, server: FakeSupabase, context: ModelContext,
                          safety: @escaping (ModelContext) -> Bool = { _ in true }) -> CloudBackupService {
        let suite = "SpenDropCloudTests.\(UUID().uuidString)"
        return CloudBackupService(auth: auth, transport: server, defaults: UserDefaults(suiteName: suite)!,
                                  device: .init(id: "device-A", name: "iPhone", appVersion: "1.4 (1)"),
                                  contextProvider: { context }, canUseLocalStore: { true }, makeSafetyBackup: safety)
    }

    static func sampleData(_ ctx: ModelContext) {
        let maybank = Account(name: "Maybank", type: .bank); ctx.insert(maybank)
        let bijoy = PayBookProfile(name: "Bijoy"); ctx.insert(bijoy)
        let dinner = Expense(amount: 30, merchant: "Dinner", fundingAccount: "Maybank"); ctx.insert(dinner)
        dinner.account = maybank
        var split = SplitDraft(); split.add(bijoy); split.payer = bijoy; split.apply(to: dinner, in: ctx)
        ctx.insert(MoneyMovement(kind: .loanGiven, amountMinor: 15000, person: bijoy, account: maybank))
        TransactionClassifier.learn(merchant: "Dinner", category: .food, in: ctx)
        try? ctx.save()
    }

    public static func runAllTests() async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Cloud Backup") { results.append($0) }

        // Upload: path, headers, metadata, append-only, change detection
        do {
            let server = FakeSupabase()
            let auth = await signedInAuth(server)
            let ctx = TestKit.context()
            sampleData(ctx)
            let cloud = makeCloud(auth: auth, server: server, context: ctx)
            let ok = await cloud.backupNow()
            let upload = server.requests.first { $0.httpMethod == "POST" && $0.url!.path.hasPrefix("/storage/v1/object/backups/") }
            let row = server.rows.first ?? [:]
            let path = row["object_path"] as? String ?? ""
            let uploaded = server.objects[path].flatMap { try? UserDataBackupService.makeDecoder().decode(UserDataBackupService.BackupPayload.self, from: $0) }
            t.check("Backup: file uploaded to <user>/<device>/ with the user's token, never overwriting (x-upsert false)",
                    ok && path.hasPrefix("user-123/device-A/") && upload?.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" &&
                    upload?.value(forHTTPHeaderField: "x-upsert") == "false" && uploaded?.expenses.count == 1 && cloud.status == .upToDate,
                    expected: "uploaded, upToDate", actual: "ok=\(ok) path=\(path) status=\(cloud.status)")
            t.check("Backup metadata: device, app/schema/backup version, counts (user id assigned by the server)",
                    row["device_id"] as? String == "device-A" && row["backup_version"] as? Int == 3 && row["schema_version"] as? String == "3.0.0" &&
                    row["expenses_count"] as? Int == 1 && row["people_count"] as? Int == 1 && row["accounts_count"] as? Int == 1 &&
                    row["movements_count"] as? Int == 1 && row["user_id"] == nil && cloud.lastBackupDate != nil,
                    expected: "complete metadata", actual: "\(row.keys.sorted())")

            let uploadsBefore = server.objects.count
            _ = await cloud.backupNow()
            let unchanged = server.objects.count
            ctx.insert(Expense(amount: 3, merchant: "Kopi"))
            try? ctx.save()
            _ = await cloud.backupNow()
            t.check("Unchanged data is not re-uploaded; a change creates a NEW backup (old one kept)",
                    uploadsBefore == 1 && unchanged == 1 && server.objects.count == 2 && server.rows.count == 2,
                    expected: "1, 1, 2", actual: "\(uploadsBefore), \(unchanged), \(server.objects.count)")
        }

        // Not signed in / offline / failures never affect local data
        do {
            let ctx = TestKit.context()
            sampleData(ctx)
            let server = FakeSupabase()
            let signedOut = AuthService(config: AuthTests.config, transport: server, store: MemorySecureStore())
            let c1 = makeCloud(auth: signedOut, server: server, context: ctx)
            _ = await c1.backupNow()
            let unconfigured = makeCloud(auth: AuthService(config: nil, transport: server, store: MemorySecureStore()), server: server, context: ctx)
            _ = await unconfigured.backupNow()
            t.check("Not signed in / not configured: no upload, clear status", c1.status == .notSignedIn && unconfigured.status == .notConfigured &&
                    server.requests.isEmpty, expected: "notSignedIn, notConfigured, 0 requests", actual: "\(c1.status) \(unconfigured.status) \(server.requests.count)")

            let s2 = FakeSupabase()
            let c2 = makeCloud(auth: await signedInAuth(s2), server: s2, context: ctx)
            c2.isOnline = false
            let requestsBefore = s2.requests.count
            _ = await c2.backupNow()
            t.check("Offline: waits for the network, no request, local data untouched",
                    c2.status == .waitingForNetwork && s2.requests.count == requestsBefore && TestKit.count(Expense.self, in: ctx) == 1,
                    expected: "waitingForNetwork", actual: "\(c2.status)")

            let s3 = FakeSupabase()
            let c3 = makeCloud(auth: await signedInAuth(s3), server: s3, context: ctx)
            s3.fail("/storage/v1/object/backups/", status: 500)
            let failed = await c3.backupNow()
            let failedStatus = c3.status
            let retried = await c3.backupNow()
            t.check("Upload failure: 'Backup failed' shown, local data safe; Retry succeeds",
                    !failed && failedStatus.isFailure && retried && c3.status == .upToDate && s3.objects.count == 1 && TestKit.count(Expense.self, in: ctx) == 1,
                    expected: "failed then upToDate", actual: "\(failedStatus) → \(c3.status)")

            let s4 = FakeSupabase()
            let c4 = makeCloud(auth: await signedInAuth(s4), server: s4, context: ctx)
            s4.fail("/rest/v1/backups", status: 500)
            _ = await c4.backupNow()
            t.check("Metadata failure: the uploaded file is removed again (no orphan), status failed",
                    s4.objects.isEmpty && s4.rows.isEmpty && c4.status.isFailure &&
                    s4.requests.contains { $0.httpMethod == "DELETE" && $0.url!.path == "/storage/v1/object/backups" },
                    expected: "cleaned up", actual: "objects=\(s4.objects.count) status=\(c4.status)")

            let s5 = FakeSupabase()
            let c5 = makeCloud(auth: await signedInAuth(s5), server: s5, context: ctx)
            s5.fail("/storage/v1/object/backups/", status: nil)          // connection lost mid-upload
            _ = await c5.backupNow()
            let interrupted = c5.status
            let resumed = await c5.backupNow()
            t.check("Interrupted upload: waits for network, then completes on retry",
                    interrupted == .waitingForNetwork && resumed && s5.objects.count == 1,
                    expected: "waiting → uploaded", actual: "\(interrupted) → \(c5.status)")
        }

        // List + restore
        do {
            let server = FakeSupabase()
            let auth = await signedInAuth(server)
            let source = TestKit.context()
            sampleData(source)
            _ = await makeCloud(auth: auth, server: server, context: source).backupNow()

            let target = TestKit.context()
            let localOnly = Expense(amount: 9, merchant: "Only on this phone")
            target.insert(localOnly)
            try? target.save()
            var safetyCalls = 0
            let cloud = makeCloud(auth: auth, server: server, context: target, safety: { _ in safetyCalls += 1; return true })
            let list = (try? await cloud.listBackups()) ?? []
            t.check("Restore list: backups decoded with server timestamps (microseconds)", list.count == 1 && list.first?.expensesCount == 1,
                    expected: "1 backup", actual: "\(list.count)")

            var summary: UserDataBackupService.ImportSummary?
            if let record = list.first { summary = try? await cloud.restore(record) }
            let dinner = TestKit.fetch(Expense.self, in: target).first { $0.merchant == "Dinner" }
            t.check("Restore: safety copy first, then merge by id — local-only record kept, links and rules restored",
                    safetyCalls == 1 && summary?.expensesAdded == 1 && TestKit.count(Expense.self, in: target) == 2 &&
                    TestKit.fetch(Expense.self, in: target).contains { $0.id == localOnly.id } &&
                    dinner?.shares.count == 2 && dinner?.payer?.name == "Bijoy" && dinner?.account?.name == "Maybank" &&
                    TestKit.count(MoneyMovement.self, in: target) == 1 && TestKit.count(ClassificationRule.self, in: target) == 1,
                    expected: "2 expenses, links intact", actual: "safety=\(safetyCalls) expenses=\(TestKit.count(Expense.self, in: target)) shares=\(dinner?.shares.count ?? -1)")

            if let record = list.first { _ = try? await cloud.restore(record) }
            t.check("Restoring the same backup again adds nothing (duplicate-safe)",
                    TestKit.count(Expense.self, in: target) == 2 && TestKit.count(ExpenseShare.self, in: target) == 2 && TestKit.count(PayBookProfile.self, in: target) == 1,
                    expected: "same counts", actual: "\(TestKit.count(Expense.self, in: target))/\(TestKit.count(ExpenseShare.self, in: target))")

            // Safety copy failure, future format, interrupted download → nothing applied
            let blocked = TestKit.context()
            let noSafety = makeCloud(auth: auth, server: server, context: blocked, safety: { _ in false })
            var e1: CloudError?
            if let record = list.first { do { _ = try await noSafety.restore(record) } catch { e1 = error as? CloudError } }

            let future = UserDataBackupService.BackupPayload(version: UserDataBackupService.BackupPayload.currentVersion + 1, expenses: [], paybookProfiles: [])
            server.objects["user-123/device-A/future.json"] = try? UserDataBackupService.makeEncoder().encode(future)
            let futureRecord = CloudBackupRecord(id: UUID(), deviceId: "device-A", deviceName: "iPhone", appVersion: "9", schemaVersion: "9", backupVersion: 99,
                                                 createdAt: Date(), objectPath: "user-123/device-A/future.json", expensesCount: 0, peopleCount: 0,
                                                 accountsCount: 0, movementsCount: 0, sizeBytes: 0)
            var e2: CloudError?
            do { _ = try await noSafety.restore(futureRecord) } catch { e2 = error as? CloudError }

            server.fail("/storage/v1/object/authenticated/", status: nil)
            var e3: CloudError?
            if let record = list.first { do { _ = try await cloud.restore(record) } catch { e3 = error as? CloudError } }
            t.check("Restore refuses safely: no safety copy / newer format / interrupted download → nothing changed",
                    e1 == .safetyBackupFailed && TestKit.count(Expense.self, in: blocked) == 0 &&
                    e2 == .unsupportedBackup(UserDataBackupService.BackupPayload.currentVersion + 1) && e3 == .offline &&
                    TestKit.count(Expense.self, in: target) == 2,
                    expected: "3 safe refusals", actual: "\(String(describing: e1)) \(String(describing: e2)) \(String(describing: e3))")
        }

        // Full round trip: cloud backup → wipe → cloud restore
        do {
            let server = FakeSupabase()
            let auth = await signedInAuth(server)
            let original = TestKit.context()
            sampleData(original)
            let originalSummary = FinancialCalculator.summary(expenses: TestKit.fetch(Expense.self, in: original), movements: TestKit.fetch(MoneyMovement.self, in: original))
            let originalIDs = Set(TestKit.fetch(Expense.self, in: original).map(\.id) + TestKit.fetch(MoneyMovement.self, in: original).map(\.id))
            _ = await makeCloud(auth: auth, server: server, context: original).backupNow()

            let wiped = TestKit.context()        // empty "new phone"
            let cloud = makeCloud(auth: auth, server: server, context: wiped)
            if let record = try? await cloud.listBackups().first { _ = try? await cloud.restore(record) }
            let restoredExpenses = TestKit.fetch(Expense.self, in: wiped)
            let restoredMovements = TestKit.fetch(MoneyMovement.self, in: wiped)
            let restoredSummary = FinancialCalculator.summary(expenses: restoredExpenses, movements: restoredMovements)
            let bijoy = TestKit.fetch(PayBookProfile.self, in: wiped).first
            t.check("Cloud round trip onto an empty device: same ids, links, balances and totals",
                    Set(restoredExpenses.map(\.id) + restoredMovements.map(\.id)) == originalIDs && restoredSummary == originalSummary &&
                    bijoy.map { PersonLedger.balances(for: $0)["RM"] } == 15000 - 1500 &&
                    restoredMovements.first?.account?.name == "Maybank" && TestKit.count(ClassificationRule.self, in: wiped) == 1,
                    expected: "identical", actual: "ids=\(Set(restoredExpenses.map(\.id) + restoredMovements.map(\.id)) == originalIDs) totals=\(restoredSummary == originalSummary) bijoy=\(bijoy.map { PersonLedger.balances(for: $0)["RM"] ?? 0 } ?? 0)")
        }

        return results
    }
}
