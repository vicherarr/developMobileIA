// app_workspace/app/src/main/java/com/example/app/ui/home/HomeScreen.kt | source set: src/main | package: com.example.app.ui.home
//
// Stateless screen: uiState in, callbacks out. Previews (light + dark) live in
// HomePreviews.kt; screenshot previews live in
// app_workspace/app/src/screenshotTest/kotlin/com/example/app/ui/home/HomeScreenshotTest.kt.
// Keep this file free of preview imports and sample data.
package com.example.app.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.example.app.R

@Composable
fun HomeScreen(
    uiState: HomeUiState,
    onAction: (HomeAction) -> Unit,
    onTodoClick: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    var showAddDialog by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        modifier = modifier,
        topBar = { TopAppBar(title = { Text(stringResource(R.string.home_title)) }) },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                text = { Text(stringResource(R.string.add_todo)) },
                onClick = { showAddDialog = true },
            )
        },
    ) { innerPadding ->
        val contentModifier = Modifier.padding(innerPadding)
        when (uiState) {
            HomeUiState.Loading -> LoadingState(contentModifier)
            HomeUiState.Empty -> EmptyState(
                modifier = contentModifier,
                onAddClick = { showAddDialog = true },
            )
            is HomeUiState.Error -> ErrorState(
                message = uiState.message,
                onRetry = { onAction(HomeAction.ClearError) },
                modifier = contentModifier,
            )
            is HomeUiState.Success -> TodoList(
                todos = uiState.todos,
                onAction = onAction,
                onTodoClick = onTodoClick,
                modifier = contentModifier,
            )
        }
    }

    if (showAddDialog) {
        AddTodoDialog(
            onDismiss = { showAddDialog = false },
            onConfirm = { title ->
                showAddDialog = false
                onAction(HomeAction.Add(title))
            },
        )
    }
}

@Composable
private fun TodoList(
    todos: List<TodoUi>,
    onAction: (HomeAction) -> Unit,
    onTodoClick: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        items(items = todos, key = { todo -> todo.id }) { todo ->
            TodoRow(
                todo = todo,
                onClick = { onTodoClick(todo.id) },
                onToggle = { isDone -> onAction(HomeAction.Toggle(todo.id, isDone)) },
                onDelete = { onAction(HomeAction.Delete(todo.id)) },
            )
        }
    }
}

@Composable
private fun TodoRow(
    todo: TodoUi,
    onClick: () -> Unit,
    onToggle: (Boolean) -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val toggleLabel = stringResource(R.string.todo_toggle, todo.title)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(
            checked = todo.isDone,
            onCheckedChange = onToggle,
            modifier = Modifier.semantics { contentDescription = toggleLabel },
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = todo.title,
                style = MaterialTheme.typography.bodyLarge,
                textDecoration = if (todo.isDone) TextDecoration.LineThrough else null,
            )
        }
        TextButton(onClick = onDelete) {
            Text(stringResource(R.string.delete))
        }
    }
}

@Composable
private fun LoadingState(modifier: Modifier = Modifier) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
private fun EmptyState(
    onAddClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = stringResource(R.string.empty_hint),
            style = MaterialTheme.typography.bodyLarge,
        )
        TextButton(onClick = onAddClick) {
            Text(stringResource(R.string.add_todo))
        }
    }
}

@Composable
private fun ErrorState(
    message: UiMessage,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = message.asText(),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.error,
        )
        TextButton(onClick = onRetry) {
            Text(stringResource(R.string.retry))
        }
    }
}

@Composable
private fun AddTodoDialog(
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var title by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.add_todo)) },
        text = {
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                singleLine = true,
                label = { Text(stringResource(R.string.todo_title_label)) },
            )
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(title) }) {
                Text(stringResource(R.string.save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.cancel))
            }
        },
    )
}

@Composable
private fun UiMessage.asText(): String = when (this) {
    UiMessage.Generic -> stringResource(R.string.error_generic)
    UiMessage.BlankTitle -> stringResource(R.string.error_blank_title)
    UiMessage.NotFound -> stringResource(R.string.error_not_found)
}
