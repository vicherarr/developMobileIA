# CI recipes

Copy the job that matches the gate you are running. Placeholders that depend on
the runner are marked **[environment-specific]**. Paths assume the pipeline
repository is checked out and the Gradle root is `app_workspace/`; remove the
`working-directory` if your Gradle root is the repository root.

Expected result for every recipe: Gradle exits 0 with `BUILD SUCCESSFUL`, and
the report paths below exist. A job that only prints logs is not evidence.

## 1. PR job: JVM tests, lint, screenshot verification

```yaml
name: android-tests
on:
  pull_request:
  push:
    branches: [main]

jobs:
  jvm:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    defaults:
      run:
        working-directory: app_workspace
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - uses: gradle/actions/setup-gradle@v4
        with:
          cache-read-only: ${{ github.ref != 'refs/heads/main' }}

      - name: Unit tests
        run: ./gradlew :app:testDebugUnitTest --console=plain

      - name: Lint
        run: ./gradlew :app:lintDebug --console=plain

      - name: Screenshot regression
        run: ./gradlew :app:verifyRoborazziDebug --console=plain

      - name: Upload evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-evidence
          path: |
            app_workspace/app/build/reports/tests/
            app_workspace/app/build/test-results/
            app_workspace/app/build/reports/lint-results-debug.*
            app_workspace/app/build/reports/roborazzi/
            app_workspace/app/build/outputs/roborazzi/
            app_workspace/.pipeline/reports/test-*.json
          if-no-files-found: ignore
          retention-days: 14
```

Read on failure: `app/build/test-results/testDebugUnitTest/TEST-<fqcn>.xml`
(first `<failure>`), `app/build/reports/lint-results-debug.html`, and
`app/build/reports/roborazzi/index.html`. Screenshot verify failures also write
`*_compare.png` under `app/build/outputs/roborazzi/`.

If the project does not use Roborazzi, replace the screenshot step with
`./gradlew :app:verifyPaparazziDebug --console=plain`. Do not keep both tasks.

## 2. Manual job: record new screenshot baselines

Run only through `workflow_dispatch`; never auto-commit images from a PR.

```yaml
name: record-screenshots
on:
  workflow_dispatch:
    inputs:
      reason:
        description: Why the baselines change
        required: true

jobs:
  record:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: app_workspace
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.ref }}
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      - uses: gradle/actions/setup-gradle@v4

      - name: Record
        run: ./gradlew :app:recordRoborazziDebug --console=plain

      - uses: actions/upload-artifact@v4
        with:
          name: screenshot-baselines
          path: app_workspace/app/src/test/snapshots/
          retention-days: 7
```

Download the artifact, review every new/changed PNG against the spec, commit it
with the reason, then run the PR job. Do not let a bot push baselines
unreviewed: a visual diff can hide a real regression.

## 3. Nightly or label-gated: emulator smoke

`[environment-specific]` — requires Linux with KVM. GitHub-hosted Ubuntu runners
provide `/dev/kvm`; macOS/Windows runners and many self-hosted runners do not.
The Android CLI is **not** preinstalled on GitHub-hosted images: install it per
`https://developer.android.com/tools/agents`, and ensure SDK platform 36 plus
emulator packages are available.

```yaml
name: device-smoke
on:
  workflow_dispatch:
  schedule:
    - cron: "0 4 * * *"

jobs:
  smoke:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    defaults:
      run:
        working-directory: app_workspace
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      - uses: gradle/actions/setup-gradle@v4

      - name: Create and boot AVD
        run: |
          android emulator create medium_phone
          android emulator start --cold --headless medium_phone

      - name: Build, install, launch
        run: |
          android build :app@debug
          android run --apks=app/build/outputs/apk/debug/app-debug.apk

      - name: Capture layout and screen
        run: |
          mkdir -p .pipeline/artifacts/device
          android layout --pretty --output=.pipeline/artifacts/device/home.json
          android screen capture --annotate --output=.pipeline/artifacts/device/home.png

      - name: Drive the primary journey
        run: |
          android input tap 'text=Add ride' --wait=5000
          android input text 'Oil change' 'class=EditText'
          android input tap 'text=Save' --wait=5000
          android layout --pretty --output=.pipeline/artifacts/device/after-save.json
          android screen capture --annotate --output=.pipeline/artifacts/device/after-save.png

      - name: Instrumented tests
        run: ./gradlew :app:connectedDebugAndroidTest --console=plain

      - name: Upload device evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: device-evidence
          path: |
            app_workspace/.pipeline/artifacts/device/
            app_workspace/app/build/reports/androidTests/
            app_workspace/app/build/outputs/androidTest-results/
          if-no-files-found: ignore

      - name: Stop AVD
        if: always()
        run: android emulator stop medium_phone
```

Pass means the `after-save.json` layout contains the saved item and the
`after-save.png` shows it. A selector timeout in `android input` fails the step;
do not add retries to hide a broken journey. Keep journeys to one per `must`
flow and at most 12 steps.

## 4. Generic CI (no GitHub Actions)

```bash
#!/usr/bin/env bash
# ci-test.sh — run from the pipeline root.
set -euo pipefail
cd "${APP_DIR:-app_workspace}"

./gradlew :app:testDebugUnitTest \
          :app:verifyRoborazziDebug \
          :app:lintDebug \
          --console=plain --build-cache

# Optional device stage (requires a booted emulator):
# ./gradlew :app:connectedDebugAndroidTest --console=plain
```

Archive the same paths as the PR job. With Jenkins/GitLab, publish JUnit XML
from `app/build/test-results/testDebugUnitTest/*.xml` and HTML from
`app/build/reports/`.

## Caching notes

- `gradle/actions/setup-gradle@v4` caches Gradle dependencies and the wrapper;
  don't add a second `~/.gradle` cache for the same job.
- Cache Robolectric's downloaded runtime separately; it is large and rarely
  changes:

```yaml
      - uses: actions/cache@v4
        with:
          path: ~/.m2/repository/org/robolectric
          key: ${{ runner.os }}-robolectric-4.17
          restore-keys: ${{ runner.os }}-robolectric-
```

- Do **not** cache `app_workspace/app/build/` or `app_workspace/.gradle/`.
  Stale task outputs cause false greens.
- `org.gradle.caching=true` is already written by the scaffold. Use
  `--build-cache` on the command line only when the CI backend provides a
  shared build cache.
- Pin the JDK to 17 and keep it identical between PR, record, and device jobs.
  A JDK or renderer change can invalidate screenshot baselines.
- Cache keys for baselines are not cache keys: baselines are committed source,
  not build output.

## Failure handling

- Unit test: read the first `<failure>` in the XML; re-run only that class
  locally with `--tests "*ClassName"`.
- Lint: read the first `Error:` line; warnings are reported, not fatal.
- Screenshot: download `roborazzi` artifacts, compare the reference and actual
  PNG; if the change is intentional, record in the manual job and review.
- Device: download the layout JSON first, then the annotated PNG; a missing
  node is usually a selector or a test-tag problem, not a flaky emulator.
- Never make CI green by adding `|| true`, `continue-on-error`, `-x test`, or
  deleting an assertion. Fix the test or escalate with an `HD`.
