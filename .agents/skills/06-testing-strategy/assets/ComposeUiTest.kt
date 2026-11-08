// Test source set: app/src/test/java (Robolectric + Compose) — package com.example.app.ui.home
//
// Robolectric runs these on the JVM; no emulator. Copy to src/androidTest only
// when the behavior genuinely depends on real system UI. The screen contract is
// HomeScreen(uiState, onAction, onTodoClick, modifier). The root test tag is
// applied by this test, so no production-only tag is required.
package com.example.app.ui.home

import androidx.activity.ComponentActivity
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertDoesNotExist
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.app.R
import com.example.app.ui.theme.AppTheme
import com.google.common.truth.Truth.assertThat
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class HomeScreenTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val rootTag = "home_screen"

    private val todos = listOf(
        TodoUi(id = 1, title = "Oil change", isDone = false),
        TodoUi(id = 2, title = "Tyre pressure", isDone = true),
    )

    @Test
    fun `success renders the list and reports item clicks`() {
        var clicked: Long? = null
        compose.setContent {
            AppTheme {
                HomeScreen(
                    uiState = HomeUiState.Success(todos),
                    onAction = {},
                    onTodoClick = { clicked = it },
                    modifier = Modifier.testTag(rootTag),
                )
            }
        }

        compose.onNodeWithTag(rootTag).assertIsDisplayed()
        compose.onNodeWithText("Oil change").assertIsDisplayed().performClick()

        assertThat(clicked).isEqualTo(1L)
    }

    @Test
    fun `loading replaces the list with progress`() {
        compose.setContent {
            AppTheme {
                HomeScreen(
                    uiState = HomeUiState.Loading,
                    onAction = {},
                    onTodoClick = {},
                )
            }
        }

        compose.onNodeWithText(compose.activity.getString(R.string.loading)).assertIsDisplayed()
        compose.onNodeWithText("Oil change").assertDoesNotExist()
    }

    @Test
    fun `empty state exposes no rows`() {
        compose.setContent {
            AppTheme {
                HomeScreen(
                    uiState = HomeUiState.Empty,
                    onAction = {},
                    onTodoClick = {},
                )
            }
        }

        compose.onNodeWithText(compose.activity.getString(R.string.empty_hint)).assertIsDisplayed()
        compose.onNodeWithText("Oil change").assertDoesNotExist()
    }

    @Test
    fun `error uses the string resource and sends retry action`() {
        var action: HomeAction? = null
        compose.setContent {
            AppTheme {
                HomeScreen(
                    uiState = HomeUiState.Error(UiMessage.Generic),
                    onAction = { action = it },
                    onTodoClick = {},
                )
            }
        }

        compose.onNodeWithText(compose.activity.getString(R.string.retry))
            .assertIsDisplayed()
            .performClick()

        assertThat(action).isNotNull()
    }

    // Animations: do not sleep. Use virtual frames, e.g.
    // compose.mainClock.autoAdvance = false
    // compose.mainClock.advanceTimeBy(500)
    // compose.waitForIdle()
    //
    // State restoration: StateRestorationTester(compose).emulateSavedInstanceStateRestore()
    // is the device-free way to prove rememberSaveable wiring.
}
