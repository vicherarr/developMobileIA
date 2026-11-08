---
name: 04-ui-compose
description: Builds the Compose UI layer for this Android pipeline - Material 3 stateless screens, ViewModel state machines exposing StateFlow with Loading/Success/Empty/Error, Navigation 3 hosts with @Serializable NavKey back stacks and typed arguments, theme wiring, light/dark previews and host-side screenshot previews. Use when adding or changing a screen, UI state, ViewModel, navigation, theme, empty/loading/error handling, or previews, or when G4 must pass. Triggers - Compose screen, UI, ViewModel, UiState, StateFlow, state hoisting, navigation, Navigation 3, NavKey, NavDisplay, preview, Material 3, theme, screenshot test, G4.
metadata:
  author: TodoMoteros
  version: "1.0"
---

# UI with Compose (G4)

G4 turns the G3 domain API and the spec's `screens[]` into Compose screens that
are stateless, previewable, and drive one ViewModel each. The screen renders
state; the ViewModel owns it; navigation passes typed keys. Nothing else.

## Contract

| Field | Value |
|---|---|
| Reads | `00_memory/TECH_STACK.md`, `app_workspace/.pipeline/spec.json` (`screens`, `acceptance`), `app_workspace/.pipeline/plan.md`, `app_workspace/.pipeline/reports/domain-*.json`, the G3 use cases and models |
| Writes | the file map below; `app_workspace/.pipeline/reports/ui-<UTC>.json`; append-only `00_memory/DECISION_LOG.md` |
| Gate | `G4` - `:app:compileDebugKotlin` green, a preview per screen state, evidence `"status":"pass"` |
| Handoff | `05-build-test-loop` (G5) |

Do not edit `STATE.json` (the orchestrator owns it). Do not add repository or
DAO code here: if G3 is missing something, return to `03-domain-and-data`.

## Preconditions

| Check | Command | If it fails |
|---|---|---|
| G3 green | `ls app_workspace/.pipeline/reports/domain-*.json` | stop, return to `03-domain-and-data` |
| Domain API exists | `grep -rl "interface TodoRepository" app_workspace/app/src/main/java/` | stop; the UI cannot invent a data API |
| Navigation 3 present | `grep -rln navigation3 app_workspace/app/build.gradle.kts` | stop, hand back to `02-android-scaffold` |
| Lifecycle compose | `grep -rln lifecycle app_workspace/app/build.gradle.kts` | add `lifecycle-runtime-compose` + `lifecycle-viewmodel-compose`, version 2.10.0 |
| No blocking HD | `grep -c 'blocking: yes' 02_pending_review/human_decisions.md` | stop, `09-human-review` |

Read the screen contract from the spec:

```bash
python3 -c 'import json;s=json.load(open("app_workspace/.pipeline/spec.json"));[print(f["id"], f.get("screens")) for f in s["features"] if f["priority"]=="must"]'
```

Every screen in `screens[].states` must be rendered. A missing state is an
incomplete G4, not a polish item.

## Step 1 - Decide the screen inventory

| Spec says | Build |
|---|---|
| one screen | one route, one screen, one ViewModel |
| list + detail | two routes, typed detail key (`todoId: Long`) |
| tabs or a multi-step flow | one nested nav host owned by the feature |
| a state not listed | do not invent it; add it to the spec first |

One ViewModel per screen. Do not pass a ViewModel to a child composable; pass
state and lambdas down.

## Step 2 - Theme and strings

Standardize on `AppTheme` in `app_workspace/app/src/main/java/com/example/app/ui/theme/Theme.kt`:
Material 3 `lightColorScheme()` / `darkColorScheme()`, `dynamicDarkColorScheme`
guarded by `Build.VERSION.SDK_INT >= Build.VERSION_CODES.S`, typography from the
template. If G2 named the theme composable after the project, rename it here and
record a `DL`; do not keep two themes.

Externalize every user-facing string in
`app_workspace/app/src/main/res/values/strings.xml`. The assets assume:

| Keys | Use |
|---|---|
| `home_title`, `add_todo`, `todo_title_label`, `save`, `cancel`, `delete` | chrome |
| `empty_hint`, `retry`, `loading`, `error_*` | non-happy states and `UiMessage` |
| `todo_toggle` (`%1$s`) | checkbox content description |

## Step 3 - UI state and ViewModel

Copy `assets/ViewModel.kt`. Shape, in this order, one file per screen:

```kotlin
sealed interface HomeUiState {
    data object Loading : HomeUiState
    data class Success(val todos: List<TodoUi>) : HomeUiState
    data object Empty : HomeUiState
    data class Error(val message: UiMessage) : HomeUiState
}

class HomeViewModel(...) : ViewModel() {
    val uiState: StateFlow<HomeUiState> = observeTodos()
        .map { todos -> if (todos.isEmpty()) HomeUiState.Empty else HomeUiState.Success(todos.toUi()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeUiState.Loading)

    fun onAction(action: HomeAction) { /* one when, one launch per write */ }
}
```

Rules:

- `StateFlow<UiState>` only; no `LiveData`, no mutable state exposed.
- `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), Loading)` is
  mandatory: it survives rotation and stops work when the screen is gone.
- `UiState` holds pure Kotlin only: no `Context`, `Bitmap`, `Uri`, `R`, or
  resource ids. Strings resolve in the composable.
- Emit a `UiMessage` enum from failures; map it to `stringResource` in the
  screen. Never build English text inside the ViewModel.
- `onAction` is the single entry point; no public function per button. Writes
  run in `viewModelScope.launch` and surface failures as `UiMessage`.
- `SavedStateHandle` is optional (the asset keeps the pending error); the factory
  takes `AppContainer` and uses `createSavedStateHandle()`.

## Step 4 - Stateless screen

Copy `assets/Screen.kt`. The signature is the contract:

```kotlin
@Composable
fun HomeScreen(
    uiState: HomeUiState,
    onAction: (HomeAction) -> Unit,
    onTodoClick: (Long) -> Unit,
    modifier: Modifier = Modifier,
)
```

Rules:

- `modifier: Modifier = Modifier` is the first optional parameter and is applied
  to the outermost composable.
- `Scaffold` + Material 3 `TopAppBar`; content gets `innerPadding` and never
  draws under system bars.
- Collections use `LazyColumn` with `items(items, key = { it.id })`; no stable
  key means broken scroll state and no animations.
- Render every `UiState` branch explicitly; use an exhaustive `when` so a new
  state fails compilation instead of showing a blank screen.
- Local UI-only state (dialog visibility, draft) may use `rememberSaveable`. Open
  the add dialog from the screen, then send `HomeAction.Add(title)` on confirm.
- Loading, Empty and Error views are real composables with text or a retry
  action, not empty `Box`es.
- Accessibility: tappable rows are at least 48dp, checkboxes get a content
  description, and text is never the only signal of the "done" state.

## Step 5 - Navigation 3 host

Copy `assets/Navigation.kt`. Non-negotiables:

| Rule | Why |
|---|---|
| Routes are `@Serializable data object` (no args) or `@Serializable data class` (typed args) implementing `androidx.navigation3.runtime.NavKey` | `rememberNavBackStack` persists the stack through config changes only for serializable keys |
| Back stack from `rememberNavBackStack(StartRoute)` | do not build a plain `mutableStateListOf` |
| `NavDisplay(backStack, onBack, entryProvider)` with `NavEntry(key) { ... }` | one place owns rendering and system back |
| `onBack = { if (backStack.size > 1) backStack.removeLastOrNull() }` | at the root, let the Activity finish |
| Arguments travel as fields on the key (`TodoDetailRoute(todoId)`) | no `Bundle`, no string routes, no `navArgument` |
| Guard pushes with `if (backStack.lastOrNull() != route) add(route)` | prevents duplicate destinations from double taps |

Nested features: the outer `NavDisplay` holds feature routes; a feature exposes
its own `NavDisplay` with a private back stack and receives callbacks instead of
reaching into the outer stack. Get ViewModels from the factory, never manually.

## Step 6 - Previews and screenshot previews

Two kinds, both required:

| Kind | Where | Purpose |
|---|---|---|
| IDE previews | `app_workspace/app/src/main/java/com/example/app/ui/home/HomePreviews.kt` | light + dark, every state, fast design feedback |
| Screenshot previews | `app_workspace/app/src/screenshotTest/kotlin/com/example/app/ui/home/HomeScreenshotTest.kt` | host-side golden images (copy `assets/PreviewTest.kt`) |

Rules: wrap every preview in `AppTheme` and `Surface` (an unthemed preview
fails on `CompositionLocal`), use deterministic sample data, emit one `@Preview`
per state, and keep sample data out of the screen file. Dark is
`uiMode = Configuration.UI_MODE_NIGHT_YES`.

Screenshot previews use the AGP test-suite convention (`@PreviewTest` +
`@Preview`, source set `screenshotTest`). That engine needs a newer AGP than the
9.0.1 baseline, and the legacy `com.android.compose.screenshot` plugin is
forbidden by `02-android-scaffold`, so the file stays inert until a suite exists:
record a `DL`, let G5 render with `android preview render`, and never claim PNGs
you did not produce.

## Step 7 - Wire the activity and the container

`app_workspace/app/src/main/java/com/example/app/MainActivity.kt`:

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as TodoApplication).container
        setContent { AppTheme { AppNavigation(container = container) } }
    }
}
```

`enableEdgeToEdge()` before `setContent` if the template uses it. The Activity
is the only place that knows about the `Application`.

## Step 8 - Test the state machine

Create `app_workspace/app/src/test/java/com/example/app/ui/home/HomeViewModelTest.kt`:

- `MainDispatcherRule` replacing `Dispatchers.Main`; fake use cases with fixed
  `Flow`s and `Result`s.
- Assert: initial `Loading`; empty list -> `Empty`; items -> `Success`; failed
  write -> `Error`; `ClearError` -> content. Read `uiState.value` after
  `advanceUntilIdle()` and collect `WhileSubscribed` flows in `backgroundScope`.

Deepen the strategy with `06-testing-strategy` (it owns coverage and the
acceptance-criterion matrix). Do not skip this test because "the screen is
simple": it is the only automated proof that the screen has states.

## File map

Source root `app_workspace/app/src/main/java/com/example/app/`; screenshot source
set `app_workspace/app/src/screenshotTest/kotlin/com/example/app/`; tests
`app_workspace/app/src/test/java/com/example/app/`.

| File under root | Package |
|---|---|
| `ui/theme/Theme.kt` | `com.example.app.ui.theme` |
| `ui/home/HomeScreen.kt` | `com.example.app.ui.home` |
| `ui/home/HomePreviews.kt` | `com.example.app.ui.home` |
| `ui/home/HomeViewModel.kt` | `com.example.app.ui.home` |
| `ui/detail/TodoDetailScreen.kt` | `com.example.app.ui.detail` |
| `ui/navigation/AppNavigation.kt` | `com.example.app.ui.navigation` |
| `MainActivity.kt` | `com.example.app` |
| `HomeScreenshotTest.kt` (screenshotTest source set) | `com.example.app.ui.home` |
| `HomeViewModelTest.kt` (test source set) | `com.example.app.ui.home` |

Other concrete writes: `app_workspace/app/src/main/res/values/strings.xml` (keys
from Step 2), `app_workspace/app/build.gradle.kts` (lifecycle-compose alias), and
`app_workspace/.pipeline/reports/ui-<UTC>.json`.

## Testing hooks

Unit-testable on the JVM: every ViewModel state transition with fake use cases,
`UiMessage` mapping, and the domain-to-UI mapper (`Todo.toUi()`). Not unit-testable:
layout, color, and padding - that is what previews and the device gate are for.
Previewable: every screen in every state, light and dark, at font scale 1.0 and
1.3; the preview list must match the spec's `screens[].states`. Screenshot-testable:
the same previews once the screenshot suite exists.

## Quality bar

- One screen file per spec screen, under ~250 lines; extract row and state
  composables instead of nesting.
- No `@Composable` calls a repository or use case directly; strings come from
  `strings.xml`; the preview inventory equals the spec's state inventory.

## Anti-patterns

- **Do NOT** pass the ViewModel or `NavController` into child composables.
- **Do NOT** expose `MutableStateFlow` or `var` state from the ViewModel.
- **Do NOT** put `Context`, `R.string.*`, or Android types in `UiState`.
- **Do NOT** create a new `CoroutineScope` in a composable; use
  `rememberCoroutineScope()` only for UI-local work.
- **Do NOT** add `Modifier` params at the end or ignore the incoming one.
- **Do NOT** key a `LazyColumn` by index.
- **Do NOT** hand-write `Bundle` arguments or string routes in Navigation 3.
- **Do NOT** mark G4 pass on a compile-only run with no previews.

## Token economy

Read only `00_memory/TECH_STACK.md`, `app_workspace/.pipeline/spec.json`, the G3
use cases you call, and the files you edit. Do not open the whole UI package, the
whole theme, or `build.gradle.kts`; grep for the alias you need. Previews are
cheaper than device runs: iterate with `android preview list` before building.
If compilation fails twice, hand it to `05-build-test-loop` instead of guessing.

## Verification

From the pipeline root:

```bash
source scripts/lib/android_env.sh
gradlew :app:compileDebugKotlin
gradlew :app:testDebugUnitTest --tests "*HomeViewModelTest"
android preview list -f json
```

Expected: `BUILD SUCCESSFUL` twice, and a JSON list containing one entry per
preview function (`HomeScreenPreview`, `HomeScreenDarkPreview`,
`HomeScreenEmptyPreview`, `HomeScreenEmptyDarkPreview`). A missing state is a failed G4.
Optionally render:

```bash
android preview render -o app_workspace/.pipeline/artifacts/previews -f json
```

Evidence, same shape as the G2 report:

```json
{"schema":1,"gate":"G4","status":"pass","timestamp":"<UTC ISO-8601>",
 "screens":["Home","TodoDetail"],"states":["Loading","Empty","Error","Success"],
 "previews":6,"render":"android-preview-list","commands":[{"exit":0}],"notes":[]}
```

Path: `app_workspace/.pipeline/reports/ui-<UTC>.json`. `pass` requires compile,
the ViewModel test, and the preview inventory. Then append a `DL` for theme
naming and any screenshot-suite decision, and hand off to G5.

## Stop conditions

| Condition | Action |
|---|---|
| G3 evidence is missing or red | stop, return to `03-domain-and-data` |
| A screen state is not in the spec | do not invent it; update the spec via `01-spec-and-scope` or raise `HD` |
| The design needs a product decision (copy, tone, brand color) | `HD-###` (class C), freeze G4 |
| Navigation 3 APIs are absent from the scaffold | `HD-###` (environment); do not swap in Navigation 2 |
| Preview render fails 3 times on the same error | stop, `HD-###` with the render log |
| A blocking HD is open | stop; no evidence file for G4 |

Hand off to `05-build-test-loop` only with a green compile, a green ViewModel
test, and a preview for every state on disk.
