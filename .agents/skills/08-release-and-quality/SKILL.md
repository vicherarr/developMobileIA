---
name: 08-release-and-quality
description: Runs the pre-release quality gate G7 for the generated Android app. Builds the release AAB and APK with R8 and resource shrinking, runs lint and unit tests, analyzes size and optimization output, compares the APK against the stored size baseline, scans manifests and sources for hardcoded secrets, missing android:exported, usesCleartextTraffic, debuggable release builds and signing leaks, then emits reports/quality-<UTC>.json with pass or fail findings. Use when preparing a Play Store release, signing an AAB, checking R8, minify or ProGuard keep rules, shrinking app size, fixing lint errors, validating targetSdk levels, 64-bit support, data safety or permissions, or triaging a release-only regression. Triggers - release, release build, bundleRelease, assembleRelease, AAB, APK, R8, minify, ProGuard, keep rules, shrinking, size budget, baseline, lint, quality gate, Play, Play Console, signing, keystore, targetSdk, 64-bit, data safety, permissions, debuggable, cleartext, exported, G7.
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Release and quality (gate G7)

G7 turns a verified app into an uploadable one. The gate is objective: a
release build with R8, lint, unit tests, size evidence and manifest/signing
hygiene, recorded in `app_workspace/.pipeline/reports/quality-<UTC>.json` with
`status` `pass` or `fail`. The gate never edits sources. When a check fails you
fix the app, then run the gate again.

## Contract

- **Reads:** the release-ready project, `spec.json` constraints,
  `00_memory/TECH_STACK.md`, and the `G5` evidence in `reports/verify-*.json`.
- **Writes:** `reports/quality-<UTC>.json`, raw `artifacts/analyze-*-<UTC>.json`,
  and `artifacts/size-baseline.json` on the first run.
- **Gate:** `G7`.
- **Handoff:** pipeline complete on pass; on failure, back to
  `05-build-test-loop` (code defects) or `09-human-review` (release decisions
  such as signing material or policy risk).

## Preconditions

1. `app_workspace/.pipeline/reports/device-<UTC>.json` exists and says `pass`
   (G6), with PNGs in `app_workspace/.pipeline/artifacts/`.
2. `app_workspace/.pipeline/spec.json` defines the release scope; no blocking
   `HD-###` is open in `02_pending_review/human_decisions.md`.
3. Release signing is a human decision. If the spec does not say how the AAB is
   signed and distributed, open an HD before touching signing configuration.
4. Record the current baseline and gate intent in `00_memory/SESSION_STATE.md`.

## One command

```bash
.agents/skills/08-release-and-quality/scripts/quality_gate.sh
```

Expected tail on success:

```text
status: pass
PASS report=app_workspace/.pipeline/reports/quality-20261108T160542Z.json errors=0 warnings=1 apk_bytes=4823110
```

Read the evidence before claiming the gate:

```bash
jq -e '.status=="pass" and .build.exit_code==0 and (.counts.errors==0)' \
  "$(ls -t app_workspace/.pipeline/reports/quality-*.json | head -1)"
echo "G7 evidence OK"
```

## What the gate runs

| Step | Command | Pass criteria |
|---|---|---|
| Build, lint, tests | `./gradlew :app:assembleRelease :app:lintRelease :app:testDebugUnitTest` | exit 0, no lint errors, tests green |
| Artifacts | locate `app/build/outputs/bundle/release/app-release.aab` and `app/build/outputs/apk/release/*.apk` | both exist, sizes recorded |
| R8 / optimization | `android analyze <apk> --analysis=optimization -f json` | command succeeds, raw output stored |
| Size / basic | `android analyze <apk> --analysis=basic -f json` | command succeeds, raw output stored |
| Size budget | compare APK bytes with `artifacts/size-baseline.json` | growth ≤ `--size-limit-pct` (default 10) |
| Secrets | source scan | no hardcoded keys, tokens, passwords, private keys |
| Manifest | `android:exported`, `usesCleartextTraffic`, `debuggable`, merged release manifest | no missing exported on filtered components, no cleartext, not debuggable |
| SDK levels | `app/build.gradle.kts` | `targetSdk` present and ≥ 36 |
| Signing | `keystore.properties` ignored, release `signingConfig` present | no secret leak, uploadable signing path |
| R8 keep rules | scan of the gradle log | no unresolved `Missing class` warnings |

## Release build and R8

```bash
./gradlew :app:bundleRelease
# app/build/outputs/bundle/release/app-release.aab
./gradlew :app:assembleRelease
# app/build/outputs/apk/release/app-release.apk
```

AGP 9.0.1 R8 defaults are not the old defaults. Full mode is on, the default
rule file is `proguard-android-optimize.txt` only, and optimized resource
shrinking is enabled. Debug builds skip minification, so only a release build
proves R8 behavior. Two consequences dominate failures:

- `-keep class com.example.Foo` keeps the class but no longer keeps its default
  constructor. Add `-keep class com.example.Foo { <init>(); }` when reflection,
  serialization or a framework instantiates it.
- kapt is incompatible with AGP 9; keep KSP2. If a generated class disappears,
  fix the KSP configuration or add a narrow keep rule, never widen to
  `-keep class ** { *; }`.

```bash
ls -l app/build/outputs/mapping/release/mapping.txt
```

No `mapping.txt` means R8 did not run as expected or the build did not complete;
treat that as a finding, not cosmetics. Keep `mapping.txt` for Play
deobfuscation.

### Keep-rule workflow

1. Reproduce the crash on a release build (`07-device-verification`, release
   spot check).
2. Identify the stripped class from the stack trace and `mapping.txt`.
3. Install the analyzer skill once: `android skills add r8-analyzer`, then use
   it to read the analyze output.
4. Add the narrowest rule to `proguard-rules.pro`.
5. Rebuild, reinstall, replay the journey, and re-run this gate.

Never disable minification, resource shrinking or R8 full mode to make a
release crash disappear. That trades a debuggable failure for a size and
performance regression.

## Size evidence and the baseline

```bash
android analyze app/build/outputs/apk/release/app-release.apk --analysis=optimization -f json
android analyze app/build/outputs/apk/release/app-release.apk --analysis=basic -f json
```

The gate stores raw output as `artifacts/analyze-optimization-<UTC>.json` and
`artifacts/analyze-basic-<UTC>.json`, then compares APK bytes against
`artifacts/size-baseline.json`:

```json
{"schema":1,"generated_utc":"2026-11-08T16:05:42Z","apk":"app/build/outputs/apk/release/app-release.apk","apk_bytes":4823110,"aab_bytes":3901002}
```

- First run with no baseline creates it and records an info finding.
- Growth above the limit is an error finding and fails the gate.
- `--write-baseline` adopts the current build. That is a human decision: log it
  in `DECISION_LOG.md` (`DL-###`) with the reason before using it.
- Do not delete or hand-edit the baseline to silence a regression. Find what
  grew first: new dependency, unshrunk resource, duplicated asset, native libs.

Baseline profiles and Macrobenchmark are an optional upgrade at G7: add them
when startup or scroll performance is a stated requirement, not as a gate
prerequisite.

## Signing

Debug builds are signed with the auto-generated debug keystore. Release signing
must come from an ignored `keystore.properties` consumed by `signingConfigs`,
or from Play App Signing in CI. A sketch:

```kotlin
val keystoreProperties = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
android {
    signingConfigs {
        create("release") {
            storeFile = file(keystoreProperties.getProperty("storeFile"))
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
        }
    }
    buildTypes { release { signingConfig = signingConfigs.getByName("release") } }
}
```

Rules:

- Never commit `keystore.properties`, `*.jks` or `*.keystore`.
- Never hardcode passwords in Gradle files, CI YAML or Kotlin sources.
- CI supplies secrets through environment variables; the file is materialized
  at build time and deleted after.
- Never change the signing configuration to debug to make an install succeed.
- Play App Signing is the default recommendation; the upload key is not the app
  signing key.

Optional verification when build-tools are present:

```bash
"$ANDROID_SDK/build-tools/36.0.0/apksigner" verify --print-certs \
  app/build/outputs/apk/release/app-release.apk
```

## Play readiness

Use `references/play-checklist.md` for the full checkable list. Minimum bar:

- **Manifest**: every component with an intent filter declares
  `android:exported`; no exported component without a reason; no
  `android:debuggable="true"`; no `usesCleartextTraffic="true"`.
- **SDK levels**: `compileSdk` and `targetSdk` 36, `minSdk` 24, JVM 17. Confirm
  `targetSdk` against the Play policy in force at submission time.
- **64-bit**: if native code exists, the AAB ships 64-bit ABIs; no
  `abiFilters` that drop them.
- **Permissions**: every dangerous or sensitive permission has a user-facing
  justification and, where applicable, the Play permissions declaration.
- **Data safety**: the Play data safety form matches what the app actually
  collects, stores and shares; privacy policy URL is live.
- **Accessibility**: TalkBack path verified at G6; content descriptions and
  touch targets pass.
- **Adaptive / edge-to-edge**: edge-to-edge is mandatory for targetSdk 35+;
  layouts survive phone, tablet and foldable widths; predictive back works and
  no legacy `onBackPressed` intercepts remain.
- **Size**: within budget; `android analyze` output reviewed for unexpected
  classes, resources or native libs.
- **Crash monitoring**: a release crash would be visible (Play vitals or an
  equivalent sink); no swallowed exceptions on the main journey.

Install official guidance with
`android skills add edge-to-edge|adaptive|r8-analyzer|android-permissions-security|jetpack-compose-performance|android-profiler`
and follow it instead of improvising.

## `quality_gate.sh` reference

| Flag | Effect |
|---|---|
| `--skip-analyze` | Skip `android analyze`; size/R8 evidence is then absent and the report warns |
| `--write-baseline` | Adopt this build as the new size baseline (human decision) |
| `--size-limit-pct N` | Allowed APK growth vs baseline, default 10 |
| `--dry-run` | Print the plan, detect paths, change nothing |
| `--help` | Usage, exit 0 |

Outputs, all under `app_workspace/.pipeline/`:

```text
reports/quality-<UTC>.json           status, findings, counts, sizes
artifacts/quality-gradle-<UTC>.log   full gradle output
artifacts/analyze-optimization-<UTC>.json
artifacts/analyze-basic-<UTC>.json
artifacts/size-baseline.json         created on first run or with --write-baseline
```

Exit codes: `0` pass, `1` fail (gradle failure or any error-severity finding).
The script is read-only with respect to sources; it writes only inside the state
directory.

Report shape:

```json
{
  "schema": 1,
  "gate": "G7",
  "kind": "quality-gate",
  "status": "fail",
  "timestamp": "20261108T160542Z",
  "build": {"command": "./gradlew :app:assembleRelease :app:lintRelease :app:testDebugUnitTest", "exit_code": 0, "log": "..."},
  "artifacts": {"apk": "...", "apk_bytes": 4823110, "aab": "...", "aab_bytes": 3901002, "mapping": "..."},
  "size": {"baseline_apk_bytes": "4600000", "apk_bytes": 4823110, "growth_pct": "4.85", "limit_pct": 10, "baseline_written": false},
  "findings": [{"severity": "error", "check": "cleartext-traffic", "detail": "...:12 usesCleartextTraffic=true"}],
  "counts": {"errors": 1, "warnings": 2}
}
```

## Interpreting findings

| Check | Meaning | Fix |
|---|---|---|
| `gradle` | build, lint or test failed | read `quality-gradle-<UTC>.log`, fix one cause, rerun |
| `lint` | lint found errors | fix the reported issues; do not baseline them away |
| `hardcoded-secret` | key/token/password literal in sources | move to local properties or backend, rotate the leaked value |
| `cleartext-traffic` | HTTP allowed in release | use HTTPS; restrict `networkSecurityConfig` to debug only |
| `manifest-exported` | component with intent filter lacks `android:exported` | declare `true`/`false` explicitly with intent |
| `debuggable-release` | debug flag reaches a release path | remove it from main/flavor manifests |
| `sdk-levels` | `targetSdk` missing or below 36 | align with the verified baseline |
| `signing-hygiene` | keystore material may be committed | add to `.gitignore`, rotate, remove from history |
| `signing-config` | no release signing config | configure `keystore.properties` + `signingConfigs` or Play App Signing |
| `r8-keep-rules` | unresolved classes after shrinking | add narrow keep rules, reinstall release build |
| `r8-mapping` | `mapping.txt` missing | confirm `assembleRelease` completed and R8 ran |
| `size-regression` | APK grew beyond budget | inspect `android analyze` output, shrink or justify |
| `merged-manifest` | no merged release manifest | run `:app:assembleRelease` before the gate |
| `artifact-missing` | APK or AAB absent | fix the build, do not hand-assemble outputs |

## Stop conditions

- Gradle fails twice for the same reason: fix one thing, otherwise escalate.
- Lint reports an error the team wants to ignore: that is a human decision, not
  a config tweak; open an HD.
- R8 crashes the release build: one keep-rule iteration, verify on a device,
  then escalate if it persists.
- Size regression cannot be attributed to a change you understand: stop and
  report before shipping.
- Signing material is missing or shared by a human channel: stop and open an HD.
- `targetSdk` policy is ambiguous for the current Play requirements: confirm,
  then log the decision.

## Do NOT

- Do NOT edit application sources, manifests or Gradle configuration from
  inside the gate to turn findings green; fix the app and rerun.
- Do NOT rewrite `size-baseline.json` to hide growth; a baseline change is a
  human decision recorded as `DL-###`.
- Do NOT disable minify, shrinking or R8 full mode to silence a keep-rule
  failure.
- Do NOT sign release artifacts with the debug keystore or commit a keystore.
- Do NOT treat `assembleRelease` success as Play-ready: lint, tests, size,
  signing and device evidence are separate gates.
- Do NOT upload an AAB whose `targetSdk` is below the current policy or that
  ships no 64-bit native libraries.
- Do NOT ignore `Missing class` or `can't find referenced class` R8 warnings.
- Do NOT claim G7 from a report you did not read or from a previous session's
  report.

## Handoff

On `pass`: record the report path, APK/AAB sizes, growth percentage, baseline
state and signing method in `SESSION_STATE.md`; append any reversible choice to
`DECISION_LOG.md`. State clearly what remains unverified (for example Play
Console data safety review, which is a human action). On `fail`: keep every
artifact, write the single blocking finding in `SESSION_STATE.md`, and either
fix the app or open an `HD-###` with the evidence path. G7 is complete only
when the quality report says `pass` and the human release decision is recorded.
