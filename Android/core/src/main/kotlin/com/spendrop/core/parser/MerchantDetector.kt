package com.spendrop.core.parser

import com.spendrop.core.model.ExpenseCategory
import java.text.Normalizer

data class MerchantCandidate(
    val rawText: String,
    val normalizedName: String,
    val score: Double,
    val sourceLineIndex: Int,
    val extractionMethod: String,
    val reasons: List<String>,
)

/** Finds the merchant (or payee) on a receipt and normalises its name (iOS `MerchantDetector`). */
object MerchantDetector {
    data class KnownMerchant(
        val name: String,
        val keywords: List<String>,
        val defaultCategory: ExpenseCategory,
        /** The merchant sells several kinds of things (e.g. plain "Grab"): its category is only a suggestion. */
        val ambiguous: Boolean = false,
    )

    private fun km(name: String, keywords: List<String>, category: ExpenseCategory, ambiguous: Boolean = false) =
        KnownMerchant(name, keywords, category, ambiguous)

    val knownMerchants: List<KnownMerchant> = listOf(
        // Food & Beverage
        km("McDonald's", listOf("mcdonald's", "mcdonalds", "mcd", "golden arches"), ExpenseCategory.FOOD),
        km("KFC", listOf("kfc", "kentucky fried chicken", "qsr stores"), ExpenseCategory.FOOD),
        km("Starbucks", listOf("starbucks", "berjaya starbucks"), ExpenseCategory.FOOD),
        km("Zus Coffee", listOf("zus coffee", "zus"), ExpenseCategory.FOOD),
        km("Tealive", listOf("tealive", "loob holding"), ExpenseCategory.FOOD),
        km("Subway", listOf("subway"), ExpenseCategory.FOOD),
        km("FamilyMart", listOf("familymart", "family mart", "ql maxincome"), ExpenseCategory.FOOD),
        km("Burger King", listOf("burger king", "cosmo restaurants"), ExpenseCategory.FOOD),
        km("Pizza Hut", listOf("pizza hut"), ExpenseCategory.FOOD),
        km("Nando's", listOf("nando's", "nandos"), ExpenseCategory.FOOD),
        km("Texas Chicken", listOf("texas chicken"), ExpenseCategory.FOOD),
        km("Marrybrown", listOf("marrybrown"), ExpenseCategory.FOOD),
        km("The Coffee Bean", listOf("coffee bean", "cbtl"), ExpenseCategory.FOOD),
        // Generic words such as "restoran", "mamak" or "nasi kandar" are category signals (CategoryDetector), not a merchant.
        km("Nasi Kandar Pelita", listOf("nasi kandar pelita", "restoran nasi kandar pelita", "pelita nasi kandar"), ExpenseCategory.FOOD),

        // Transport & Rides
        km("Grab", listOf("grabcar", "grab ride", "grab taxi", "grab driver", "myteksi"), ExpenseCategory.TRANSPORT),
        km("GrabFood", listOf("grabfood", "grab food"), ExpenseCategory.FOOD),
        km("Grab", listOf("grab"), ExpenseCategory.TRANSPORT, ambiguous = true),
        km("Foodpanda", listOf("foodpanda", "food panda", "delivery hero"), ExpenseCategory.FOOD),
        km("Shell", listOf("shell petrol", "shell station", "shell"), ExpenseCategory.TRANSPORT),
        km("Petronas", listOf("petronas", "mesra"), ExpenseCategory.TRANSPORT),
        km("Caltex", listOf("caltex"), ExpenseCategory.TRANSPORT),
        km("BHPetrol", listOf("bhpetrol", "bhp"), ExpenseCategory.TRANSPORT),
        km("Touch 'n Go RFID", listOf("tng rfid", "rfid toll", "plus expressways"), ExpenseCategory.TRANSPORT),
        km("Rapid KL", listOf("rapid kl", "prasarana", "mrt", "lrt"), ExpenseCategory.TRANSPORT),

        // Groceries & Retail
        km("MYDIN", listOf("mydin"), ExpenseCategory.GROCERIES),
        km("7-Eleven", listOf("7-eleven", "7 eleven", "7eleven", "seven eleven"), ExpenseCategory.GROCERIES),
        km("Lotus's", listOf("lotus's", "lotuss", "tesco"), ExpenseCategory.GROCERIES),
        km("Jaya Grocer", listOf("jaya grocer", "trendcell"), ExpenseCategory.GROCERIES),
        km("Village Grocer", listOf("village grocer", "the food purveyor"), ExpenseCategory.GROCERIES),
        km("Giant", listOf("giant hypermarket", "giant supermarket", "gch retail"), ExpenseCategory.GROCERIES),
        km("Aeon", listOf("aeon co", "aeon big", "aeon"), ExpenseCategory.GROCERIES),
        km("99 Speedmart", listOf("99 speedmart", "speedmart"), ExpenseCategory.GROCERIES),
        km("KK Super Mart", listOf("kk super mart", "kk mart"), ExpenseCategory.GROCERIES),
        km("MR. D.I.Y.", listOf("mr. d.i.y.", "mr diy", "mrdiy"), ExpenseCategory.SHOPPING),
        km("CU Mart", listOf("cu mart", "cu convenient store"), ExpenseCategory.GROCERIES),

        // Shopping & E-Commerce
        km("Shopee", listOf("shopee", "shopeepay"), ExpenseCategory.SHOPPING),
        km("Lazada", listOf("lazada"), ExpenseCategory.SHOPPING),
        km("TikTok Shop", listOf("tiktok shop", "tiktok"), ExpenseCategory.SHOPPING),
        km("Uniqlo", listOf("uniqlo"), ExpenseCategory.SHOPPING),
        km("Zara", listOf("zara"), ExpenseCategory.SHOPPING),

        // Health & Pharmacy
        km("Watsons", listOf("watsons", "watson's"), ExpenseCategory.HEALTH),
        km("Guardian", listOf("guardian"), ExpenseCategory.HEALTH),
        km("Caring Pharmacy", listOf("caring pharmacy", "caring"), ExpenseCategory.HEALTH),

        // Bills & Utilities
        km("TNB", listOf("tenaga nasional", "tnb"), ExpenseCategory.BILLS),
        km("Air Selangor", listOf("air selangor", "syabas"), ExpenseCategory.BILLS),
        km("Unifi", listOf("unifi", "telekom malaysia", "tm"), ExpenseCategory.BILLS),
        km("Maxis", listOf("maxis", "hotlink"), ExpenseCategory.BILLS),
        km("CelcomDigi", listOf("celcomdigi", "celcom", "digi"), ExpenseCategory.BILLS),
        km("U Mobile", listOf("u mobile", "umobile"), ExpenseCategory.BILLS),

        // Entertainment & Subscriptions
        km("Netflix", listOf("netflix"), ExpenseCategory.SUBSCRIPTION),
        km("Spotify", listOf("spotify"), ExpenseCategory.SUBSCRIPTION),
        km("Apple Services", listOf("apple.com/bill", "itunes.com/bill", "apple bill"), ExpenseCategory.SUBSCRIPTION),
        km("Google Play", listOf("google play", "google *"), ExpenseCategory.SUBSCRIPTION),
        km("GSC Cinemas", listOf("gsc cinemas", "golden screen cinemas", "gsc"), ExpenseCategory.ENTERTAINMENT),
        km("TGV Cinemas", listOf("tgv cinemas", "tgv"), ExpenseCategory.ENTERTAINMENT),
    )

    // MARK: - Semantic negative exclusion rules

    private val footerHelpKeywords = listOf(
        "for help with", "don't recognise", "dont recognise", "dispute a charge",
        "dispute a", "dispute", "contact maybank", "contact cimb", "contact rhb",
        "contact public bank", "contact bank islam", "contact wise", "contact us",
        "wallet uses maps", "report incorrect merchant info", "report incorrect",
        "help improve accuracy", "reporting incorrect information",
        "actual transaction amount in myr will reflect", "overseas transaction fee",
        "customer service", "help centre", "help center", "terms and conditions",
        "privacy policy", "careline", "toll free", "disclaimer", "share receipt",
    )

    private val uiActionKeywords = setOf(
        "share receipt", "share", "cancel", "done", "back", "close", "home",
        "menu", "download", "print", "pay again", "repeat transaction", "add to favourites",
        "view details", "save receipt", "<", ">", "•", "status", "details", "summary",
        "note", "notes", "remark", "remarks", "app test", "from", "to", "nickname",
        "when", "repeat", "transaction alert", "find out more",
    )

    private val statusKeywords = listOf(
        "status: approved", "status:approved", "status: failed", "status: pending",
        "payment successful", "transaction successful", "berjaya", "transaksi berjaya",
        "payment failed", "transfer successful", "approved", "successful", "failed", "declined",
    )

    private val identifierKeywords = listOf(
        "reference number", "ref no", "reference no", "transaction reference",
        "terminal id", "merchant id", "approval code", "auth code",
        "batch no", "trace no", "stan", "rrn", "account number", "account no",
        "duitnow ref no.", "duitnow ref no", "octo reference no.", "octo reference no",
        "beneficiary account number", "recipient reference", "ref:", "ref :",
    )

    private val paymentKeywords = listOf(
        "apple pay", "apple wallet", "pay with apple", "apple cash",
        "maybank visa debit", "cimb mastercard", "visa debit", "mastercard debit",
        "credit card", "debit card", "payment method", "paid via", "funding source",
        "maybank debit card visa", "duitnow qr", "duitnow transfer", "fpx",
        "payment type", "transfer type", "transfer method", "ewallet balance",
        "wallet balance", "bank/e-wallet account", "bank/e-wallet", "recipient bank/e-wallet",
        "receiving bank", "recipient bank", "payment",
    )

    private val malaysianLocations = setOf(
        "cyberjaya", "selangor", "kuala lumpur", "kl", "petaling jaya", "pj",
        "subang jaya", "subang", "shah alam", "putrajaya", "penang", "pulau pinang",
        "johor bahru", "jb", "melaka", "malacca", "ipoh", "perak", "kedah",
        "kuching", "sarawak", "kota kinabalu", "sabah", "pahang", "kuantan",
        "terengganu", "kelantan", "negeri sembilan", "seremban", "malaysia",
    )

    private val systemGenericWords = setOf(
        "wallet", "ewallet", "account", "bank account", "bank/e-wallet account", "bank/e-wallet",
        "transaction type", "transfer type", "transfer method", "payment type", "account number",
        "account no", "transfer to", "paid to", "receiver", "recipient", "beneficiary",
        "beneficiary name", "recipient bank", "receiving bank", "recipient bank/e-wallet",
        "recipient's name", "recipient name", "recipient's bank", "beneficiary's name", "beneficiary's bank", "merchant name",
        "date & time", "date/time", "date", "time", "when", "repeat", "remark", "remarks",
        "duitnow ref no.", "duitnow ref no", "reference no.", "reference no",
        "gong cha", "rm 2 gong cha", "is here on near me!", "near me", "fund transfer",
    )

    private val addressSuffixes = setOf("st", "st.", "street", "rd", "rd.", "road", "ave", "ave.", "avenue", "dr", "drive", "blvd", "boulevard", "lane", "ln", "way", "highway", "hwy")
    private val addressPrefixes = setOf("jalan", "persiaran", "lorong", "lebuh", "no.", "lot", "unit", "floor", "level", "block", "building", "suite")

    private val amountRegex = icuRegex("""(?:rm|myr|\$)\s*[0-9]+""", caseInsensitive = true)
    private val monthRegex = icuRegex("""\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b""", caseInsensitive = true)
    private val pureBanks = listOf("maybank", "cimb", "rhb", "public bank", "bank islam", "hong leong", "ambank", "touch 'n go", "tng")

    // MARK: - Validation & disqualification

    fun isAddressLine(text: String): Boolean {
        val lower = text.lowercase().trimWs()
        for (p in addressPrefixes) if (lower.startsWith("$p ") || lower.startsWith("$p.")) return true
        for (s in addressSuffixes) if (lower.endsWith(" $s") || lower.endsWith(" $s.")) return true

        val parts = lower.splitNonEmpty(' ')
        val first = parts.firstOrNull()
        if (first != null && parts.size >= 2 &&
            first.allCodePoints { isNumberChar(it) || isPunctuationChar(it) || it == '#'.code || it == '-'.code }
        ) {
            if (parts.drop(1).any { it in addressSuffixes || it in addressPrefixes }) return true
        }
        return false
    }

    fun isDisqualifiedLine(text: String): Boolean {
        val trimmed = text.trimWs()
        if (trimmed.isEmpty() || trimmed.charCount < 2) return true
        val lower = trimmed.lowercase()

        // Pure numbers, masks, punctuation
        if (trimmed.allCodePoints { isNumberChar(it) || isPunctuationChar(it) || isWhitespaceChar(it) || it == '*'.code }) return true

        // Amount patterns ("RM 10.00", "Paid RM25.90", "-RM12.00")
        if (lower.contains("rm") || lower.contains("myr") || lower.contains("$")) {
            if (amountRegex.containsMatchIn(lower)) return true
        }
        if (lower == "total" || lower == "amount" || lower == "jumlah" || lower.contains("total rm")) return true

        // Generic system table labels that must never be a merchant
        if (lower in systemGenericWords) return true
        // Footer / help / support
        if (footerHelpKeywords.any { lower.contains(it) }) return true
        // UI actions & table labels
        if (lower in uiActionKeywords) return true
        // Status
        for (kw in statusKeywords) if (lower == kw || lower.startsWith("$kw:") || lower.startsWith(kw)) return true
        // Identifiers
        for (kw in identifierKeywords) if (lower == kw || lower.startsWith("$kw:") || lower.startsWith("$kw ") || lower.startsWith(kw)) return true
        // Payment / account instruments
        for (kw in paymentKeywords) if (lower == kw || lower.startsWith("$kw:")) return true
        // Date / time lines
        if (isDateTimeLine(trimmed)) return true
        // Street address lines
        if (isAddressLine(trimmed)) return true
        // Status bar artifacts
        if (lower.contains("5g") || lower.contains("4g") || lower.contains("lte") || lower.contains("!!!!") || lower.contains("...")) return true
        // Pure bank names (when not explicitly labeled as merchant)
        if (pureBanks.any { lower == it || lower == "$it bank" || lower == "$it berhad" }) return true
        return false
    }

    fun isDateTimeLine(text: String): Boolean {
        val lower = text.lowercase()
        val hasYear = lower.contains("2024") || lower.contains("2025") || lower.contains("2026") || lower.contains("2027")
        val hasTime = lower.contains("am") || lower.contains("pm") || (text.contains(":") && text.countCodePoints { isNumberChar(it) } >= 3)
        val hasMonth = monthRegex.containsMatchIn(lower)
        return (hasYear && (text.contains("/") || text.contains("-") || text.contains(","))) || (hasTime && (text.contains(":") || hasMonth))
    }

    // MARK: - Normalisation

    private val suffixRegex = icuRegex(
        """\s*[-–•/]\s*(?:Applepay-Ec|ApplePay-EC|Applepay|Apple\s*Pay|FPX|DuitNow(?:\s*QR)?|D-QR|QR\s*Pay|QR|EC)\b.*$""",
        caseInsensitive = true,
    )
    private val parenRegex = icuRegex("""\s*\((?:Apple\s*Pay|FPX|DuitNow|QR)\)""", caseInsensitive = true)
    private val legalSuffixes = listOf("(M) SDN BHD", "SDN BHD", "SDN. BHD.", "SDN", "BHD", "ENTERPRISE", "PLT", "LTD", "INC", "CORP")
    private const val EDGE_PUNCTUATION = "-:,•()\"'"

    fun normalizeMerchantName(raw: String): String {
        var name = raw.trimWs()

        // 1. Strip location: "Brain Freeze Vape Shop, Cyberjaya, Selangor" -> "Brain Freeze Vape Shop"
        if (name.contains(",")) {
            val parts = name.splitNonEmpty(',').map { it.trimWs() }
            if (parts.size >= 2) {
                val remainingAreLocations = parts.drop(1).all { part ->
                    val lowerPart = part.lowercase()
                    lowerPart in malaysianLocations || lowerPart.startsWith("jalan") || lowerPart.startsWith("persiaran") ||
                        lowerPart.startsWith("lorong") || lowerPart.startsWith("no.")
                }
                if (remainingAreLocations && parts[0].isNotEmpty()) name = parts[0]
            }
        }

        // 2. Payment channel / metadata suffixes ("- Applepay-Ec", "- FPX", "- DuitNow", "- QR") and "(Apple Pay)"
        name = suffixRegex.matcher(name).replaceAll("")
        name = parenRegex.matcher(name).replaceAll("")

        // 3. Corporate entity words: the LAST occurrence of each is removed, wherever it is (as iOS does).
        for (suffix in legalSuffixes) {
            val idx = name.lastIndexOf(suffix, ignoreCase = true)
            if (idx >= 0) name = name.removeRange(idx, idx + suffix.length)
        }

        // 4. Leading/trailing punctuation (keep periods of acronyms like MR. D.I.Y.)
        name = name.trimWs().trim { it in EDGE_PUNCTUATION }.trimWs()
        if (name.endsWith(".") && name.count { it == '.' } <= 1) name = name.dropLast(1).trimWs()

        // Canonical casing for known brands
        knownMerchant(name)?.let { return it.name }
        return name
    }

    // MARK: - Detection

    /** The merchant name and (for an unambiguous known merchant) its category. */
    fun detect(lines: List<String>, fullText: String): Pair<String?, ExpenseCategory?> {
        val lowerFull = fullText.lowercase()
        val candidates = mutableListOf<MerchantCandidate>()

        val isAppleWallet = lowerFull.contains("wallet uses maps") ||
            (lowerFull.contains("report incorrect merchant info") && lowerFull.contains("status: approved"))

        var primaryAmountIndex: Int? = null
        var primaryDateIndex: Int? = null
        lines.forEachIndexed { idx, line ->
            val trimmed = line.trimWs()
            val lower = trimmed.lowercase()
            if (primaryAmountIndex == null &&
                (lower.startsWith("rm ") || lower.startsWith("rm") || lower.startsWith("$") || lower.startsWith("- rm") || lower.startsWith("-rm")) &&
                !lower.contains("total")
            ) primaryAmountIndex = idx
            if (primaryDateIndex == null && isDateTimeLine(trimmed)) primaryDateIndex = idx
        }

        fun add(raw: String, normalized: String, score: Double, idx: Int, method: String, reason: String) {
            candidates += MerchantCandidate(raw, normalized, score, idx, method, listOf(reason))
        }

        // STRATEGY 1: Apple Wallet structure (title line between the amount and the date)
        val amtIdx = primaryAmountIndex
        if (isAppleWallet && amtIdx != null) {
            val endIdx = primaryDateIndex ?: minOf(amtIdx + 3, lines.size - 1)
            if (endIdx > amtIdx) {
                for (i in (amtIdx + 1)..endIdx) {
                    val line = lines[i]
                    if (!isDisqualifiedLine(line)) {
                        val normalized = normalizeMerchantName(line)
                        if (normalized.isNotEmpty() && normalized.charCount >= 2) {
                            add(line, normalized, 95.0, i, "apple_wallet_title", "Apple Wallet title line between Amount and Date")
                            break
                        }
                    }
                }
            }
        }

        // STRATEGY 2: Explicit labelled field (key: value)
        for (regex in sameLinePatterns) {
            lines.forEachIndexed { idx, line ->
                val trimmed = line.trimWs()
                val m = regex.matcher(trimmed)
                if (m.find() && m.groupCount() >= 1 && m.group(1) != null) {
                    val rawValue = m.group(1).trimWs()
                    if (!isDisqualifiedLine(rawValue)) {
                        val normalized = normalizeMerchantName(rawValue)
                        if (normalized.isNotEmpty() && normalized.charCount >= 2) {
                            add(rawValue, normalized, 100.0, idx, "explicit_same_line_label", "Explicit labeled merchant field on same line")
                        }
                    }
                }
            }
        }

        // Standalone label on line i, value on line i+offset
        lines.forEachIndexed { idx, line ->
            val trimmed = line.trimWs()
            if (standaloneLabelRegex.containsMatchIn(trimmed)) {
                val maxOffset = minOf(15, lines.size - idx - 1)
                if (maxOffset >= 1) {
                    for (offset in 1..maxOffset) {
                        val nextLine = lines[idx + offset].trimWs()
                        if (!isDisqualifiedLine(nextLine)) {
                            val normalized = normalizeMerchantName(nextLine)
                            if (normalized.isNotEmpty() && normalized.charCount >= 2) {
                                val score = if (offset == 1) 100.0 else maxOf(70.0, 100.0 - offset * 2)
                                add(nextLine, normalized, score, idx + offset, "explicit_next_line_label",
                                    "Explicit standalone label followed by value at offset $offset")
                                break
                            }
                        }
                    }
                }
            }
        }

        // STRATEGY 3: Bank app header (line directly above the amount)
        if (amtIdx != null && amtIdx > 0) {
            val lineAbove = lines[amtIdx - 1]
            if (!isDisqualifiedLine(lineAbove)) {
                val normalized = normalizeMerchantName(lineAbove)
                if (normalized.isNotEmpty() && normalized.charCount >= 2) {
                    add(lineAbove, normalized, 85.0, amtIdx - 1, "amount_header_above", "Prominent line directly above transaction amount")
                }
            }
        }

        // STRATEGY 4: Physical receipt header (top 5 lines)
        lines.take(5).forEachIndexed { idx, line ->
            if (!isDisqualifiedLine(line)) {
                val normalized = normalizeMerchantName(line)
                if (normalized.isNotEmpty() && normalized.charCount in 3..35) {
                    add(line, normalized, 75.0 - idx * 5, idx, "receipt_header", "Top line in receipt header")
                }
            }
        }

        // Highest score wins; ties go to the earliest candidate (stable, like iOS).
        val best = candidates.sortedByDescending { it.score }.firstOrNull()
        if (best == null || best.score < 30.0) return null to null
        return best.normalizedName to categoryForMerchant(best.normalizedName)
    }

    private val sameLinePatterns = listOf(
        """^(?:merchant(?:\s*name)?|payee(?:\s*name)?|beneficiary(?:['’]s)?(?:\s*name)?|recipient(?:['’]s)?(?:\s*name)?|receiver(?:['’]s)?(?:\s*name)?|paid\s*to|pay\s*to|store|shop)\s*[:\-]\s*(.+)$""",
        """^(?:nama\s*penerima|diterima\s*oleh|kepada|penerima)\s*[:\-]\s*(.+)$""",
        """^to\s*[:\-]\s*(.+)$""",
        """\b(?:payment\s+(?:rm|myr)?\s*[0-9.,]+\s+to|paid\s+to|transfer\s+to)\s+([A-Za-z0-9\s&'.()\-]{2,35}?)(?:\s+accepted|\s+successful|\s+on|\.|$)""",
    ).map { icuRegex(it, caseInsensitive = true) }

    private val standaloneLabelRegex = icuRegex(
        """^(?:merchant(?:\s*name)?|payee(?:\s*name)?|beneficiary(?:['’]s)?(?:\s*name)?|recipient(?:['’]s)?(?:\s*name)?|receiver(?:['’]s)?(?:\s*name)?|paid\s*to|pay\s*to|transfer\s*to|to|store|shop|kepada|penerima|nama\s*penerima)\s*[:\-]?$""",
        caseInsensitive = true,
    )

    private fun categoryForMerchant(name: String): ExpenseCategory? {
        val item = knownMerchant(name) ?: return null
        return if (item.ambiguous) null else item.defaultCategory
    }

    /**
     * The known merchant a name refers to, matching whole words only: "MCD" and "McDonald's Bangsar" are McDonald's,
     * but "MCDERMOTT LAW", "SHELLY BEAUTY", "DIGITAL STORE" and "ATMOS CAFE" are not.
     */
    fun knownMerchant(name: String?): KnownMerchant? {
        if (name == null) return null
        val text = " " + normalizedWords(name) + " "
        if (text.trim { it == ' ' || it == '\t' }.charCount < 2) return null
        for (item in knownMerchants) {
            for (keyword in item.keywords) {
                val kw = normalizedWords(keyword)
                if (kw.isEmpty()) continue
                if (text.contains(" $kw ")) return item
            }
        }
        return null
    }

    /**
     * Lowercase words separated by single spaces; apostrophes kept inside words ("lotus's"), "-", "." and "*" kept;
     * every other non-letter / non-digit becomes a separator.
     */
    fun normalizedWords(text: String): String {
        val lowered = Normalizer.normalize(text, Normalizer.Form.NFC).lowercase().replace('’', '\'')
        val out = StringBuilder(lowered.length)
        lowered.codePoints().forEach { cp ->
            if (isLetterChar(cp) || isNumberChar(cp) || Character.getType(cp) == Character.NON_SPACING_MARK.toInt() ||
                cp == '\''.code || cp == '-'.code || cp == '.'.code || cp == '*'.code
            ) out.appendCodePoint(cp) else out.append(' ')
        }
        return out.toString().splitNonEmpty(' ').joinToString(" ")
    }
}
