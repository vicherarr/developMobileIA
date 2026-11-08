// app_workspace/app/src/main/java/com/example/app/data/local/entity/TodoEntity.kt | source set: src/main | package: com.example.app.data.local.entity
//
// Room row for a todo. The domain model lives in domain/model/Todo.kt
// (package com.example.app.domain.model); this file owns the mapping.
package com.example.app.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.example.app.domain.model.Todo

@Entity(
    tableName = "todos",
    indices = [
        Index(value = ["is_done"]),
        Index(value = ["created_at"]),
    ],
)
data class TodoEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0L,
    @ColumnInfo(name = "title")
    val title: String,
    @ColumnInfo(name = "is_done", defaultValue = "0")
    val isDone: Boolean = false,
    @ColumnInfo(name = "created_at")
    val createdAtMillis: Long,
)

fun TodoEntity.toDomain(): Todo = Todo(
    id = id,
    title = title,
    isDone = isDone,
    createdAtMillis = createdAtMillis,
)

fun Todo.toEntity(): TodoEntity = TodoEntity(
    id = id,
    title = title,
    isDone = isDone,
    createdAtMillis = createdAtMillis,
)

/*
 * Domain counterpart, created in the same step. A Kotlin file has exactly one
 * package, so the model stays in the domain package and only the mapper lives here.
 *
 *   app_workspace/app/src/main/java/com/example/app/domain/model/Todo.kt
 *   package com.example.app.domain.model
 *
 *   data class Todo(
 *       val id: Long,
 *       val title: String,
 *       val isDone: Boolean,
 *       val createdAtMillis: Long,
 *   )
 */
