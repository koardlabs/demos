package com.koard.android

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.koard.android.ui.TapToPayTutorial
import com.koard.android.ui.theme.KoardAndroidSDKTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class StandardDemoUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun tutorialCanSwipeNavigateBackAndCloseInDarkMode() {
        val visible = mutableStateOf(true)
        var closes = 0
        compose.setContent {
            KoardAndroidSDKTheme(darkTheme = true) {
                if (visible.value) TapToPayTutorial { closes++; visible.value = false }
            }
        }
        compose.onNodeWithText("Prepare your phone").assertIsDisplayed()
        compose.onNodeWithTag("tutorial.back").assertIsNotEnabled()
        compose.onNodeWithTag("tutorial.pager").performTouchInput { swipeLeft() }
        compose.waitForIdle()
        compose.onNodeWithText("Accept a contactless card").assertIsDisplayed()
        compose.onNodeWithTag("tutorial.back").assertIsEnabled().performClick()
        compose.onNodeWithText("Prepare your phone").assertIsDisplayed()
        repeat(4) { compose.onNodeWithTag("tutorial.next").assertIsDisplayed().performClick(); compose.waitForIdle() }
        compose.onNodeWithText("Wait for the payment result").assertIsDisplayed()
        compose.onNodeWithTag("tutorial.next").assertTextEquals("Done").performClick()
        assertEquals(1, closes)
        compose.onNodeWithTag("tutorial.pager").assertDoesNotExist()
    }

    @Test fun tutorialCanCloseBeforeTheLastPage() {
        var closes = 0
        compose.setContent { KoardAndroidSDKTheme { TapToPayTutorial { closes++ } } }
        compose.onNodeWithTag("tutorial.close").assertIsDisplayed().performClick()
        assertEquals(1, closes)
    }
}
