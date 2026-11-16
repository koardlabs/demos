package com.koard.android.ui

import com.koardlabs.merchant.sdk.domain.KoardReaderStatus

/** Reader prompts describe cardholder actions, never an approval result. */
internal fun readerStatusTitle(status: KoardReaderStatus?, tapAttempts: Int): String = when (status) {
    KoardReaderStatus.preparing, null -> "Preparing"
    KoardReaderStatus.readyForTap -> if (tapAttempts > 0) "Please tap again" else "Ready for tap"
    KoardReaderStatus.cardDetected -> "Card detected"
    KoardReaderStatus.pinEntryRequested -> "Enter PIN"
    KoardReaderStatus.pinEntryCompleted -> "PIN captured"
    KoardReaderStatus.readCompleted -> "Read complete"
    KoardReaderStatus.readNotCompleted -> "Read failed"
    KoardReaderStatus.readCancelled -> "Cancelled"
    KoardReaderStatus.readRetry -> "Retry tap"
    KoardReaderStatus.processing, KoardReaderStatus.unknown -> "Processing"
    KoardReaderStatus.complete -> "Completing"
    KoardReaderStatus.developerModeEnabled -> "Blocked"
    KoardReaderStatus.seePhone -> "Check your phone"
    KoardReaderStatus.removeCard -> "Remove card"
    KoardReaderStatus.tryAnotherCard -> "Try another card"
    KoardReaderStatus.presentOneCardOnly -> "Present one card only"
    KoardReaderStatus.signatureRequested -> "Signature requested"
    KoardReaderStatus.cancelOrEnter -> "Cancel or enter"
    KoardReaderStatus.practiceMode -> "Practice mode"
    KoardReaderStatus.authorizing -> "Authorizing"
    KoardReaderStatus.pinIncorrect -> "Incorrect PIN"
    KoardReaderStatus.strongCvm -> "Verification complete"
    KoardReaderStatus.pinBypassed -> "PIN bypassed"
    KoardReaderStatus.pinNotProvided -> "PIN not provided"
}
