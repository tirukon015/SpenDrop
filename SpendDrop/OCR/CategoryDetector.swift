import Foundation

public struct CategoryDetector {
    public static func detect(text: String, detectedMerchant: String?, merchantCategory: ExpenseCategory?) -> ExpenseCategory {
        // If the detected merchant already provided a trusted category, prefer it
        if let cat = merchantCategory {
            return cat
        }

        let lower = text.lowercased()

        // Rules based on text keywords
        if containsAny(lower, ["restaurant", "cafe", "coffee", "bistro", "bakery", "kopitiam", "dining", "lunch", "dinner", "breakfast", "burger", "pizza", "nasi", "mee", "roti", "teh", "ayam", "food"]) {
            return .food
        }

        if containsAny(lower, ["supermarket", "hypermarket", "grocery", "groceries", "pasar", "pasar malam", "mart", "convenience", "fresh market", "fruit", "vegetable"]) {
            return .groceries
        }

        if containsAny(lower, ["petrol", "fuel", "diesel", "ron95", "ron97", "parking", "toll", "rfid", "touch 'n go rfid", "lrt", "mrt", "monorail", "bus", "taxi", "ride", "flight", "airasia"]) {
            return .transport
        }

        if containsAny(lower, ["electricity", "tenaga", "water", "air selangor", "utility", "bill", "bil", "telekom", "postpaid", "prepaid", "broadband", "unifi", "internet"]) {
            return .bills
        }

        if containsAny(lower, ["pharmacy", "farmasi", "clinic", "klinik", "hospital", "doctor", "dental", "gigi", "optometry", "glasses", "medicine", "ubat"]) {
            return .health
        }

        if containsAny(lower, ["cinema", "movie", "theatre", "wayang", "game", "bowling", "karaoke", "steam"]) {
            return .entertainment
        }

        if containsAny(lower, ["tuition", "university", "college", "school", "sekolah", "exam", "bookstore", "stationery", "popular bookstore", "mph"]) {
            return .education
        }

        if containsAny(lower, ["hotel", "resort", "homestay", "airbnb", "hostel", "tour", "travel", "vacation"]) {
            return .travel
        }

        if containsAny(lower, ["subscription", "recurring", "monthly fee", "annual fee", "membership"]) {
            return .subscription
        }

        if containsAny(lower, ["salon", "barber", "haircut", "spa", "massage", "facial", "nail"]) {
            return .personal
        }

        if containsAny(lower, ["mall", "fashion", "boutique", "apparel", "shoes", "clothing", "accessories", "hardware", "gadget", "store"]) {
            return .shopping
        }

        return .other
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        for keyword in keywords {
            if text.contains(keyword) {
                return true
            }
        }
        return false
    }
}
