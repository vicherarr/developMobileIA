// Test source set: app/src/test/java (Roborazzi + Robolectric, JVM) — package com.example.app.ui.home
//
// Baselines: app/src/test/snapshots/<name>.png. Record with
// `./gradlew :app:recordRoborazziDebug`, verify with
// `./gradlew :app:verifyRoborazziDebug` (the G5 command). The outputDir and
// filePathStrategy live in app/build.gradle.kts and gradle.properties.
package com.example.app.ui.home

import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.app.ui.theme.AppTheme
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class HomeRoborazziTest {

    @get:Rule
    val compose = createComposeRule()

    private val todos = listOf(
        TodoUi(id = 1, title = "Oil change", isDone = false),
        TodoUi(id = 2, title = "Tyre pressure", isDone = true),
    )

    @Test
    fun success() {
        compose.setContent {
            AppTheme {
                HomeScreen(
                    uiState = HomeUiState.Success(todos),
                    onAction = {},
                    onTodoClick = {},
                )
            }
        }
        compose.onRoot().captureRoboImage("home_success.png")
    }

    @Test
    fun empty() {
        compose.setContent {
            AppTheme {
                HomeScreen(
                    uiState = HomeUiState.Empty,
                    onAction = {},
                    onTodoClick = {},
                )
            }
        }
        compose.onRoot().captureRoboImage("home_empty.png")
    }

    @Test
    fun error() {
        compose.setContent {
            AppTheme {
                HomeScreen(
                    uiState = HomeUiState.Error(UiMessage.Generic),
                    onAction = {},
                    onTodoClick = {},
                )
            }
        }
        compose.onRoot().captureRoboImage("home_error.png")
    }

    @Test
    fun success_fontScale150() {
        compose.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(1.5f)) {
                AppTheme {
                    HomeScreen(
                        uiState = HomeUiState.Success(todos),
                        onAction = {},
                        onTodoClick = {},
                    )
                }
            }
        }
        compose.onRoot().captureRoboImage("home_success_fontScale150.png")
    }
}

// ---------------------------------------------------------------------------
// AGP test suites variant — ONLY for AGP >= 9.5.0-alpha03 (the scaffold is
// AGP 9.0.1, so this block is documentation, not an active test).
//
// 1. gradle.properties:
//    android.experimental.enableScreenshotTest=true
//    android.experimental.testSuiteSupport=true
//
// 2. app/build.gradle.kts:
//    android {
//        testOptions {
//            screenshotTests.create("screenshotTest") {
//                engineVersion = "0.0.1-alpha16"
//                targetVariants.add("debug")
//                dependencies {
//                    implementation(libs.androidx.compose.ui.tooling)
//                    implementation("com.android.tools.screenshot:screenshot-validation-api:0.0.1-alpha16")
//                }
//            }
//        }
//    }
//
// 3. Move this file to app/src/screenshotTest/kotlin/com/example/app/ui/home/:
//
//    @PreviewTest
//    @Preview(showBackground = true, widthDp = 411, heightDp = 891)
//    @Composable
//    fun HomeSuccessPreview() {
//        AppTheme {
//            HomeScreen(HomeUiState.Success(sampleTodos), onAction = {}, onTodoClick = {})
//        }
//    }
//
// 4. Tasks: ./gradlew updateScreenshotTestDefaultDebugTestSuite
//           ./gradlew testScreenshotTestDefaultDebugTestSuite
//    Reference: app/src/screenshotTestDefaultDebug/reference/
//    Report:    app/build/reports/tests/testScreenshotTestDefaultDebugTestSuite/index.html
//
// With the current AGP 9.0.1, use Roborazzi above. `android preview render`
// is the no-baseline fallback: android preview render :app --fqn=<PreviewFqn>.
// ---------------------------------------------------------------------------
