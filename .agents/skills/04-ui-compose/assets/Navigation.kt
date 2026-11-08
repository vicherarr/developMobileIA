// app_workspace/app/src/main/java/com/example/app/ui/navigation/AppNavigation.kt | source set: src/main | package: com.example.app.ui.navigation
//
// Navigation 3. Routes are @Serializable NavKeys, arguments are fields on the
// key (no Bundle, no string routes). The outer host owns app-level destinations;
// the todo feature owns a nested host with its own back stack, so feature steps
// never leak into the app stack.
package com.example.app.ui.navigation

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.example.app.di.AppContainer
import com.example.app.ui.detail.TodoDetailScreen
import com.example.app.ui.home.HomeScreen
import com.example.app.ui.home.HomeViewModel
import kotlinx.serialization.Serializable

@Serializable
data object TodoFeatureRoute : NavKey

@Serializable
data object TodoListRoute : NavKey

@Serializable
data class TodoDetailRoute(val todoId: Long) : NavKey

@Composable
fun AppNavigation(
    container: AppContainer,
    modifier: Modifier = Modifier,
) {
    val appStack = rememberNavBackStack(TodoFeatureRoute)

    NavDisplay(
        backStack = appStack,
        modifier = modifier,
        onBack = { if (appStack.size > 1) appStack.removeLastOrNull() },
        entryProvider = { key ->
            when (key) {
                TodoFeatureRoute -> NavEntry(key) {
                    TodoFeatureNavHost(container = container)
                }
                else -> NavEntry(key) {
                    Text(text = "Unknown destination: $key")
                }
            }
        },
    )
}

@Composable
fun TodoFeatureNavHost(
    container: AppContainer,
    modifier: Modifier = Modifier,
) {
    val featureStack = rememberNavBackStack(TodoListRoute)

    NavDisplay(
        backStack = featureStack,
        modifier = modifier,
        onBack = { if (featureStack.size > 1) featureStack.removeLastOrNull() },
        entryProvider = { key ->
            when (key) {
                TodoListRoute -> NavEntry(key) {
                    val viewModel: HomeViewModel = viewModel(
                        factory = HomeViewModel.factory(container),
                    )
                    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
                    HomeScreen(
                        uiState = uiState,
                        onAction = viewModel::onAction,
                        onTodoClick = { todoId ->
                            val target = TodoDetailRoute(todoId)
                            if (featureStack.lastOrNull() != target) {
                                featureStack.add(target)
                            }
                        },
                    )
                }
                is TodoDetailRoute -> NavEntry(key) {
                    TodoDetailScreen(
                        todoId = key.todoId,
                        onBack = { featureStack.removeLastOrNull() },
                    )
                }
                else -> NavEntry(key) {
                    Text(text = "Unknown destination: $key")
                }
            }
        },
    )
}
