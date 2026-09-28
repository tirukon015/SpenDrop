import Foundation
import CoreGraphics

public struct MerchantCandidate {
    public let rawText: String
    public let normalizedName: String
    public var score: Double
    public let sourceLineIndex: Int
    public let extractionMethod: String
    public var reasons: [String]
}

public struct MerchantDetector {
    public struct KnownMerchant {
        public let name: String
        public let keywords: [String]
        public let defaultCategory: ExpenseCategory
    }

    public static let knownMerchants: [KnownMerchant] = [
        // Food & Beverage
        KnownMerchant(name: "McDonald's", keywords: ["mcdonald's", "mcdonalds", "mcd", "golden arches"], defaultCategory: .food),
        KnownMerchant(name: "KFC", keywords: ["kfc", "kentucky fried chicken", "qsr stores"], defaultCategory: .food),
        KnownMerchant(name: "Starbucks", keywords: ["starbucks", "berjaya starbucks"], defaultCategory: .food),
        KnownMerchant(name: "Zus Coffee", keywords: ["zus coffee", "zus"], defaultCategory: .food),
        KnownMerchant(name: "Tealive", keywords: ["tealive", "loob holding"], defaultCategory: .food),
        KnownMerchant(name: "Subway", keywords: ["subway"], defaultCategory: .food),
        KnownMerchant(name: "FamilyMart", keywords: ["familymart", "family mart", "ql maxincome"], defaultCategory: .food),
        KnownMerchant(name: "Burger King", keywords: ["burger king", "cosmo restaurants"], defaultCategory: .food),
        KnownMerchant(name: "Pizza Hut", keywords: ["pizza hut"], defaultCategory: .food),
        KnownMerchant(name: "Nando's", keywords: ["nando's", "nandos"], defaultCategory: .food),
        KnownMerchant(name: "Texas Chicken", keywords: ["texas chicken"], defaultCategory: .food),
        KnownMerchant(name: "Marrybrown", keywords: ["marrybrown"], defaultCategory: .food),
        KnownMerchant(name: "The Coffee Bean", keywords: ["coffee bean", "cbtl"], defaultCategory: .food),
        KnownMerchant(name: "Mamak", keywords: ["mamak", "restoran", "nasi kandar", "pelita", "syed"], defaultCategory: .food),

        // Transport & Rides
        KnownMerchant(name: "Grab", keywords: ["grabcar", "grab ride", "grab taxi", "grab driver", "myteksi"], defaultCategory: .transport),
        KnownMerchant(name: "GrabFood", keywords: ["grabfood", "grab food"], defaultCategory: .food),
        KnownMerchant(name: "Foodpanda", keywords: ["foodpanda", "food panda", "delivery hero"], defaultCategory: .food),
        KnownMerchant(name: "Shell", keywords: ["shell petrol", "shell station", "shell"], defaultCategory: .transport),
        KnownMerchant(name: "Petronas", keywords: ["petronas", "mesra"], defaultCategory: .transport),
        KnownMerchant(name: "Caltex", keywords: ["caltex"], defaultCategory: .transport),
        KnownMerchant(name: "BHPetrol", keywords: ["bhpetrol", "bhp"], defaultCategory: .transport),
        KnownMerchant(name: "Touch 'n Go RFID", keywords: ["tng rfid", "rfid toll", "plus expressways"], defaultCategory: .transport),
        KnownMerchant(name: "Rapid KL", keywords: ["rapid kl", "prasarana", "mrt", "lrt"], defaultCategory: .transport),

        // Groceries & Retail
        KnownMerchant(name: "MYDIN", keywords: ["mydin"], defaultCategory: .groceries),
        KnownMerchant(name: "7-Eleven", keywords: ["7-eleven", "7 eleven", "seven eleven"], defaultCategory: .groceries),
        KnownMerchant(name: "Lotus's", keywords: ["lotus's", "lotuss", "tesco"], defaultCategory: .groceries),
        KnownMerchant(name: "Jaya Grocer", keywords: ["jaya grocer", "trendcell"], defaultCategory: .groceries),
        KnownMerchant(name: "Village Grocer", keywords: ["village grocer", "the food purveyor"], defaultCategory: .groceries),
        KnownMerchant(name: "Giant", keywords: ["giant hypermarket", "giant supermarket", "gch retail"], defaultCategory: .groceries),
        KnownMerchant(name: "Aeon", keywords: ["aeon co", "aeon big", "aeon"], defaultCategory: .groceries),
        KnownMerchant(name: "99 Speedmart", keywords: ["99 speedmart", "speedmart"], defaultCategory: .groceries),
        KnownMerchant(name: "KK Super Mart", keywords: ["kk super mart", "kk mart"], defaultCategory: .groceries),
        KnownMerchant(name: "MR. D.I.Y.", keywords: ["mr. d.i.y.", "mr diy", "mrdiy"], defaultCategory: .shopping),
        KnownMerchant(name: "CU Mart", keywords: ["cu mart", "cu convenient store"], defaultCategory: .groceries),

        // Shopping & E-Commerce
        KnownMerchant(name: "Shopee", keywords: ["shopee", "shopeepay"], defaultCategory: .shopping),
        KnownMerchant(name: "Lazada", keywords: ["lazada"], defaultCategory: .shopping),
        KnownMerchant(name: "TikTok Shop", keywords: ["tiktok shop", "tiktok"], defaultCategory: .shopping),
        KnownMerchant(name: "Uniqlo", keywords: ["uniqlo"], defaultCategory: .shopping),
        KnownMerchant(name: "Zara", keywords: ["zara"], defaultCategory: .shopping),

        // Health & Pharmacy
        KnownMerchant(name: "Watsons", keywords: ["watsons", "watson's"], defaultCategory: .health),
        KnownMerchant(name: "Guardian", keywords: ["guardian"], defaultCategory: .health),
        KnownMerchant(name: "Caring Pharmacy", keywords: ["caring pharmacy", "caring"], defaultCategory: .health),

        // Bills & Utilities
        KnownMerchant(name: "TNB", keywords: ["tenaga nasional", "tnb"], defaultCategory: .bills),
        KnownMerchant(name: "Air Selangor", keywords: ["air selangor", "syabas"], defaultCategory: .bills),
        KnownMerchant(name: "Unifi", keywords: ["unifi", "telekom malaysia", "tm"], defaultCategory: .bills),
        KnownMerchant(name: "Maxis", keywords: ["maxis", "hotlink"], defaultCategory: .bills),
        KnownMerchant(name: "CelcomDigi", keywords: ["celcomdigi", "celcom", "digi"], defaultCategory: .bills),
        KnownMerchant(name: "U Mobile", keywords: ["u mobile", "umobile"], defaultCategory: .bills),

        // Entertainment & Subscriptions
        KnownMerchant(name: "Netflix", keywords: ["netflix"], defaultCategory: .subscription),
        KnownMerchant(name: "Spotify", keywords: ["spotify"], defaultCategory: .subscription),
        KnownMerchant(name: "Apple Services", keywords: ["apple.com/bill", "itunes.com/bill", "apple bill"], defaultCategory: .subscription),
        KnownMerchant(name: "Google Play", keywords: ["google play", "google *"], defaultCategory: .subscription),
        KnownMerchant(name: "GSC Cinemas", keywords: ["gsc cinemas", "golden screen cinemas", "gsc"], defaultCategory: .entertainment),
        KnownMerchant(name: "TGV Cinemas", keywords: ["tgv cinemas", "tgv"], defaultCategory: .entertainment)
    ]

    // MARK: - Semantic Negative Exclusion Rules

    private static let footerHelpKeywords = [
        "for help with", "don't recognise", "dont recognise", "dispute a charge",
        "dispute a", "dispute", "contact maybank", "contact cimb", "contact rhb",
        "contact public bank", "contact bank islam", "contact wise", "contact us",
        "wallet uses maps", "report incorrect merchant info", "report incorrect",
        "help improve accuracy", "reporting incorrect information",
        "actual transaction amount in myr will reflect", "overseas transaction fee",
        "customer service", "help centre", "help center", "terms and conditions",
        "privacy policy", "careline", "toll free", "disclaimer", "share receipt"
    ]

    private static let uiActionKeywords: Set<String> = [
        "share receipt", "share", "cancel", "done", "back", "close", "home",
        "menu", "download", "print", "pay again", "repeat transaction", "add to favourites",
        "view details", "save receipt", "<", ">", "•", "status", "details", "summary",
        "note", "notes", "remark", "remarks", "app test", "from", "to", "nickname",
        "when", "repeat", "transaction alert", "find out more"
    ]

    private static let statusKeywords = [
        "status: approved", "status:approved", "status: failed", "status: pending",
        "payment successful", "transaction successful", "berjaya", "transaksi berjaya",
        "payment failed", "transfer successful", "approved", "successful", "failed", "declined"
    ]

    private static let identifierKeywords = [
        "reference number", "ref no", "reference no", "transaction reference",
        "terminal id", "merchant id", "approval code", "auth code",
        "batch no", "trace no", "stan", "rrn", "account number", "account no",
        "duitnow ref no.", "duitnow ref no", "octo reference no.", "octo reference no",
        "beneficiary account number", "recipient reference", "ref:", "ref :"
    ]

    private static let paymentKeywords = [
        "apple pay", "apple wallet", "pay with apple", "apple cash",
        "maybank visa debit", "cimb mastercard", "visa debit", "mastercard debit",
        "credit card", "debit card", "payment method", "paid via", "funding source",
        "maybank debit card visa", "duitnow qr", "duitnow transfer", "fpx",
        "payment type", "transfer type", "transfer method", "ewallet balance",
        "wallet balance", "bank/e-wallet account", "bank/e-wallet", "recipient bank/e-wallet",
        "receiving bank", "recipient bank", "payment"
    ]

    private static let malaysianLocations: Set<String> = [
        "cyberjaya", "selangor", "kuala lumpur", "kl", "petaling jaya", "pj",
        "subang jaya", "subang", "shah alam", "putrajaya", "penang", "pulau pinang",
        "johor bahru", "jb", "melaka", "malacca", "ipoh", "perak", "kedah",
        "kuching", "sarawak", "kota kinabalu", "sabah", "pahang", "kuantan",
        "terengganu", "kelantan", "negeri sembilan", "seremban", "malaysia"
    ]

    // MARK: - Validation & Disqualification

    public static func isAddressLine(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let addressSuffixes: Set<String> = ["st", "st.", "street", "rd", "rd.", "road", "ave", "ave.", "avenue", "dr", "drive", "blvd", "boulevard", "lane", "ln", "way", "highway", "hwy"]
        let addressPrefixes: Set<String> = ["jalan", "persiaran", "lorong", "lebuh", "no.", "lot", "unit", "floor", "level", "block", "building", "suite"]

        for p in addressPrefixes {
            if lower.hasPrefix("\(p) ") || lower.hasPrefix("\(p).") { return true }
        }
        for s in addressSuffixes {
            if lower.hasSuffix(" \(s)") || lower.hasSuffix(" \(s).") { return true }
        }

        let parts = lower.split(separator: " ").map { String($0) }
        if let first = parts.first, first.allSatisfy({ $0.isNumber || $0.isPunctuation || $0 == "#" || $0 == "-" }), parts.count >= 2 {
            let hasAddrWord = parts.dropFirst().contains { word in
                addressSuffixes.contains(word) || addressPrefixes.contains(word)
            }
            if hasAddrWord { return true }
        }
        return false
    }

    public static func isDisqualifiedLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count < 2 { return true }
        let lower = trimmed.lowercased()

        // Pure numbers, masks, punctuation
        if trimmed.allSatisfy({ $0.isNumber || $0.isPunctuation || $0.isWhitespace || $0 == "*" }) {
            return true
        }

        // Amount patterns (matches "RM 10.00", "Paid RM25.90", "-RM12.00", etc.)
        if lower.contains("rm") || lower.contains("myr") || lower.contains("$") {
            let amountRegex = try? NSRegularExpression(pattern: #"(?:rm|myr|\$)\s*[0-9]+"#, options: [.caseInsensitive])
            let fullRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            if amountRegex?.firstMatch(in: lower, options: [], range: fullRange) != nil {
                return true
            }
        }
        if lower == "total" || lower == "amount" || lower == "jumlah" || lower.contains("total rm") {
            return true
        }

        // Generic system table labels that must never be a merchant
        let systemGenericWords: Set<String> = [
            "wallet", "ewallet", "account", "bank account", "bank/e-wallet account", "bank/e-wallet",
            "transaction type", "transfer type", "transfer method", "payment type", "account number",
            "account no", "transfer to", "paid to", "receiver", "recipient", "beneficiary",
            "beneficiary name", "recipient bank", "receiving bank", "recipient bank/e-wallet",
            "date & time", "date/time", "date", "time", "when", "repeat", "remark", "remarks",
            "duitnow ref no.", "duitnow ref no", "reference no.", "reference no",
            "gong cha", "rm 2 gong cha", "is here on near me!", "near me", "fund transfer"
        ]
        if systemGenericWords.contains(lower) {
            return true
        }

        // Footer / Help / Support
        for kw in footerHelpKeywords {
            if lower.contains(kw) { return true }
        }

        // UI actions & table labels
        if uiActionKeywords.contains(lower) { return true }

        // Status
        for kw in statusKeywords {
            if lower == kw || lower.hasPrefix("\(kw):") || lower.hasPrefix(kw) { return true }
        }

        // Identifiers
        for kw in identifierKeywords {
            if lower == kw || lower.hasPrefix("\(kw):") || lower.hasPrefix("\(kw) ") || lower.hasPrefix(kw) { return true }
        }

        // Payment / account instruments
        for kw in paymentKeywords {
            if lower == kw || lower.hasPrefix("\(kw):") { return true }
        }

        // Date / Time lines
        if isDateTimeLine(trimmed) { return true }

        // Street address lines
        if isAddressLine(trimmed) { return true }

        // Status bar artifacts
        if lower.contains("5g") || lower.contains("4g") || lower.contains("lte") ||
           lower.contains("!!!!") || lower.contains("...") {
            return true
        }

        // Pure bank names (when not explicitly labeled as merchant)
        let pureBanks = ["maybank", "cimb", "rhb", "public bank", "bank islam", "hong leong", "ambank", "touch 'n go", "tng"]
        if pureBanks.contains(where: { lower == $0 || lower == "\($0) bank" || lower == "\($0) berhad" }) {
            return true
        }

        return false
    }

    public static func isDateTimeLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasYear = lower.contains("2024") || lower.contains("2025") || lower.contains("2026") || lower.contains("2027")
        let hasTime = lower.contains("am") || lower.contains("pm") || (text.contains(":") && text.filter({ $0.isNumber }).count >= 3)
        let monthRegex = try? NSRegularExpression(pattern: #"\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b"#, options: [.caseInsensitive])
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        let hasMonth = (monthRegex?.firstMatch(in: lower, options: [], range: range) != nil)

        if (hasYear && (text.contains("/") || text.contains("-") || text.contains(","))) || (hasTime && (text.contains(":") || hasMonth)) {
            return true
        }
        return false
    }

    // MARK: - Normalization

    public static func normalizeMerchantName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Strip Location: if contains comma followed by location (e.g. "Brain Freeze Vape Shop, Cyberjaya, Selangor")
        if name.contains(",") {
            let parts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 2 {
                let remainingAreLocations = parts.dropFirst().allSatisfy { part in
                    let lowerPart = part.lowercased()
                    return malaysianLocations.contains(lowerPart) ||
                           lowerPart.hasPrefix("jalan") || lowerPart.hasPrefix("persiaran") ||
                           lowerPart.hasPrefix("lorong") || lowerPart.hasPrefix("no.")
                }
                if remainingAreLocations && !parts[0].isEmpty {
                    name = parts[0]
                }
            }
        }

        // 2. Strip payment channel / metadata suffixes:
        // "- Applepay-Ec", "- ApplePay-EC", "- Applepay", "- Apple Pay", "- FPX", "- DuitNow", "- QR", "- EC"
        let suffixRegex = try? NSRegularExpression(
            pattern: #"\s*[-–•/]\s*(?:Applepay-Ec|ApplePay-EC|Applepay|Apple\s*Pay|FPX|DuitNow(?:\s*QR)?|D-QR|QR\s*Pay|QR|EC)\b.*$"#,
            options: [.caseInsensitive]
        )
        if let regex = suffixRegex {
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            name = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
        }

        // Parenthesized metadata like "(Apple Pay)" or "(FPX)"
        let parenRegex = try? NSRegularExpression(
            pattern: #"\s*\((?:Apple\s*Pay|FPX|DuitNow|QR)\)"#,
            options: [.caseInsensitive]
        )
        if let regex = parenRegex {
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            name = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
        }

        // 3. Strip corporate entity suffixes
        let legalSuffixes = [
            "(M) SDN BHD", "SDN BHD", "SDN. BHD.", "SDN", "BHD",
            "ENTERPRISE", "PLT", "LTD", "INC", "CORP"
        ]
        for suffix in legalSuffixes {
            if let range = name.range(of: suffix, options: [.caseInsensitive, .backwards]) {
                name.removeSubrange(range)
            }
        }

        // 4. Clean leading/trailing punctuation (do NOT strip periods if acronym like MR. D.I.Y.)
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                   .trimmingCharacters(in: CharacterSet(charactersIn: "-:,•()\"'"))
                   .trimmingCharacters(in: .whitespacesAndNewlines)

        if name.hasSuffix(".") && name.filter({ $0 == "." }).count <= 1 {
            name.removeLast()
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Check if normalized name matches known brand for canonical casing & branding
        let lower = name.lowercased()
        for item in knownMerchants {
            for kw in item.keywords {
                if lower == kw || lower.contains(kw) || kw.contains(lower) {
                    return item.name
                }
            }
        }

        return name
    }

    // MARK: - Core Detection Entrypoints

    public static func detect(lines: [String], fullText: String) -> (merchant: String?, category: ExpenseCategory?) {
        return detect(lines: lines, fullText: fullText, recognizedLines: [])
    }

    public static func detect(lines: [String], fullText: String, recognizedLines: [RecognizedTextLine] = []) -> (merchant: String?, category: ExpenseCategory?) {
        let lowerFull = fullText.lowercased()
        var candidates: [MerchantCandidate] = []

        let isAppleWallet = lowerFull.contains("wallet uses maps") ||
                            (lowerFull.contains("report incorrect merchant info") && lowerFull.contains("status: approved"))

        var primaryAmountIndex: Int? = nil
        var primaryDateIndex: Int? = nil

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            if primaryAmountIndex == nil && (lower.hasPrefix("rm ") || lower.hasPrefix("rm") || lower.hasPrefix("$") || lower.hasPrefix("- rm") || lower.hasPrefix("-rm")) &&
               !lower.contains("total") {
                primaryAmountIndex = idx
            }
            if primaryDateIndex == nil && isDateTimeLine(trimmed) {
                primaryDateIndex = idx
            }
        }

        // STRATEGY 1: Apple Wallet Structure (Highest structural priority for Apple Wallet)
        if isAppleWallet, let amtIdx = primaryAmountIndex {
            let endIdx = primaryDateIndex ?? min(amtIdx + 3, lines.count - 1)
            if endIdx > amtIdx {
                for i in (amtIdx + 1)...endIdx {
                    let line = lines[i]
                    if !isDisqualifiedLine(line) {
                        let normalized = normalizeMerchantName(line)
                        if !normalized.isEmpty && normalized.count >= 2 {
                            candidates.append(MerchantCandidate(
                                rawText: line,
                                normalizedName: normalized,
                                score: 95.0,
                                sourceLineIndex: i,
                                extractionMethod: "apple_wallet_title",
                                reasons: ["Apple Wallet title line between Amount and Date"]
                            ))
                            break
                        }
                    }
                }
            }
        }

        // STRATEGY 2: Explicit Labeled Field (Key-Value)
        let sameLinePatterns = [
            #"^(?:merchant(?:\s*name)?|payee(?:\s*name)?|beneficiary(?:\s*name)?|recipient(?:\s*name)?|receiver(?:\s*name)?|paid\s*to|pay\s*to|store|shop)\s*[:\-]\s*(.+)$"#,
            #"^(?:nama\s*penerima|diterima\s*oleh|kepada|penerima)\s*[:\-]\s*(.+)$"#,
            #"^to\s*[:\-]\s*(.+)$"#,
            #"\b(?:payment\s+(?:rm|myr)?\s*[0-9.,]+\s+to|paid\s+to|transfer\s+to)\s+([A-Za-z0-9\s&'.()\-]{2,35}?)(?:\s+accepted|\s+successful|\s+on|\.|$)"#
        ]

        for pattern in sameLinePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                for (idx, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                    if let match = regex.firstMatch(in: trimmed, options: [], range: range),
                       match.numberOfRanges > 1,
                       let captureRange = Range(match.range(at: 1), in: trimmed) {
                        let rawValue = String(trimmed[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !isDisqualifiedLine(rawValue) {
                            let normalized = normalizeMerchantName(rawValue)
                            if !normalized.isEmpty && normalized.count >= 2 {
                                candidates.append(MerchantCandidate(
                                    rawText: rawValue,
                                    normalizedName: normalized,
                                    score: 100.0,
                                    sourceLineIndex: idx,
                                    extractionMethod: "explicit_same_line_label",
                                    reasons: ["Explicit labeled merchant field on same line"]
                                ))
                            }
                        }
                    }
                }
            }
        }

        // Standalone label on line i, value on line i+offset
        let standaloneLabelRegex = try? NSRegularExpression(
            pattern: #"^(?:merchant(?:\s*name)?|payee(?:\s*name)?|beneficiary(?:\s*name)?|recipient(?:\s*name)?|receiver(?:\s*name)?|paid\s*to|pay\s*to|transfer\s*to|to|store|shop|kepada|penerima|nama\s*penerima)\s*[:\-]?$"#,
            options: [.caseInsensitive]
        )
        if let regex = standaloneLabelRegex {
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                    let maxOffset = min(15, lines.count - idx - 1)
                    if maxOffset >= 1 {
                        for offset in 1...maxOffset {
                            let nextLine = lines[idx + offset].trimmingCharacters(in: .whitespacesAndNewlines)
                            if !isDisqualifiedLine(nextLine) {
                                let normalized = normalizeMerchantName(nextLine)
                                if !normalized.isEmpty && normalized.count >= 2 {
                                    let score = offset == 1 ? 100.0 : max(70.0, 100.0 - Double(offset * 2))
                                    candidates.append(MerchantCandidate(
                                        rawText: nextLine,
                                        normalizedName: normalized,
                                        score: score,
                                        sourceLineIndex: idx + offset,
                                        extractionMethod: "explicit_next_line_label",
                                        reasons: ["Explicit standalone label followed by value at offset \(offset)"]
                                    ))
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }

        // STRATEGY 3: Bank App Header (Line directly above amount)
        if let amtIdx = primaryAmountIndex, amtIdx > 0 {
            let lineAbove = lines[amtIdx - 1]
            if !isDisqualifiedLine(lineAbove) {
                let normalized = normalizeMerchantName(lineAbove)
                if !normalized.isEmpty && normalized.count >= 2 {
                    candidates.append(MerchantCandidate(
                        rawText: lineAbove,
                        normalizedName: normalized,
                        score: 85.0,
                        sourceLineIndex: amtIdx - 1,
                        extractionMethod: "amount_header_above",
                        reasons: ["Prominent line directly above transaction amount"]
                    ))
                }
            }
        }

        // STRATEGY 4: Physical Receipt Header (Top 5 lines)
        for (idx, line) in lines.prefix(5).enumerated() {
            if !isDisqualifiedLine(line) {
                let normalized = normalizeMerchantName(line)
                if !normalized.isEmpty && normalized.count >= 3 && normalized.count <= 35 {
                    candidates.append(MerchantCandidate(
                        rawText: line,
                        normalizedName: normalized,
                        score: 75.0 - Double(idx * 5),
                        sourceLineIndex: idx,
                        extractionMethod: "receipt_header",
                        reasons: ["Top line in receipt header"]
                    ))
                }
            }
        }

        // Pick highest scoring candidate
        guard let best = candidates.sorted(by: { $0.score > $1.score }).first, best.score >= 30.0 else {
            return (nil, nil)
        }

        let matchedCat = categoryForMerchant(best.normalizedName)
        return (best.normalizedName, matchedCat)
    }

    private static func categoryForMerchant(_ name: String) -> ExpenseCategory? {
        let lower = name.lowercased()
        for item in knownMerchants {
            for kw in item.keywords {
                if lower.contains(kw) || kw.contains(lower) {
                    return item.defaultCategory
                }
            }
        }
        return nil
    }
}
