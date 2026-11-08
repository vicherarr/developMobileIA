# Visual and screenshot testing tooling matrix

Baseline for this pipeline: AGP `9.0.1`, Gradle `9.1.0`, Kotlin `2.3.20`,
Compose BOM `2026.03.01`, compileSdk/targetSdk `36`, minSdk `24`, JDK 17.
Versions below were verified on Maven Central / Google Maven on 2026-11-08.
**Default: Roborazzi 1.78.0** because it runs on the JVM, is JUnit4-native, and
works with the scaffold's AGP 9.0.1. Paparazzi 1.3.5 is the fallback; AGP test
suites are a future option, not a current one.

## Comparison

| Criterion | Roborazzi 1.78.0 | Paparazzi 1.3.5 | Compose Preview Screenshot Testing (AGP suites) | `android preview render` | Instrumented Dropshots 0.6.0 |
|---|---|---|---|---|---|
| Renderer | Robolectric + native graphics (`@GraphicsMode(NATIVE)`) | LayoutLib (same family as Studio previews) | LayoutLib through AGP test suites | Compose preview renderer via Android CLI | Real device GPU/SurfaceFlinger |
| Fidelity | High for layout/theme; not pixel-identical to a phone | High for layout; approximates device rendering | High; official renderer | Preview-level; no system chrome | Highest: real pixels, system UI, fonts, OEM quirks |
| Device needed | No | No | No | No | Yes (emulator or phone) |
| Speed | Seconds per class after first run; first run downloads `android-all` | Seconds; no Robolectric startup | Medium; Gradle test-suite lifecycle | Build + render per invocation; `--daemon` helps | Slowest: boot, install, instrumentation |
| Setup cost | Medium: plugin + Robolectric + `isIncludeAndroidResources` | Low-medium: plugin; LayoutLib comes with it | Medium-high: experimental flags, DSL, AGP alpha | Low: Android CLI only | Medium: plugin + emulator + instrumentation runner |
| Baselines | `app/src/test/snapshots/*.png` (with `outputDir` configured) | `app/src/test/snapshots/*.png` | `{module}/src/{suite}{Target}{Variant}/reference/` | None; PNG per invocation | `app/src/androidTest/screenshots/` |
| Report | `app/build/reports/roborazzi/index.html` | Gradle output + `app/build/reports/paparazzi/` | `{module}/build/reports/tests/{taskName}/index.html` | Absolute PNG paths on stdout; `--output` | `app/build/outputs/androidTest-results/connected/` |
| Determinism | High when Robolectric/Roborazzi and OS are pinned | High when LayoutLib version is pinned | High; AGP-managed | Not a comparison gate | Lower: animations, fonts, GPU, device state |
| AGP 9.0.1 fit | Works | Check plugin compatibility first | **No** — requires AGP `>= 9.5.0-alpha03` | Works | Works |
| Best for | Default regression screenshots, component and screen states | Design-system snapshots, preview-like rendering | Official path after an intentional AGP upgrade | G4/G5 smoke, no baseline, no device | G6 edge-to-edge, notifications, PiP, system dialogs |

Do not run Roborazzi and Paparazzi in the same module: two visual frameworks
would fight over `src/test/snapshots` and Gradle test tasks. Pick one per
module; the pipeline default is Roborazzi.

## Exact coordinates and setup

### Roborazzi 1.78.0

Plugin: `io.github.takahirom.roborazzi` version `1.78.0`.
Libraries: `io.github.takahirom.roborazzi:roborazzi:1.78.0`,
`io.github.takahirom.roborazzi:roborazzi-compose:1.78.0`,
`io.github.takahirom.roborazzi:roborazzi-junit-rule:1.78.0`.
Runtime host: `org.robolectric:robolectric:4.17` (latest stable; do not use
`4.18-beta-1`). AndroidX test support: `androidx.test:core:1.7.0`,
`androidx.test.ext:junit:1.3.0`, `androidx.test.espresso:espresso-core:3.7.0`.

```kotlin
// app/build.gradle.kts
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.roborazzi)
}

android {
    testOptions.unitTests {
        isIncludeAndroidResources = true
        all { it.systemProperty("robolectric.graphicsMode", "NATIVE") }
    }
}

roborazzi {
    outputDir.set(layout.projectDirectory.dir("src/test/snapshots"))
}

dependencies {
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.roborazzi.junit.rule)
}
```

```properties
# gradle.properties
roborazzi.record.filePathStrategy=relativePathFromRoborazziContextOutputDirectory
```

```bash
./gradlew :app:recordRoborazziDebug --console=plain   # write/update baselines
./gradlew :app:verifyRoborazziDebug --console=plain   # compare, fail on diff
./gradlew :app:compareRoborazziDebug --console=plain  # diff artifacts for review
```

Record once, inspect the PNG/diff, commit `app/src/test/snapshots/`. Verify in
CI and G5. First run downloads `org.robolectric:android-all-instrumented`; cache
`~/.m2/repository/org/robolectric` in CI. Pin Robolectric and Roborazzi
together: a renderer change is a visual-baseline change, not a routine bump.

### Paparazzi 1.3.5

Plugin: `app.cash.paparazzi` version `1.3.5`; the plugin supplies
`app.cash.paparazzi:paparazzi:1.3.5` to the test classpath. Test API:
`Paparazzi` JUnit4 rule and `paparazzi.snapshot { ... }`.

Catalog entries (not added by default — only when Paparazzi is actually chosen):

```toml
[versions]
paparazzi = "1.3.5"

[plugins]
paparazzi = { id = "app.cash.paparazzi", version.ref = "paparazzi" }
```

```kotlin
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.paparazzi)
}
```

```bash
./gradlew :app:recordPaparazziDebug --console=plain
./gradlew :app:verifyPaparazziDebug --console=plain
```

Baselines live in `app/src/test/snapshots/`; failures and diff images are
written under `app/build/reports/paparazzi/` (the exact subdirectory is printed
by the task). Paparazzi is tied to LayoutLib and AGP internals: prove it applies
and renders one snapshot on AGP 9.0.1 before adopting it. If the plugin rejects
AGP 9, use Roborazzi or `android preview render`; **never downgrade AGP** to
keep a screenshot tool.

### Compose Preview Screenshot Testing with AGP test suites

Status: experimental. Requires AGP `>= 9.5.0-alpha03`, engine
`0.0.1-alpha16`, and `com.android.tools.screenshot:screenshot-validation-api:0.0.1-alpha16`.
It replaces the deprecated standalone `com.android.compose.screenshot` plugin.
The scaffold's AGP 9.0.1 **cannot** run it; do not add the flags or DSL now.

```properties
# gradle.properties
android.experimental.enableScreenshotTest=true
android.experimental.testSuiteSupport=true
```

```kotlin
// app/build.gradle.kts (only after the AGP upgrade)
android {
    testOptions {
        screenshotTests.create("screenshotTest") {
            engineVersion = "0.0.1-alpha16"
            targetVariants.add("debug")
            dependencies {
                implementation(libs.androidx.compose.ui.tooling)
                implementation("com.android.tools.screenshot:screenshot-validation-api:0.0.1-alpha16")
            }
        }
    }
}
```

Source set: `app/src/screenshotTest/kotlin/`. Annotate previews with
`@PreviewTest` plus `@Preview` (or a multi-preview). Tasks:

```bash
./gradlew :app:updateScreenshotTestDefaultDebugTestSuite --console=plain
./gradlew :app:testScreenshotTestDefaultDebugTestSuite --console=plain
```

References: `app/src/screenshotTestDefaultDebug/reference/`.
Report: `app/build/reports/tests/testScreenshotTestDefaultDebugTestSuite/index.html`.

Adopt only with a planned AGP upgrade, a written `DL`, and a clean build. The
experimental DSL can change; the pipeline's default must keep working.

### `android preview render`

No Gradle plugin, no baseline, no device. Use it to prove a preview compiles
and renders, especially at G4 before a baseline exists.

```bash
android preview list :app -f json
android preview render :app --fqn=com.example.app.ui.home.HomePreviewsKt.HomeScreenPreview \
  --output=.pipeline/artifacts/previews --component-tree -f json
```

At least one `--fqn` is required; repeat it per preview or loop over `preview list`.
The command prints absolute paths of the generated PNG and component-tree JSON.
An empty preview list means the screen has no `@Preview`, which is a G4 defect.
Use `--daemon` for repeated renders in one session. This is a smoke check, not a
pixel regression gate: it has no reference image and no comparison.

### Instrumented Dropshots 0.6.0

Plugin: `com.dropbox.dropshots` version `0.6.0`; runtime
`com.dropbox.dropshots:dropshots:0.6.0` (Android test source set). Test API:
`Dropshots()` JUnit4 rule, `dropshots.assertSnapshot(view)`.

```kotlin
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.dropshots)
}
```

```toml
[plugins]
dropshots = { id = "com.dropbox.dropshots", version = "0.6.0" }
```

References: `app/src/androidTest/screenshots/`. Record with the variant task
(for example `./gradlew :app:recordDebugScreenshots --console=plain`), verify
with `./gradlew :app:connectedDebugAndroidTest --console=plain`. Failure images:
`app/build/outputs/androidTest-results/connected/`.

Choose Dropshots only for what Robolectric cannot represent: real system bars,
edge-to-edge insets, notification shade, PiP, keyboard/IME, OEM fonts. It is a
`G6` tool; it must not gate `G5`, which has no device guarantee. Instrumented
tests run under `testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"`
(the scaffold default); do not introduce a custom runner. Journeys are
agent-driven with `android layout`, `android input`, and `android screen
capture`; Android CLI exposes no journey subcommand.

## Migrating from the deprecated standalone plugin

`com.android.compose.screenshot` is unmaintained. Do not add it to new modules.
Migration is possible only after AGP `>= 9.5.0-alpha03`; on the current AGP
9.0.1, stay on Roborazzi. Never combine the standalone plugin and AGP test
suites in one module.

| Concept | Standalone plugin (deprecated) | AGP test suites |
|---|---|---|
| Plugin | `com.android.compose.screenshot` `0.0.1-alpha16` | No screenshot plugin; built into AGP test suites |
| Source set | `src/screenshotTest/kotlin/` | `src/{suite}/kotlin/` (for example `src/screenshotTest/kotlin/`) |
| Enable | `android.experimental.enableScreenshotTest=true` | plus `android.experimental.testSuiteSupport=true` |
| Dependencies | `screenshotTestImplementation(...)` | `testOptions.screenshotTests.create(...) { dependencies { ... } }` |
| Update | `./gradlew updateDebugScreenshotTest` | `./gradlew update{Suite}{Target}{Variant}TestSuite` |
| Verify | `./gradlew validateDebugScreenshotTest` | `./gradlew test{Suite}{Target}{Variant}TestSuite` |
| References | `src/screenshotTestDebug/reference/` | `src/{suite}{Target}{Variant}/reference/` |
| Report | `build/reports/screenshotTest/debug/` | `build/reports/tests/{taskName}/index.html` |

A screenshot tool upgrade/migration is a separate gated change: update AGP only
with `02-android-scaffold` rules, record a `DL`, rebuild, re-record baselines,
and review every image diff. Do not smuggle it into a feature test PR.

## Decision rules

1. Device/system UI involved or pixel-perfect proof required → Dropshots at G6.
2. Default visual regression, JVM speed, committed baselines → Roborazzi.
3. Roborazzi cannot render on the host (native graphics/AGP issue) → Paparazzi,
   after a one-test compatibility check.
4. AGP intentionally upgraded to `>= 9.5.0-alpha03` and experimental tooling is
   accepted → AGP test suites, with `DL`.
5. No baseline needed, quick smoke, or debugging a preview → `android preview render`.
6. Never use screenshots to assert business logic, navigation callbacks, or
   accessible labels; those belong in behavior tests.

Recording discipline: record only after an intentional, spec-backed UI change;
review the diff image, not just the green check; keep captures component-scoped
where possible; freeze locale, timezone, screen qualifiers, and font scale; do
not capture clocks, random data, remote images, or animations.
