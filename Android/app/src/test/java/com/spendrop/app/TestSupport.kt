package com.spendrop.app

import androidx.test.core.app.ApplicationProvider
import com.spendrop.app.cloud.MemorySecureStore

/** A container with an in-memory database and an in-memory session store (no Keystore on the JVM). */
fun testContainer(): AppContainer = AppContainer(ApplicationProvider.getApplicationContext(), inMemory = true, secureStore = MemorySecureStore())
