package com.koard.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.espresso.Espresso.pressBack
import org.junit.Rule
import org.junit.Test

/** Checks the actual app startup and keyboard without submitting a login. */
class StandardDemoStartupTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun loginRemainsVisibleAndInteractiveAfterSdkStartup() {
        compose.waitUntil(timeoutMillis = 45_000) {
            compose.onAllNodesWithTag("login.code").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("login.submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("login.code").performScrollTo().assertIsDisplayed().performTextInput("ABC123456789")
        compose.onNodeWithTag("login.code").assertTextContains("ABC123456789")
        compose.onNodeWithTag("login.pin").performScrollTo().assertIsDisplayed().performTextInput("123456")
        pressBack()
        compose.onNodeWithTag("login.submit").performScrollTo().assertIsDisplayed().assertIsEnabled()
    }
}
