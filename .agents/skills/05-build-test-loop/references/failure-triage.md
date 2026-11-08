# Failure triage catalogue

Reference for `05-build-test-loop`. Each row: symptom → diagnosis command →
fix. Ordered by how often it shows up in agent-driven Android work.

## 0. How to read a Gradle failure

```bash
./gradlew :app:assembleDebug --console=plain --stacktrace 2>&1 | tail -n 60
```

Order of truth:

1. The first `e:` line (Kotlin) or `error:` line (Java/resource).
2. The `* What went wrong:` block.
3. The deepest `Caused by:` — that is usually the real cause.
4. Only then the plugin/task line.

Never act on the last line alone: it is usually a generic wrapper
(`Execution failed for task ...`).

## 1. Environment and toolchain

| Symptom | Diagnosis | Fix |
|---|---|---|
| `SDK location not found` | `echo $ANDROID_HOME; ls app_workspace/local.properties` | write `sdk.dir` (scaffold does), or export `ANDROID_HOME` |
| `Unsupported class file major version 6x` | `./gradlew --version` | AGP 9 wants JDK 17+; point `org.gradle.java.home` or `JAVA_HOME` at 17/21 |
| `Unsupported Java. Gradle ... does not support Java 2x` | `./gradlew --version` | Gradle wrapper too old for the JDK; bump wrapper, not JDK |
| `Read-only file system` writing `~/.gradle` | `ls -ld ~/.gradle` | set `GRADLE_USER_HOME` to a writable path (pipeline uses `.cache/gradle-home`) |
| `Could not resolve ...:9.0.1` | `curl -sI https://dl.google.com/dl/android/maven2/` | network/offline; pre-warm cache or restore `google()` repository |
| `Plugin [id: 'com.android.application' ...] was not found` | check `settings.gradle.kts` `pluginManagement.repositories` | needs `google()`; or `includeBuild` is missing |
| `Timeout waiting to lock ...` | another Gradle daemon | `./gradlew --stop`, then re-run |
| `No space left on device` | `df -h` | clean `~/.gradle/caches` or `build/` |

## 2. AGP 9 specific

| Symptom | Cause | Fix |
|---|---|---|
| `Plugin [id: 'org.jetbrains.kotlin.android'] was not found` | AGP 9 has built-in Kotlin | remove the plugin from root and module files |
| `kapt is not compatible with built-in Kotlin` | kapt with AGP 9 | migrate to KSP2; Hilt/Room support KSP |
| `ClassCastException: ...ApplicationExtensionImpl cannot be cast to BaseExtension` | third-party plugin on legacy DSL | update plugin, or temporarily `android.newDsl=false` (removed in AGP 10 — log it as debt) |
| `android.r8.integratedResourceShrinking is not supported` | removed property | delete it; R8 does resource shrinking |
| `getDefaultProguardFile("proguard-android.txt")` fails | AGP 9 only allows `proguard-android-optimize.txt` | switch the file |
| `-keep class A` no longer keeps constructor (release crash) | strict full mode | write explicit keep rules incl. `<init>()` |
| `compileSdk 37` unsupported | AGP 9.0 max is API 36.1 | use compileSdk 36 or upgrade AGP (gated change) |
| Variant API compile errors in custom plugins | legacy `applicationVariants` | migrate to `androidComponents.onVariants` |

## 3. Kotlin compile

| Symptom | Typical cause | Fix |
|---|---|---|
| `Unresolved reference: viewModelScope` | missing `lifecycle-viewmodel-ktx`/compose artifact | add catalog alias |
| `Unresolved reference: collectAsStateWithLifecycle` | missing `lifecycle-runtime-compose` | add dependency |
| `Unresolved reference: material3` | material3 not in dependencies (BOM alone is not enough) | add `implementation(libs.androidx.compose.material3)` |
| `Smart cast to 'X' is impossible` | mutable/var captured in lambda | local `val`, or `?.let` |
| `@Composable invocations can only happen from the context of a @Composable function` | calling composable outside composition | hoist, or pass state + lambda |
| `Cannot infer type` / `Not enough information to infer T` | generic + lambda | explicit type argument on the call |
| `Overload resolution ambiguity` | duplicate versions on classpath | `./gradlew :app:dependencies --configuration debugCompileClasspath` |
| `Val cannot be reassigned` in state hoisting | param passed by value | add `onValueChange` callback |
| `Function has no parameters but one argument was supplied` | API drift (e.g. nav3) | check the actual signature in the library source |

## 4. KSP / Room / Hilt

| Symptom | Fix |
|---|---|
| `kspDebugKotlin` fails with `Cannot find implementation for X` | add `@Entity`/`@Dao` correctly; make DAOs abstract or interfaces; verify `room-ktx` + `room-compiler` via ksp |
| `Room cannot verify the data integrity` | schema changed without migration | bump `version`, add `Migration`, or `fallbackToDestructiveMigration()` in debug only |
| `Schema export directory is not provided` | set `ksp { arg("room.schemaLocation", "$projectDir/schemas") }` |
| `Hilt: [Dagger/MissingBinding]` | missing `@Inject constructor` / `@Module` provider | provide the binding, or use constructor injection on the ViewModel |
| `Hilt ViewModel must extend ViewModel` | wrong base class | extend `androidx.lifecycle.ViewModel` |
| `@HiltAndroidApp` missing | app class not annotated | annotate `Application` and register in manifest |

## 5. Resources and manifest

| Symptom | Fix |
|---|---|
| `Unresolved reference: R` | namespace mismatch in `build.gradle.kts`; or module without `android` plugin |
| `resource string/foo not found` | missing `strings.xml` entry, or wrong qualifier directory |
| `Android resource linking failed: duplicate value` | same string in two configs without qualifier |
| `Manifest merger failed: android:exported needs to be explicitly specified` | add `android:exported="true|false"` to every component with an intent filter |
| `uses-sdk:minSdkVersion X cannot be smaller than version Y` | a dependency requires a higher minSdk → raise minSdk or exclude the artifact |
| `ClassNotFoundException` on a manifest component | class moved/renamed; fix `android:name` (fully qualified) |

## 6. Tests

| Symptom | Fix |
|---|---|
| `No tests found for :app:testDebugUnitTest` | tests are in `src/test/java|kotlin`; JUnit4 needs `@Test` from `org.junit.Test` |
| `junit.framework.AssertionFailedError` with no message | add messages; assert domain values, not internals |
| `Method ... not mocked` (android.jar) | use Robolectric or extract Android-free logic |
| `IllegalStateException: Module with the Main dispatcher had failed to initialize` | `Dispatchers.setMain(StandardTestDispatcher())` in a rule |
| Test hangs | real dispatcher / real network / infinite flow; inject dispatchers, use `runTest` |
| `UncompletedCoroutinesError` | leaked scope; cancel the subject or use `backgroundScope` |
| Flaky ordering | `Flow`/`SharedFlow` without `testScheduler`; use Turbine `awaitItem()` |
| Screenshot differs by a few pixels | font rendering/anti-aliasing; pin device density + `fontScale`, or use a tolerant comparator |
| `@Preview` not found by `android preview list` | preview function must be top-level/annotated and in a source set included in the build |

## 7. Compose runtime

| Symptom | Fix |
|---|---|
| Screen blank in preview | state defaults to loading; provide a preview with explicit `Success` state |
| `LazyColumn` item duplicate key crash | stable unique keys; never index-based keys for mutable lists |
| Infinite recomposition | state written during composition; move to `LaunchedEffect`/`remember` |
| `IllegalArgumentException: Key ... was already used` | nav back stack duplicate; use `distinct` or typed keys |
| ANR in tests | busy loop on main thread; move work to injected dispatcher |

## 8. When to stop triaging

Escalate with an `HD` when any is true:

- 3 informed attempts on the same error class.
- The fix requires changing a dependency version (gated change).
- The fix requires a product decision.
- The failure points at a Google-side bug (check the issue tracker via
  `android docs search`) and a workaround would hide a real defect.
