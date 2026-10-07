package com.spendrop.core.parser

import com.spendrop.core.model.Expense
import com.spendrop.core.model.ExpenseCategory
import com.spendrop.core.model.PaymentChannel
import com.spendrop.core.model.PaymentSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset

/**
 * Port of iOS `TransactionParserTests.runAllTests()` (OCR/TransactionParserTests.swift): every case about parsing.
 * Cases about SwiftData persistence, duplicate detection, PayBook, the filter engine, logo assets and the share
 * view model (iOS tests 11, 12, 21–23, 32, 43–51, 56–72, 87, 91–93) belong to other modules and are not here.
 * Test numbers in the names match the iOS file.
 */
class TransactionParserTest {
    /** iOS `makeOCRResult(text:)`: non-empty lines at confidence 0.95, full text unchanged. */
    private fun parse(text: String): ParsedTransaction =
        TransactionParser.parse(text.trimIndent(), lineConfidence = 0.95f, zone = ZoneOffset.UTC)

    @Test fun t01_tngMcDonaldsPayment() {
        val p = parse(
            """
            Touch 'n Go eWallet
            Payment Successful
            RM18.50
            Paid to: McDonald's
            16 Sep 2026 9:42 PM
            Ref No: TNG992837194
            """,
        )
        assertEquals(1850L, p.amountMinor)
        assertEquals(PaymentSource.TOUCH_N_GO, p.paymentSource)
        assertEquals("McDonald's", p.merchant)
        assertEquals(ExpenseCategory.FOOD, p.category)
        assertTrue(p.isCompletedTransaction)
    }

    @Test fun t02_maybankMydinTransfer() {
        val p = parse(
            """
            Maybank2u
            Transfer Successful
            Amount: RM42.90
            Recipient: MYDIN
            16/09/2026
            Reference: MBB20260916892
            """,
        )
        assertEquals(4290L, p.amountMinor)
        assertEquals(PaymentSource.MAYBANK, p.paymentSource)
        assertEquals("MYDIN", p.merchant)
        assertEquals(ExpenseCategory.GROCERIES, p.category)
    }

    @Test fun t03_cimbShellPetrol() {
        val p = parse(
            """
            CIMB OCTO
            DuitNow Transfer Successful
            RM50.00
            Paid to: Shell
            """,
        )
        assertEquals(5000L, p.amountMinor)
        assertEquals(PaymentSource.CIMB, p.paymentSource)
        assertEquals("Shell", p.merchant)
        assertEquals(ExpenseCategory.TRANSPORT, p.category)
    }

    @Test fun t04_applePayStarbucks() {
        val p = parse(
            """
            Apple Pay
            Paid RM25.90
            Starbucks
            16 Sep 2026
            """,
        )
        assertEquals(2590L, p.amountMinor)
        assertEquals(PaymentSource.APPLE_PAY, p.paymentSource)
        assertEquals("Starbucks", p.merchant)
    }

    @Test fun t05_receiptTotalBeatsSubtotalAndTax() {
        val p = parse(
            """
            KOPITIAM RESTORAN
            Tax Invoice
            Subtotal RM20.00
            SST 6% RM1.20
            Total RM21.20
            Cash
            """,
        )
        assertEquals(2120L, p.amountMinor)
    }

    @Test fun t06_falsePositiveAccountBalance() {
        val p = parse(
            """
            Maybank2u
            Welcome Back
            Available Balance
            RM1,250.00
            Account No: 114012345678
            """,
        )
        assertTrue(p.isBalanceOrLimitOnly)
        assertNull(p.amountMinor)
    }

    @Test fun t07_falsePositiveCreditLimit() {
        val p = parse(
            """
            RHB Bank
            Credit Limit
            RM5,000.00
            Available Credit: RM4,500.00
            """,
        )
        assertTrue(p.isBalanceOrLimitOnly)
        assertNull(p.amountMinor)
    }

    @Test fun t08_falsePositiveRewardPoints() {
        val p = parse(
            """
            Touch 'n Go eWallet
            My Rewards
            2,500 points
            Points expiring soon
            """,
        )
        assertTrue(p.isBalanceOrLimitOnly)
        assertNull(p.amountMinor)
    }

    @Test fun t09_failedPayment() {
        val p = parse(
            """
            Touch 'n Go eWallet
            Payment Failed
            RM25.90
            Reason: Insufficient Balance
            """,
        )
        assertTrue(p.isFailedTransaction)
    }

    @Test fun t10_qrPaymentWithoutMerchant() {
        val p = parse(
            """
            DuitNow QR
            Payment Successful
            RM15.00
            Ref: 981273981
            """,
        )
        assertEquals(1500L, p.amountMinor)
        assertEquals(PaymentSource.QR_PAYMENT, p.paymentSource)
        assertNull(p.merchant)
    }

    @Test fun t13_receiverNameDetection() {
        val p = parse(
            """
            DuitNow Transfer
            Transfer Successful
            RM85.00
            Receiver: RANA SOHEL
            17 Sep 2026 10:15 AM
            Ref No: DT991823719
            """,
        )
        assertEquals(8500L, p.amountMinor)
        assertEquals("RANA SOHEL", p.merchant)
    }

    @Test fun t14_tngAmountBeatsAdvertisement() {
        val p = parse(
            """
            Touch 'n Go eWallet
            Transferred
            RM22.00
            Receiver: RANA SOHEL
            Date: 15/09/2026
            Time: 13:49:06
            Ref: TNG992837194
            Special Offer
            Panasonic Air Conditioner
            RM450
            Shop Now
            """,
        )
        assertEquals(2200L, p.amountMinor)
        assertEquals("RANA SOHEL", p.merchant)
        assertEquals("touch_n_go", p.provider)
        assertTrue(p.providerConfidence >= 0.90)
        assertNotEquals(45000L, p.amountMinor)
    }

    @Test fun t15_multipleAmountsTotalWins() {
        val p = parse(
            """
            Payment Receipt
            Amount: RM50.00
            Service Fee: RM1.00
            Total: RM51.00
            Balance: RM948.00
            Cashback: RM5.00
            Paid to: Coffee Bean
            """,
        )
        assertEquals(5100L, p.amountMinor)
        assertTrue(p.merchant.orEmpty().contains("Coffee Bean"))
    }

    @Test fun t16_multipleAmountsWithoutTotal() {
        val p = parse(
            """
            Transfer Receipt
            Amount: RM50.00
            Service Fee: RM1.00
            Balance: RM948.00
            Receiver: Ali Express
            """,
        )
        assertEquals(5000L, p.amountMinor)
    }

    @Test fun t17_malaysianProviderAutoDetection() {
        val cases = listOf(
            "Touch 'n Go eWallet\nPayment Successful\nRM10.00" to "touch_n_go",
            "MAE by Maybank2u\nTransfer Successful\nRM20.00" to "maybank",
            "CIMB OCTO\nTransfer Successful\nRM30.00" to "cimb",
            "RHB Mobile Banking\nSuccessful\nRM40.00" to "rhb",
            "Public Bank PB Engage\nPayment Successful\nRM50.00" to "public_bank",
            "Bank Islam GO\nTransfer Successful\nRM60.00" to "bank_islam",
            "GrabPay\nPayment Successful\nRM70.00" to "grabpay",
            "Boost eWallet\nPayment Successful\nRM80.00" to "boost",
            "DuitNow Transfer\nSuccessful\nRM90.00" to "duitnow",
        )
        assertEquals(cases.map { it.second }, cases.map { parse(it.first).provider })
    }

    @Test fun t18_unknownProviderStillExtracts() {
        val p = parse(
            """
            Transfer Successful
            RM35.00
            Receiver: Ali Baba
            Date: 12/09/2026
            """,
        )
        assertEquals("unknown", p.provider)
        assertEquals(3500L, p.amountMinor)
        assertEquals("Ali Baba", p.merchant)
    }

    @Test fun t19_lowConfidenceBareAmounts() {
        val p = parse(
            """
            Statement of Account
            22.00
            20.00
            2.00
            """,
        )
        assertEquals(ParsingConfidence.LOW, p.confidence)
        assertTrue(p.amountCandidates.size >= 3)
    }

    @Test fun t20_normalizedTransactionModel() {
        val p = parse(
            """
            Touch 'n Go eWallet
            Transferred
            RM22.00
            Receiver: RANA SOHEL
            Date: 15/09/2026
            Time: 13:49:06
            Ref: TNG123456
            """,
        )
        val map = p.toNormalizedMap()
        assertEquals("touch_n_go", map["provider"])
        assertEquals(22.0, map["amount"])
        assertEquals("RANA SOHEL", map["merchant"])
        assertEquals("2026-09-15", map["date"])
        assertEquals("13:49:06", map["time"])
        assertEquals("transferred", map["status"])
        // The moment itself, read in the parser's zone (UTC here).
        assertEquals(java.time.Instant.parse("2026-09-15T13:49:06Z").toEpochMilli(), p.date)
    }

    @Test fun t24_providerTouchNGo() {
        val p = parse(
            """
            Touch 'n Go eWallet
            Payment Successful
            RM 15.80
            Subway Malaysia
            18 Sep 2026 12:30
            """,
        )
        assertEquals(PaymentSource.TOUCH_N_GO, p.paymentSource)
        assertNull(p.underlyingBank)
        assertEquals("ewallet", p.paymentMethod)
    }

    @Test fun t25_providerMaybankMae() {
        val p = parse(
            """
            MAE by Maybank2u
            Transfer Successful
            RM 45.00
            Recipient: Ahmad Zaki
            18/09/2026
            """,
        )
        assertEquals(PaymentSource.MAYBANK, p.paymentSource)
        assertEquals(PaymentSource.MAYBANK, p.underlyingBank)
    }

    @Test fun t26_providerCimb() {
        val p = parse(
            """
            CIMB OCTO
            DuitNow Transfer Successful
            RM 88.00
            Beneficiary: Siti Nurhaliza
            Reference: 20260918112233
            """,
        )
        assertEquals(PaymentSource.CIMB, p.paymentSource)
        assertEquals(PaymentSource.CIMB, p.underlyingBank)
    }

    @Test fun t27_providerRhb() {
        val p = parse(
            """
            RHB Mobile Banking
            Successful Transaction
            RM 120.00
            Paid to: Tenaga Nasional
            18 Sep 2026
            """,
        )
        assertEquals(PaymentSource.RHB, p.paymentSource)
        assertEquals(PaymentSource.RHB, p.underlyingBank)
    }

    @Test fun t28_applePayStandaloneNoBank() {
        val p = parse(
            """
            Starbucks Coffee
            Total: RM 25.90
            Paid with Apple Pay
            Device Account Number: *1234
            18/09/2026 09:15
            """,
        )
        assertEquals(PaymentSource.APPLE_PAY, p.paymentSource)
        assertNull(p.underlyingBank)
        assertEquals(2590L, p.amountMinor)
    }

    @Test fun t29_applePayWithCimb() {
        val p = parse(
            """
            Starbucks Coffee
            Total: RM 28.50
            Payment Method: Apple Pay
            Card: CIMB Bank Debit *8821
            18/09/2026 14:02
            """,
        )
        assertEquals(PaymentSource.APPLE_PAY, p.paymentSource)
        assertEquals(PaymentSource.CIMB, p.underlyingBank)
        assertEquals("digital_wallet", p.paymentMethod)
        assertNotEquals("CIMB", p.merchant)
    }

    @Test fun t30_applePayWithMaybank() {
        val p = parse(
            """
            Uniqlo Mid Valley
            Total: RM 149.90
            Paid using Apple Pay
            Funding: Maybank Visa Signature
            18/09/2026 16:20
            """,
        )
        assertEquals(PaymentSource.APPLE_PAY, p.paymentSource)
        assertEquals(PaymentSource.MAYBANK, p.underlyingBank)
    }

    @Test fun t31_unknownProviderFallback() {
        val p = parse(
            """
            Kopitiam Ah Kow
            RM 12.50
            Receipt #48291
            18/09/2026 08:30
            """,
        )
        assertTrue(p.paymentSource == PaymentSource.UNKNOWN || p.paymentSource == null)
        assertEquals("unknown", p.provider)
        assertEquals(1250L, p.amountMinor)
        assertNotNull(p.merchant)
    }

    @Test fun t33_cimbQrPaymentAdExclusions() {
        val p = parse(
            """
            Transaction Summary
            MYR 0.01
            18 Sep 2026 2:17:49 PM
            OCTO Reference No.
            DuitNow Reference No.
            To
            From
            283547681
            03382744
            RUKON TOUHIDUL ISLAM
            SAVINGS ACCT-i PLUS
            7658174175
            QR BASKIN-ROBBINS CAMPAIGN
            RM5 OFF
            Scan & pay via QR with OCTO!
            Minimum spend RM15 (non-promotional items only)
            Validity: 1 September 2026 - 31 January 2027
            Find out more
            Terms and Conditions apply.
            Done
            """,
        )
        assertEquals(1L, p.amountMinor)
        assertEquals("cimb", p.provider)
        assertEquals("duitnow_qr", p.paymentMethod)
        assertEquals(PaymentSource.CIMB, p.underlyingBank)
        assertEquals("RUKON TOUHIDUL ISLAM", p.merchant)
        assertNotEquals(500L, p.amountMinor)
        assertNotEquals(1500L, p.amountMinor)
    }

    @Test fun t34_cimbNotificationFpx() {
        val p = parse(
            """
            Transaction Alert
            CIMB: FPX Payment RM932.46 to IPAY88 (M) SDN BHD accepted on 06-Aug-2026, 23:13:56. Call the no at the back of your card for queries.
            """,
        )
        assertEquals(93246L, p.amountMinor)
        assertEquals("cimb", p.provider)
        assertEquals("bank_transfer", p.paymentMethod)
        assertEquals("IPAY88", p.merchant)
    }

    @Test fun t35_cimbInterbankSenderNotRecipient() {
        val p = parse(
            """
            Transaction Summary
            MYR 1.00
            18 Sep 2026 2:18:39 PM
            Reference No.
            TO
            Nickname
            From
            When
            Repeat
            Transfer Method
            Payment Type
            283550902
            TOUHIDUL ISLAM RUKON
            Maybank 168603292644
            Rukon
            SAVINGS ACCT-i PLUS
            7658174175
            Today, 18 Sep 2026
            No
            Duit Now to Account
            Fund Transfer
            Done
            """,
        )
        assertEquals(100L, p.amountMinor)
        assertEquals("cimb", p.provider)
        assertEquals(PaymentSource.CIMB, p.underlyingBank)
        assertEquals("duitnow", p.paymentMethod)
    }

    @Test fun t36_maybankInterbankSenderNotRecipient() {
        val p = parse(
            """
            Maybank
            DuitNow Transfer
            Successful
            Reference ID
            035649071M
            Beneficiary name
            TOUHIDUL ISLAM RUKON
            Beneficiary account number
            2160 1100 0364 06
            Receiving bank
            RHB BANK
            Recipient reference
            Rukon
            Payment details
            App Test
            Amount
            RM 0.01
            18 Sep 2026, 02:16 PM
            """,
        )
        assertEquals(1L, p.amountMinor)
        assertEquals("maybank", p.provider)
        assertEquals(PaymentSource.MAYBANK, p.underlyingBank)
        assertEquals("duitnow", p.paymentMethod)
        assertEquals("TOUHIDUL ISLAM RUKON", p.merchant)
    }

    @Test fun t37_maybankScanAndPay() {
        val p = parse(
            """
            Maybank
            Scan & Pay
            Successful
            Reference ID
            QR70737488
            18 Sep 2026, 2:15 PM
            Beneficiary Name
            RUKONTOUHIDULISLAM
            Amount
            RM 0.01
            Note: This receipt is computer generated
            Malayan Banking Berhad
            """,
        )
        assertEquals(1L, p.amountMinor)
        assertEquals("maybank", p.provider)
        assertEquals("duitnow_qr", p.paymentMethod)
        assertEquals("RUKONTOUHIDULISLAM", p.merchant)
    }

    @Test fun t38_rhbInterbankSenderNotRecipient() {
        val p = parse(
            """
            Status
            Successful
            02:21PM Friday, 18 September 2026 MYT
            Amount
            MYR 1.00
            Reference ID
            DuitNow
            Transfer
            17897124619260845
            From
            RHB Smart Account
            21601100036406
            To
            TOUHIDUL ISLAM RUKON
            7658174175
            Bank
            CIMB
            Transfer Method
            DuitNow (Instant)
            """,
        )
        assertEquals(100L, p.amountMinor)
        assertEquals("rhb", p.provider)
        assertEquals(PaymentSource.RHB, p.underlyingBank)
        assertEquals("duitnow", p.paymentMethod)
        assertEquals("TOUHIDUL ISLAM RUKON", p.merchant)
    }

    @Test fun t39_rhbDuitNowQr() {
        val p = parse(
            """
            Status
            Successful
            02:19PM Friday, 18 September 2026 MYT
            Amount
            MYR 0.01
            Reference ID
            DuitNow QR
            20260918RHBBMYKL0400QR59060146
            From
            RHB Smart Account
            21601100036406
            To
            RUKONTOUHIDULISLAM
            Payment Type
            Duit Now QR P2P
            """,
        )
        assertEquals(1L, p.amountMinor)
        assertEquals("rhb", p.provider)
        assertEquals("duitnow_qr", p.paymentMethod)
        assertEquals("RUKONTOUHIDULISLAM", p.merchant)
    }

    @Test fun t40_tngNotificationNegativeAmount() {
        val p = parse(
            """
            Details
            -RM12.00
            Transaction Type
            Transfer to Wallet
            Transfer To
            BARAKAT MD ABUL
            Payment Details
            BARAKAT MD ABUL
            Payment Method
            eWallet Balance
            Date/Time
            02/08/2026 13:07:14
            Wallet Ref 2026080211121700010100171897968925005
            Status
            Successful
            """,
        )
        assertEquals(1200L, p.amountMinor)
        assertEquals("touch_n_go", p.provider)
        assertEquals("ewallet", p.paymentMethod)
        assertNull(p.underlyingBank)
        assertEquals("BARAKAT MD ABUL", p.merchant)
    }

    @Test fun t41_tngInterbankNearMeAd() {
        val p = parse(
            """
            RM 1.00
            Transferred
            Receiver
            Nickname
            Transaction Type
            Transfer to
            Recipient Bank/E-Wallet
            Account Number
            Transfer Type
            Remark
            Date & Time
            DuitNow Ref No.
            TOUHIDUL ISLAM RUKON
            Rukon
            DuitNow Transfer
            Bank/E-Wallet Account
            Maybank
            168603292644
            Fund Transfer
            18/09/2026 14:12:57
            20260918TNGDMYNB010ORM42680415
            Gong cha
            RM 2 Gong Cha
            is here on Near Me!
            Done
            """,
        )
        assertEquals(100L, p.amountMinor)
        assertNotEquals(200L, p.amountMinor)
        assertEquals("touch_n_go", p.provider)
        assertEquals("duitnow", p.paymentMethod)
        assertEquals("TOUHIDUL ISLAM RUKON", p.merchant)
    }

    @Test fun t42_tngQrTransfer() {
        val p = parse(
            """
            RM 0.01
            Transferred
            Receiver: RIYAD MD TANVIR ISLAM
            Fund Transfer
            18/09/2026 14:13:58
            Done
            """,
        )
        assertEquals(1L, p.amountMinor)
        assertEquals("touch_n_go", p.provider)
        assertEquals("RIYAD MD TANVIR ISLAM", p.merchant)
    }

    @Test fun t52_maybankPlusApplePay() {
        val p = parse(
            """
            Apple Pay
            Paid RM50.00 to Starbucks
            Maybank Debit Card ending in 4175
            26 Sep 2026
            """,
        )
        assertEquals(5000L, p.amountMinor)
        assertEquals(PaymentChannel.APPLE_PAY, p.paymentChannel)
        assertTrue(p.displayFundingAccount.contains("Maybank"))
    }

    @Test fun t53_maybankPlusDuitNowQr() {
        val p = parse(
            """
            Maybank2u
            Scan & Pay Successful
            RM35.00
            Paid to: Restaurant Ali
            DuitNow QR Reference: MBBQR102938
            """,
        )
        assertEquals(3500L, p.amountMinor)
        assertEquals(PaymentChannel.DUITNOW_QR, p.paymentChannel) // receipt says "DuitNow QR": the specific channel
        assertTrue(p.displayFundingAccount.contains("Maybank"))
    }

    @Test fun t54_maybankPlusBankTransfer() {
        val p = parse(
            """
            Maybank
            DuitNow Transfer Successful
            Amount: RM500.00
            Recipient: Rahim bin Ahmad
            Reference: 20260925MBB8291
            """,
        )
        assertEquals(50000L, p.amountMinor)
        assertEquals(PaymentChannel.BANK_TRANSFER, p.paymentChannel)
        assertTrue(p.displayFundingAccount.contains("Maybank"))
    }

    @Test fun t55_wisePlusApplePay() {
        val p = parse(
            """
            Apple Pay
            RM20.00
            Uniqlo
            Paid with Wise Card ending in 8891
            """,
        )
        assertEquals(2000L, p.amountMinor)
        assertEquals(PaymentChannel.APPLE_PAY, p.paymentChannel)
        assertTrue(p.displayFundingAccount.contains("Wise"))
    }

    @Test fun t73_maeShopeeApplepayEcReceiptIsUnknownChannel() {
        val p = parse(
            """
            10:14 O
            • Shopee
            <
            !!!! 5G 64
            27 Sep 2026, 10:14 AM
            SHOPEE - APPLEPAY-EC
            - RM 4.48
            Payment
            Reference Number
            Merchant name
            Terminal ID
            Merchant ID
            Approval Code
            Maybank Debit Card Visa
            ************ 9034
            626902161660
            SHOPEE - APPLEPAY-EC
            75003178
            027007722648
            145592
            Share Receipt
            * Actual transaction amount in MYR will reflect in your
            transaction history once it's processed. It will include the
            overseas transaction fee and admin fee.
            """,
        )
        // Merchant name "APPLEPAY-EC" without Apple Wallet markers must not set the channel.
        assertEquals(PaymentChannel.UNKNOWN, p.paymentChannel)
        assertTrue(p.fundingAccount == "Maybank" || p.displayFundingAccount == "Maybank")
        assertTrue(p.fundingInstrument?.lowercase()?.contains("visa") == true) // reported (not part of iOS pass condition)
        assertEquals(448L, p.amountMinor)
        assertEquals("Shopee", p.merchant)
    }

    @Test fun t74_appleWalletEzFreshMart() {
        val p = parse(
            """
            1:30 1
            !!!!
            <
            RM 74.20
            EZ Fresh Mart, Cyberjaya, Selangor
            27/09/2026, 8:36 PM
            Status: Approved
            Maybank Visa Debit
            Total
            RM 74.20
            NION
            CYBERIA 3.
            NEURON
            PERSIARAN SEPANG
            Zumo
            EZ Fresh Mart
            PERSIARAN MULTIMEDIA
            -IMEDIA
            EZ Fresh Mart
            JALAN FA
            Contact Maybank
            For help with a charge you don't recognise or to dispute a
            charge, contact Maybank.
            Report Incorrect Merchant Info
            Wallet uses Maps to provide merchant name, category and
            location for your transactions. Help improve accuracy by
            reporting incorrect information.
            """,
        )
        assertEquals(PaymentChannel.APPLE_PAY, p.paymentChannel)
        assertTrue(p.fundingAccount == "Maybank" || p.displayFundingAccount == "Maybank")
        assertTrue(p.fundingInstrument?.lowercase()?.contains("visa debit") == true) // reported (not part of iOS pass condition)
        assertEquals(7420L, p.amountMinor)
        assertEquals("EZ Fresh Mart", p.merchant)
    }

    private val walletFooter = """
        Contact Maybank
        For help with a charge you don't recognise or to dispute a
        charge, contact Maybank.
        Report Incorrect Merchant Info
        Wallet uses Maps to provide merchant name, category and
        location for your transactions. Help improve accuracy by
        reporting incorrect information.
    """.trimIndent()

    @Test fun t75_appleWalletShopee() {
        val p = parse(
            """
            |1:30 1
            |.!!!
            |<
            |RM 4.48
            |Shopee - Applepay-Ec
            |27/09/2026, 10:14AM
            |Status: Approved
            |Maybank Visa Debit
            |Total
            |RM 4.48
            """.trimMargin() + "\n" + walletFooter,
        )
        assertEquals(PaymentChannel.APPLE_PAY, p.paymentChannel)
        assertTrue(p.fundingAccount == "Maybank" || p.displayFundingAccount == "Maybank")
        assertEquals(448L, p.amountMinor)
        assertEquals("Shopee", p.merchant)
    }

    @Test fun t76_appleWalletBrainFreeze() {
        val p = parse(
            """
            |1:30
            |!!!!
            |<
            |RM 40.00
            |Brain Freeze Vape Shop, Cyberjaya, Selangor
            |26/09/2026, 3:13 PM
            |Status: Approved
            |Maybank Visa Debit
            |Total
            |RM 40.00
            |Warung Hanna
            |SERIN
            |PERSIARAN CERIA
            |& RESIDENCY
            |AN FAUNA 1
            |Brain Freeze Vape Shop
            |KNOKRAT 6
            |Brain Freeze Vape Shop
            """.trimMargin() + "\n" + walletFooter,
        )
        assertEquals(PaymentChannel.APPLE_PAY, p.paymentChannel)
        assertTrue(p.fundingAccount == "Maybank" || p.displayFundingAccount == "Maybank")
        assertEquals(4000L, p.amountMinor)
        assertEquals("Brain Freeze Vape Shop", p.merchant)
    }

    @Test fun t77_appleWalletShell() {
        val p = parse(
            """
            |1:30
            |!!!!
            |<
            |RM 23.20
            |Shell, Cyberjaya, Selangor
            |21/09/2026, 8:12 PM
            |Status: Approved
            |Maybank Visa Debit
            |Total
            |RM 23.20
            |7-Eleven
            |CERIA
            |SI
            |Shell
            |SERIN
            |SIDENCY
            |Restoran
            |A -Nazmaju
            |SIARAN APEC
            |Shell
            """.trimMargin() + "\n" + walletFooter,
        )
        assertEquals(PaymentChannel.APPLE_PAY, p.paymentChannel)
        assertTrue(p.fundingAccount == "Maybank" || p.displayFundingAccount == "Maybank")
        assertEquals(2320L, p.amountMinor)
        assertEquals("Shell", p.merchant)
        assertEquals(ExpenseCategory.TRANSPORT, p.category) // reported on iOS (not part of its pass condition)
    }

    @Test fun t78_section18AppleWalletShopeeNotFooterText() {
        val p = parse(
            """
            |8:17
            |.!!!
            |<
            |RM 22.48
            |Shopee - Applepay-Ec
            |26/09/2026, 8:16 PM
            |Status: Approved
            |Maybank Visa Debit
            |Total
            |RM 22.48
            """.trimMargin() + "\n" + walletFooter,
        )
        assertEquals("Shopee", p.merchant)
        assertNotEquals("dispute a", p.merchant)
        assertNotEquals("Maybank", p.merchant)
        assertNotEquals("Contact Maybank", p.merchant)
        assertEquals(2248L, p.amountMinor)
        assertEquals(PaymentChannel.APPLE_PAY, p.paymentChannel)
        assertTrue(p.fundingAccount == "Maybank" || p.displayFundingAccount == "Maybank")
    }

    @Test fun t79_testA_explicitMerchantField() {
        val p = parse(
            """
            Merchant: Guardian Pharmacy
            Amount: RM25.00
            Date: 26/09/2026
            """,
        )
        assertEquals("Guardian", p.merchant)
    }

    @Test fun t80_testB_headerMerchantWithoutLabel() {
        val p = parse(
            """
            McDonald's Restaurant
            123 Main St
            RM 15.50
            """,
        )
        assertEquals("McDonald's", p.merchant)
    }

    @Test fun t81_testC_bankInFooterIsNotMerchant() {
        val p = parse(
            """
            RM 50.00
            Zus Coffee
            Total: RM50.00
            Contact Maybank
            For help with a charge, contact Maybank.
            """,
        )
        assertEquals("Zus Coffee", p.merchant)
    }

    @Test fun t82_testD_helpTextIsNotMerchant() {
        val p = parse(
            """
            RM 10.00
            Tealive
            For help with a charge you don't recognise or to dispute a charge, contact Maybank.
            """,
        )
        assertEquals("Tealive", p.merchant)
        assertNotEquals("dispute a", p.merchant)
    }

    @Test fun t83_testE_paymentFieldIsNotMerchant() {
        val p = parse(
            """
            Payment: Maybank Visa Debit
            Amount: RM30.00
            KFC Cyberjaya
            """,
        )
        assertEquals("KFC", p.merchant)
    }

    @Test fun t84_testF_legitimateHyphenPreserved() {
        assertEquals("7-Eleven", MerchantDetector.normalizeMerchantName("7-Eleven"))
    }

    @Test fun t85_testG_paymentSuffixStripped() {
        assertEquals("Shopee", MerchantDetector.normalizeMerchantName("Shopee - Applepay-Ec"))
    }

    @Test fun t86_testH_noReliableMerchant() {
        val p = parse(
            """
            DuitNow QR
            Payment Successful
            RM15.00
            Ref: 12345
            """,
        )
        assertNull(p.merchant)
    }

    private fun expenseFrom(p: ParsedTransaction, fallbackMerchant: String) = Expense(
        id = "e", amountMinor = p.amountMinor ?: 0, merchant = p.merchant ?: fallbackMerchant,
        categoryRaw = (p.category ?: ExpenseCategory.OTHER).raw, paymentChannelRaw = p.paymentChannel.raw,
        fundingAccount = p.displayFundingAccount, fundingInstrument = p.fundingInstrument, date = 0, createdAt = 0, updatedAt = 0,
    )

    @Test fun t88_flow_appleWalletKeepsApplePayIntoExpense() {
        val p = parse(
            """
            RM 128.50
            Shopee - Applepay-Ec
            28 September 2026 at 09:30
            Status: Approved
            Maybank Visa Debit
            Contact Maybank
            """,
        )
        val e = expenseFrom(p, "Shopee")
        assertEquals(PaymentChannel.APPLE_PAY, e.paymentChannel)
        assertEquals("Maybank", e.effectiveFundingAccount)
        assertEquals("Maybank Visa Debit", e.fundingInstrument)
        assertEquals("Maybank • Apple Pay", e.displayFundingAndChannel)
    }

    @Test fun t89_flow_duitNowQrKeepsChannelIntoExpense() {
        val p = parse(
            """
            DuitNow QR
            Payment Successful
            RM 18.00
            Paid to: Nasi Kandar Pelita
            Touch 'n Go eWallet
            """,
        )
        val e = expenseFrom(p, "Nasi Kandar Pelita")
        assertEquals(PaymentChannel.DUITNOW_QR, e.paymentChannel)
        assertTrue(e.displayFundingAndChannel.contains("DuitNow QR"))
    }

    @Test fun t90_flow_bankTransferKeepsChannelIntoExpense() {
        val p = parse(
            """
            DuitNow Transfer
            Transfer Successful
            RM 250.00
            Recipient: Alice Tan
            CIMB Bank
            """,
        )
        val e = expenseFrom(p, "Alice Tan")
        assertEquals(PaymentChannel.BANK_TRANSFER, e.paymentChannel)
        assertTrue(e.displayFundingAndChannel.contains("Bank Transfer"))
    }

    // Phase 7 (Data/Tests/Phase7Tests.swift): incoming screenshot keeps its amount and suggests Money In.
    @Test fun phase7_incomingScreenshotSuggestsMoneyIn() {
        val text = "Maybank2u\nDuitNow Transfer\nYou have received\nRM 50.00\nfrom BIJOY DAS\n29 Sep 2026\nReference: MBB123"
        val p = TransactionParser.parse(OcrResult(text, text.split("\n").map { OcrLine(it, 0.95f) }, 0.95f), ZoneOffset.UTC)
        assertEquals(5000L, p.amountMinor)
        assertEquals(com.spendrop.core.model.MoneyMovementKind.OTHER_IN, p.suggestedMovementKind)
        assertNotNull(p.directionReason)
    }

    @Test fun ocrBoxesNearBottomAndReadingOrder() {
        // Boxes in top-left normalised coordinates: a bare amount low on the page scores as "near bottom".
        val lines = listOf(
            OcrLine("RM 9.90", 0.9f, OcrBox(0.1f, 0.90f, 0.3f, 0.92f)),
            OcrLine("Statement", 0.9f, OcrBox(0.1f, 0.05f, 0.5f, 0.07f)),
            OcrLine("Kedai", 0.9f, OcrBox(0.6f, 0.051f, 0.8f, 0.069f)),
        )
        val ocr = OcrResult.fromRecognizedLines(lines)
        assertEquals(listOf("Statement", "Kedai", "RM 9.90"), ocr.lines.map { it.text })
        assertEquals("Statement\nKedai\nRM 9.90", ocr.fullText)
        val candidate = TransactionParser.extractAndClassifyAmounts(ocr, false).candidates.single()
        assertEquals(MonetarySemanticType.UNKNOWN, candidate.semanticType)
        assertEquals(0.20, candidate.confidenceScore, 1e-9)
        assertFalse(candidate.semanticType.isExcludedFromTransactionAmount)
    }
}
