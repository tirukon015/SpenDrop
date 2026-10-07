package com.spendrop.core.parser

import org.junit.Assert.assertTrue
import org.junit.Test

class ParserSelfTestTest {
    @Test fun allInAppSelfTestsPass() {
        val results = ParserSelfTest.run()
        assertTrue(results.size >= 9)
        results.forEach { assertTrue("${it.testName}: ${it.actual}", it.passed) }
    }
}
