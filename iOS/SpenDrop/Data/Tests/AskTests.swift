import Foundation

/// Fake SpenDrop AI server for tests: records requests and returns a canned reply (or fails as offline).
final class FakeAskServer: HTTPTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var status = 200
    var body: Data = Data()
    var offline = false

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if offline { throw CloudError.offline }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// Ask SpenDrop client: answer decoding, request shape, auth header and error mapping. `--run-ask-tests`
@MainActor
public struct AskTests {
    static let sampleAnswer = """
    {"conversationId":"7c9e6679-7425-40de-944b-e07fc1f90ae7","answer":{
      "status":"answered","text":"You spent RM 1,234.50 this month. এই মাসে খরচ।",
      "preface":"Here's this month so far.","understoodAs":"spending in October 2026",
      "insight":"Food is your top category.","suggestion":"Set a food budget.",
      "blocks":[
        {"type":"metric","label":"Spent","valueMinor":123450,"currency":"MYR","caption":"1–8 Oct"},
        {"type":"comparison","currency":"MYR","a":{"label":"Oct","valueMinor":123450,"count":40},"b":{"label":"Sep","valueMinor":100000,"count":35},"diffMinor":23450,"pct":null},
        {"type":"hologram","payload":{"x":1}},
        {"type":"breakdown","title":"By category","currency":"MYR","kind":"category","items":[{"key":"food","label":"Food","valueMinor":50000,"count":20,"diffMinor":-100}]},
        {"type":"transactions","title":"Biggest","items":[{"id":"t1","merchant":"Tealive","amountMinor":1500,"spendMinor":750,"currency":"MYR","date":"2026-10-06T04:31:00Z","localDate":"2026-10-06","localTime":"12:31","category":"Food","fundingAccount":"Maybank","paymentChannel":"duitnow_qr","hasReceipt":true,"isShared":true,"source":"ocr"}],"more":3},
        {"type":"findings","title":"Notes","items":[{"title":"Weekend spikes","detail":"Saturdays cost most."}]},
        {"type":"metric","label":"broken"}
      ],
      "evidence":[{"tool":"sum_spending","transactionCount":40,"period":{"from":"2026-10-01","to":"2026-10-08"},"filters":{},"generatedAt":"2026-10-08T10:00:00Z"}],
      "followUps":["Compare with last month","Show food only"],
      "focus":null,
      "meta":{"requestId":"req-1","intent":"spend_total","route":"tools","provider":"x","tools":[{"name":"sum_spending","ok":true,"ms":12}],"totalMs":300}
    }}
    """

    static func service(_ server: FakeAskServer, token: @escaping @MainActor () async throws -> String = { "tok-123" }) -> AskService {
        AskService(baseURL: URL(string: "https://ask.example.test")!, transport: server, accessToken: token, timeZone: { "Asia/Kuala_Lumpur" })
    }

    public static func runAllTests() async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        let t = TestKit(suite: "Ask SpenDrop") { results.append($0) }

        // Decoding: all known block types, unknown/malformed blocks skipped, null pct, evidence footer
        do {
            let decoded = try? JSONDecoder().decode(AskChatResponse.self, from: Data(sampleAnswer.utf8))
            let answer = decoded?.answer
            let kinds = answer?.blocks.map { block -> String in
                switch block {
                case .metric: return "metric"
                case .comparison: return "comparison"
                case .breakdown: return "breakdown"
                case .transactions: return "transactions"
                case .findings: return "findings"
                }
            } ?? []
            var pctIsNil = false
            if case let .comparison(_, _, _, diff, pct)? = answer?.blocks.first(where: { if case .comparison = $0 { return true }; return false }) {
                pctIsNil = pct == nil && diff == 23450
            }
            t.check("Decodes AskAnswer; unknown + malformed blocks ignored; null pct kept as nil",
                    decoded?.conversationId == "7c9e6679-7425-40de-944b-e07fc1f90ae7" && answer?.status == .answered &&
                    kinds == ["metric", "comparison", "breakdown", "transactions", "findings"] && pctIsNil &&
                    answer?.followUps.count == 2 && answer?.understoodAs == "spending in October 2026" &&
                    answer?.requestId == "req-1" && answer?.text.contains("এই মাসে") == true,
                    expected: "5 blocks, pct nil, Bengali text intact", actual: "\(kinds) pctNil=\(pctIsNil)")
            t.check("Evidence footer reads 'Based on N transactions · period'",
                    answer?.evidence.first?.footerText == "Based on 40 transactions · 2026-10-01 – 2026-10-08",
                    expected: "Based on 40 transactions · 2026-10-01 – 2026-10-08", actual: answer?.evidence.first?.footerText ?? "nil")
            t.check("Money shows server minor units as RM (no client re-totalling)",
                    AskMoney.format(123450, currency: "MYR") == CurrencyFormatter.format(amount: 1234.50, currency: "RM"),
                    expected: CurrencyFormatter.format(amount: 1234.50, currency: "RM"), actual: AskMoney.format(123450, currency: "MYR"))

            let minimal = try? JSONDecoder().decode(AskAnswer.self, from: Data(#"{"status":"brand_new","text":"Hi"}"#.utf8))
            t.check("Minimal / future answers still decode",
                    minimal?.status == .unknown && minimal?.blocks.isEmpty == true && minimal?.text == "Hi",
                    expected: "unknown status, no blocks", actual: "\(String(describing: minimal?.status))")
        }

        // Request: exact body keys, Bearer header, JSON content type, endpoint
        do {
            let server = FakeAskServer()
            server.body = Data(sampleAnswer.utf8)
            let ask = service(server)
            let first = try? await ask.send(message: "  How much this month?  ", conversationId: nil)
            _ = try? await ask.send(message: "And food?", conversationId: first?.conversationId)
            let bodies = server.requests.map { (try? JSONSerialization.jsonObject(with: $0.httpBody ?? Data())) as? [String: Any] ?? [:] }
            let firstKeys = Set(bodies.first?.keys.map { $0 } ?? [])
            let secondKeys = Set(bodies.last?.keys.map { $0 } ?? [])
            let allowed: Set<String> = ["message", "conversationId", "timeZone"]
            let raw = server.requests.compactMap { $0.httpBody.flatMap { String(data: $0, encoding: .utf8) } }.joined()
            t.check("Body has only message/conversationId/timeZone and never a user id",
                    server.requests.count == 2 && firstKeys == ["message", "timeZone"] && secondKeys == allowed &&
                    bodies.first?["message"] as? String == "How much this month?" &&
                    bodies.last?["conversationId"] as? String == "7c9e6679-7425-40de-944b-e07fc1f90ae7" &&
                    bodies.first?["timeZone"] as? String == "Asia/Kuala_Lumpur" &&
                    !raw.lowercased().contains("user"),
                    expected: "[message, timeZone] then [message, conversationId, timeZone]",
                    actual: "\(firstKeys.sorted()) then \(secondKeys.sorted())")
            let req = server.requests.first
            t.check("POST /api/ai/chat with Authorization: Bearer <token> and JSON content type",
                    req?.httpMethod == "POST" && req?.url?.absoluteString == "https://ask.example.test/api/ai/chat" &&
                    req?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-123" &&
                    req?.value(forHTTPHeaderField: "Content-Type") == "application/json",
                    expected: "Bearer tok-123", actual: req?.value(forHTTPHeaderField: "Authorization") ?? "nil")
        }

        // Message validation never reaches the network
        do {
            let server = FakeAskServer()
            let ask = service(server)
            var emptyRejected = false, longRejected = false
            do { _ = try await ask.send(message: "   ", conversationId: nil) } catch AskError.invalidMessage { emptyRejected = true } catch {}
            do { _ = try await ask.send(message: String(repeating: "a", count: 1001), conversationId: nil) } catch AskError.invalidMessage { longRejected = true } catch {}
            t.check("Empty and >1000-character questions are rejected locally",
                    emptyRejected && longRejected && server.requests.isEmpty,
                    expected: "both rejected, 0 requests", actual: "empty=\(emptyRejected) long=\(longRejected) requests=\(server.requests.count)")
        }

        // Errors: 401 → sign-in; signed out (no token) → sign-in with no request; offline; server message shown
        do {
            let server = FakeAskServer()
            server.status = 401
            server.body = Data(#"{"error":{"code":"unauthorized","message":"Sign in required"}}"#.utf8)
            var got: AskError?
            do { _ = try await service(server).send(message: "hi", conversationId: nil) } catch { got = error as? AskError }
            t.check("401 maps to the sign-in state", got == .notSignedIn,
                    expected: "notSignedIn", actual: String(describing: got))

            let noSession = FakeAskServer()
            var signedOut: AskError?
            do { _ = try await service(noSession, token: { throw CloudError.notSignedIn }).send(message: "hi", conversationId: nil) }
            catch { signedOut = error as? AskError }
            t.check("Not signed in to SpenDrop Cloud: sign-in state, nothing sent",
                    signedOut == .notSignedIn && noSession.requests.isEmpty,
                    expected: "notSignedIn, 0 requests", actual: "\(String(describing: signedOut)) requests=\(noSession.requests.count)")

            let offline = FakeAskServer()
            offline.offline = true
            var offlineError: AskError?
            do { _ = try await service(offline).send(message: "hi", conversationId: nil) } catch { offlineError = error as? AskError }
            t.check("Offline maps to the offline message",
                    offlineError == .offline && offlineError?.errorDescription?.contains("still available offline") == true &&
                    AskService.map(URLError(.notConnectedToInternet)) == .offline,
                    expected: "offline", actual: String(describing: offlineError))

            let limited = FakeAskServer()
            limited.status = 429
            limited.body = Data(#"{"error":{"code":"rate_limited","message":"Slow down a little."}}"#.utf8)
            var rate: AskError?
            do { _ = try await service(limited).send(message: "hi", conversationId: nil) } catch { rate = error as? AskError }
            t.check("Server error message is shown as-is and 429 is retryable",
                    rate == .server(status: 429, code: "rate_limited", message: "Slow down a little.") &&
                    rate?.errorDescription == "Slow down a little." && rate?.isRetryable == true,
                    expected: "Slow down a little.", actual: rate?.errorDescription ?? "nil")
        }

        // Conversation model keeps the conversationId for follow-ups and New chat resets it
        do {
            let server = FakeAskServer()
            server.body = Data(sampleAnswer.utf8)
            let model = AskSpenDropModel(service: service(server))
            model.send("How much this month?")
            await waitUntil { !model.isSending }
            let kept = model.conversationId
            model.newChat()
            t.check("Model keeps conversationId from the reply; New chat clears it",
                    kept == "7c9e6679-7425-40de-944b-e07fc1f90ae7" && model.conversationId == nil && model.turns.isEmpty,
                    expected: "kept then cleared", actual: "kept=\(kept ?? "nil") after=\(model.conversationId ?? "nil")")
        }

        // Greeting respects Show My Name
        do {
            let user = AuthUser(id: "u", email: "rukon.dev@example.com", name: "Touhidul Islam", provider: "google")
            let emailOnly = AuthUser(id: "u", email: "rukon.dev@example.com", name: nil, provider: "email")
            t.check("Greeting uses the name only when Show My Name is on",
                    AskSpenDropSettings.greeting(for: user, showName: true) == "Hi, Touhidul" &&
                    AskSpenDropSettings.greeting(for: emailOnly, showName: true) == "Hi, rukon.dev" &&
                    AskSpenDropSettings.greeting(for: user, showName: false) == "Hi there",
                    expected: "Hi, Touhidul / Hi, rukon.dev / Hi there",
                    actual: AskSpenDropSettings.greeting(for: user, showName: true))
        }

        return results
    }

    private static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
