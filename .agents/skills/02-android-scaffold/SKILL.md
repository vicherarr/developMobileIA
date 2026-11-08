---
name: 02-android-scaffold
description: Creates and verifies the Android Gradle project tree for the pipeline using Android CLI and the official template, then pins versions and records them in memory. Use when starting the project, recreating a broken workspace, adding Gradle modules, configuring the version catalog or build flags, or when the build cannot even start. Triggers - scaffold, create project, android create, gradle setup, module, libs.versions.toml, AGP 9, version catalog, build.gradle.kts, settings.gradle.kts, local.properties.
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Android scaffold (G2)

Start from the official generator, never from a hand-written Gradle file. A
hand-written `build.gradle.kts` from memory is the single most common way an
agent produces a project that never compiles.

## Contract

- **Reads:** `app_workspace/.pipeline/spec.json`, `00_memory/TECH_STACK.md`
- **Writes:** `app_workspace/**` (project), `app_workspace/.pipeline/reports/scaffold-<UTC>.json`,
  `00_memory/TECH_STACK.md`, append `00_memory/DECISION_LOG.md`,
  update `STATE.json`
- **Gate:** `G2` — a project that **builds** `:app@debug`
- **Handoff:** `03-domain-and-data` (G3)

## Step 1 - Preflight

```bash
android -V                      # CLI installed and working
android info                    # SDK path + config
android sdk list --installed    # platforms;android-36 and build-tools must exist
java -version                   # JDK 17+ (AGP 9 minimum); 17 is the toolchain target
```

If `android` writes fail with `Read-only file system`, the agent sandbox is
blocking the CLI's cache under `$HOME/.android/cli` or SDK writes under
`$ANDROID_HOME`. Pipeline scripts already redirect HOME to
`<pipeline>/.cache/android-cli-home`; SDK package installs still need real
write access. Re-run that step outside the sandbox or fix permissions — do not
work around it by copying random jars.

## Step 2 - Generate from the official template

`android create` exists in **two incompatible signatures**, depending on the
CLI *bundle* the installed CLI resolves (the binary version can be identical):

| Interface | Flags | Constraints |
|---|---|---|
| `legacy` | `--name`, `--minSdk`, `-o`, `[template]` | output dir must be **empty**, no `--force`, **exits 0 even on failure** |
| `current` | `--name`, `--min-sdk`, `--application-id`, `--namespace`, `--output`, `--force` | documented on developer.android.com |

Probe it before using it:

```bash
android create -h | grep -c -- '--application-id'   # 1 = current, 0 = legacy
```

Never call `android create` directly from a skill: the wrapper handles both.

```bash
.agents/skills/02-android-scaffold/scripts/scaffold_project.sh --dry-run  # inspect the plan
.agents/skills/02-android-scaffold/scripts/scaffold_project.sh            # create + verify
```

What the script guarantees, whichever interface is installed:

1. **Staging**: generates into `mktemp -d` and merges into `app_workspace`, so an
   existing `.pipeline/` or `README.md` never trips the "directory is not empty"
   rule, and no `--force` is needed for the CLI.
2. **Package normalization**: the legacy interface ignores
   `--application-id`/`--namespace` and derives the package from the app name
   (`Example App` → `com.example.exampleapp`). The script moves the source
   directories and rewrites references to the `applicationId` from `spec.json`.
3. **SDK levels from the spec**: `minSdk`/`compileSdk`/`targetSdk` from
   `spec.json` override the template. This matters: a current template may ship
   `compileSdk 37` while the pinned AGP 9.0.1 supports up to 36.1.
4. **Artifact validation**: success is `gradlew` + `settings.gradle.kts` present,
   never the CLI exit code.
5. **`--force`** replaces the previous project files but keeps `.pipeline/` and
   `README.md`.

`android create --list` shows templates:

| Template | Use |
|---|---|
| `empty-activity` (default) | Compose + Activity + AGP 9 — **use this** |
| `empty-activity-lightbuild` | experimental build backend; not the default |

Run the pipeline wrapper, which adds the deterministic post-processing and the
verification build:

```bash
.agents/skills/02-android-scaffold/scripts/scaffold_project.sh --dry-run   # inspect first
.agents/skills/02-android-scaffold/scripts/scaffold_project.sh             # create + verify
```

It is idempotent by refusal: it will not overwrite an existing `gradlew` unless
you pass `--force`. Re-running with `--force` replaces generated files — treat
that as a destructive operation and confirm with the human first.

## Step 3 - Know what you got

The template is the baseline of truth. Do not "modernize" it blindly:

| Item | Template value | Rule |
|---|---|---|
| AGP | `9.0.1` | AGP 9 = built-in Kotlin; **never** apply `org.jetbrains.kotlin.android`; kapt is incompatible |
| Gradle wrapper | `9.1.0` | AGP 9 requires >= 9.1.0; do not downgrade |
| Kotlin (Compose compiler plugin) | `2.3.20` | bump only together with AGP and a green build |
| Compose BOM | `2026.03.01` | all Compose artifacts are versionless via the BOM |
| compileSdk / targetSdk | from `spec.json` (default `36`) | AGP 9.0 supports up to API 36.1; a newer template may say 37 |
| minSdk | `24` | lower only with a written reason (desugaring, market) |
| Java toolchain | `17` | matches AGP 9 requirement |
| Navigation | Navigation 3 (`navigation3-runtime`/`ui`) | declarative back stack, `@Serializable` keys |
| Version catalog | `gradle/libs.versions.toml` | the only place versions live |

Detailed baseline and upgrade rules: `references/agp9-baseline.md`.

## Step 4 - Decide the module layout (once, on purpose)

Default: **single `:app` module with package boundaries**. Split into Gradle
modules when at least one is true:

- build time is dominated by one huge module (usually > 60 s incremental),
- two features need different `minSdk`/dependencies,
- a library is published or shared with another app.

When splitting, the pipeline convention is:

```
app_workspace/
├── app/                      # Activity, navigation host, DI container
├── core/
│   ├── design-system/        # theme, tokens, shared composables
│   ├── database/             # Room database, entities, DAOs
│   ├── network/              # HTTP client, DTOs
│   └── common/               # Result types, dispatchers, utils
└── feature/
    └── <name>/               # screen + ViewModel + tests
```

Each new library module needs three edits, in this order:

1. `settings.gradle.kts`: `include(":core:design-system")`
2. `gradle/libs.versions.toml`: add the plugin/library aliases
3. `<module>/build.gradle.kts`: `alias(libs.plugins.android.library)` +
   `namespace`, `compileSdk`, `minSdk`, `buildFeatures { compose = true }`

Then run the loop (`05-build-test-loop`) — a module graph that does not build is
worthless. Record the split as a `DL` entry.

## Step 5 - Pin versions and sync memory

`TECH_STACK.md` must match `gradle/libs.versions.toml` exactly. After
scaffolding, copy the generated versions into it (the script prints and records
them in the report). Rules:

- Versions are **exact**, never ranges or `+`.
- Adding a dependency = adding a catalog alias + a `TECH_STACK` row in the same
  change.
- Upgrades are a separate, gated task: bump → build → tests → device check →
  log `DL`. Never mix an upgrade into a feature change.
- To check the current stable version, query the registry rather than guessing:

```bash
android studio version-lookup androidx.compose.ui:ui   # when Android Studio is connected
curl -s https://dl.google.com/dl/android/maven2/androidx/room/room-runtime/maven-metadata.xml | grep -o '<release>[^<]*'
```

## Step 6 - Verify and report

The verification build is the gate:

```bash
android build ':app@debug'
```

Pass requires a resolved build with an APK. Evidence is
`reports/scaffold-<UTC>.json` with `"status":"pass"`. A project that generates
but does not build leaves `G2` open — the status is `fail`, never `pass` with a
warning.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Read-only file system` on `$HOME/.android` | sandboxed HOME | pipeline redirects HOME; if it persists, `ANDROID_CLI_HOME=<writable>` |
| `Read-only file system` on SDK package install | SDK not writable | run with SDK write access or pre-install packages |
| `Unsupported class file major version` | JDK too old/new for Gradle | JDK 17+; `./gradlew --version` to confirm |
| `Could not resolve com.android.tools.build:gradle:9.0.1` | offline / repo filters | needs `google()` in `settings.gradle.kts`; check network |
| `Plugin [id: 'org.jetbrains.kotlin.android'] was not found` | AGP 9 built-in Kotlin | delete the plugin; it must not be applied |
| `kapt is not compatible` | AGP 9 built-in Kotlin | use KSP2 (`com.google.devtools.ksp`) |
| Gradle distribution download fails | proxy/offline | pre-warm `GRADLE_USER_HOME` or vendor the distribution |
| `SDK location not found` | no `local.properties` | script writes `sdk.dir`; else set `ANDROID_HOME` |
| `Cannot create template: Directory ... is not empty` | legacy bundle requires an empty output dir | never point it at `app_workspace`; the script uses staging |
| `Unknown options: '--application-id=...'` | legacy bundle signature | let the script probe capabilities; do not hardcode flags |
| `Package platforms/android-37 not found` | template asks for an SDK package that the repo/channel does not publish | harmless warning if the project still generates; keep `compileSdk` from the spec |
| `android create` exits 0 but no project exists | legacy bundle swallows errors | validate `gradlew` + `settings.gradle.kts`, not the exit code |

## Anti-patterns

- **Do NOT** write `settings.gradle.kts`/`build.gradle.kts` from memory instead
  of running the generator.
- **Do NOT** trust `android create`'s exit code; it returns 0 on some failures.
- **Do NOT** point `android create` at `app_workspace` directly; use the staging
  script or the legacy bundle will refuse a non-empty directory.
- **Do NOT** add dependencies with hardcoded versions inside module files; use
  the catalog.
- **Do NOT** apply `kotlin-android`, `kotlin-kapt`, or `com.android.compose.screenshot`
  (deprecated, replaced by AGP test suites).
- **Do NOT** enable `android.newDsl=false` or `android.builtInKotlin=false` to
  make an old plugin work — replace the plugin.
- **Do NOT** commit `local.properties`, keystores, or `build/`.
- **Do NOT** mark `G2` pass on a `--dry-run`, on a warning, or on "it generated".

## Stop conditions

- SDK/CLI cannot write anywhere and no writable workaround exists → `HD`
  (environment), stop.
- The template needed does not exist (`android create --list`) → `HD` with the
  closest option and the tradeoff.
- The generated project cannot build because the JDK is incompatible and cannot
  be changed in this environment → `HD` (environment).
