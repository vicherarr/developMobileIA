// app_workspace/app/src/main/java/com/example/app/ui/home/HomeViewModel.kt | source set: src/main | package: com.example.app.ui.home
//
// Owns the screen state machine. UiState is pure Kotlin: no Context, no R, no
// Android types. Strings are resolved in HomeScreen from UiMessage.
package com.example.app.ui.home

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.app.di.AppContainer
import com.example.app.domain.model.Todo
import com.example.app.domain.usecase.AddTodoUseCase
import com.example.app.domain.usecase.DeleteTodoUseCase
import com.example.app.domain.usecase.DomainError
import com.example.app.domain.usecase.DomainException
import com.example.app.domain.usecase.ObserveTodosUseCase
import com.example.app.domain.usecase.SetTodoDoneUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Loading : HomeUiState
    data class Success(val todos: List<TodoUi>) : HomeUiState
    data object Empty : HomeUiState
    data class Error(val message: UiMessage) : HomeUiState
}

data class TodoUi(
    val id: Long,
    val title: String,
    val isDone: Boolean,
)

enum class UiMessage {
    Generic,
    BlankTitle,
    NotFound,
}

sealed interface HomeAction {
    data class Add(val title: String) : HomeAction
    data class Toggle(val id: Long, val isDone: Boolean) : HomeAction
    data class Delete(val id: Long) : HomeAction
    data object ClearError : HomeAction
}

fun Todo.toUi(): TodoUi = TodoUi(id = id, title = title, isDone = isDone)

class HomeViewModel(
    observeTodos: ObserveTodosUseCase,
    private val addTodo: AddTodoUseCase,
    private val setTodoDone: SetTodoDoneUseCase,
    private val deleteTodo: DeleteTodoUseCase,
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val pendingMessage = MutableStateFlow(
        savedStateHandle.get<String>(KEY_MESSAGE)?.toUiMessage(),
    )

    val uiState: StateFlow<HomeUiState> = combine(
        observeTodos(),
        pendingMessage,
    ) { todos, message ->
        render(todos = todos, message = message)
    }
        .catch { emit(HomeUiState.Error(UiMessage.Generic)) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = HomeUiState.Loading,
        )

    fun onAction(action: HomeAction) {
        when (action) {
            is HomeAction.Add -> submit { addTodo(action.title) }
            is HomeAction.Toggle -> submit { setTodoDone(action.id, action.isDone) }
            is HomeAction.Delete -> submit { deleteTodo(action.id) }
            HomeAction.ClearError -> updateMessage(null)
        }
    }

    private fun submit(block: suspend () -> Result<*>) {
        viewModelScope.launch {
            updateMessage(block().exceptionOrNull().toUiMessage())
        }
    }

    private fun updateMessage(message: UiMessage?) {
        pendingMessage.value = message
        savedStateHandle[KEY_MESSAGE] = message?.name
    }

    private fun render(todos: List<Todo>, message: UiMessage?): HomeUiState = when {
        message != null -> HomeUiState.Error(message)
        todos.isEmpty() -> HomeUiState.Empty
        else -> HomeUiState.Success(todos.map(Todo::toUi))
    }

    private fun Throwable?.toUiMessage(): UiMessage? = when (this) {
        null -> null
        is DomainException -> when (error) {
            DomainError.InvalidTitle -> UiMessage.BlankTitle
            DomainError.UnknownTodo -> UiMessage.NotFound
        }
        else -> UiMessage.Generic
    }

    private fun String.toUiMessage(): UiMessage? =
        UiMessage.entries.firstOrNull { it.name == this }

    companion object {
        private const val KEY_MESSAGE = "pending_message"

        fun factory(container: AppContainer): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                HomeViewModel(
                    observeTodos = container.observeTodos,
                    addTodo = container.addTodo,
                    setTodoDone = container.setTodoDone,
                    deleteTodo = container.deleteTodo,
                    savedStateHandle = createSavedStateHandle(),
                )
            }
        }
    }
}
