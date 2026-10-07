package com.spendrop.core

import java.util.UUID

object Ids {
    /** New record id: lower-case UUID (Postgres `uuid` text form; iOS compares UUIDs case-insensitively). */
    fun new(): String = UUID.randomUUID().toString()
    /** Normalises any UUID text (iOS writes upper case) to lower case. */
    fun normalize(id: String): String = id.trim().lowercase()
}
