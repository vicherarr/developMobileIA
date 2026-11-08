# AGP 9 baseline and version policy

Snapshot verified on **2026-11-08** from the official `android create` template
(`empty-activity`), Google Maven and the AGP 9.0 release notes. Treat this file
as the reference for `TECH_STACK.md`; if they disagree, the build report from
`02-android-scaffold` wins and this file is stale.

## What the generator gives you

| Component | Template value | Notes |
|---|---|---|
| AGP | `9.0.1` | built-in Kotlin, new DSL only |
| Gradle wrapper | `9.1.0` | AGP 9 minimum and default |
| Kotlin (Compose compiler plugin) | `2.3.20` | KGP is a runtime dependency of AGP 9 (min 2.2.10) |
| Compose BOM | `2026.03.01` | Compose artifacts stay versionless |
| `androidx.core:core-ktx` | `1.18.0` | |
| `androidx.activity:activity-compose` | `1.13.0` | |
| `androidx.lifecycle` | `2.10.0` | runtime-compose, viewmodel-compose, viewmodel-navigation3 |
| Navigation 3 | `navigation3-runtime` / `navigation3-ui` `1.0.1` | declarative back stack |
| compileSdk / targetSdk | `36` | AGP 9.0 supports up to API 36.1 |
| minSdk | `24` | |
| Java target | `17` (toolchain) | AGP 9 minimum JDK |
| Test libs | JUnit 4.13.2, coroutines-test, Compose ui-test, androidx.test | |

## AGP 9 rules that break naive code

1. **Built-in Kotlin.** `org.jetbrains.kotlin.android` must not be applied. Only
   the Compose compiler plugin and the serialization plugin remain.
2. **kapt is incompatible.** Use KSP2 (`com.google.devtools.ksp`). AGP upgrades
   KSP to match KGP unless you override it in the root `buildscript`.
3. **New DSL only.** Legacy variant API (`applicationVariants`, `variantFilter`)
   is gone. Use `androidComponents.onVariants` / `beforeVariants`.
4. **R8 defaults changed.** Full mode on, optimized resource shrinking on,
   `proguard-android-optimize.txt` only, and `-keep class A` no longer implies
   keeping the default constructor.
5. **Stricter defaults.** `android.useAndroidX=true`, unique package names,
   `targetSdk` defaults to `compileSdk`, missing proguard files fail the build.
6. **compileSdk ceiling.** AGP 9.0 tops out at API 36.1; API 37 needs a newer
   AGP.

## Version policy

- **Exact pins only.** No `+`, no ranges. One place: `gradle/libs.versions.toml`.
- **The template set is the safe set.** AGP, KGP, Compose BOM and Navigation are
  a tested combination; bump them together or not at all.
- **Every bump is a gated change:** bump → `05-build-test-loop` green → screenshot
  comparison → device smoke → `DL` entry → update `TECH_STACK.md`.
- **Never mix** a version bump into a feature change.

## Check the current stable version (do not guess)

```bash
# Google-hosted artifacts (AGP, AndroidX)
curl -s https://dl.google.com/dl/android/maven2/androidx/room/room-runtime/maven-metadata.xml \
  | grep -o '<release>[^<]*'
curl -s https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml \
  | grep -oE '<version>[^<]*' | grep -vE 'alpha|beta|rc' | tail -n 3

# Maven Central (Kotlin, KSP, Ktor, Roborazzi, ...)
curl -s https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml \
  | grep -oE '<version>[^<]*' | grep -vE 'Beta|RC|dev' | tail -n 3

# With Android Studio connected
android studio version-lookup androidx.compose:compose-bom com.google.dagger:hilt-android
```

Also useful: `android sdk list --available`, `android docs search "AGP 9 release"`.

## Upgrade lanes (only when a task requires them)

| Need | Lane | Prerequisite |
|---|---|---|
| API 37 / newer AGP features | AGP 9.5.x + compileSdk 37 | Gradle wrapper matching, full loop green, `DL` |
| Latest Compose | bump BOM only | Material 3 API changes checked in previews |
| Newer Kotlin | AGP runtime KGP matrix | override via root `buildscript` only if AGP 9 min is satisfied |
| Screen-level testing | AGP test suites (AGP 9.5+alpha engine) or Roborazzi | see `06-testing-strategy` |

Official upgrade skill: `android skills add agp-9-upgrade` (from the Android
skills repository). Prefer it over manual migration for existing projects.

## Deprecated / removed — do not add to new projects

- `com.android.compose.screenshot` (standalone screenshot plugin) — replaced by
  AGP test suites; Roborazzi/Paparazzi remain valid alternatives.
- `kotlin-kapt`, `kotlin-android`.
- `android.newDsl=false`, `android.builtInKotlin=false` (removed in AGP 10).
- Density split APKs (`splits.density`) — use App Bundles.
- `proguard-android.txt`.
