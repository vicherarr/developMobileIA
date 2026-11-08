// app_workspace/app/src/main/java/com/example/app/data/local/TodoDao.kt | source set: src/main | package: com.example.app.data.local
//
// Reads are cold Flows so Room invalidates them on every write. Writes are
// suspend and return the affected row count where the caller needs it.
package com.example.app.data.local

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert
import com.example.app.data.local.entity.TodoEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TodoDao {

    @Query("SELECT * FROM todos ORDER BY is_done ASC, created_at DESC")
    fun observeAll(): Flow<List<TodoEntity>>

    @Query("SELECT * FROM todos WHERE id = :id")
    fun observeById(id: Long): Flow<TodoEntity?>

    @Query("SELECT * FROM todos WHERE is_done = :isDone ORDER BY created_at DESC")
    suspend fun getByDone(isDone: Boolean): List<TodoEntity>

    @Insert(onConflict = OnConflictStrategy.FAIL)
    suspend fun insert(entity: TodoEntity): Long

    @Upsert
    suspend fun upsertAll(entities: List<TodoEntity>)

    @Update
    suspend fun update(entity: TodoEntity): Int

    @Query("UPDATE todos SET is_done = :isDone WHERE id = :id")
    suspend fun setDone(id: Long, isDone: Boolean): Int

    @Delete
    suspend fun delete(entity: TodoEntity): Int

    @Query("DELETE FROM todos WHERE id = :id")
    suspend fun deleteById(id: Long): Int

    @Query("DELETE FROM todos")
    suspend fun deleteAll(): Int
}
