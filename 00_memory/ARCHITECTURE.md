# Architecture

> Stable record of patterns and boundaries. Update rarely, deliberately, and
> with a `DL` entry. Volatile state lives in `SESSION_STATE.md`.

## Product context

- App: `<app-name>`
- Audience: `<who and when>`
- Platforms: phone (baseline) · tablet/foldable if `spec.json` says so
- Offline-first: `<yes/no>`

## Layering

```
ui/            Compose screens, ViewModels, UI state, navigation
domain/        models, repository interfaces, use cases (no Android imports)
data/          Room/DataStore/network implementations, DTOs, mappers
di/            AppContainer (manual) or Hilt modules
```

Rules:

- `domain` never imports `android.*`, `androidx.*` or `data.*`.
- `ui` depends on `domain` only, never on `data` implementations.
- `data` implements `domain` interfaces; mappers keep entities out of the UI.
- One direction of dependency: `ui → domain ← data`. No cycles.

## UI pattern

- Unidirectional data flow: immutable `UiState` + events in, state out.
- Every screen has: stateless composable (`Screen(state, onAction)`), stateful
  entry (`ScreenRoute(viewModel)`), sealed `UiState` with
  `Loading/Success/Empty/Error`.
- State survives configuration changes via `ViewModel` + `SavedStateHandle`.
- Navigation: Navigation 3, `@Serializable` keys, back stack is the single
  source of truth for navigation.
- Theming: Material 3, dynamic color opt-in, light + dark, edge-to-edge with
  insets handled by `Scaffold`/`safeDrawingPadding`.

## Data pattern

- Repository interface in `domain`, implementation in `data`.
- Room is the local source of truth; remote (if any) writes through the
  repository, never directly into the UI.
- Flows for reads, `suspend` + `Result` for writes.
- Dispatchers injected (`CoroutineDispatcher`), never hardcoded in business code.
- Errors modelled as a sealed `DataError`, mapped to user messages in the UI.

## Dependency injection

Default: manual constructor injection with an `AppContainer` created in the
`Application` class. Add Hilt (+ KSP2) only when the graph exceeds ~30
dependencies or the team already uses it; record the switch as a `DL`.

## Module strategy

Start single-module (`:app`) with package boundaries. Split into `core/*` and
`feature/*` Gradle modules when incremental build time dominates, a feature needs
different SDK/dependencies, or a library is published. Every split is a `DL`.

## Testing seams (design for these from day one)

| Seam | Why |
|---|---|
| Repository interface | fake data without a device |
| Injected dispatcher | deterministic coroutine tests |
| Injected clock/`TimeSource` | no time-dependent flakiness |
| `UiState` as data | screenshot/preview per state |
| Previewable stateless composables | visual verification without an emulator |

## Quality bars

- Startup to first frame: `<perfBudgetMs>` ms (from `spec.json`).
- Every interactive element has an accessibility label.
- No `GlobalScope`, no `runBlocking` in production code.
- No business logic in composables or Activities.
