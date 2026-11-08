// app_workspace/app/src/main/java/com/example/app/data/repository/RoomTodoRepository.kt | source set: src/main | package: com.example.app.data.repository
//
// Room-backed implementation of com.example.app.domain.repository.TodoRepository.
// The interface is pure Kotlin and lives in the domain package (see SKILL.md);
// this file is the only place that knows about TodoEntity, the DAO and the
// dispatcher. Dispatchers.IO is injected by AppContainer, never referenced here.
package com.example.app.data.repository

import com.example.app.data.local.TodoDao
import com.example.app.data.local.entity.TodoEntity
import com.example.app.data.local.entity.toDomain
import com.example.app.domain.model.Todo
import com.example.app.domain.repository.TodoRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

/** Failures the data layer can report; UI maps them to its own messages. */
sealed interface DataError {
    data object Local : DataError
    data object NotFound : DataError
    data class Unknown(val message: String?) : DataError
}

class DataException(
    val error: DataError,
    cause: Throwable? = null,
) : Exception(error.toString(), cause)

class RoomTodoRepository(
    private val dao: TodoDao,
    private val ioDispatcher: CoroutineDispatcher,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) : TodoRepository {

    override fun observeTodos(): Flow<List<Todo>> =
        dao.observeAll()
            .map { entities -> entities.map(TodoEntity::toDomain) }
            .flowOn(ioDispatcher)

    override fun observeTodo(id: Long): Flow<Todo?> =
        dao.observeById(id)
            .map { entity -> entity?.toDomain() }
            .flowOn(ioDispatcher)

    override suspend fun add(title: String): Result<Long> = withContext(ioDispatcher) {
        dataCall { dao.insert(TodoEntity(title = title, createdAtMillis = nowMillis())) }
    }

    override suspend fun setDone(id: Long, isDone: Boolean): Result<Unit> =
        withContext(ioDispatcher) {
            dataCall { dao.setDone(id, isDone) }.mapRowsApplied()
        }

    override suspend fun delete(id: Long): Result<Unit> = withContext(ioDispatcher) {
        dataCall { dao.deleteById(id) }.mapRowsApplied()
    }

    private fun Result<Int>.mapRowsApplied(): Result<Unit> =
        mapCatching { rows ->
            if (rows == 0) throw DataException(DataError.NotFound) else Unit
        }

    private suspend fun <T> dataCall(block: suspend () -> T): Result<T> =
        try {
            Result.success(block())
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (exception: Exception) {
            Result.failure(DataException(DataError.Local, exception))
        }
}
