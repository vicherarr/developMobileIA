---
name: 03-domain-and-data
description: Builds the domain and data layers for this Android pipeline - Room entities, DAOs and schema export via KSP2, repository interfaces with Room-backed implementations and an injected CoroutineDispatcher, single-responsibility use cases returning Result, DataStore for small flags, manual DI via AppContainer, and JVM unit tests. Use when adding persistence, offline caching, a data model, a repository, a use case, KSP or Room wiring, or when G3 must pass. Triggers - domain, data layer, Room, DataStore, KSP, entity, DAO, query, repository, use case, mapper, migration, offline, cache, persistence, Flow, Result, unit test, G3.
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Domain and data (G3)

G3 turns `spec.json` `data[]` entries into a compiling, tested data path. No
composables and no ViewModels belong in this gate: deliver an API that G4 can
call without reading the implementation.

## Contract

| Field | Value |
|---|---|
| Reads | `00_memory/TECH_STACK.md`, `app_workspace/.pipeline/spec.json`, `app_workspace/.pipeline/plan.md`, `app_workspace/.pipeline/reports/scaffold-*.json`, `app_workspace/gradle/libs.versions.toml` (grep only), `app_workspace/app/build.gradle.kts` |
| Writes | the file map below; `app_workspace/.pipeline/reports/domain-<UTC>.json`; `00_memory/TECH_STACK.md` (new versions, same change); append-only `00_memory/DECISION_LOG.md` |
| Gate | `G3` - `:app:testDebugUnitTest` green, evidence file `"status":"pass"` |
| Handoff | `04-ui-compose` (G4) |

Do not edit `STATE.json` (the orchestrator owns it) or add composables here: UI
belongs to G4.

## Preconditions

| Check | Command | If it fails |
|---|---|---|
| G2 project exists | `test -x app_workspace/gradlew` | stop, hand back to `02-android-scaffold` |
| Spec is frozen | `test -f app_workspace/.pipeline/spec.json` | stop, hand back to `01-spec-and-scope` |
| No blocking question | `grep -c 'blocking: yes' 02_pending_review/human_decisions.md` | stop, `09-human-review` |
| AGP 9 Kotlin | `grep -rln 'org.jetbrains.kotlin.android' app_workspace/app/build.gradle.kts` | remove that plugin; AGP 9 has built-in Kotlin |
| No kapt | `grep -rln 'kotlin-kapt' app_workspace/ \|\| echo "no kapt"` | replace with KSP2; kapt cannot run on AGP 9 |

Read every `must` feature's `data[]` from `spec.json`. Entity fields must be
concrete types there. Missing fields
are a product decision: raise `HD-###` (class C) with two model options and a
default. Do not invent domain fields to fill the gap.

## Step 1 - Choose the storage per entity

| Data shape | Store | Reason |
|---|---|---|
| Ordered/filtered collection, queried, survives restart | Room | SQL, Flow invalidation, indices |
| A few scalars (sort order, onboarding flag, last sync) | DataStore Preferences | no schema, no migrations |
| Secret/token | Keystore-backed store | not Room, not plain DataStore |

Default: Room for entities, DataStore only for flags. Never store a list in
DataStore; never use Room for one boolean.

Room 2.8.5, DataStore 1.3.0, kotlinx-coroutines 1.10.2 are the pinned baseline.
AGP 9.0.1 and Kotlin 2.3.20 come from the scaffold; do not bump them here.

Flags: add `data/preferences/SettingsRepository.kt` using
`preferencesDataStore(name = "settings")`, `Flow<T>` reads, `edit { }` writes.

## Step 2 - Wire KSP2 and dependencies (minimal diff)

Add catalog entries. KSP2 uses its own standalone version scheme (no Kotlin
prefix); resolve the current one instead of guessing:

```bash
curl -s https://repo1.maven.org/maven2/com/google/devtools/ksp/com.google.devtools.ksp.gradle.plugin/maven-metadata.xml \
  | grep -o '<release>[^<]*'
```

`gradle/libs.versions.toml` additions:

```toml
[versions]
room = "2.8.5"
ksp  = "2.3.13"   # standalone KSP2 version; confirm with the query above

[libraries]
androidx-room-runtime  = { module = "androidx.room:room-runtime",  version.ref = "room" }
androidx-room-ktx      = { module = "androidx.room:room-ktx",      version.ref = "room" }
androidx-room-compiler = { module = "androidx.room:room-compiler", version.ref = "room" }

[plugins]
ksp = { id = "com.google.devtools.ksp", version.ref = "ksp" }
```

AGP 9 aligns KSP to its bundled Kotlin; add an explicit root `buildscript`
classpath only when you deliberately need a different version.

In `app/build.gradle.kts`: add `alias(libs.plugins.ksp)` to the existing
`plugins {}`, add `ksp { arg("room.schemaLocation", "$projectDir/schemas") }`,
and add `implementation(libs.androidx.room.runtime)`,
`implementation(libs.androidx.room.ktx)`, `ksp(libs.androidx.room.compiler)`.
Add `testImplementation(kotlinx-coroutines-test)` and the JUnit alias from the
catalog for tests. Never add `org.jetbrains.kotlin.android` or kapt. Keep the
diff to these lines - do not rewrite the whole build file. Add the same versions
to `00_memory/TECH_STACK.md` in this change (`10-project-memory` rule: catalog
and memory never drift).

## Step 3 - Write entity, domain model, mapper

Copy `assets/Entity.kt` and adapt package names. Layout, assuming the default
single `:app` module and `com.example.app` as the `applicationId`:

```
app_workspace/app/src/main/java/com/example/app/data/local/entity/TodoEntity.kt
app_workspace/app/src/main/java/com/example/app/domain/model/Todo.kt
```

The domain model is the only type the rest of the app sees:

```kotlin
package com.example.app.domain.model

data class Todo(
    val id: Long,
    val title: String,
    val isDone: Boolean,
    val createdAtMillis: Long,
)
```

Rules for the entity:

- `@PrimaryKey(autoGenerate = true) val id: Long = 0`.
- Every snake_case column gets `@ColumnInfo(name = "...")`.
- Index every column used in a `WHERE` or `ORDER BY` clause.
- `@Entity(tableName = "...")` is explicit; never rely on the class name.
- Mappers are extension functions next to the entity, never in the domain
  model, never inside the repository.

## Step 4 - Write the DAO and the database

Copy `assets/Dao.kt`. The database class that exposes it:

```kotlin
@Database(entities = [TodoEntity::class], version = 1, exportSchema = true)
abstract class AppDatabase : RoomDatabase() {
    abstract fun todoDao(): TodoDao
}
```

Non-negotiables:

- Reads return `Flow<List<Entity>>` (or `Flow<Entity?>`) so the UI recomposes on
  writes; one-shot reads use `suspend`.
- Writes are `suspend`; inserts use `@Insert(onConflict = OnConflictStrategy.FAIL)`
  unless the spec asks for upsert, in which case `@Upsert` belongs in the DAO.
- Every `@Query` parameter is bound with `:name`; never string-concatenate.
- No `@Transaction` around single statements; use it for multi-statement writes.

## Step 5 - Write repository interface and implementation

Create `domain/repository/TodoRepository.kt` with exactly this shape; it imports
nothing from Android or Room:

```kotlin
package com.example.app.domain.repository

import com.example.app.domain.model.Todo
import kotlinx.coroutines.flow.Flow

interface TodoRepository {
    fun observeTodos(): Flow<List<Todo>>
    fun observeTodo(id: Long): Flow<Todo?>
    suspend fun add(title: String): Result<Long>
    suspend fun setDone(id: Long, isDone: Boolean): Result<Unit>
    suspend fun delete(id: Long): Result<Unit>
}
```

Then copy `assets/Repository.kt` to
`data/repository/RoomTodoRepository.kt`: it declares `DataError`,
`DataException` and the implementation, which takes `dao: TodoDao` plus
`ioDispatcher: CoroutineDispatcher`. Never write `Dispatchers.IO` inside the
implementation: the container injects it, tests inject `StandardTestDispatcher`.

Error contract:

| Failure | Return |
|---|---|
| Write/exception | `Result.failure(DataException(DataError.Local))` |
| Update matched 0 rows | `Result.failure(DataException(DataError.NotFound))` |
| Unexpected | `Result.failure(DataException(DataError.Unknown(message)))` |

Reads stay exception-free `Flow<T>`; expose a `catch` in the ViewModel (G4).

## Step 6 - Write use cases

Copy `assets/UseCase.kt`. One public `operator fun invoke`, one responsibility,
`domain.usecase` package, zero Android imports. Validation belongs here:
`AddTodoUseCase` trims and rejects blank titles with
`DomainException(DomainError.InvalidTitle)` before touching the repository.
Use cases return `Result<T>` or `Flow<T>`; never a ViewModel type, never UI text.

## Step 7 - Wire manual DI

Default: a small `AppContainer` created by the `Application` class. Hilt 2.60.1
with KSP is the opt-in alternative and costs ~30 minutes of build setup for a
one-module app, so it is not the default.

Create `di/AppContainer.kt` and `TodoApplication.kt` under the source root.
`AppContainer` builds the database, repository and use cases lazily and exposes
`observeTodos`, `addTodo`, `setTodoDone`, `deleteTodo` (G4 calls those names). It
is the only place that names `Dispatchers.IO`. Register `android:name=".TodoApplication"`
in the manifest and expose the container as `TodoApplication.container` for G4.

## Step 8 - Test what can break

Create `app_workspace/app/src/test/java/com/example/app/...` tests:

| Target | Test type | Minimum coverage |
|---|---|---|
| Use cases | pure JVM + fake repository, `runTest` | blank title rejected, happy path, repository failure propagated |
| Repository impl | fake DAO + `StandardTestDispatcher` | entity to domain mapping, `NotFound` on 0 rows, dispatcher used |
| Mappers | trivial round-trip | `toEntity().toDomain()` identity |
| DAO | Room in-memory (instrumented) | one query per screen state; may be deferred to G5, must exist before G7 |

Use `assertTrue(result.isSuccess)` / `assertIs<DataException>` style assertions;
a test that only asserts "no crash" is not evidence.

## File map (default single `:app` module)

Source root: `app_workspace/app/src/main/java/com/example/app/`; tests under
`app_workspace/app/src/test/java/com/example/app/`.

| File under root | Package |
|---|---|
| `domain/model/Todo.kt` | `com.example.app.domain.model` |
| `domain/repository/TodoRepository.kt` | `com.example.app.domain.repository` |
| `domain/usecase/TodoUseCases.kt` | `com.example.app.domain.usecase` |
| `data/local/entity/TodoEntity.kt` | `com.example.app.data.local.entity` |
| `data/local/TodoDao.kt` | `com.example.app.data.local` |
| `data/local/AppDatabase.kt` | `com.example.app.data.local` |
| `data/repository/RoomTodoRepository.kt` | `com.example.app.data.repository` |
| `di/AppContainer.kt` | `com.example.app.di` |
| `TodoApplication.kt` | `com.example.app` |

Other writes, all concrete:

- `app_workspace/gradle/libs.versions.toml` and
  `app_workspace/app/build.gradle.kts` - room, ksp, coroutines-test aliases, KSP
  plugin, schema arg, dependencies.
- `app_workspace/app/src/main/AndroidManifest.xml` - `android:name=".TodoApplication"`.
- `app_workspace/app/schemas/<db>/1.json` - KSP export, commit it.
- `app_workspace/.pipeline/reports/domain-<UTC>.json` - evidence.
- `00_memory/TECH_STACK.md`, `00_memory/DECISION_LOG.md` - versions and `DL`.

If G2 created split modules (`core/database`, `core/common`), keep the package
tails and move the `data` files there; log a `DL`.

## Testing hooks

Unit-testable without a device or Robolectric: every use case, every repository
method, every mapper. Design for it: constructor injection for DAO, dispatcher,
and a `nowMillis: () -> Long` clock so timestamp assertions are deterministic.
Test the DAO against `Room.inMemoryDatabaseBuilder` only in `androidTest`.
Previewable at G3: nothing - do not add `@Preview` here.

## Quality bar

- The domain package has zero `android.*` / `androidx.*` imports. Verify:
  `grep -rn "android\." app_workspace/app/src/main/java/com/example/app/domain/ || echo clean`
- A G4 agent can implement a screen from `TodoRepository` + use cases alone.
- Every DAO query has a test or a named consumer.
- No `Dispatchers.IO`, `Context`, or `ViewModel` reference in domain/data
  interfaces.
- Schema JSON is exported and committed; `exportSchema = true`.

## Anti-patterns

- **Do NOT** pass `TodoEntity` above the data layer or `Context` below it.
- **Do NOT** hardcode `Dispatchers.IO` in the repository; inject it.
- **Do NOT** catch `Throwable` and swallow it; convert to `DataError` and return.
- **Do NOT** add a migration for version 1. Destructive fallback is acceptable
  only while the app has zero installed users; state it in a `DL`.
- **Do NOT** use `LiveData`; this pipeline standardizes on `Flow`.
- **Do NOT** add Hilt, Koin, or a network client the spec does not ask for.
- **Do NOT** mark G3 pass on a compile-only run; the unit tests are the gate.

## Token economy

Read `00_memory/TECH_STACK.md`, `app_workspace/.pipeline/spec.json`, and the files
you are about to edit. Nothing else. Use `grep` for aliases in
`libs.versions.toml`; never open the whole catalog. Do not dump
`build.gradle.kts`, Gradle logs, or the Room schema into context - grep the one
line you need. If a build fails, hand it to `05-build-test-loop` instead of
iterating here.

## Verification

Run from the pipeline root (the helper sets `APP_ROOT` and a writable
`GRADLE_USER_HOME`):

```bash
source scripts/lib/android_env.sh
gradlew :app:compileDebugKotlin
gradlew :app:testDebugUnitTest --tests "*UseCaseTest" --tests "*RepositoryTest"
```

Expected: `BUILD SUCCESSFUL` for each, and
`app_workspace/app/build/test-results/testDebugUnitTest/*.xml` with
`failures="0"`. Then confirm schema export:
`ls app_workspace/app/schemas/*/1.json`.

Write the evidence file with the same shape as the G2 report:

```json
{"schema":1,"gate":"G3","status":"pass","timestamp":"<UTC ISO-8601>",
 "dispatcher_injection":true,"entities":["TodoEntity"],
 "tests":{"task":":app:testDebugUnitTest","failures":0,"tests":6},
 "commands":[{"cmd":":app:testDebugUnitTest","exit":0}],"notes":[]}
```

Status is `pass` only when the test task exited 0; `compile` alone is `fail`.
Append a `DL` for the storage and dispatcher decisions, then hand off.

## Stop conditions

| Condition | Action |
|---|---|
| G2 is red or the project does not build | hand back to `02-android-scaffold`; do not fix Gradle here |
| Entity fields, ownership, or retention are ambiguous | `HD-###` (class C), freeze G3 |
| The spec needs a migration for existing user data | `HD-###` with migration options; never destructively migrate silently |
| KSP cannot resolve against the scaffold Kotlin | one retry with a compatible KSP2 release, then `HD-###` (environment) |
| Test task fails 3 times for the same error class | stop, `HD-###` with the last 100 log lines |
| A blocking HD is open | stop; no evidence file for G3 |

Hand off to `04-ui-compose` only with a green evidence file, a clean domain
package, and the writes list above on disk.
