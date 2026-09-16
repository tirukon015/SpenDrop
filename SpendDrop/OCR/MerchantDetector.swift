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

    /// Detects merchant name and default category from OCR text and line items
    public static func detect(lines: [String], fullText: String) -> (merchant: String?, category: ExpenseCategory?) {
        let lowerFullText = fullText.lowercased()

        // 1. Direct match with known merchants
        for item in knownMerchants {
            for keyword in item.keywords {
                if lowerFullText.contains(keyword) {
                    return (item.name, item.defaultCategory)
                }
            }
        }

        // 2. Look for labeled merchant patterns: "Merchant: XYZ", "To: XYZ", "Paid To: XYZ", "Recipient: XYZ"
        let labelPatterns = [
            #"(?:merchant|paid to|pay to|to|recipient|store)\s*[:\-]?\s*([A-Za-z0-9\s&'.-]{2,30})"#,
            #"(?:diterima oleh|kepada|penerima)\s*[:\-]?\s*([A-Za-z0-9\s&'.-]{2,30})"#
        ]

        for pattern in labelPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                for line in lines {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if let match = regex.firstMatch(in: line, options: [], range: range),
                       match.numberOfRanges > 1,
                       let captureRange = Range(match.range(at: 1), in: line) {
                        let candidate = String(line[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        // Verify candidate isn't an account number or amount
                        if !candidate.isEmpty && candidate.count >= 3 && !candidate.lowercased().contains("rm") && !candidate.lowercased().contains("account") {
                            return (cleanMerchantName(candidate), nil)
                        }
                    }
                }
            }
        }

        // 3. Receipt header heuristic: in physical receipts, the very first prominent non-generic line is often the store name
        for line in lines.prefix(4) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            let isGeneric = lower.contains("tax invoice") || lower.contains("receipt") || lower.contains("welcome") ||
                            lower.contains("tel:") || lower.contains("date:") || lower.contains("table") ||
                            lower.contains("ssm") || lower.contains("co. reg") || lower.contains("resit") ||
                            lower.contains("payment") || lower.contains("successful")
            if !isGeneric && trimmed.count >= 4 && trimmed.count <= 35 && !trimmed.allSatisfy({ $0.isNumber || $0.isPunctuation }) {
                return (cleanMerchantName(trimmed), nil)
            }
        }

        return (nil, nil)
    }

    private static func cleanMerchantName(_ name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "SDN BHD", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "SDN. BHD.", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "BHD", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "ENTERPRISE", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-:,."))
        return cleaned.isEmpty ? name : cleaned
    }
}
