# Tech Stack — <app-name>

<!--
Single source of truth for versions. Bootstrap copies this file to
`00_memory/TECH_STACK.md`.

Rules:
- Every version that ships appears here AND in `gradle/libs.versions.toml`.
- Any change to one is made together with the other, in the same change.
- A mismatch is a defect: fix it before writing gate evidence.
- SDK levels and the JVM toolchain live in the module build file; mirror them here.
- Do not duplicate versions in ARCHITECTURE.md or feature docs.

The baseline below is the official `android create` template, already pinned by
the scaffold. Replace values only through a recorded upgrade.
-->

| Field | Value |
|---|---|
| Last reconciled with `gradle/libs.versions.toml` | `<YYYY-MM-DD>` |
| Catalog path | `gradle/libs.versions.toml` |
| Verified by | `<agent role>` |

## 1. Build and toolchain

<!-- Mirrors [versions] plus the Gradle wrapper and module build settings. -->

| Item | Pinned | Source of truth | Rationale |
|---|---|---|---|
| Android Gradle Plugin | `9.0.1` | catalog `[plugins]` | Scaffold baseline |
| Gradle wrapper | `9.1.0` | `gradle/wrapper/gradle-wrapper.properties` | AGP 9 requires ≥ 9.1.0 |
| Kotlin | `2.3.20` | catalog `[plugins]` | Compose compiler plugin bundled |
| JDK / JVM toolchain | `17` | module `build.gradle.kts` | AGP 9 minimum |
| `compileSdk` | `36` | module `build.gradle.kts` | Scaffold baseline |
| `targetSdk` | `36` | module `build.gradle.kts` | Scaffold baseline |
| `minSdk` | `24` | module `build.gradle.kts` | Scaffold baseline |
| Version catalog | `gradle/libs.versions.toml` | repo | Single source for dependency coordinates |

## 2. Runtime dependencies

<!-- Shipped libraries only. One row per artifact. -->

| Artifact | Version | Why it is here | Added by |
|---|---|---|---|
| `androidx.compose:compose-bom` | `2026.03.01` | Aligns all Compose artifacts | scaffold |
| `androidx.core:core-ktx` | `1.18.0` | Kotlin extensions for framework APIs | scaffold |
| `androidx.activity:activity-compose` | `1.13.0` | Compose-enabled `ComponentActivity` | scaffold |
| `androidx.lifecycle:lifecycle-*` | `2.10.0` | ViewModel and lifecycle-aware collection | scaffold |
| `androidx.navigation3:navigation3-runtime` | `1.0.1` | Navigation 3 back stack | scaffold |
| `androidx.navigation3:navigation3-ui` | `1.0.1` | Nav3 scene rendering | scaffold |
| `androidx.lifecycle:lifecycle-viewmodel-navigation3` | `2.10.0` | ViewModel scoping per Nav3 entry | scaffold |
| `<additional artifact>` | `<version>` | `<one line>` | `DL-###` |

## 3. Evaluated, not adopted

<!-- Available and compatible, but not on the classpath. Adopting any of these
     requires a DL-### first. Versions listed are the latest stable seen in the
     wild on 2026-11-08, not a recommendation. -->

| Candidate | Version seen | Would replace | Status |
|---|---|---|---|
| Room | `2.8.5` | hand-rolled persistence | not adopted |
| Hilt | `2.60.1` | manual DI + `AppContainer` | not adopted (default is manual DI) |
| KSP | `2.3.13` | kapt (incompatible on AGP 9) | required only with Hilt/Room codegen |
| Roborazzi | `1.78.0` | none | not adopted |
| Paparazzi | `1.3.5` | none | not adopted |
| MockK | `1.14.12` | fakes | not adopted |
| Turbine | `1.2.1` | manual flow collection in tests | not adopted |

## 4. Compose, testing, and DI policy

| Area | Default | Opt-in |
|---|---|---|
| UI | Compose, Material 3, single theme module | none |
| DI | Manual constructor injection + `AppContainer` | Hilt + KSP |
| Local tests | JUnit4 plus fakes | MockK, Turbine |
| Screenshot tests | none until a `DL-###` | Roborazzi or Paparazzi |
| Instrumented tests | Compose UI test on device | none |

## 5. AGP 9 constraints

<!-- A change that violates one of these is a defect even if a local build passes. -->

- AGP 9 has built-in Kotlin support: **never** apply `org.jetbrains.kotlin.android`.
- `kapt` is incompatible with AGP 9. Use KSP2 for annotation processing.
- Gradle must be `>= 9.1.0`; JDK must be 17.
- The Compose compiler is the Kotlin plugin (`org.jetbrains.kotlin.plugin.compose`), versioned with Kotlin.
- AGP, Gradle, and Kotlin move together: bumping one requires checking the other two.

## 6. Catalog layout

<!-- Shape to preserve in gradle/libs.versions.toml. -->

```toml
[versions]
agp = "9.0.1"
kotlin = "2.3.20"
composeBom = "2026.03.01"

[libraries]
androidx-core-ktx = { group = "androidx.core", name = "core-ktx", version.ref = "coreKtx" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
```

## 7. Upgrade rules

1. Read the current row here and the matching catalog entry; they must already agree.
2. Check the constraint table in section 5 before choosing a version.
3. Change the catalog version, then the consuming build file if needed.
4. Update the row here in the same change, with the reason on one line.
5. Append a `DL-###` for any major or behavior-changing bump.
6. Rebuild and re-test; attach the evidence path.
7. Never bump a version "while passing through" without updating this file.

## 8. Drift check

- [ ] Every shipped row in section 2 has a catalog entry with the same version.
- [ ] Every shipped catalog entry has a row in section 2.
- [ ] Gradle wrapper version equals section 1.
- [ ] `compileSdk`, `targetSdk`, `minSdk`, and the JVM toolchain appear in the module build file and match section 1.
- [ ] No version number is duplicated in `ARCHITECTURE.md` or any feature doc.
- [ ] The last-reconciled date above is today's session date.

## 9. Changelog

| Date | Change | Decision |
|---|---|---|
| `<YYYY-MM-DD>` | Scaffold baseline pinned | `DL-000` |
