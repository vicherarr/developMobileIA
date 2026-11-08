// app_workspace/app/src/main/java/com/example/app/domain/usecase/TodoUseCases.kt | source set: src/main | package: com.example.app.domain.usecase
//
// One responsibility per use case, one public operator. No Android types, no
// UI text, no ViewModel references: this package must stay unit-testable on the JVM.
package com.example.app.domain.usecase

import com.example.app.domain.model.Todo
import com.example.app.domain.repository.TodoRepository
import kotlinx.coroutines.flow.Flow

class ObserveTodosUseCase(
    private val repository: TodoRepository,
) {
    operator fun invoke(): Flow<List<Todo>> = repository.observeTodos()
}

class ObserveTodoUseCase(
    private val repository: TodoRepository,
) {
    operator fun invoke(id: Long): Flow<Todo?> = repository.observeTodo(id)
}

class AddTodoUseCase(
    private val repository: TodoRepository,
) {
    suspend operator fun invoke(title: String): Result<Long> {
        val cleanTitle = title.trim()
        if (cleanTitle.isEmpty() || cleanTitle.length > MAX_TITLE_LENGTH) {
            return Result.failure(DomainException(DomainError.InvalidTitle))
        }
        return repository.add(cleanTitle)
    }

    private companion object {
        const val MAX_TITLE_LENGTH = 200
    }
}

class SetTodoDoneUseCase(
    private val repository: TodoRepository,
) {
    suspend operator fun invoke(id: Long, isDone: Boolean): Result<Unit> {
        if (id <= 0L) return Result.failure(DomainException(DomainError.UnknownTodo))
        return repository.setDone(id, isDone)
    }
}

class DeleteTodoUseCase(
    private val repository: TodoRepository,
) {
    suspend operator fun invoke(id: Long): Result<Unit> {
        if (id <= 0L) return Result.failure(DomainException(DomainError.UnknownTodo))
        return repository.delete(id)
    }
}

sealed interface DomainError {
    data object InvalidTitle : DomainError
    data object UnknownTodo : DomainError
}

class DomainException(val error: DomainError) : IllegalArgumentException(error.toString())
