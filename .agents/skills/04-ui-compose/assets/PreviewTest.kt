// app_workspace/app/src/screenshotTest/kotlin/com/example/app/ui/home/HomeScreenshotTest.kt | source set: screenshotTest | package: com.example.app.ui.home
//
// Host-side screenshot previews (AGP test-suite convention): @PreviewTest marks
// the function as a render target, the repeated @Preview annotations produce one
// image per device/uiMode/fontScale combination. Requires the screenshot test
// suite to be configured (ui-tooling + screenshot-validation-api in the
// screenshotTest source set); without it this source set is not compiled.
// See 06-testing-strategy for the engine version and the suite DSL.
package com.example.app.ui.home

import android.content.res.Configuration
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.android.tools.screenshot.PreviewTest
import com.example.app.ui.theme.AppTheme

@PreviewTest
@Preview(name = "home-light", device = PHONE, showBackground = true)
@Preview(
    name = "home-dark",
    device = PHONE,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
    showBackground = true,
)
@Preview(name = "home-font-1.3", device = PHONE, fontScale = 1.3f, showBackground = true)
@Composable
fun HomeScreenScreenshot() {
    AppTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            HomeScreen(
                uiState = HomeUiState.Success(sampleTodos),
                onAction = {},
                onTodoClick = {},
            )
        }
    }
}

@PreviewTest
@Preview(name = "home-empty-light", device = PHONE, showBackground = true)
@Preview(
    name = "home-empty-dark",
    device = PHONE,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
    showBackground = true,
)
@Composable
fun HomeScreenEmptyScreenshot() {
    AppTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            HomeScreen(
                uiState = HomeUiState.Empty,
                onAction = {},
                onTodoClick = {},
            )
        }
    }
}

private const val PHONE = "spec:width=411dp,height=891dp,dpi=420"

private val sampleTodos = listOf(
    TodoUi(id = 1L, title = "Renew the insurance", isDone = false),
    TodoUi(id = 2L, title = "Book the mechanic", isDone = true),
    TodoUi(id = 3L, title = "Pay the road tax", isDone = false),
)
