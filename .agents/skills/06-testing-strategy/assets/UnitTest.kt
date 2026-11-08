// Test source set: app/src/test/java (JVM) — package com.example.app.domain.usecase
//
// JUnit4 is the pipeline default. JUnit5 (org.junit.jupiter:junit-jupiter:6.1.3)
// is allowed only in a pure-JVM source set with no JUnit4 tests; never enable
// useJUnitPlatform() in a source set that still contains JUnit4 tests.
// Adapt the package and sample types to the app; keep the assertions on behavior.
package com.example.app.domain.usecase

import app.cash.turbine.test
import com.example.app.domain.model.Todo
import com.example.app.domain.repository.TodoRepository
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import org.junit.Test

class AddTodoUseCaseTest {

    private val repository = FakeTodoRepository()
    private val addTodo = AddTodoUseCase(repository)

    @Test
    fun `blank title is rejected before touching the repository`() = runTest {
        val result = addTodo("   ")

        assertThat(result.isFailure).isTrue()
        assertThat((result.exceptionOrNull() as DomainException).error)
            .isEqualTo(DomainError.InvalidTitle)
        assertThat(repository.addedTitles).isEmpty()
    }

    @Test
    fun `title is trimmed and persisted once`() = runTest {
        val result = addTodo("  Oil change  ")

        assertThat(result.getOrNull()).isEqualTo(1L)
        assertThat(repository.addedTitles).containsExactly("Oil change")
    }

    @Test
    fun `repository failure is propagated unchanged`() = runTest {
        repository.failWith = IllegalStateException("disk full")

        val result = addTodo("Oil change")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
    }
}

class ObserveTodosUseCaseTest {

    @Test
    fun `emits the current list and reacts to repository writes`() = runTest {
        val repository = FakeTodoRepository()
        val observeTodos = ObserveTodosUseCase(repository)
        val oilChange = Todo(id = 1, title = "Oil change", isDone = false, createdAtMillis = 0)
        val tyrePressure = oilChange.copy(id = 2, title = "Tyre pressure", isDone = true)

        observeTodos().test {
            assertThat(awaitItem()).isEmpty()

            repository.todos.value = listOf(oilChange)
            assertThat(awaitItem()).containsExactly(oilChange)

            repository.todos.value = listOf(oilChange, tyrePressure)
            assertThat(awaitItem()).containsExactly(oilChange, tyrePressure).inOrder()

            cancelAndIgnoreRemainingEvents()
        }
    }
}

/**
 * Hand-written fake: the pipeline prefers fakes over mocks because they make
 * the emitted states visible and survive refactors. MockK 1.14.12 is reserved
 * for final/third-party seams:
 *
 * val repository = mockk<TodoRepository> {
 *     every { observeTodos() } returns flowOf(emptyList())
 * }
 */
private class FakeTodoRepository : TodoRepository {

    val todos = MutableStateFlow<List<Todo>>(emptyList())
    val addedTitles = mutableListOf<String>()
    var failWith: Throwable? = null
    private var nextId = 1L

    override fun observeTodos(): Flow<List<Todo>> = todos.asStateFlow()

    override fun observeTodo(id: Long): Flow<Todo?> =
        todos.map { list -> list.find { it.id == id } }

    override suspend fun add(title: String): Result<Long> {
        failWith?.let { return Result.failure(it) }
        addedTitles += title
        return Result.success(nextId++)
    }

    override suspend fun setDone(id: Long, isDone: Boolean): Result<Unit> =
        failWith?.let { Result.failure(it) } ?: Result.success(Unit)

    override suspend fun delete(id: Long): Result<Unit> =
        failWith?.let { Result.failure(it) } ?: Result.success(Unit)
}
