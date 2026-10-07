package com.spendrop.app.ai

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/*
 * The "Ask SpenDrop" answer, exactly as the shared SpenDrop server returns it (WebApp/src/lib/ai/types.ts).
 * Money is integer minor units and is only formatted here, never re-added: totals come from the server.
 * Decoding is lenient: unknown fields are ignored and an unknown block type is dropped, so a newer server never
 * breaks an older app.
 */

@Serializable
data class AskChatResponse(val conversationId: String, val answer: AskAnswer)

@Serializable
data class AskAnswer(
    val status: String = "answered",
    val text: String = "",
    @Serializable(with = AnswerBlockListSerializer::class) val blocks: List<AnswerBlock> = emptyList(),
    val evidence: List<AskEvidence> = emptyList(),
    val followUps: List<String> = emptyList(),
    val understoodAs: String? = null,
    val preface: String? = null,
    val insight: String? = null,
    val suggestion: String? = null,
    val focus: JsonObject? = null,
    val meta: AskMeta? = null,
)

@Serializable
data class AskEvidence(
    val tool: String = "",
    val transactionCount: Int = 0,
    val period: String = "",
    val filters: String = "",
    val generatedAt: String = "",
)

@Serializable
data class AskMeta(
    val requestId: String = "",
    val intent: String = "",
    val route: String = "",
    val provider: String = "",
    val totalMs: Long = 0,
)

@Serializable
sealed class AnswerBlock {
    @Serializable @SerialName("metric")
    data class Metric(val label: String, val valueMinor: Long, val currency: String, val caption: String? = null) : AnswerBlock()

    @Serializable @SerialName("comparison")
    data class Comparison(val currency: String, val a: Side, val b: Side, val diffMinor: Long, val pct: Double? = null) : AnswerBlock() {
        @Serializable data class Side(val label: String, val valueMinor: Long, val count: Int = 0)
    }

    @Serializable @SerialName("breakdown")
    data class Breakdown(val title: String, val currency: String, val kind: String = "", val items: List<Item> = emptyList()) : AnswerBlock() {
        @Serializable data class Item(val key: String = "", val label: String, val valueMinor: Long, val count: Int = 0, val diffMinor: Long? = null)
    }

    @Serializable @SerialName("transactions")
    data class Transactions(val title: String, val items: List<TxnCard> = emptyList(), val more: Int? = null) : AnswerBlock()

    @Serializable @SerialName("findings")
    data class Findings(val title: String, val items: List<Finding> = emptyList()) : AnswerBlock() {
        @Serializable data class Finding(val title: String, val detail: String = "")
    }
}

@Serializable
data class TxnCard(
    val id: String,
    val merchant: String = "",
    val amountMinor: Long,
    val spendMinor: Long = amountMinor,
    val currency: String = "RM",
    val date: String = "",
    val localDate: String = "",
    val localTime: String = "",
    val category: String = "",
    val recordedCategory: String? = null,
    val fundingAccount: String = "",
    val paymentChannel: String = "",
    val hasReceipt: Boolean = false,
    val isShared: Boolean = false,
    val source: String = "",
)

/** Decodes each block on its own; a block of an unknown type (or a malformed one) is skipped instead of failing the answer. */
object AnswerBlockListSerializer : KSerializer<List<AnswerBlock>> {
    private val elements = ListSerializer(JsonElement.serializer())
    override val descriptor = elements.descriptor

    override fun deserialize(decoder: Decoder): List<AnswerBlock> {
        val json = (decoder as? JsonDecoder)?.json ?: AskJson
        return elements.deserialize(decoder).mapNotNull { el ->
            runCatching { json.decodeFromJsonElement(AnswerBlock.serializer(), el) }.getOrNull()
        }
    }

    override fun serialize(encoder: Encoder, value: List<AnswerBlock>) =
        encoder.encodeSerializableValue(ListSerializer(AnswerBlock.serializer()), value)
}

/** Shared JSON settings for the AI API. */
val AskJson = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true }
