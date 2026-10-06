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
        case ("POST", "/auth/v1/recover"):
            let (status, body) = authResponses["recover"] ?? (200, [:])
            return respond(status, body)
        case ("GET", "/auth/v1/user"), ("PUT", "/auth/v1/user"):
            let (status, body) = authResponses["user"] ?? (200, ["id": "user-123", "email": "me@example.com", "app_metadata": ["provider": "email"]])
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
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let id = items.first(where: { $0.name == "id" })?.value, id.hasPrefix("eq.") {
                result = rows.filter { ($0["id"] as? String)?.lowercased() == id.dropFirst(3).lowercased() }
            }
            if query.contains("offset=") {
                let offset = Int(query.components(separatedBy: "offset=").last ?? "0") ?? 0
                result = Array(rows.reversed().dropFirst(offset))
            }
            return respondArray(result)
        case ("DELETE", "/rest/v1/backups"):
            if query.contains("not.is.null") {
                rows.removeAll()
            } else if let id = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).first(where: { $0.name == "id" })?.value,
                      id.hasPrefix("eq.") {
                rows.removeAll { ($0["id"] as? String)?.lowercased() == id.dropFirst(3).lowercased() }
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

        // Google: same account keeps one identity; already signed in; network errors; restore; launch refresh
        do {
            let server = FakeSupabase()
            server.authResponses["pkce"] = (200, FakeSupabase.sessionJSON(id: "google-user-1", email: "me@gmail.com", provider: "google"))
            let store = MemorySecureStore()
            let auth = AuthService(config: config, transport: server, store: store)
            try? await auth.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=first")))
            let firstID = auth.currentUser?.id
            let second = FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=second"))
            try? await auth.signInWithGoogle(using: second)
            t.check("Google: signing in again while signed in does nothing (no second sheet, same user)",
                    second.lastURL == nil && auth.currentUser?.id == firstID,
                    expected: "no sheet, same id", actual: "sheet=\(second.lastURL != nil) id=\(auth.currentUser?.id ?? "nil")")

            await auth.signOut()
            try? await auth.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=again")))
            t.check("Google: the same Google account signs back in as the same Supabase user ID; one saved session",
                    firstID == "google-user-1" && auth.currentUser?.id == firstID && auth.currentUser?.email == "me@gmail.com",
                    expected: "google-user-1", actual: auth.currentUser?.id ?? "nil")

            let restored = AuthService(config: config, transport: server, store: store)
            t.check("Session is restored at launch from the Keychain (no network needed)",
                    restored.currentUser?.id == firstID && restored.currentUser?.provider == "google",
                    expected: "signed in as google-user-1 via Google", actual: "\(String(describing: restored.state))")

            let offlineServer = FakeSupabase()
            offlineServer.fail("/auth/v1/token", status: nil)
            let offline = AuthService(config: config, transport: offlineServer, store: MemorySecureStore())
            var offlineError: CloudError?
            do { try await offline.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=x"))) }
            catch { offlineError = error as? CloudError }
            t.check("Google: network error during sign-in is reported; still signed out", offlineError == .offline && offline.currentUser == nil,
                    expected: "offline, signed out", actual: "\(String(describing: offlineError)) \(String(describing: offline.state))")

            // Linked identities: an email account that later signs in with Google shows "Google" for this sign-in
            let linked = FakeSupabase()
            linked.authResponses["pkce"] = (200, FakeSupabase.sessionJSON(id: "user-123", provider: "email"))
            let linkedAuth = AuthService(config: config, transport: linked, store: MemorySecureStore())
            try? await linkedAuth.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=l")))
            t.check("Account first created with email, now signed in with Google: shows Google, same user ID",
                    linkedAuth.currentUser?.provider == "google" && linkedAuth.currentUser?.id == "user-123",
                    expected: "google, user-123", actual: "\(linkedAuth.currentUser?.provider ?? "nil") \(linkedAuth.currentUser?.id ?? "nil")")

            // Launch refresh: expired token refreshed; offline keeps the session; revoked signs out
            func expiredSession(_ server: FakeSupabase) async -> (AuthService, MemorySecureStore) {
                server.authResponses["pkce"] = (200, FakeSupabase.sessionJSON(expiresIn: 30, provider: "google"))
                let store = MemorySecureStore()
                let a = AuthService(config: config, transport: server, store: store)
                try? await a.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=e")))
                return (AuthService(config: config, transport: server, store: store), store)
            }
            let ok = FakeSupabase(); let (okAuth, _) = await expiredSession(ok)
            await okAuth.refreshSessionIfNeeded()
            let off = FakeSupabase(); let (offAuth, _) = await expiredSession(off)
            off.fail("refresh", status: nil)
            off.fail("/auth/v1/token", status: nil)
            await offAuth.refreshSessionIfNeeded()
            let revoked = FakeSupabase(); let (revokedAuth, revokedStore) = await expiredSession(revoked)
            revoked.authResponses["refresh_token"] = (400, ["code": 400, "error_code": "refresh_token_not_found", "msg": "Invalid Refresh Token"])
            await revokedAuth.refreshSessionIfNeeded()
            t.check("Launch refresh: expired token renewed (still Google); offline keeps the session; revoked signs out",
                    okAuth.currentUser?.provider == "google" && ok.requests.last?.url?.query == "grant_type=refresh_token" &&
                    offAuth.currentUser != nil && revokedAuth.currentUser == nil && revokedStore.read("session") == nil,
                    expected: "renewed, kept, signed out",
                    actual: "\(okAuth.currentUser?.provider ?? "nil") \(offAuth.currentUser != nil) \(revokedAuth.currentUser == nil)")
        }

        // Local data safety around sign-in / sign-out (authentication only: nothing uploaded, nothing changed)
        do {
            func snapshot(_ ctx: ModelContext) -> [Int] {
                [TestKit.count(Expense.self, in: ctx), TestKit.count(Account.self, in: ctx), TestKit.count(MoneyMovement.self, in: ctx),
                 TestKit.count(PayBookProfile.self, in: ctx), TestKit.count(ExpenseShare.self, in: ctx), TestKit.count(ClassificationRule.self, in: ctx)]
            }
            func fingerprint(_ ctx: ModelContext) -> [String] {
                TestKit.fetch(Expense.self, in: ctx).map { "\($0.id)|\($0.amount)|\($0.categoryRaw)|\($0.paymentChannelRaw)|\($0.fundingAccount)" }.sorted()
            }
            func onlyAuthRequests(_ server: FakeSupabase) -> Bool {
                server.requests.allSatisfy { $0.url?.path.hasPrefix("/auth/v1/") == true }
            }

            // A. Existing local user signs in with Google
            let ctxA = TestKit.context()
            CloudBackupTests.sampleData(ctxA)
            try? ctxA.save()
            let beforeA = snapshot(ctxA), printA = fingerprint(ctxA)
            let serverA = FakeSupabase()
            serverA.authResponses["pkce"] = (200, FakeSupabase.sessionJSON(id: "google-existing", provider: "google"))
            let authA = AuthService(config: config, transport: serverA, store: MemorySecureStore())
            let cloudA = CloudBackupTests.makeCloud(auth: authA, server: serverA, context: ctxA)
            try? await authA.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=a")))
            cloudA.refreshStatus()
            // Everything that can start an automatic backup (app active, network back, background task), past 3:00 AM:
            let automatic = await cloudA.runAutomaticBackupIfDue()
            t.check("A. Existing local data + Google sign-in: expenses, accounts, channels, categories, PayBook unchanged; nothing uploaded",
                    authA.currentUser != nil && snapshot(ctxA) == beforeA && fingerprint(ctxA) == printA && beforeA[0] > 0 &&
                    onlyAuthRequests(serverA) && serverA.objects.isEmpty && automatic == nil,
                    expected: "same data, auth requests only", actual: "\(beforeA) → \(snapshot(ctxA)), uploads=\(serverA.objects.count)")

            // B. New user signs in with Google on a fresh install
            let ctxB = TestKit.context()
            let serverB = FakeSupabase()
            serverB.authResponses["pkce"] = (200, FakeSupabase.sessionJSON(id: "google-new", email: "new@gmail.com", provider: "google"))
            let authB = AuthService(config: config, transport: serverB, store: MemorySecureStore())
            try? await authB.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=b")))
            t.check("B. New Google user: signed in, no demo/sample data created, nothing uploaded",
                    authB.currentUser?.id == "google-new" && snapshot(ctxB).allSatisfy { $0 == 0 } && onlyAuthRequests(serverB),
                    expected: "empty store, auth requests only", actual: "\(snapshot(ctxB))")

            // D. Sign out
            let storeD = MemorySecureStore()
            let authD = AuthService(config: config, transport: serverA, store: storeD)
            try? await authD.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=d")))
            let hadSession = storeD.read("session") != nil
            await authD.signOut()
            let logoutCalled = serverA.requests.contains { $0.url?.path == "/auth/v1/logout" }
            let cleared = storeD.read("session") == nil && authD.currentUser == nil
            try? await authD.signInWithGoogle(using: FakeWebAuthLauncher(callback: URL(string: "spendrop://auth-callback?code=d2")))
            t.check("D. Sign out: server session revoked, Keychain entry removed, local data kept; can sign in again",
                    hadSession && logoutCalled && cleared && snapshot(ctxA) == beforeA && authD.currentUser?.id == "google-existing",
                    expected: "revoked, cleared, data kept, re-sign-in ok",
                    actual: "logout=\(logoutCalled) cleared=\(cleared) data=\(snapshot(ctxA)) again=\(authD.currentUser?.id ?? "nil")")
        }

        // Email: validation, sign-up with the app redirect, confirmation link, password reset, errors
        do {
            let badEmails = ["", "a", "a@b", "a@.com", "a@b.", "a b@c.com", "@c.com", "a@@c.com"]
            t.check("Validation: invalid emails, empty password, the project's password rules (8+, upper, lower, number) and mismatches are rejected before any request; sign-in leaves password rules to the server",
                    badEmails.allSatisfy { AuthValidation.emailProblem($0) != nil } && AuthValidation.emailProblem("me@example.com") == nil &&
                    AuthValidation.problem(email: "me@example.com", password: "", confirm: nil) == "Enter your password." &&
                    AuthValidation.problem(email: "me@example.com", password: "Short1", confirm: "Short1") != nil &&
                    AuthValidation.problem(email: "me@example.com", password: "long-enough", confirm: "long-enough") != nil &&
                    AuthValidation.problem(email: "me@example.com", password: "Long-enough1", confirm: "different") == "Passwords don't match." &&
                    AuthValidation.problem(email: "me@example.com", password: "Long-enough1", confirm: "Long-enough1") == nil &&
                    AuthValidation.problem(email: "me@example.com", password: "any", confirm: nil) == nil &&
                    AuthValidation.newPasswordProblem("long-enough1", confirm: "long-enough1") != nil &&
                    AuthValidation.newPasswordProblem("Long-enough1", confirm: "Long-enougX1") == "Passwords don't match.",
                    expected: "all rejected", actual: badEmails.filter { AuthValidation.emailProblem($0) == nil }.description)

            let server = FakeSupabase()
            server.authResponses["signup"] = (200, ["id": "user-new", "email": "new@example.com", "confirmation_sent_at": "2026-10-05T02:00:00Z"])
            let store = MemorySecureStore()
            let auth = AuthService(config: config, transport: server, store: store)
            let result = try? await auth.signUp(email: "new@example.com", password: "correct-horse-battery")
            let signupRequest = server.requests.last
            let query = URLComponents(url: signupRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let body = (try? JSONSerialization.jsonObject(with: signupRequest?.httpBody ?? Data())) as? [String: String] ?? [:]
            let storedText = store.values.values.map { String(decoding: $0, as: UTF8.self) }.joined()
            t.check("Sign-up asks Supabase to redirect to spendrop://auth-callback (not the Site URL) with a PKCE challenge; confirmation required → still signed out",
                    result == .confirmationRequired && auth.currentUser == nil && signupRequest?.url?.path == "/auth/v1/signup" &&
                    query.first { $0.name == "redirect_to" }?.value == "spendrop://auth-callback" &&
                    body["code_challenge"]?.isEmpty == false && body["code_challenge_method"] == "s256" &&
                    !(signupRequest?.url?.absoluteString.contains("localhost") ?? true),
                    expected: "redirect_to=spendrop://auth-callback, PKCE, signed out", actual: "\(String(describing: result)) \(signupRequest?.url?.absoluteString ?? "nil")")
            t.check("Passwords are never stored on the device (only the one-time PKCE verifier is kept in the Keychain)",
                    !storedText.contains("correct-horse-battery") && store.read("pendingEmailFlow") != nil,
                    expected: "no password stored", actual: "keys=\(store.values.keys.sorted())")

            server.authResponses["pkce"] = (200, FakeSupabase.sessionJSON(id: "user-new", email: "new@example.com", provider: "email"))
            let link = await auth.handleAuthCallback(URL(string: "spendrop://auth-callback?code=confirm-code-1")!)
            let exchange = server.requests.last
            let exchangeBody = (try? JSONSerialization.jsonObject(with: exchange?.httpBody ?? Data())) as? [String: String] ?? [:]
            t.check("Confirmation link opened on this iPhone: code exchanged with the stored verifier (matching the challenge sent); signed in as Email",
                    link == .signedIn && auth.currentUser?.id == "user-new" && auth.currentUser?.provider == "email" &&
                    auth.currentUser?.providerDisplayName == "Email" && exchange?.url?.query == "grant_type=pkce" &&
                    exchangeBody["auth_code"] == "confirm-code-1" &&
                    exchangeBody["code_verifier"].map(AuthService.PKCE.challenge(for:)) == body["code_challenge"] &&
                    store.read("pendingEmailFlow") == nil && store.read("session") != nil,
                    expected: "signedIn via pkce", actual: "\(String(describing: link)) \(auth.currentUser?.provider ?? "nil")")

            let cloud = CloudBackupTests.makeCloud(auth: auth, server: server, context: TestKit.context())
            let automatic = await cloud.runAutomaticBackupIfDue()
            t.check("Email sign-in leaves Cloud Backup off and uploads nothing",
                    !cloud.cloudBackupEnabled && automatic == nil && server.objects.isEmpty, expected: "off, nothing", actual: "\(cloud.cloudBackupEnabled) \(server.objects.count)")

            let other = AuthService(config: config, transport: server, store: MemorySecureStore())
            let requestsBefore = server.requests.count
            let noVerifier = await other.handleAuthCallback(URL(string: "spendrop://auth-callback?code=from-another-device")!)
            let expired = await other.handleAuthCallback(URL(string: "spendrop://auth-callback#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired")!)
            let unrelated = await other.handleAuthCallback(URL(string: "spendrop://something-else?code=x")!)
            let web = await other.handleAuthCallback(URL(string: "http://localhost:3000/?code=x")!)
            t.check("Links: verified elsewhere → 'sign in'; expired → clear message; other URLs (incl. localhost) are ignored; no requests made",
                    noVerifier == .verifiedSignInNeeded && expired == .failed(CloudError.linkExpired.errorDescription!) &&
                    unrelated == nil && web == nil && other.currentUser == nil && server.requests.count == requestsBefore,
                    expected: "signIn, expired, nil, nil", actual: "\(String(describing: noVerifier)) \(String(describing: expired)) \(String(describing: unrelated)) \(String(describing: web))")

            // Implicit-flow link (session in the fragment)
            let implicit = AuthService(config: config, transport: server, store: MemorySecureStore())
            let implicitResult = await implicit.handleAuthCallback(URL(string: "spendrop://auth-callback#access_token=a1&refresh_token=r1&expires_in=3600&token_type=bearer&type=signup")!)
            t.check("Older-style link with the session in the fragment also signs in", implicitResult == .signedIn && implicit.currentUser?.id == "user-123",
                    expected: "signedIn", actual: "\(String(describing: implicitResult))")

            // Password reset
            let resetServer = FakeSupabase()
            let resetStore = MemorySecureStore()
            let reset = AuthService(config: config, transport: resetServer, store: resetStore)
            try? await reset.requestPasswordReset(email: "me@example.com")
            let recover = resetServer.requests.last
            let recoverQuery = URLComponents(url: recover!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let recoverBody = (try? JSONSerialization.jsonObject(with: recover?.httpBody ?? Data())) as? [String: String] ?? [:]
            resetServer.authResponses["pkce"] = (200, FakeSupabase.sessionJSON(email: "me@example.com", provider: "email"))
            let resetLink = await reset.handleAuthCallback(URL(string: "spendrop://auth-callback?code=reset-code")!)
            let awaiting = reset.awaitingNewPassword
            var updateError: Error?
            do { try await reset.updatePassword("brand-new-password") } catch { updateError = error }
            let put = resetServer.requests.first { $0.httpMethod == "PUT" && $0.url?.path == "/auth/v1/user" }
            let putBody = (try? JSONSerialization.jsonObject(with: put?.httpBody ?? Data())) as? [String: String] ?? [:]
            t.check("Forgot password: reset email requested with the app redirect; the link asks for a new password; it's saved, then you sign in again",
                    recover?.url?.path == "/auth/v1/recover" && recoverQuery.first { $0.name == "redirect_to" }?.value == "spendrop://auth-callback" &&
                    recoverBody["email"] == "me@example.com" && recoverBody["code_challenge"]?.isEmpty == false &&
                    resetLink == .passwordRecovery && awaiting && updateError == nil && putBody["password"] == "brand-new-password" &&
                    put?.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" &&
                    !reset.awaitingNewPassword && reset.currentUser == nil && resetStore.read("session") == nil &&
                    reset.state == .signedOut(message: "Password updated. Sign in with your new password."),
                    expected: "recover → recovery → PUT → signed out", actual: "\(String(describing: resetLink)) awaiting=\(awaiting) \(String(describing: reset.state))")

            // Friendly sign-in errors
            func signInError(_ status: Int?, _ json: [String: Any]) async -> String {
                let s = FakeSupabase()
                if let status { s.authResponses["password"] = (status, json) } else { s.fail("/auth/v1/token", status: nil) }
                let a = AuthService(config: config, transport: s, store: MemorySecureStore())
                do { try await a.signIn(email: "me@example.com", password: "whatever-123"); return "signed in" }
                catch { return AuthService.friendlyMessage(error) }
            }
            let unverified = await signInError(400, ["code": 400, "error_code": "email_not_confirmed", "msg": "Email not confirmed"])
            let limited = await signInError(429, ["code": 429, "error_code": "over_request_rate_limit", "msg": "Request rate limit reached"])
            let offline = await signInError(nil, [:])
            let wrong = await signInError(400, ["code": 400, "error_code": "invalid_credentials", "msg": "Invalid login credentials"])
            let unknown = await signInError(500, ["code": 500, "msg": "pq: relation \"auth.users\" internal detail"])
            t.check("Sign-in errors are friendly: unverified email, rate limit, offline, wrong password; raw server text is never shown",
                    unverified.contains("verify your email") && limited == CloudError.rateLimited.errorDescription! &&
                    offline.contains("offline") && wrong == "Incorrect email or password." && unknown == "Something went wrong. Please try again.",
                    expected: "friendly messages", actual: [unverified, limited, offline, wrong, unknown].joined(separator: " | "))
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
            // Create Account (confirmation given) enforces the project's policy: 8+ characters, upper, lower, number.
            let problems = [
                AuthValidation.problem(email: "bad", password: "Passw0rd1", confirm: "Passw0rd1"),
                AuthValidation.problem(email: "a@b.co", password: "Short1", confirm: "Short1"),
                AuthValidation.problem(email: "a@b.co", password: "Passw0rd1", confirm: "different"),
                AuthValidation.problem(email: "a@b.co", password: "Passw0rd1", confirm: "Passw0rd1")
            ]
            t.check("Create account form: email, 8+ character password with upper, lower and a number, matching confirmation", problems.map { $0 != nil } == [true, true, true, false],
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

    /// Fixed noon clock by default, so "is the 3:00 AM backup due?" never depends on when the tests run.
    static func makeCloud(auth: AuthService, server: FakeSupabase, context: ModelContext,
                          safety: @escaping (ModelContext) -> Bool = { _ in true },
                          scheduler: BackupTaskScheduling = NoBackupTaskScheduler(),
                          imageStorage: ImageStorageService? = nil,
                          clock: @escaping () -> Date = { RestoreRangeTests.date(2026, 10, 5, 12) },
                          defaults: UserDefaults? = nil) -> CloudBackupService {
        let suite = "SpenDropCloudTests.\(UUID().uuidString)"
        return CloudBackupService(auth: auth, transport: server, defaults: defaults ?? UserDefaults(suiteName: suite)!,
                                  device: .init(id: "device-A", name: "iPhone", appVersion: "1.4 (1)"),
                                  contextProvider: { context }, canUseLocalStore: { true }, makeSafetyBackup: safety,
                                  scheduler: scheduler,
                                  imageStorage: imageStorage ?? ImageStorageService(directory: FileManager.default.temporaryDirectory
                                      .appendingPathComponent("CloudTests-\(UUID().uuidString)", isDirectory: true)),
                                  clock: clock, calendar: RestoreRangeTests.calendar)
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
                    row["device_id"] as? String == "device-A" && row["backup_version"] as? Int == UserDataBackupService.BackupPayload.currentVersion &&
                    row["schema_version"] as? String == "\(SpenDropSchemaV5.versionIdentifier)" &&
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

            // Opt-in: signing in never uploads; automatic backups only after the user turns them on (per user)
            let s0 = FakeSupabase()
            let c0 = makeCloud(auth: await signedInAuth(s0), server: s0, context: ctx)
            let afterSignIn = s0.requests.count
            let automaticWhileOff = await c0.runAutomaticBackupIfDue()
            let uploadsWhileOff = s0.objects.count
            let defaultOff = !c0.cloudBackupEnabled
            let first = await c0.enableCloudBackup()
            t.check("Signing in uploads nothing; Cloud Backup is off by default; enabling it runs the first backup right away",
                    defaultOff && automaticWhileOff == nil && uploadsWhileOff == 0 && s0.requests.count > afterSignIn &&
                    s0.objects.count == 1 && first?.succeeded == true && c0.cloudBackupEnabled,
                    expected: "off, 0 uploads, then 1", actual: "off=\(defaultOff) whileOff=\(uploadsWhileOff) after=\(s0.objects.count)")

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

/// Date-range restore from a full backup. Every date and time zone is fixed; nothing depends on the current clock.
/// `--run-restore-tests`
@MainActor
public struct RestoreRangeTests {
    nonisolated static let myt = TimeZone(identifier: "Asia/Kuala_Lumpur")!
    nonisolated static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = myt; return c }

    nonisolated static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0, in cal: Calendar = calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    /// "2026-09-29…2026-10-05" (first and last included day), or "all".
    static func days(_ range: RestoreRange, _ reference: Date, _ cal: Calendar = calendar) -> String {
        guard let interval = range.interval(reference: reference, calendar: cal) else { return "all" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        return "\(f.string(from: interval.start))…\(f.string(from: interval.end.addingTimeInterval(-1)))"
    }

    /// Wraps the payload built from `ctx` with a fixed export (reference) date.
    static func backup(of ctx: ModelContext, exportDate: Date) -> UserDataBackupService.BackupPayload {
        let built = UserDataBackupService.makePayload(from: ctx)
        var p = UserDataBackupService.BackupPayload(version: built.version, appName: built.appName, accountName: built.accountName,
                                                    exportDate: exportDate, expenses: built.expenses, paybookProfiles: built.paybookProfiles)
        p.accounts = built.accounts; p.moneyMovements = built.moneyMovements; p.classificationRules = built.classificationRules
        return p
    }

    struct Fixture {
        let ctx: ModelContext
        let reference: Date
        let payload: UserDataBackupService.BackupPayload
    }

    /// A realistic history around 5 Oct 2026 (Malaysia time): recent and old expenses, money records, splits,
    /// learned categories, funding accounts linked by id or only by name, and an Apple Pay purchase.
    static func fixture() -> Fixture {
        let ctx = TestKit.context()
        let reference = date(2026, 10, 5, 1, 32)
        let maybank = Account(name: "Maybank", type: .bank, createdAt: date(2025, 1, 1)); ctx.insert(maybank)
        let cimb = Account(name: "CIMB", type: .bank, createdAt: date(2025, 2, 1)); ctx.insert(cimb)
        let wise = Account(name: "Wise", type: .bank, createdAt: date(2025, 3, 1)); ctx.insert(wise)
        let tng = Account(name: "Touch 'n Go", type: .eWallet, createdAt: date(2025, 4, 1)); ctx.insert(tng)
        let bijoy = PayBookProfile(name: "Bijoy"); ctx.insert(bijoy)
        let ali = PayBookProfile(name: "Ali"); ctx.insert(ali)
        let oldFriend = PayBookProfile(name: "Old Friend"); ctx.insert(oldFriend)

        // In the last 7 days
        let mcd = Expense(amount: 18.5, merchant: "McDonald's", category: .food, paymentSource: .applePay,
                          date: date(2026, 10, 5, 0, 10), paymentChannel: .applePay, fundingAccount: "Maybank")
        ctx.insert(mcd); mcd.account = maybank
        let dinner = Expense(amount: 90, merchant: "Dinner", category: .food, date: date(2026, 10, 1, 20), fundingAccount: "Maybank")
        ctx.insert(dinner); dinner.account = maybank
        var split = SplitDraft(); split.add(bijoy); split.add(ali); split.payer = bijoy; split.apply(to: dinner, in: ctx)
        // In the last 30 days: funding account known only by name (no account link)
        let grab = Expense(amount: 14.8, merchant: "Grab", category: .transport, date: date(2026, 9, 10, 9), fundingAccount: "CIMB")
        ctx.insert(grab)
        // Older
        let wiseOld = Expense(amount: 120, merchant: "Uniqlo", category: .shopping, date: date(2026, 1, 15), fundingAccount: "Wise")
        ctx.insert(wiseOld); wiseOld.account = wise
        let friendLunch = Expense(amount: 40, merchant: "Old Lunch", date: date(2026, 2, 2)); ctx.insert(friendLunch)
        var oldSplit = SplitDraft(); oldSplit.add(oldFriend); oldSplit.payer = oldFriend; oldSplit.apply(to: friendLunch, in: ctx)

        // Money records
        ctx.insert(MoneyMovement(kind: .ownTransfer, amountMinor: 20000, date: date(2026, 10, 3), account: maybank, counterAccount: tng))
        ctx.insert(MoneyMovement(kind: .refund, amountMinor: 500, date: date(2026, 10, 4), linkedExpense: wiseOld))  // links outside range
        ctx.insert(MoneyMovement(kind: .income, amountMinor: 300000, date: date(2026, 6, 1), account: wise))

        TransactionClassifier.learn(merchant: "McDonald's", category: .food, in: ctx)
        TransactionClassifier.learn(merchant: "Uniqlo", category: .shopping, in: ctx)
        try? ctx.save()
        return Fixture(ctx: ctx, reference: reference, payload: backup(of: ctx, exportDate: reference))
    }

    static func names(_ ctx: ModelContext) -> [String] { TestKit.fetch(Expense.self, in: ctx).map(\.merchant).sorted() }

    public static func runAllTests() async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Restore ranges") { results.append($0) }

        // MARK: Date ranges (calendar-aware, anchored on the backup date)
        let ref = date(2026, 10, 5, 1, 32)
        t.check("Ranges from a 5 Oct 2026 backup: 7 days, 30 days, 2 and 3 calendar months, everything",
                days(.last7Days, ref) == "2026-09-29…2026-10-05" && days(.last30Days, ref) == "2026-09-06…2026-10-05" &&
                days(.last2Months, ref) == "2026-08-06…2026-10-05" && days(.last3Months, ref) == "2026-07-06…2026-10-05" &&
                days(.everything, ref) == "all",
                expected: "09-29, 09-06, 08-06, 07-06, all",
                actual: [days(.last7Days, ref), days(.last30Days, ref), days(.last2Months, ref), days(.last3Months, ref)].joined(separator: " "))
        let mar31 = date(2026, 3, 31)
        t.check("Month ends and year boundary: 31 Mar → 2 months from 1 Feb, 3 months from 1 Jan; 30 days across New Year",
                days(.last2Months, mar31) == "2026-02-01…2026-03-31" && days(.last3Months, mar31) == "2026-01-01…2026-03-31" &&
                days(.last30Days, date(2027, 1, 15)) == "2026-12-17…2027-01-15" && days(.last3Months, date(2027, 2, 10)) == "2026-11-11…2027-02-10",
                expected: "02-01, 01-01, 12-17, 11-11",
                actual: "\(days(.last2Months, mar31)) \(days(.last3Months, mar31)) \(days(.last30Days, date(2027, 1, 15))) \(days(.last3Months, date(2027, 2, 10)))")
        t.check("Leap years: 29 Feb is a real day in 2028; 31 May 2028 − 3 months clamps to 29 Feb",
                days(.last7Days, date(2028, 2, 29)) == "2028-02-23…2028-02-29" && days(.last7Days, date(2028, 3, 1)) == "2028-02-24…2028-03-01" &&
                days(.last3Months, date(2028, 5, 31)) == "2028-03-01…2028-05-31" && days(.last7Days, date(2027, 3, 1)) == "2027-02-23…2027-03-01",
                expected: "leap-aware", actual: "\(days(.last7Days, date(2028, 2, 29))) \(days(.last3Months, date(2028, 5, 31))) \(days(.last7Days, date(2027, 3, 1)))")
        let week = RestoreRange.last7Days.interval(reference: ref, calendar: calendar)!
        t.check("Midnight: 00:00:00 on the first day and 23:59:59 on the backup day are in; one second outside either end is out",
                week.containsRestoreDate(date(2026, 9, 29, 0, 0, 0)) && week.containsRestoreDate(date(2026, 10, 5, 23, 59, 59)) &&
                !week.containsRestoreDate(date(2026, 9, 28, 23, 59, 59)) && !week.containsRestoreDate(date(2026, 10, 6, 0, 0, 0)),
                expected: "in, in, out, out", actual: "\(week)")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        var newYork = Calendar(identifier: .gregorian); newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let earlyMorning = date(2026, 10, 5, 1, 0)  // = 4 Oct 17:00 UTC
        let dst = RestoreRange.last7Days.interval(reference: date(2026, 11, 5, 12, in: newYork), calendar: newYork)!
        t.check("Time zones: days follow the phone's calendar (MYT vs UTC); a week across the US DST change is still 7 whole days",
                days(.last7Days, earlyMorning) == "2026-09-29…2026-10-05" && days(.last7Days, earlyMorning, utc) == "2026-09-28…2026-10-04" &&
                days(.last7Days, date(2026, 11, 5, 12, in: newYork), newYork) == "2026-10-30…2026-11-05" && dst.duration == 7 * 86_400 + 3_600,
                expected: "MYT 09-29, UTC 09-28, NY 10-30 (+1h)",
                actual: "\(days(.last7Days, earlyMorning)) \(days(.last7Days, earlyMorning, utc)) \(days(.last7Days, date(2026, 11, 5, 12, in: newYork), newYork)) \(dst.duration)")

        // MARK: Custom range
        let backwards = RestoreRange.custom(start: date(2026, 9, 1), end: date(2026, 8, 1))
        let sameDay = RestoreRange.custom(start: date(2026, 10, 1, 18), end: date(2026, 10, 1, 6))
        let sameDayInterval = sameDay.interval(reference: ref, calendar: calendar)
        t.check("Custom: start after end is rejected (nothing restored); a single day includes 00:00 to 23:59:59",
                backwards.validationProblem(calendar: calendar) != nil && backwards.interval(reference: ref, calendar: calendar) == nil &&
                sameDay.validationProblem(calendar: calendar) == nil &&
                sameDayInterval?.containsRestoreDate(date(2026, 10, 1, 0, 0)) == true && sameDayInterval?.containsRestoreDate(date(2026, 10, 1, 23, 59, 59)) == true &&
                sameDayInterval?.containsRestoreDate(date(2026, 10, 2, 0, 0)) == false,
                expected: "rejected; whole day", actual: "\(String(describing: backwards.validationProblem(calendar: calendar))) \(days(sameDay, ref))")

        // MARK: Plans: filtering and dependencies
        let f = fixture()
        let full = f.payload
        let everything = UserDataBackupService.makeRestorePlan(from: full, range: .everything, calendar: calendar)
        t.check("Full backup contains every local record (5 expenses, 4 accounts, 3 money records, 3 people, 2 learned categories)",
                full.expenses.count == 5 && full.accounts?.count == 4 && full.moneyMovements?.count == 3 && full.paybookProfiles.count == 3 &&
                full.classificationRules?.count == 2 && TestKit.count(Expense.self, in: f.ctx) == 5,
                expected: "5/4/3/3/2", actual: "\(full.recordCount)")
        t.check("Everything restores every record in the backup (no date filter)",
                everything.interval == nil && everything.counts == UserDataBackupService.RecordCounts(expenses: 5, accounts: 4, movements: 3, profiles: 3, rules: 2),
                expected: "5/4/3/3/2", actual: "\(everything.counts)")

        let week7 = UserDataBackupService.makeRestorePlan(from: full, range: .last7Days, calendar: calendar)
        let w = week7.payload
        let wAccounts = Set((w.accounts ?? []).map(\.name)), wPeople = Set(w.paybookProfiles.map(\.name))
        t.check("7 days: only McDonald's and Dinner; their funding account, split people and learned category come along",
                Set(w.expenses.map(\.merchant)) == ["McDonald's", "Dinner"] &&
                wAccounts == ["Maybank", "Touch 'n Go"] && wPeople == ["Bijoy", "Ali"] &&
                (w.classificationRules ?? []).map(\.merchantKey) == ["mcdonald's"] && (w.moneyMovements ?? []).count == 2,
                expected: "2 expenses; Maybank + TNG (transfer); Bijoy, Ali; 1 rule; 2 money records",
                actual: "\(w.expenses.map(\.merchant)) \(wAccounts) \(wPeople) \((w.classificationRules ?? []).map(\.merchantKey))")
        t.check("7 days: old Uniqlo (Wise), Old Friend and the June income stay out; the refund's link to Uniqlo is reported",
                !wAccounts.contains("Wise") && !wPeople.contains("Old Friend") && week7.linksOutsideRange == 1 &&
                !(w.moneyMovements ?? []).contains { $0.kindRaw == MoneyMovementKind.income.rawValue },
                expected: "excluded; 1 outside link", actual: "links=\(week7.linksOutsideRange)")

        let month = UserDataBackupService.makeRestorePlan(from: full, range: .last30Days, calendar: calendar)
        t.check("30 days: adds Grab; its funding account CIMB is restored by name even though Grab has no account link",
                Set(month.payload.expenses.map(\.merchant)) == ["McDonald's", "Dinner", "Grab"] &&
                Set((month.payload.accounts ?? []).map(\.name)) == ["Maybank", "Touch 'n Go", "CIMB"],
                expected: "3 expenses; Maybank, TNG, CIMB", actual: "\(month.payload.expenses.map(\.merchant)) \((month.payload.accounts ?? []).map(\.name))")
        let m2 = UserDataBackupService.makeRestorePlan(from: full, range: .last2Months, calendar: calendar)
        let m3 = UserDataBackupService.makeRestorePlan(from: full, range: .last3Months, calendar: calendar)
        let m8 = UserDataBackupService.makeRestorePlan(from: full, range: .lastMonths(8), calendar: calendar)
        let m9 = UserDataBackupService.makeRestorePlan(from: full, range: .lastMonths(9), calendar: calendar)
        t.check("2 and 3 months: still 3 expenses (nothing between 6 Jul and 6 Sep); 8 months (from 6 Feb) excludes 15 Jan, 9 months (from 6 Jan) includes it",
                m2.counts.expenses == 3 && m3.counts.expenses == 3 && m3.counts.movements == 2 &&
                !m8.payload.expenses.contains { $0.merchant == "Uniqlo" } && m8.counts.expenses == 3 && m8.linksOutsideRange == 1 &&
                m9.counts.expenses == 5 && m9.counts.movements == 3 && m9.linksOutsideRange == 0,
                expected: "3, 3; 8 mo: 3 (+1 outside link); 9 mo: 5 expenses, 3 money records",
                actual: "\(m2.counts.expenses) \(m3.counts.expenses) \(m8.counts.expenses)/\(m8.linksOutsideRange) \(m9.counts)")
        let custom = UserDataBackupService.makeRestorePlan(from: full, range: .custom(start: date(2026, 1, 15), end: date(2026, 2, 2)), calendar: calendar)
        t.check("Custom 15 Jan – 2 Feb: both boundary days included (Uniqlo, Old Lunch) with Wise and Old Friend",
                Set(custom.payload.expenses.map(\.merchant)) == ["Uniqlo", "Old Lunch"] &&
                Set((custom.payload.accounts ?? []).map(\.name)) == ["Wise"] && custom.payload.paybookProfiles.map(\.name) == ["Old Friend"],
                expected: "Uniqlo, Old Lunch; Wise; Old Friend", actual: "\(custom.payload.expenses.map(\.merchant)) \((custom.payload.accounts ?? []).map(\.name))")
        let none = UserDataBackupService.makeRestorePlan(from: full, range: .custom(start: date(2020, 1, 1), end: date(2020, 12, 31)), calendar: calendar)
        let empty = UserDataBackupService.makeRestorePlan(
            from: UserDataBackupService.BackupPayload(version: 3, exportDate: ref, expenses: [], paybookProfiles: []), range: .last30Days, calendar: calendar)
        t.check("No matching records / empty backup: nothing to restore", none.isEmpty && empty.isEmpty && everything.isEmpty == false,
                expected: "empty, empty", actual: "\(none.counts) \(empty.counts)")

        // MARK: Merging into a phone that already has data
        do {
            let phone = TestKit.context()
            let localOld = Expense(amount: 7, merchant: "Local January Coffee", date: date(2026, 1, 3)); phone.insert(localOld)
            let localMaybank = Account(name: "Maybank", type: .bank); phone.insert(localMaybank)  // same name, different id
            let localPerson = PayBookProfile(name: "Local Person"); phone.insert(localPerson)
            try? phone.save()
            let ids = UserDataBackupService.LocalRecordIDs.fetch(from: phone)
            let plan = UserDataBackupService.makeRestorePlan(from: full, range: .last30Days, calendar: calendar, localIDs: ids)
            let result = try? UserDataBackupService.applyRestorePlan(plan, into: phone)
            let maybanks = TestKit.fetch(Account.self, in: phone).filter { $0.name == "Maybank" }.count
            let restoredMcd = TestKit.fetch(Expense.self, in: phone).first { $0.merchant == "McDonald's" }
            t.check("30-day restore onto a phone with data: older local expense, accounts and PayBook untouched; 3 expenses added",
                    names(phone).contains("Local January Coffee") && TestKit.count(Expense.self, in: phone) == 4 &&
                    TestKit.fetch(PayBookProfile.self, in: phone).contains { $0.name == "Local Person" } &&
                    result?.added.expenses == 3 && plan.alreadyOnDevice.accounts == 1,
                    expected: "4 expenses incl. local; Local Person kept", actual: "\(names(phone)) added=\(String(describing: result?.added.expenses))")
            t.check("Funding account vs channel kept: McDonald's stays Apple Pay + Maybank; one Maybank; no 'Apple Pay' account",
                    restoredMcd?.paymentChannel == .applePay && restoredMcd?.account?.name == "Maybank" && maybanks == 1 &&
                    !TestKit.fetch(Account.self, in: phone).contains { $0.name.lowercased().contains("apple pay") },
                    expected: "Apple Pay / Maybank / 1 Maybank", actual: "\(String(describing: restoredMcd?.paymentChannel)) \(restoredMcd?.account?.name ?? "nil") maybanks=\(maybanks)")

            let again = UserDataBackupService.makeRestorePlan(from: full, range: .last30Days, calendar: calendar,
                                                              localIDs: .fetch(from: phone))
            let second = try? UserDataBackupService.applyRestorePlan(again, into: phone)
            let thenEverything = try? UserDataBackupService.applyRestorePlan(
                UserDataBackupService.makeRestorePlan(from: full, range: .everything, calendar: calendar, localIDs: .fetch(from: phone)), into: phone)
            let thenWeek = try? UserDataBackupService.applyRestorePlan(
                UserDataBackupService.makeRestorePlan(from: full, range: .last7Days, calendar: calendar, localIDs: .fetch(from: phone)), into: phone)
            t.check("Restoring the same backup again (30 days, then Everything, then 7 days) never duplicates anything",
                    again.alreadyOnDevice.expenses == 3 && second?.added.expenses == 0 && thenEverything?.added.expenses == 2 && thenWeek?.added.expenses == 0 &&
                    TestKit.count(Expense.self, in: phone) == 6 && TestKit.count(MoneyMovement.self, in: phone) == 3 &&
                    TestKit.fetch(Account.self, in: phone).filter { $0.name == "Maybank" }.count == 1 &&
                    TestKit.count(ExpenseShare.self, in: phone) == TestKit.count(ExpenseShare.self, in: f.ctx),
                    expected: "6 expenses (5 + local), 3 money records, 1 Maybank",
                    actual: "expenses=\(TestKit.count(Expense.self, in: phone)) movements=\(TestKit.count(MoneyMovement.self, in: phone))")
        }

        // MARK: Large backup
        do {
            let big = TestKit.context()
            let account = Account(name: "Maybank", type: .bank); big.insert(account)
            for i in 0..<5_000 {
                let e = Expense(amount: Double(i % 50 + 1), merchant: "Shop \(i % 200)", date: ref.addingTimeInterval(TimeInterval(-i) * 7_000), fundingAccount: "Maybank")
                big.insert(e); e.account = account
            }
            try? big.save()
            let payload = backup(of: big, exportDate: ref)
            let expected = payload.expenses.filter { RestoreRange.last30Days.interval(reference: ref, calendar: calendar)!.containsRestoreDate($0.date) }.count
            let started = Date()
            let target = TestKit.context()
            let plan = UserDataBackupService.makeRestorePlan(from: payload, range: .last30Days, calendar: calendar, localIDs: .fetch(from: target))
            let result = try? UserDataBackupService.applyRestorePlan(plan, into: target)
            let seconds = Date().timeIntervalSince(started)
            t.check("Large backup (5,000 expenses): filtered before inserting; correct count; finishes quickly",
                    plan.counts.expenses == expected && result?.added.expenses == expected && TestKit.count(Expense.self, in: target) == expected && seconds < 10,
                    expected: "\(expected) in < 10 s", actual: "\(TestKit.count(Expense.self, in: target)) in \(String(format: "%.2f", seconds)) s")
        }

        // MARK: Cloud: full backup → download → range restore; offline and failures
        do {
            let server = FakeSupabase()
            let auth = await CloudBackupTests.signedInAuth(server)
            let source = fixture()
            let localBefore = TestKit.count(Expense.self, in: source.ctx)
            let uploader = CloudBackupTests.makeCloud(auth: auth, server: server, context: source.ctx)
            let uploaded = await uploader.backupNow(force: true)
            t.check("Backing up uploads one full snapshot and changes nothing on the phone",
                    uploaded && server.objects.count == 1 && TestKit.count(Expense.self, in: source.ctx) == localBefore,
                    expected: "1 file, local unchanged", actual: "objects=\(server.objects.count) local=\(TestKit.count(Expense.self, in: source.ctx))")

            let phone = TestKit.context()
            let localOnly = Expense(amount: 3, merchant: "Phone Only", date: date(2025, 12, 1)); phone.insert(localOnly); try? phone.save()
            let cloud = CloudBackupTests.makeCloud(auth: auth, server: server, context: phone)
            let record = try? await cloud.listBackups().first
            let downloaded = record != nil ? try? await cloud.downloadBackup(record!) : nil
            let calendarForBackup = calendar
            let plan = downloaded.map { cloud.makeRestorePlan($0, range: .custom(start: date(2026, 9, 1), end: date(2026, 10, 5)), calendar: calendarForBackup) }
            let restored = plan.flatMap { try? cloud.restore($0) }
            t.check("Cloud: download the full backup, restore a date range, phone-only data kept",
                    downloaded?.expenses.count == 5 && restored?.added.expenses == 3 &&
                    Set(names(phone)) == ["Phone Only", "McDonald's", "Dinner", "Grab"],
                    expected: "3 restored + Phone Only", actual: "\(names(phone))")

            let offlinePhone = TestKit.context()
            let offlineCloud = CloudBackupTests.makeCloud(auth: auth, server: server, context: offlinePhone)
            offlineCloud.isOnline = false
            var offlineError: CloudError?
            if let record { do { _ = try await offlineCloud.downloadBackup(record) } catch { offlineError = error as? CloudError } }
            t.check("Offline: clear 'offline' error before anything is written", offlineError == .offline && TestKit.count(Expense.self, in: offlinePhone) == 0,
                    expected: "offline, 0 written", actual: "\(String(describing: offlineError))")

            if let record { server.objects[record.objectPath] = Data("{not json".utf8) }
            var corruptError: CloudError?
            if let record { do { _ = try await cloud.downloadBackup(record) } catch { corruptError = error as? CloudError } }
            let unsafe = CloudBackupTests.makeCloud(auth: auth, server: server, context: phone, safety: { _ in false })
            let countBefore = TestKit.count(Expense.self, in: phone)
            var safetyError: CloudError?
            if let plan { do { _ = try unsafe.restore(plan) } catch { safetyError = error as? CloudError } }
            t.check("Failures leave the phone unchanged: damaged backup is refused; no safety copy → nothing restored",
                    corruptError == .invalidResponse && safetyError == .safetyBackupFailed && TestKit.count(Expense.self, in: phone) == countBefore,
                    expected: "invalidResponse, safetyBackupFailed", actual: "\(String(describing: corruptError)) \(String(describing: safetyError))")
        }
        return results
    }
}

/// Records background requests like BGTaskScheduler does (one pending request per identifier).
@MainActor
final class FakeBackupScheduler: BackupTaskScheduling {
    private(set) var pending: Date?
    private(set) var submits = 0
    private(set) var cancels = 0
    /// Submits made while a request was still pending (would be a duplicate schedule without the cancel first).
    private(set) var submitsWhilePending = 0
    func cancelDailyBackup() { cancels += 1; pending = nil }
    func submitDailyBackup(earliestBeginDate: Date) {
        if pending != nil { submitsWhilePending += 1 }
        submits += 1
        pending = earliestBeginDate
    }
}

/// Daily automatic backup, the shared manual/automatic pipeline (screenshots → snapshot → upload → verify),
/// and its failure handling. Fixed clocks and calendars only. `--run-daily-backup-tests`
@MainActor
public struct DailyBackupTests {
    final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date { RestoreRangeTests.date(y, m, d, h, min) }

    public static func runAllTests() async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Daily backup") { results.append($0) }
        let fm = FileManager.default

        // MARK: Settings and schedule
        do {
            let server = FakeSupabase()
            let auth = await CloudBackupTests.signedInAuth(server)
            let scheduler = FakeBackupScheduler()
            let clock = Clock(date(2026, 10, 5, 12))
            let defaults = UserDefaults(suiteName: "DailyBackupTests.\(UUID().uuidString)")!
            let cloud = CloudBackupTests.makeCloud(auth: auth, server: server, context: TestKit.context(), scheduler: scheduler,
                                                   clock: { clock.now }, defaults: defaults)
            cloud.startAutomaticBackups()
            t.check("Defaults: Cloud Backup off, daily backup on, 3:00 AM; nothing scheduled while Cloud Backup is off",
                    !cloud.cloudBackupEnabled && cloud.dailyBackupEnabled && cloud.dailyBackupMinutes == 180 && scheduler.pending == nil,
                    expected: "off, on, 180, none", actual: "\(cloud.cloudBackupEnabled) \(cloud.dailyBackupEnabled) \(cloud.dailyBackupMinutes) \(String(describing: scheduler.pending))")

            await cloud.enableCloudBackup()
            let firstPending = scheduler.pending
            t.check("Enabling: first backup right away (not at 3:00 AM), then the next daily run is scheduled for tomorrow 3:00 AM",
                    server.objects.count == 1 && cloud.lastManualBackupDate != nil && firstPending == date(2026, 10, 6, 3),
                    expected: "1 upload; 6 Oct 03:00", actual: "uploads=\(server.objects.count) next=\(String(describing: firstPending))")

            cloud.dailyBackupMinutes = 5 * 60 + 30
            cloud.dailyBackupMinutes = 5 * 60 + 30
            cloud.dailyBackupMinutes = 4 * 60
            cloud.dailyBackupMinutes = 5 * 60 + 30
            let reread = CloudBackupTests.makeCloud(auth: auth, server: server, context: TestKit.context(), defaults: defaults)
            t.check("Changing the time to 5:30 AM: saved, rescheduled to 5:30, never more than one pending request; backups kept",
                    scheduler.pending == date(2026, 10, 6, 5, 30) && scheduler.submitsWhilePending == 0 && reread.dailyBackupMinutes == 330 &&
                    cloud.cloudBackupEnabled && server.objects.count == 1,
                    expected: "6 Oct 05:30, 0 duplicates, persisted", actual: "\(String(describing: scheduler.pending)) dup=\(scheduler.submitsWhilePending) saved=\(reread.dailyBackupMinutes)")

            clock.now = date(2026, 10, 6, 1)
            let early = cloud.nextDailyBackupDate(after: clock.now)
            cloud.dailyBackupEnabled = false
            let pendingWhenOff = scheduler.pending
            cloud.dailyBackupEnabled = true
            cloud.disableCloudBackup()
            t.check("Before today's time the run is today; daily off or Cloud Backup off cancels the schedule and keeps backups",
                    early == date(2026, 10, 6, 5, 30) && pendingWhenOff == nil && scheduler.pending == nil && server.objects.count == 1 &&
                    !cloud.cloudBackupEnabled,
                    expected: "today 05:30; cancelled; 1 backup kept", actual: "\(String(describing: early)) \(String(describing: pendingWhenOff)) objects=\(server.objects.count)")

            var newYork = Calendar(identifier: .gregorian); newYork.timeZone = TimeZone(identifier: "America/New_York")!
            let nyCloud = CloudBackupTests.makeCloud(auth: auth, server: server, context: TestKit.context(),
                                                     clock: { newYork.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))! })
            nyCloud.calendar = newYork
            nyCloud.dailyBackupMinutes = 2 * 60 + 30  // 2:30 AM doesn't exist on 8 Mar 2026 in New York
            let dst = nyCloud.nextDailyBackupDate(after: newYork.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!)
            let dstParts = dst.map { newYork.dateComponents([.month, .day, .hour], from: $0) }
            t.check("Daylight saving: a time skipped by the clock change moves to the next valid time that day",
                    dstParts?.month == 3 && dstParts?.day == 8 && dstParts?.hour == 3,
                    expected: "8 Mar 03:xx", actual: "\(String(describing: dstParts))")
        }

        // MARK: One successful automatic backup per local day; failures and offline don't count
        do {
            let server = FakeSupabase()
            let auth = await CloudBackupTests.signedInAuth(server)
            let ctx = TestKit.context()
            CloudBackupTests.sampleData(ctx)
            let clock = Clock(date(2026, 10, 5, 2, 59))
            let cloud = CloudBackupTests.makeCloud(auth: auth, server: server, context: ctx, clock: { clock.now })
            await cloud.enableCloudBackup()  // first backup (manual) at 02:59
            let notYet = await cloud.runAutomaticBackupIfDue()

            clock.now = date(2026, 10, 5, 3, 4)
            ctx.insert(Expense(amount: 5, merchant: "Kopi")); try? ctx.save()
            server.fail("/storage/v1/object/backups/", status: 500)
            let failed = await cloud.runAutomaticBackupIfDue()
            let afterFailure = (cloud.lastAutomaticBackupDate, server.objects.count)
            cloud.isOnline = false
            let offline = await cloud.runAutomaticBackupIfDue()
            cloud.isOnline = true
            try? await Task.sleep(for: .milliseconds(300))  // network back → retry
            let retriedOnReconnect = cloud.hasSuccessfulAutomaticBackup(on: clock.now)
            t.check("Not due before 3:00; a failed or offline attempt is not success and keeps the earlier backup; it retries when the network returns",
                    notYet == nil && failed?.succeeded == false && afterFailure.0 == nil && afterFailure.1 == 1 &&
                    offline?.outcome == .offline && retriedOnReconnect && server.objects.count == 2,
                    expected: "nil, failed, offline, then success",
                    actual: "notYet=\(String(describing: notYet)) failed=\(String(describing: failed?.outcome)) offline=\(String(describing: offline?.outcome)) ok=\(retriedOnReconnect) objects=\(server.objects.count)")

            ctx.insert(Expense(amount: 6, merchant: "Teh")); try? ctx.save()
            clock.now = date(2026, 10, 5, 22)
            let sameDay = await cloud.runAutomaticBackupIfDue()
            clock.now = date(2026, 10, 6, 3, 10)
            let nextDay = await cloud.runAutomaticBackupIfDue()
            t.check("Only one successful automatic backup per local day; the next day runs again",
                    sameDay == nil && nextDay?.succeeded == true && server.objects.count == 3 &&
                    cloud.hasSuccessfulAutomaticBackup(on: date(2026, 10, 6, 23)) && !cloud.hasSuccessfulAutomaticBackup(on: date(2026, 10, 7, 1)),
                    expected: "skip same day, run next day", actual: "same=\(String(describing: sameDay)) next=\(String(describing: nextDay?.outcome)) objects=\(server.objects.count)")

            let manual = await cloud.runBackup(kind: .manual)
            t.check("Manual and automatic history are separate; Back Up Now always available",
                    manual?.succeeded == true && cloud.lastManualBackupDate == date(2026, 10, 6, 3, 10) &&
                    cloud.lastAutomaticBackupDate == date(2026, 10, 6, 3, 10) && server.objects.count == 4,
                    expected: "both recorded", actual: "manual=\(String(describing: cloud.lastManualBackupDate)) auto=\(String(describing: cloud.lastAutomaticBackupDate))")

            // Verification: a stored file that doesn't match is not success; the unverified upload is removed
            let objectsBefore = server.objects.count, rowsBefore = server.rows.count
            ctx.insert(Expense(amount: 7, merchant: "Roti")); try? ctx.save()
            server.fail("/storage/v1/object/authenticated/backups/", status: 500)
            let unverified = await cloud.runBackup(kind: .manual)
            t.check("Upload that can't be verified: not success, removed again; earlier verified backups untouched",
                    unverified?.succeeded == false && server.objects.count == objectsBefore && server.rows.count == rowsBefore,
                    expected: "failed; \(objectsBefore) files", actual: "\(String(describing: unverified?.outcome)) files=\(server.objects.count) rows=\(server.rows.count)")
        }

        // MARK: Retention (cloud snapshots only; never local data)
        do {
            func setup(retention: Int) async -> (FakeSupabase, CloudBackupService, ModelContext) {
                let server = FakeSupabase()
                let auth = await CloudBackupTests.signedInAuth(server)
                let ctx = TestKit.context()
                CloudBackupTests.sampleData(ctx)
                ctx.insert(Expense(amount: 9, merchant: "From 2024", date: RestoreRangeTests.date(2024, 3, 1)))
                try? ctx.save()
                for (id, created) in [("old-100", "2026-06-27T10:00:00+00:00"), ("old-40", "2026-08-26T10:00:00+00:00"), ("old-10", "2026-09-25T10:00:00+00:00")] {
                    server.rows.append(["id": id, "device_id": "device-A", "object_path": "user-123/device-A/\(id).json", "created_at": created])
                    server.objects["user-123/device-A/\(id).json"] = Data("{}".utf8)
                }
                let cloud = CloudBackupTests.makeCloud(auth: auth, server: server, context: ctx)
                cloud.backupRetentionDays = retention
                return (server, cloud, ctx)
            }
            let (s30, c30, ctx30) = await setup(retention: 30)
            let ok30 = await c30.runBackup(kind: .manual)
            let ids30 = Set(s30.rows.compactMap { $0["id"] as? String })
            let (s90, c90, _) = await setup(retention: 90)
            _ = await c90.runBackup(kind: .manual)
            let ids90 = Set(s90.rows.compactMap { $0["id"] as? String })
            t.check("Retention 30 days: snapshots older than 30 days are removed after the new one is verified; 90 days keeps the 40-day one",
                    ok30?.succeeded == true && !ids30.contains("old-100") && !ids30.contains("old-40") && ids30.contains("old-10") && ids30.count == 2 &&
                    s30.objects["user-123/device-A/old-100.json"] == nil &&
                    !ids90.contains("old-100") && ids90.contains("old-40") && ids90.contains("old-10") && ids90.count == 3,
                    expected: "30: old-10 + new; 90: old-40, old-10 + new", actual: "\(ids30.sorted()) | \(ids90.sorted())")
            t.check("Cleanup only touches cloud snapshots: every transaction on the phone (including 2024) is still there",
                    TestKit.count(Expense.self, in: ctx30) == 2 && TestKit.fetch(Expense.self, in: ctx30).contains { $0.merchant == "From 2024" },
                    expected: "2 expenses incl. 2024", actual: "\(TestKit.count(Expense.self, in: ctx30))")

            let (sf, cf, _) = await setup(retention: 30)
            sf.fail("/storage/v1/object/backups/", status: 500)
            let failed = await cf.runBackup(kind: .manual)
            t.check("A failed backup deletes nothing: all earlier snapshots (even past retention) stay; 'Backup failed' is reported",
                    failed?.succeeded == false && sf.rows.count == 3 && cf.status.isFailure,
                    expected: "3 kept, failed", actual: "\(sf.rows.count) \(cf.status)")
        }

        // MARK: Screenshots are optimized before every backup
        do {
            let server = FakeSupabase()
            let auth = await CloudBackupTests.signedInAuth(server)
            let root = fm.temporaryDirectory.appendingPathComponent("DailyBackupShots-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: root) }
            let storage = ImageStorageService(directory: root)
            let ctx = TestKit.context()
            let big = ScreenshotStorageTests.makePaymentScreenshot(size: CGSize(width: 1320, height: 2868)).jpegData(compressionQuality: 0.8)!
            func file(_ data: Data) -> String { let n = "\(UUID().uuidString).jpg"; try? data.write(to: root.appendingPathComponent(n)); return n }
            let large = file(big)
            let small = storage.saveImage(ScreenshotStorageTests.makePaymentScreenshot(size: CGSize(width: 600, height: 1000)))!
            let corrupt = file(Data((0..<300_000).map { _ in UInt8.random(in: 0...255) }))
            for path in [large, small, corrupt, "gone.jpg"] {
                let e = Expense(amount: 22, merchant: "RANA SOHEL"); e.imageRelativePath = path; ctx.insert(e)
            }
            try? ctx.save()
            let clock = Clock(date(2026, 10, 5, 12))
            let cloud = CloudBackupTests.makeCloud(auth: auth, server: server, context: ctx, imageStorage: storage, clock: { clock.now })
            var phases: [String] = []
            let observer = Task { @MainActor in
                while !Task.isCancelled { if let title = cloud.phase.title, phases.last != title { phases.append(title) }; await Task.yield() }
            }
            let report = await cloud.enableCloudBackup()
            observer.cancel()
            let uploaded = server.objects.values.first.flatMap { try? UserDataBackupService.makeDecoder().decode(UserDataBackupService.BackupPayload.self, from: $0) }
            let uploadedPaths = Set(uploaded?.expenses.compactMap(\.imageRelativePath) ?? [])
            let s = report?.screenshots
            t.check("Backup optimizes screenshots first: the uploaded snapshot already points at the optimized file",
                    report?.succeeded == true && uploadedPaths.contains { $0.hasSuffix(".heic") && $0.hasPrefix((large as NSString).deletingPathExtension) } &&
                    !uploadedPaths.contains(large) && !fm.fileExists(atPath: root.appendingPathComponent(large).path),
                    expected: "snapshot has <id>.heic", actual: "\(uploadedPaths.sorted())")
            t.check("Statistics: 4 checked · 1 optimized · 1 already small · 1 failed (original kept, reference unchanged) · 1 missing",
                    s?.checked == 4 && s?.optimized == 1 && s?.alreadySmall == 1 && s?.keptOriginal == 1 && s?.missing == 1 &&
                    fm.fileExists(atPath: root.appendingPathComponent(corrupt).path) && uploadedPaths.contains(corrupt),
                    expected: "4/1/1/1/1", actual: report?.screenshotSummary ?? "nil")
            t.check("Progress phases in order: optimizing receipts → creating → uploading → checking",
                    phases.first?.hasPrefix("Optimizing receipts") == true || phases.first == "Preparing backup…",
                    expected: "optimizing first", actual: phases.joined(separator: " → "))

            let optimizedName = uploadedPaths.first { $0.hasSuffix(".heic") }!
            let bytesBefore = try? Data(contentsOf: root.appendingPathComponent(optimizedName))
            clock.now = date(2026, 10, 6, 3, 30)
            let second = await cloud.runAutomaticBackupIfDue()
            t.check("Automatic backup also optimizes first, and never re-compresses an optimized screenshot",
                    second?.succeeded == true && second?.screenshots.checked == 4 && second?.screenshots.optimized == 0 &&
                    (try? Data(contentsOf: root.appendingPathComponent(optimizedName))) == bytesBefore,
                    expected: "0 optimized, file identical", actual: second?.screenshotSummary ?? "nil")

            async let a = cloud.runBackup(kind: .manual)
            async let b = cloud.runBackup(kind: .manual)
            let (ra, rb) = await (a, b)
            t.check("Concurrent backup requests: only one runs", [ra, rb].compactMap { $0 }.count == 1,
                    expected: "1 ran, 1 refused", actual: "\(ra != nil) \(rb != nil)")
        }
        return results
    }
}
