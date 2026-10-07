package com.spendrop.app.permissions

import org.junit.Assert.assertEquals
import org.junit.Test

class PermissionRulesTest {
    private fun facts(granted: Boolean = false, requested: Boolean = false, permanent: Boolean = false, sdk: Int = 30, since: Int = 1, hw: Boolean = true) =
        PermissionFacts(sdk, since, hw, granted, requested, permanent)

    @Test fun initiallyNotRequested() = assertEquals(PermissionStatus.NOT_REQUESTED, PermissionRules.status(facts()))
    @Test fun granted() = assertEquals(PermissionStatus.GRANTED, PermissionRules.status(facts(granted = true, requested = true)))
    @Test fun denied() = assertEquals(PermissionStatus.DENIED, PermissionRules.status(facts(requested = true)))
    @Test fun permanentlyDenied() = assertEquals(PermissionStatus.PERMANENTLY_DENIED, PermissionRules.status(facts(requested = true, permanent = true)))
    @Test fun grantedInSettingsBeatsOldPermanentRecord() = assertEquals(PermissionStatus.GRANTED, PermissionRules.status(facts(granted = true, requested = true, permanent = true)))
    @Test fun unavailableOnOlderAndroid() = assertEquals(PermissionStatus.NOT_AVAILABLE, PermissionRules.status(facts(sdk = 30, since = 33)))
    @Test fun unavailableWithoutHardware() = assertEquals(PermissionStatus.NOT_AVAILABLE, PermissionRules.status(facts(hw = false)))

    @Test fun outcomes() {
        assertEquals(RequestOutcome.GRANTED, PermissionRules.outcome(granted = true, canAskAgain = false))
        assertEquals(RequestOutcome.DENIED, PermissionRules.outcome(granted = false, canAskAgain = true))
        assertEquals(RequestOutcome.PERMANENTLY_DENIED, PermissionRules.outcome(granted = false, canAskAgain = false))
    }

    @Test fun onlyCameraIsARuntimePermission() {
        assertEquals(listOf(SpenDropAccess.CAMERA), SpenDropAccess.items.filter { it.runtime }.map { it.permission })
        SpenDropAccess.items.filter { it.permission == null }.forEach { assertEquals(true, it.noPermissionReason != null) }
    }
}
