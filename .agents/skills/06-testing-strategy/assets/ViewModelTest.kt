// Test source set: app/src/test/java (JVM + coroutines-test) — package com.example.app.ui.home
//
// The ViewModel is a state machine. Drive it with virtual time and a fake
// repository; never let viewModelScope use the real Main dispatcher. The
// uiState flow uses WhileSubscribed, so collect it (Turbine does) before
// asserting; uiState.value alone would stay at Loading. Merge into the G4
// HomeViewModelTest.kt skeleton; do not add a second test class.
package com.example.app.ui.home

import app.cash.turbine.test
import com.example.app.domain.model.Todo
import com.example.app.domain.repository.TodoRepository
import com.example.app.domain.usecase.ObserveTodosUseCase
import com.example.app.domain.usecase.SetTodoDoneUseCase
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestWatcher
import org.junit.runner.Description

// If HomeViewModelTest already defines MainDispatcherRule, move this class to
// src/test/java/.../testing/MainDispatcherRule.kt and import it; never duplicate it.
@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    val dispatcher: TestDispatcher = StandardTestDispatcher(),
) : TestWatcher() {

    override fun starting(description: Description) {
        Dispatchers.setMain(dispatcher)
    }

    override fun finished(description: Description) {
        Dispatchers.resetMain()
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelTest {

    @get:Rule
    val mainDispatcher = MainDispatcherRule()

    private val repository = FakeTodoRepository()
    private val oilChange = Todo(id = 1, title = "Oil change", isDone = false, createdAtMillis = 0)

    private fun homeViewModel() = HomeViewModel(
        observeTodos = ObserveTodosUseCase(repository),
        setTodoDone = SetTodoDoneUseCase(repository),
    )

    @Test
    fun `uiState goes loading then empty then success`() = runTest(mainDispatcher.dispatcher) {
        val viewModel = homeViewModel()

        viewModel.uiState.test {
            assertThat(awaitItem()).isEqualTo(HomeUiState.Loading)
            assertThat(awaitItem()).isEqualTo(HomeUiState.Empty)

            repository.todos.value = listOf(oilChange)

            val success = awaitItem()
            assertThat(success).isInstanceOf(HomeUiState.Success::class.java)
            assertThat((success as HomeUiState.Success).todos.map { it.title })
                .containsExactly("Oil change")

            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `flow failure becomes error instead of crashing`() = runTest(mainDispatcher.dispatcher) {
        repository.failWith = IllegalStateException("offline")
        val viewModel = homeViewModel()

        viewModel.uiState.test {
            assertThat(awaitItem()).isEqualTo(HomeUiState.Loading)
            assertThat(awaitItem()).isInstanceOf(HomeUiState.Error::class.java)
            cancelAndIgnoreRemainingEvents()
        }
    }
}

/**
 * Contract assumed by this test: HomeUiState is Loading/Success/Empty/Error,
 * uiState is a StateFlow, and the ViewModel takes the use cases. Adapt
 * constructor names to the generated factory; keep the assertions on observable
 * state, not on internal calls.
 */
private class FakeTodoRepository : TodoRepository {

    val todos = MutableStateFlow<List<Todo>>(emptyList())
    var failWith: Throwable? = null

    override fun observeTodos(): Flow<List<Todo>> =
        if (failWith == null) todos.asStateFlow() else flow { throw failWith!! }

    override fun observeTodo(id: Long): Flow<Todo?> =
        if (failWith == null) todos.map { list -> list.find { it.id == id } }
        else flow { throw failWith!! }

    override suspend fun add(title: String): Result<Long> =
        failWith?.let { Result.failure(it) } ?: Result.success(1L)

    override suspend fun setDone(id: Long, isDone: Boolean): Result<Unit> =
        failWith?.let { Result.failure(it) } ?: Result.success(Unit)

    override suspend fun delete(id: Long): Result<Unit> =
        failWith?.let { Result.failure(it) } ?: Result.success(Unit)
}
