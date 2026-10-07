import Foundation

// MARK: - Configuration

/// Where the shared SpenDrop AI server lives. Optional `SPENDROP_API_URL` in the git-ignored
/// `CloudConfig/SupabaseConfig.plist`; otherwise the production web app.
public enum AskConfig {
    public static let defaultBaseURL = URL(string: "https://spendrop.vercel.app")!

    public static func baseURL(bundle: Bundle = .main) -> URL {
        guard let fileURL = bundle.url(forResource: "SupabaseConfig", withExtension: "plist", subdirectory: "CloudConfig"),
              let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let text = (plist["SPENDROP_API_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.hasPrefix("YOUR_"),
              let url = URL(string: text), url.scheme == "https", url.host != nil else {
            return defaultBaseURL
        }
        return url
    }
}

// MARK: - Answer model (mirrors the server's AskAnswer; decoded tolerantly)

/// A small JSON value, for fields whose exact shape the app only displays (evidence period, filters).
public enum AskJSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AskJSONValue])
    case array([AskJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: AskJSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([AskJSONValue].self) { self = .array(v) }
        else { self = .null }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Human text for an evidence period: a string as-is, or an object's label, or "from – to".
    public var periodText: String? {
        switch self {
        case .string(let s): return s.isEmpty ? nil : s
        case .object(let o):
            if let label = o["label"]?.stringValue, !label.isEmpty { return label }
            let from = o["from"]?.stringValue ?? o["start"]?.stringValue
            let to = o["to"]?.stringValue ?? o["end"]?.stringValue
            switch (from, to) {
            case let (f?, t?): return f == t ? f : "\(f) – \(t)"
            case let (f?, nil): return "from \(f)"
            case let (nil, t?): return "until \(t)"
            default: return nil
            }
        default: return nil
        }
    }
}

public struct AskTransactionCard: Decodable, Equatable, Identifiable {
    public let id: String
    public let merchant: String
    public let amountMinor: Int
    public let spendMinor: Int?
    public let currency: String
    public let date: String?
    public let localDate: String?
    public let localTime: String?
    public let category: String?
    public let recordedCategory: String?
    public let fundingAccount: String?
    public let paymentChannel: String?
    public let hasReceipt: Bool
    public let isShared: Bool
    public let source: String?

    enum CodingKeys: String, CodingKey {
        case id, merchant, amountMinor, spendMinor, currency, date, localDate, localTime, category, recordedCategory
        case fundingAccount, paymentChannel, hasReceipt, isShared, source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        merchant = (try? c.decode(String.self, forKey: .merchant)) ?? "Unknown"
        amountMinor = try c.decode(Int.self, forKey: .amountMinor)
        spendMinor = try? c.decodeIfPresent(Int.self, forKey: .spendMinor)
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "MYR"
        date = try? c.decodeIfPresent(String.self, forKey: .date)
        localDate = try? c.decodeIfPresent(String.self, forKey: .localDate)
        localTime = try? c.decodeIfPresent(String.self, forKey: .localTime)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        recordedCategory = try? c.decodeIfPresent(String.self, forKey: .recordedCategory)
        fundingAccount = try? c.decodeIfPresent(String.self, forKey: .fundingAccount)
        paymentChannel = try? c.decodeIfPresent(String.self, forKey: .paymentChannel)
        hasReceipt = (try? c.decodeIfPresent(Bool.self, forKey: .hasReceipt)) ?? false
        isShared = (try? c.decodeIfPresent(Bool.self, forKey: .isShared)) ?? false
        source = try? c.decodeIfPresent(String.self, forKey: .source)
    }
}

public struct AskComparisonSide: Decodable, Equatable {
    public let label: String
    public let valueMinor: Int
    public let count: Int?
}

public struct AskBreakdownItem: Decodable, Equatable, Identifiable {
    public let key: String
    public let label: String
    public let valueMinor: Int
    public let count: Int?
    public let diffMinor: Int?
    public var id: String { key }

    enum CodingKeys: String, CodingKey { case key, label, valueMinor, count, diffMinor }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        key = (try? c.decode(String.self, forKey: .key)) ?? label
        valueMinor = try c.decode(Int.self, forKey: .valueMinor)
        count = try? c.decodeIfPresent(Int.self, forKey: .count)
        diffMinor = try? c.decodeIfPresent(Int.self, forKey: .diffMinor)
    }
}

public struct AskFinding: Decodable, Equatable {
    public let title: String
    public let detail: String?
}

public enum AskBlock: Equatable {
    case metric(label: String, valueMinor: Int, currency: String, caption: String?)
    case comparison(currency: String, a: AskComparisonSide, b: AskComparisonSide, diffMinor: Int, pct: Double?)
    case breakdown(title: String, currency: String, kind: String?, items: [AskBreakdownItem])
    case transactions(title: String, items: [AskTransactionCard], more: Int?)
    case findings(title: String, items: [AskFinding])
}

/// Decodes one block, or nil for an unknown type or a malformed block (never fails the whole answer).
struct LossyAskBlock: Decodable {
    let block: AskBlock?

    enum CodingKeys: String, CodingKey {
        case type, label, valueMinor, currency, caption, a, b, diffMinor, pct, title, kind, items, more
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let type = try? c.decode(String.self, forKey: .type) else { block = nil; return }
        block = Self.decode(type: type, c)
    }

    private static func decode(type: String, _ c: KeyedDecodingContainer<CodingKeys>) -> AskBlock? {
        let currency = (try? c.decode(String.self, forKey: .currency)) ?? "MYR"
        let title = (try? c.decode(String.self, forKey: .title)) ?? ""
        switch type {
        case "metric":
            guard let label = try? c.decode(String.self, forKey: .label),
                  let value = try? c.decode(Int.self, forKey: .valueMinor) else { return nil }
            return .metric(label: label, valueMinor: value, currency: currency,
                           caption: try? c.decodeIfPresent(String.self, forKey: .caption))
        case "comparison":
            guard let a = try? c.decode(AskComparisonSide.self, forKey: .a),
                  let b = try? c.decode(AskComparisonSide.self, forKey: .b) else { return nil }
            let diff = (try? c.decode(Int.self, forKey: .diffMinor)) ?? 0
            let pct = (try? c.decodeIfPresent(Double.self, forKey: .pct)) ?? nil
            return .comparison(currency: currency, a: a, b: b, diffMinor: diff, pct: pct)
        case "breakdown":
            let items = ((try? c.decode([Lossy<AskBreakdownItem>].self, forKey: .items)) ?? []).compactMap(\.value)
            return .breakdown(title: title, currency: currency, kind: try? c.decodeIfPresent(String.self, forKey: .kind), items: items)
        case "transactions":
            let items = ((try? c.decode([Lossy<AskTransactionCard>].self, forKey: .items)) ?? []).compactMap(\.value)
            return .transactions(title: title, items: items, more: (try? c.decodeIfPresent(Int.self, forKey: .more)) ?? nil)
        case "findings":
            let items = ((try? c.decode([Lossy<AskFinding>].self, forKey: .items)) ?? []).compactMap(\.value)
            return .findings(title: title, items: items)
        default:
            return nil
        }
    }
}

struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

public struct AskEvidence: Decodable, Equatable {
    public let tool: String?
    public let transactionCount: Int?
    public let period: AskJSONValue?
    public let generatedAt: String?

    /// "Based on 12 transactions · 1–31 Oct 2026"
    public var footerText: String? {
        guard let count = transactionCount else { return nil }
        var text = "Based on \(count) transaction\(count == 1 ? "" : "s")"
        if let period = period?.periodText { text += " · \(period)" }
        return text
    }
}

public struct AskAnswer: Decodable, Equatable {
    public enum Status: String, Equatable {
        case answered, clarify, noMatch = "no_match", noData = "no_data", refused, error, unknown
    }

    public let status: Status
    public let text: String
    public let blocks: [AskBlock]
    public let evidence: [AskEvidence]
    public let followUps: [String]
    public let understoodAs: String?
    public let preface: String?
    public let insight: String?
    public let suggestion: String?
    public let requestId: String?

    enum CodingKeys: String, CodingKey {
        case status, text, blocks, evidence, followUps, understoodAs, preface, insight, suggestion, meta
    }

    struct Meta: Decodable { let requestId: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode(String.self, forKey: .status)) ?? "unknown"
        status = Status(rawValue: raw) ?? .unknown
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        blocks = ((try? c.decode([LossyAskBlock].self, forKey: .blocks)) ?? []).compactMap(\.block)
        evidence = ((try? c.decode([Lossy<AskEvidence>].self, forKey: .evidence)) ?? []).compactMap(\.value)
        followUps = ((try? c.decode([String].self, forKey: .followUps)) ?? []).filter { !$0.isEmpty }
        func optional(_ key: CodingKeys) -> String? {
            guard let s = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        understoodAs = optional(.understoodAs)
        preface = optional(.preface)
        insight = optional(.insight)
        suggestion = optional(.suggestion)
        requestId = ((try? c.decodeIfPresent(Meta.self, forKey: .meta)) ?? nil)?.requestId
    }
}

public struct AskChatResponse: Decodable, Equatable {
    public let conversationId: String
    public let answer: AskAnswer
}

// MARK: - Errors

public enum AskError: LocalizedError, Equatable {
    /// Not signed in to SpenDrop Cloud, or the session was rejected (401).
    case notSignedIn
    /// Cloud isn't configured in this build.
    case notConfigured
    case offline
    case cancelled
    case invalidMessage(String)
    case invalidResponse
    case server(status: Int, code: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to SpenDrop Cloud to use SpenDrop AI."
        case .notConfigured: return "SpenDrop AI isn't available in this version of SpenDrop."
        case .offline: return "You're offline. SpenDrop AI needs an internet connection — your transactions are still available offline."
        case .cancelled: return "Cancelled."
        case .invalidMessage(let message): return message
        case .invalidResponse: return "SpenDrop AI sent an unexpected response. Please try again."
        case .server(let status, _, let message):
            return message.isEmpty ? "SpenDrop AI couldn't answer right now (\(status)). Please try again." : message
        }
    }

    /// Worth a "Try again" button.
    public var isRetryable: Bool {
        switch self {
        case .offline, .invalidResponse, .cancelled: return true
        case .server(let status, _, _): return status == 429 || status >= 500
        default: return false
        }
    }
}

// MARK: - Client

/// Talks to the shared SpenDrop AI server (`/api/ai/*`). Identity comes only from the bearer token;
/// no user id is ever sent. All answers and totals are computed server-side and displayed as-is.
@MainActor
public final class AskService {
    public static let maxMessageLength = 1000

    private let baseURL: URL
    private let transport: HTTPTransport
    private let accessToken: @MainActor () async throws -> String
    private let timeZone: () -> String

    public init(baseURL: URL = AskConfig.baseURL(),
                transport: HTTPTransport = URLSessionTransport(),
                accessToken: @escaping @MainActor () async throws -> String = { try await AuthService.shared.validAccessToken() },
                timeZone: @escaping () -> String = { TimeZone.current.identifier }) {
        self.baseURL = baseURL
        self.transport = transport
        self.accessToken = accessToken
        self.timeZone = timeZone
    }

    struct ChatRequest: Encodable {
        let message: String
        let conversationId: String?
        let timeZone: String?
    }

    /// Validates and builds the request (exposed for tests).
    func makeChatRequest(message: String, conversationId: String?, token: String) throws -> URLRequest {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AskError.invalidMessage("Type a question first.") }
        guard trimmed.count <= Self.maxMessageLength else {
            throw AskError.invalidMessage("Questions can be up to \(Self.maxMessageLength) characters.")
        }
        let zone = timeZone()
        let body = ChatRequest(message: trimmed, conversationId: conversationId, timeZone: zone.isEmpty ? nil : zone)
        var request = URLRequest(url: baseURL.appendingPathComponent("api/ai/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func send(message: String, conversationId: String?) async throws -> AskChatResponse {
        let token = try await validToken()
        let request = try makeChatRequest(message: message, conversationId: conversationId, token: token)
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(AskChatResponse.self, from: data)
        } catch {
            throw AskError.invalidResponse
        }
    }

    private func validToken() async throws -> String {
        do {
            return try await accessToken()
        } catch let error as CloudError {
            throw Self.map(error)
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as CloudError {
            throw Self.map(error)
        } catch let error as URLError {
            throw Self.map(error)
        } catch is CancellationError {
            throw AskError.cancelled
        }
        guard (200..<300).contains(response.statusCode) else {
            throw Self.error(status: response.statusCode, data: data)
        }
        return data
    }

    static func map(_ error: CloudError) -> AskError {
        switch error {
        case .notSignedIn, .sessionExpired: return .notSignedIn
        case .notConfigured: return .notConfigured
        case .offline: return .offline
        case .cancelled: return .cancelled
        case .server(let status, let message): return .server(status: status, code: "", message: message)
        default: return .server(status: 0, code: "", message: error.errorDescription ?? "")
        }
    }

    static func map(_ error: URLError) -> AskError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .cancelled: return .cancelled
        default: return .server(status: 0, code: "", message: error.localizedDescription)
        }
    }

    /// Maps `{"error": {"code", "message"}}` (or anything else) to an `AskError`.
    static func error(status: Int, data: Data) -> AskError {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let inner = body?["error"] as? [String: Any]
        let code = (inner?["code"] as? String) ?? ""
        let message = (inner?["message"] as? String) ?? (body?["message"] as? String) ?? ""
        if status == 401 { return .notSignedIn }
        if status == 429 && message.isEmpty {
            return .server(status: status, code: code, message: "You're asking a little fast. Please wait a moment and try again.")
        }
        return .server(status: status, code: code, message: message)
    }
}
