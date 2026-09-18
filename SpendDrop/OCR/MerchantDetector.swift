import Foundation

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

    /// Detects merchant / payee / recipient name and default category from OCR text and line items
    public static func detect(lines: [String], fullText: String) -> (merchant: String?, category: ExpenseCategory?) {
        let lowerFullText = fullText.lowercased()

        // 1. Explicit Labeled Recipient / Payee / Merchant patterns with colon (Highest Priority)
        let labelRegexes = [
            #"\b(?:beneficiary(?:\s*name)?|receiver(?:\s*name)?|recipient(?:\s*name)?|payee(?:\s*name)?|merchant(?:\s*name)?|store)\b\s*[:\-]\s*([A-Za-z0-9\s&'.()\-]{2,40})"#,
            #"\b(?:paid\s*to|pay\s*to)\b\s*[:\-]\s*([A-Za-z0-9\s&'.()\-]{2,40})"#,
            #"\b(?:nama\s*penerima|diterima\s*oleh|kepada|penerima)\b\s*[:\-]\s*([A-Za-z0-9\s&'.()\-]{2,40})"#,
            #"\b(?:to|paid to|payment\s+(?:rm|myr)?\s*[0-9.,]+\s+to)\s+([A-Za-z0-9\s&'.()\-]{2,35}?)(?:\s+accepted|\s+successful|\s+on|\.|$)"#
        ]

        for pattern in labelRegexes {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                for line in lines {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if let match = regex.firstMatch(in: line, options: [], range: range),
                       match.numberOfRanges > 1,
                       let captureRange = Range(match.range(at: 1), in: line) {
                        let candidate = String(line[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if isValidCandidate(candidate) {
                            let cleaned = cleanMerchantName(candidate)
                            let matchedCat = categoryForKnownMerchant(cleaned)
                            return (cleaned, matchedCat)
                        }
                    }
                }
            }
        }

        // 2. Multi-line labeled patterns (e.g. line i: "Beneficiary name", line i+1: "TOUHIDUL ISLAM RUKON")
        let standaloneLabelPatterns = [
            #"^(?:beneficiary(?:\s*name)?|receiver(?:\s*name)?|recipient(?:\s*name)?|payee(?:\s*name)?|paid\s*to|pay\s*to|transfer\s*to|merchant(?:\s*name)?|merchant|to|kepada|penerima)\s*[:\-]?$"#
        ]
        for pattern in standaloneLabelPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                for (index, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                    if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                        // Look ahead up to 15 lines for the first valid candidate line (handles stacked table labels in receipts)
                        let maxOffset = min(15, lines.count - index - 1)
                        if maxOffset >= 1 {
                            for offset in 1...maxOffset {
                                let nextLine = lines[index + offset].trimmingCharacters(in: .whitespacesAndNewlines)
                                if isValidCandidate(nextLine) {
                                    let cleaned = cleanMerchantName(nextLine)
                                    let matchedCat = categoryForKnownMerchant(cleaned)
                                    return (cleaned, matchedCat)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. Direct match with known merchants
        for item in knownMerchants {
            for keyword in item.keywords {
                if lowerFullText.contains(keyword) {
                    return (item.name, item.defaultCategory)
                }
            }
        }

        // 4. Receipt header heuristic: in physical receipts, the very first prominent non-generic line is often the store name
        let nonMerchantKeywords = [
            "tax invoice", "receipt", "welcome", "tel:", "date:", "table",
            "ssm", "co. reg", "resit", "payment", "successful",
            "duitnow", "qr", "touch 'n go", "tng", "ewallet",
            "maybank", "cimb", "rhb", "apple pay", "transfer",
            "ref:", "ref no", "reference", "amount", "receiver", "recipient",
            "beneficiary", "transaction", "alert", "transaction alert", "notification"
        ]
        for line in lines.prefix(4) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            let isGeneric = nonMerchantKeywords.contains { lower.contains($0) }
            let isAmountOrNumber = lower.hasPrefix("rm") || lower.contains("rm ") || lower.contains("rm.") ||
                                   lower.contains("myr") || lower.contains("$") ||
                                   CurrencyFormatter.parse(string: trimmed) != nil ||
                                   trimmed.allSatisfy({ $0.isNumber || $0.isPunctuation || $0.isWhitespace })
            if !isGeneric && !isAmountOrNumber && trimmed.count >= 4 && trimmed.count <= 35 {
                if isValidCandidate(trimmed) {
                    return (cleanMerchantName(trimmed), nil)
                }
            }
        }

        return (nil, nil)
    }

    private static func isValidCandidate(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 2, trimmed.count <= 40 else { return false }
        let lower = trimmed.lowercased()

        // Exclude amounts, dates, and generic keywords
        if lower.contains("rm") || lower.contains("myr") || lower.contains("$") { return false }
        if lower.contains("account") || lower.contains("akaun") { return false }
        if lower.contains("successful") || lower.contains("berjaya") || lower.contains("failed") { return false }
        if lower.contains("duitnow") || lower.contains("instant transfer") { return false }
        if lower.contains("ref no") || lower.contains("reference") { return false }
        if CurrencyFormatter.parse(string: trimmed) != nil { return false }
        if trimmed.allSatisfy({ $0.isNumber || $0.isPunctuation || $0.isWhitespace || $0 == "*" }) { return false }

        // Exclude generic UI labels, headers, and navigation words
        let genericLabels: Set<String> = [
            "from", "to", "name", "date", "time", "amount", "status", "ref", "reference",
            "nickname", "when", "repeat", "transfer method", "payment type", "bank",
            "wallet", "ewallet", "details", "summary", "transaction", "alert", "transaction alert",
            "note", "transfer to", "paid to", "receiver", "recipient", "beneficiary", "beneficiary name",
            "recipient bank", "receiving bank", "recipient bank/e-wallet", "bank/e-wallet",
            "fund transfer", "done", "share receipt", "home", "activity", "profile",
            "transaction type", "transfer type", "account number", "account no", "remark", "remarks",
            "date & time", "date/time", "duitnow ref no.", "duitnow ref no", "reference no.",
            "reference no", "octo reference no.", "octo reference no", "beneficiary account number",
            "recipient reference", "payment details", "recipient's residential status", "resident",
            "non-resident", "gong cha", "app test", "bank/e-wallet account"
        ]
        if genericLabels.contains(lower) {
            return false
        }

        // Exclude payment provider and bank names so provider is not confused with merchant (Section 7)
        let providerKeywords = ["cimb", "maybank", "rhb", "touch 'n go", "tng", "apple pay", "public bank", "bank islam", "grabpay", "boost", "duitnow"]
        if providerKeywords.contains(where: { lower == $0 || lower == "\($0) bank" || lower == "\($0) ewallet" || lower == "\($0) card" || lower.hasPrefix("\($0) ") || lower.hasSuffix(" \($0)") }) {
            return false
        }

        return true
    }

    private static func categoryForKnownMerchant(_ name: String) -> ExpenseCategory? {
        let lower = name.lowercased()
        for item in knownMerchants {
            for keyword in item.keywords {
                if lower.contains(keyword) {
                    return item.defaultCategory
                }
            }
        }
        return nil
    }

    private static func cleanMerchantName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "(M) SDN BHD", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "SDN BHD", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "SDN. BHD.", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "BHD", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "ENTERPRISE", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-:,.()"))
        return cleaned.isEmpty ? name : cleaned
    }
}
