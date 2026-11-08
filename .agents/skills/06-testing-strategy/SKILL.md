---
name: 06-testing-strategy
description: Defines and enforces the test strategy for the generated Android app across G3-G6 - choosing the cheapest reliable layer (JUnit4/JUnit5 + Truth, Turbine/coroutines-test, Robolectric, Compose ui-test, Roborazzi/Paparazzi/AGP screenshot suites, agent-driven device journeys), adding version-catalog entries, writing deterministic tests, and producing reports/test-<UTC>.json as supporting G5 evidence. Use when writing, reviewing, fixing, or de-flaking tests; setting up test infrastructure; choosing between unit, Robolectric, Compose UI, screenshot, or e2e tests; running coverage or test commands; investigating CI test failures; or deciding what must be green before build/test, device verification, or release. Triggers - test, testing, unit test, ViewModel test, Robolectric, Compose UI test, UI test, screenshot test, screenshot regression, Roborazzi, Paparazzi, AGP test suites, MockK, Turbine, coverage, flaky, test report, CI, G3, G4, G5.
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Testing strategy (G3-G6)

One test per risk, at the cheapest layer that can fail. Screenshots prove pixels,
not logic. A green build without tests is not evidence.

## Contract

- **Reads:** `00_memory/TECH_STACK.md`; `app_workspace/.pipeline/spec.json`
  (`acceptance`, `flows`, `risks`); `gradle/libs.versions.toml`; module `build.gradle.kts`;
  existing `src/test` / `src/androidTest`.
- **Writes:** test sources under `app_workspace/app/src/test/` and
  `.../androidTest/`; test-only catalog/build additions;
  `app_workspace/.pipeline/reports/test-<UTC>.json`.
- **Gate:** `G5` (supports `G3`, `G4`). Screenshot baselines are recorded at
  `G4`, verified at `G5`; device journeys are `G6`.
- **Handoff:** `05-build-test-loop` owns `verify-<UTC>.json` and the build/lint/
  preview loop; `07-device-verification` owns `device-<UTC>.json`, emulator
  journeys, and instrumented evidence.
- **Owns:** layer choice, determinism, test layout, and the supplemental
  report. Do not edit production sources; hand off to `03`/`04` if a seam is
  needed.

## Decision table: choose the layer

Pick the lowest row that can observe the failure; move down only for genuinely
visual, cross-process, or device-specific risk.

| Risk | Test at | Default tool |
|---|---|---|
| Calculation, branch, validation, mapping | Pure JVM | JUnit4 + Truth |
| Emission order, loading/error flow | Coroutine unit | `runTest` + Turbine |
| ViewModel state machine, events | ViewModel unit | Turbine + fake repo + injected dispatcher |
| SQL, relations, migrations | DAO | Robolectric in-memory Room, or instrumented |
| Wire/persistence shape | Round-trip unit | kotlinx.serialization |
| State rendering, actions, semantics | Compose behavior | `createComposeRule` / `createAndroidComposeRule` |
| Layout, color, font-scale clipping | Screenshot | Roborazzi (default) |
| Whole journey across app and system UI | Device e2e | `android layout` + `input` + `screen capture` |


## Baseline setup

The scaffold is authoritative: AGP `9.0.1`, Gradle `9.1.0`, Kotlin `2.3.20`,
Compose BOM `2026.03.01`, compileSdk/targetSdk `36`, minSdk `24`, JDK 17. Do not
upgrade any of these while adding tests.

- AGP 9: **never** apply `org.jetbrains.kotlin.android`; kapt is incompatible,
  use KSP2.
- Template ships JUnit4, `coroutines-test`, Compose `ui-test-junit4`/`manifest`,
  `androidx.test:core`/`ext:junit`/`runner`, and Espresso. JUnit4 is the default;
  JUnit5 `6.1.3` only in a pure-JVM source set with no JUnit4 tests (mixing
  engines silently skips JUnit4).
- AGP `9.0.1` < test-suite floor `9.5.0-alpha03`: default screenshot is
  **Roborazzi 1.78.0**, Paparazzi 1.3.5 fallback; no standalone screenshot plugin.

### 1. Catalog entries

Merge into `app_workspace/gradle/libs.versions.toml`; do not duplicate template
keys. Check with `grep -nE '^(junit|coroutines|androidx|espresso|truth|turbine|mockk|robolectric|roborazzi)' gradle/libs.versions.toml`.

```toml
[versions]
truth = "1.4.5"
turbine = "1.2.1"
robolectric = "4.17"
roborazzi = "1.78.0"

[libraries]
truth = { module = "com.google.truth:truth", version.ref = "truth" }
turbine = { module = "app.cash.turbine:turbine", version.ref = "turbine" }
robolectric = { module = "org.robolectric:robolectric", version.ref = "robolectric" }
roborazzi = { module = "io.github.takahirom.roborazzi:roborazzi", version.ref = "roborazzi" }
roborazzi-compose = { module = "io.github.takahirom.roborazzi:roborazzi-compose", version.ref = "roborazzi" }

[plugins]
roborazzi = { id = "io.github.takahirom.roborazzi", version.ref = "roborazzi" }
```

Robolectric `4.17` is the latest stable; do not use `4.18-beta-1`. Turbine
`1.2.1` resolves coroutines `1.10.2`; align `coroutines-test` with the core
version already present (`1.10.2` or `1.11.0`). Record additions in `TECH_STACK.md`.

### 2. Module wiring

```kotlin
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.roborazzi)
}

android {
    testOptions.unitTests {
        isIncludeAndroidResources = true // graphics mode set by @GraphicsMode
    }
}

roborazzi {
    outputDir.set(layout.projectDirectory.dir("src/test/snapshots"))
}

dependencies {
    testImplementation(libs.truth)
    testImplementation(libs.turbine)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.test.manifest)
}
```

```properties
# app_workspace/gradle.properties
roborazzi.record.filePathStrategy=relativePathFromRoborazziContextOutputDirectory
```

`captureRoboImage("home_success.png")` writes
`app/src/test/snapshots/home_success.png`; commit baselines, never `build/`.

### 3. Screenshot stack

Default Roborazzi 1.78.0. Paparazzi 1.3.5 or AGP test suites only as the
decision matrix in `references/tooling-matrix.md` allows; `android preview
render` for no-baseline checks; Dropshots 0.6.0 at `G6`.

## Pipeline test matrix

Run every Task from `app_workspace` as `./gradlew <task> --console=plain`.
`<test>` = `app/src/test/java/com/example/app`; `<mod>` = `app/src/main/java/com/example/app`.
Replace `com.example.app` with the `applicationId` from `spec.json`.

| Risk | Layer | Tool | Where it lives | Command | Gate |
|---|---|---|---|---|---|
| Calculation, validation, mapping | Pure JVM | JUnit4 + Truth | `<test>/domain/` | `:app:testDebugUnitTest --tests "*UseCaseTest"` | G3 |
| Async ordering, Flow contracts | Coroutine unit | `coroutines-test` + Turbine | `<test>/domain/` | `:app:testDebugUnitTest --tests "*UseCaseTest"` | G3 |
| ViewModel state machine, events | ViewModel | Turbine + `StandardTestDispatcher` + fake repo | `<test>/ui/<feature>/` | `:app:testDebugUnitTest --tests "*ViewModelTest"` | G4 |
| SQL, relations, transactions | DAO | Robolectric in-memory Room, or instrumented (03 default) | `<test>/data/local/` or `app/src/androidTest/` | `:app:testDebugUnitTest --tests "*DaoTest"`; `:app:connectedDebugAndroidTest` | G5 / G6 |
| JSON/wire shape | Round-trip unit | JUnit4 + kotlinx.serialization | `<test>/data/` | `:app:testDebugUnitTest --tests "*SerializationTest"` | G3 |
| State rendering, clicks, semantics | Compose behavior | Robolectric + `createAndroidComposeRule` | `<test>/ui/<feature>/` | `:app:testDebugUnitTest --tests "*ScreenTest"` | G4 |
| Back, restoration, navigation results | Compose behavior | `StateRestorationTester` + Compose rule | `<test>/ui/navigation/` | `:app:testDebugUnitTest --tests "*NavigationTest"` | G4 |
| Layout, theme, font scale, sizes | Screenshot | Roborazzi; Paparazzi fallback; AGP suites after upgrade | `<test>/screenshot/`; baselines `app/src/test/snapshots/` | `:app:verifyRoborazziDebug` (record: `:app:recordRoborazziDebug`) | G4 / G5 |
| Preview renders | Render smoke | `android preview` | `@Preview` in `<mod>` | `android preview list -f json`; `android preview render -o .pipeline/artifacts/previews -f json --fqn=<FQN>` | G4 / G5 |
| Whole user flow on device | Agent e2e | `android layout`, `input`, `screen capture` | `.pipeline/artifacts/` | `references/ci-recipes.md` (device job) | G6 |
| Startup, jank | Benchmark (optional) | Macrobenchmark | separate `:benchmark` module | Device task | G7 |

Stage floors:

- **G3:** use cases, repository, and mappers have happy + failure/edge; Flow via
  Turbine. DAO Room test by G5. Advisory 70% coverage; not a gate.
- **G4:** each screen state behavior-tested; controls have semantics/`testTag`;
  screenshots at compact + expanded, fontScale 1.5, dark.
- **G5:** local tests green; screenshot verify; lint 0 errors; previews render;
  no ignored tests; test report `pass`.
- **G6:** one agent Journey per spec `flow` with layout JSON + PNG; no crash/ANR.

## Flakiness control

Fix determinism; never retry,
ignore, or weaken the assertion.

1. `runTest` for every suspend test; inject `StandardTestDispatcher` so
   `viewModelScope` never uses real `Main`. Replace `Dispatchers.Main` with a
   rule (`setMain` in `starting`, `resetMain` in `finished`).
2. Virtual time only: `advanceUntilIdle()`, `runCurrent()`, `advanceTimeBy()`.
   No `Thread.sleep`, real `delay()`, or polling.
3. Turbine: `awaitItem()`, `awaitComplete()`, `cancelAndIgnoreRemainingEvents()`;
   never assert after a terminal event.
4. Compose: `waitForIdle()` when needed; `mainClock.autoAdvance = false` +
   `mainClock.advanceTimeBy()` for animations; `waitUntil(timeoutMillis)` for
   async UI, never a sleep.
5. Freeze environment: fixed locale/timezone/qualifiers
   (`w411dp-h891dp-xxhdpi`), fixed font scale, injected `Clock`/`TimeSource`.
   No wall-clock assertions.
6. No real network, disk, or image loading; fakes return static payloads and the
   same bitmap every run. Fresh fake/DB per test; no shared mutable singletons,
   no order dependence, no `@FixMethodOrder`.
7. Screenshots: pin versions, disable animations, no clocks, random content,
   remote images, or mid-frame spinners. Run the suite twice before green.

## Test-writing rules

- Test behavior through the public API. One behavior per test; name with
  backticked sentences (`\`emits error when repository fails\``).
- Prefer hand-written fakes to mocks: they expose state transitions and survive
  refactors. Use `io.mockk:mockk:1.14.12` only for final/third-party seams; never mock
  data classes or the class under test.
- Build sample data with functions (`sampleTodo(id = 1)`); Compose matches
  role/text/description first and adds `testTag` only when semantics cannot.
- Screens are stateless: `state` + callbacks. If a composable reads the
  ViewModel directly, hand off to `04-ui-compose`; add no test hacks.
- Assert user-visible outcomes/state, not private methods/logs/call counts; use
  string resources for localized copy. Add a regression test per bug; it must
  fail before the fix.

Do NOT:

- `Thread.sleep`, `delay(1_000)`, busy-wait, or `runBlocking` in tests.
- Assert pixels/colors to prove logic; assert semantics instead.
- Snapshot a whole screen to test one component, or snapshot dynamic content.
- Add `@Ignore`, `@Suppress`, `-x test`, or delete a test to make G5 green.
- Mock the ViewModel/repository when a fake exposes the state path.
- Enable `useJUnitPlatform()` in a source set that still has JUnit4 tests.
- Apply `org.jetbrains.kotlin.android`, kapt, or the deprecated standalone
  screenshot plugin.
- Re-record baselines without confirming the UI change is intended by the spec.

## Evidence: test-<UTC>.json

Write `app_workspace/.pipeline/reports/test-<UTC>.json` with a stamp such as
`20261108T160000Z`. It supplements `05`'s `verify-<UTC>.json`; never hand-write
a passing `verify-<UTC>.json`.

```json
{
  "schema": 1,
  "gate": "G5",
  "status": "pass",
  "timestamp": "2026-11-08T16:00:00Z",
  "unit_tests": {"tests": 42, "failures": 0, "errors": 0, "skipped": 0},
  "screenshots": {"verified": 12, "baselines": "app/src/test/snapshots"},
  "previews": {"rendered": 6, "artifacts": ".pipeline/artifacts/previews"},
  "lint": {"errors": 0, "report": "app/build/reports/lint-results-debug.html"},
  "blockers": []
}
```

Count from the XML, never from memory: parse
`app/build/test-results/testDebugUnitTest/*.xml` and sum `tests`, `failures`,
`errors`, `skipped`. Any failure writes `"status": "fail"`, the first failing
test and report path in `blockers`, then stops. Partial runs are not a pass.

## Stop conditions and escalation

Budgets: 3 attempts per error class, 4 screenshot iterations, 5 G5 re-runs. On
exhaustion, stop and escalate to `09-human-review` with proposed `HD-###`; do
not edit its files.

Stop when:

- `spec.json` has no acceptance criteria for the behavior, or criteria conflict.
- A test needs a production change; hand off to `03`/`04`.
- Greening requires a dependency/AGP/Kotlin/Compose upgrade or a `minSdk`
  change. Upgrades are a separate gated change (`02` + `DL`), never a test fix.
- A visual diff is intentional but the spec does not confirm it; do not
  re-record on a guess.
- A test is flaky twice after a determinism fix; quarantine only with an `HD`
  and an owner.
- Device evidence is required but no emulator/device is available; hand off to
  `07`, do not mock the device away.
- The environment cannot run the stack (JDK, SDK 36, writable cache) and no
  documented workaround exists.

## Verification commands

Run from `app_workspace`. Read the first failure and the named report only.

| Command | Pass means | Read |
|---|---|---|
| `./gradlew :app:testDebugUnitTest --console=plain` | 0 failures/errors | `app/build/reports/tests/testDebugUnitTest/index.html` |
| `./gradlew :app:verifyRoborazziDebug --console=plain` | all baselines match | `app/build/reports/roborazzi/index.html` |
| `./gradlew :app:lintDebug --console=plain` | 0 lint errors | `app/build/reports/lint-results-debug.html` |
| `android preview list -f json` | one entry per `@Preview` | empty means G4 incomplete |
| `android preview render -o .pipeline/artifacts/previews -f json --fqn=<FQN>` | one PNG per `--fqn` (repeat per preview) | stdout prints absolute paths |
| `./gradlew :app:connectedDebugAndroidTest --console=plain` | green on a device | `app/build/reports/androidTests/connected/debug/index.html` |

Pass is `BUILD SUCCESSFUL` (Gradle) or exit 0 with PNG paths (preview render).
Full G5 also requires `05-build-test-loop/scripts/verify.sh` to write
`reports/verify-<UTC>.json` with `"status": "pass"`.

Device journeys are `07-device-verification`'s job; the exact
`android emulator create/start`, `layout`, `input`, and `screen capture`
sequence and its pass criteria live in `references/ci-recipes.md`.

## Token economy

- Run the narrowest task and `--tests` filter with `--console=plain`.
- Never paste full Gradle logs: read `e:`, `FAILURE:`, or the first `<failure`.
- Re-run only the failed class while iterating; full suite once before green.
