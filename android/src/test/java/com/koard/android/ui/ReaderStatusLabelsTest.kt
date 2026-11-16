package com.koard.android.ui

import com.koardlabs.merchant.sdk.domain.KoardReaderStatus
import org.junit.Assert.*
import org.junit.Test

class ReaderStatusLabelsTest {
    @Test fun everyPublishedReaderStatusHasAnInstruction() {
        for (status in KoardReaderStatus.entries) assertTrue(readerStatusTitle(status, 0).isNotBlank())
        assertEquals("Preparing", readerStatusTitle(null, 0))
        assertEquals("Please tap again", readerStatusTitle(KoardReaderStatus.readyForTap, 1))
        assertEquals("Check your phone", readerStatusTitle(KoardReaderStatus.seePhone, 0))
        assertEquals("Present one card only", readerStatusTitle(KoardReaderStatus.presentOneCardOnly, 0))
    }

    @Test fun cardReadAndVerificationDoNotClaimPaymentApproval() {
        assertEquals("Read complete", readerStatusTitle(KoardReaderStatus.readCompleted, 0))
        assertEquals("Verification complete", readerStatusTitle(KoardReaderStatus.strongCvm, 0))
        assertEquals("Completing", readerStatusTitle(KoardReaderStatus.complete, 0))
    }
}
