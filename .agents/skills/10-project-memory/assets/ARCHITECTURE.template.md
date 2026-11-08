# Architecture — <app-name>

<!--
Canonical architecture record. Bootstrap copies this file to
`00_memory/ARCHITECTURE.md`; agents then edit it in place.

What belongs here: patterns, module boundaries, data flow, UI conventions,
invariants. What does NOT belong here: version numbers (TECH_STACK.md),
decision reasoning (DECISION_LOG.md), current task (SESSION_STATE.md),
feature scope (app_workspace/.pipeline/spec.json).

Update only when a pattern or boundary actually changes, and date the edit in
the changelog at the bottom. Keep the file under ~200 lines.
-->

| Field | Value |
|---|---|
| App | `<app-name>` |
| Last updated | `<YYYY-MM-DD>` |
| Maintained by | `<agent role or human>` |
| Target | `compileSdk 36`, `targetSdk 36`, `minSdk 24` |

## 1. Shape

<!-- Two or three sentences: what the app is, who uses it, the one core flow.
     No marketing, no feature list. -->

`<app-name>` lets `<user>` `<core action>` and produces `<primary outcome>`.
The single core flow is: `<screen A>` → `<screen B>` → `<result>`.

## 2. Module map

<!-- One row per Gradle module. `:app` stays thin: wiring, navigation host,
     theme, DI container. Features never depend on each other. -->

| Module | Kind | Responsibility | May depend on |
|---|---|---|---|
| `:app` | Application | Entry point, navigation host, `AppContainer`, theme wiring | everything |
| `:core:model` | Library | Pure Kotlin domain types, no Android imports | nothing |
| `:core:data` | Library | Repositories, data sources, mappers | `:core:model` |
| `:core:ui` | Library | Design system: theme, tokens, shared composables | `:core:model` |
| `:feature:<name>` | Library | One screen family, its ViewModels and UI state | `:core:model`, `:core:data`, `:core:ui` |
| `:core:testing` | Test-only | Fakes, test dispatchers, fixture builders | `:core:model` |

## 3. Dependency direction

```
:app ──► :feature:* ──► :core:data ──► :core:model
  │           │             │
  └───────────┴──► :core:ui ┘
```

Rules:

- Arrows point one way. `:core:model` imports nothing from the app.
- A feature never depends on another feature; share through `:core:*`.
- `:core:data` never imports Compose.
- Adding a module requires a build-file change, a row above, and a `DL-###`.

## 4. Data flow

<!-- Describe the real path for this app, not a generic diagram. -->

```
Composable ──(events)──► ViewModel ──► UseCase? ──► Repository ──► DataSource
    ▲                        │                                        │
    └────── UiState ◄────────┘◄──────────── Flow<Model> ◄─────────────┘
```

Rules:

- Composables are stateless in the data sense: they render `UiState` and emit events.
- One `UiState` data class or sealed interface per screen, exposed as `StateFlow`.
- Repositories are the only component that knows about storage or network.
- No repository or data source type appears in a Composable signature.
- Mapping between layers happens at the boundary, in the layer that owns the type.

## 5. UI conventions

<!-- Compose-only unless a `DL-###` says otherwise. -->

| Concern | Convention |
|---|---|
| UI toolkit | Jetpack Compose only; no XML layouts |
| Navigation | Navigation 3: `NavBackStack`, entry providers, stable scene keys |
| State | Hoppla state up; every screen has `Screen` (stateful) and `Content` (stateless) |
| Previews | `@Preview` on every `Content`, no ViewModel in the preview |
| Theme | Single `<AppTheme>` in `:core:ui`; no hard-coded colors or dp in features |
| Strings | `strings.xml` only; no user-facing literals in Kotlin |
| Accessibility | `contentDescription` on every actionable icon; touch targets ≥ 48dp |
| Loading and empty | Every screen defines loading, empty, error, and content states |

## 6. State and threading

- ViewModel scope for UI work; repository scope for long-lived flows.
- Dispatchers are injected, never hard-coded, so tests can replace them.
- No blocking call on the main thread; no `runBlocking` outside tests.
- Flows are cold until collected; a one-shot result uses `suspend`, not a `SharedFlow` hack.

## 7. Dependency injection

<!-- Pipeline default. Hilt is opt-in and requires a `DL-###` first. -->

- Manual constructor injection.
- `AppContainer` is created in `<Application>` and exposed for ViewModel factories.
- A ViewModel receives dependencies through its factory, never through a global.
- New dependency procedure: add to `AppContainer` → add to the factory → add to the screen's navigation entry.
- Hilt + KSP is an opt-in alternative; record the decision before applying the plugin.

## 8. Error handling

- Failures are values, not exceptions, across layer boundaries: a sealed `Result`-style type.
- The data layer maps infrastructure errors into domain errors exactly once.
- The ViewModel maps domain errors into `UiState` messages; the UI never formats an exception.
- No empty `catch` blocks, no swallowed errors, no `printStackTrace`.

## 9. Persistence

<!-- Fill when a storage decision is recorded; link the DL id. -->

| Store | Technology | Owns | Decision |
|---|---|---|---|
| `<primary store>` | `<Room / DataStore / file>` | `<entities>` | `DL-000` |
| `<cache>` | `<technology>` | `<entities>` | `DL-000` |

Schema or format changes require a migration and a new `DL-###`.

## 10. Testing seams

- Fakes over mocks by default; MockK only for framework boundaries.
- Test dispatchers injected everywhere a dispatcher is used.
- `:core:testing` provides one fake per repository interface.
- Screenshot tests target the stateless `Content` composables.
- A unit test never needs an emulator; an instrumented test never tests business logic.

## 11. Naming and package layout

```
<com.example.app>/
├── app/            Application, MainActivity, navigation host, AppContainer
├── core/model/     domain types
├── core/data/      repository + data source implementations
├── core/ui/        theme, tokens, shared composables
└── feature/<name>/ Screen.kt, ViewModel.kt, UiState.kt, Navigation.kt
```

- Packages mirror module names; no `misc`, `utils`, or `helpers` package.
- One public type per file; file name equals the type name.
- Interface suffix `Repository`, implementation suffix `...Impl` or a named source (`...RoomSource`).

## 12. Invariants

<!-- Things a change must never break. Short, checkable sentences. -->

- [ ] `:core:model` has no Android or Compose imports.
- [ ] No feature module depends on another feature module.
- [ ] Every screen renders all four states.
- [ ] Every dependency is injected, not instantiated inside a ViewModel.
- [ ] Every user-facing string is a resource.
- [ ] Every version lives in `TECH_STACK.md` and `gradle/libs.versions.toml`, never here.

## 13. Changelog

<!-- One row per edit. Rationale goes in DECISION_LOG.md, not here. -->

| Date | Change | Decision |
|---|---|---|
| `<YYYY-MM-DD>` | Initial record | `DL-000` |
