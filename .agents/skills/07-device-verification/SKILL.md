---
name: 07-device-verification
description: Verifies the generated Android app on an emulator or physical device and produces gate G6 evidence. Boots or attaches one target, delta-installs and launches the debug app, captures annotated screenshots and UI hierarchies, drives an accessibility-tree-first visual journey (perceive, decide, act, assert), asserts visible text and nodes, and scans logcat for crashes and ANRs. Use when you must run the app, boot an emulator or AVD, install or relaunch, take a screenshot, inspect the UI hierarchy, tap, type or swipe, validate a screen visually, smoke-test a build, walk a user journey, check accessibility labels with TalkBack, triage a crash or ANR, or prove a change works before release. Triggers - emulator, AVD, device, adb, boot, headless, install, run, launch, screenshot, annotated screen, visual check, UI hierarchy, layout dump, tap, input, text entry, swipe, journey, smoke test, e2e, end-to-end, accessibility, content description, crash, logcat, ANR, foreground activity, G6, device verification.
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Device verification (gate G6)

Prove the app runs on a real Android target. A green build is not evidence. G6
passes only when `app_workspace/.pipeline/reports/device-<UTC>.json` exists and
its `status` is `pass`, with screenshots and a UI hierarchy captured in
`app_workspace/.pipeline/artifacts/`. Treat previews and unit tests as
supporting evidence, never as a substitute for a device run when the spec has
interactive behavior.

## Contract

- **Reads:** `app_workspace/.pipeline/spec.json`, `STATE.json`,
  `00_memory/TECH_STACK.md`, and the debug APK produced by `G5`.
- **Writes:** `artifacts/screen-<UTC>.png`, `artifacts/layout-<UTC>.json`,
  `artifacts/logcat-<UTC>.txt`, `reports/device-<UTC>.json`.
- **Gate:** `G6`.
- **Handoff:** `08-release-and-quality` on pass; on failure, hand the captured
  evidence back to `05-build-test-loop` or open an `HD` via `09-human-review`.

## Preconditions

1. `app_workspace/gradlew` exists; the pipeline state says the next gate is G6.
2. `app_workspace/.pipeline/reports/verify-<UTC>.json` exists and says `pass`
   (G5). Do not boot a device to hide a red build loop.
3. You can name the journey you will verify in one sentence, for example:
   "login with email and password lands on the task list".
4. Choose the target with the decision tree below and record the choice plus
   the serial in `00_memory/SESSION_STATE.md`.

## Choose the target

| Situation | Target | Notes |
|---|---|---|
| Linux host with accessible `/dev/kvm` | Emulator `medium_phone` | Default for the pipeline; `device_up.sh` creates it |
| No KVM, physical device attached | Physical device | Pass `--serial`; do not start an emulator |
| Compose-only static screen, no runtime behavior to verify | `android preview render` only | Does NOT satisfy G6 alone; record the limitation and raise an HD if the spec requires interaction |
| CI or locked-down sandbox, no device possible | Block | Write the blocker to `SESSION_STATE.md`, open an `HD-###`, stop |

Never claim G6 from preview images, screenshot tests or a successful
`assembleDebug`. Those prove rendering or compilation, not installation,
navigation or runtime permissions.

## Quick start

Run from the pipeline root. `device_up.sh` is idempotent: it reuses a booted
device, reuses an existing AVD, and only creates one when none exists.

```bash
.agents/skills/07-device-verification/scripts/device_up.sh --profile medium_phone
```

Expected result: installation and launch succeed, and the serial is printed on
the last stdout line:

```text
device ready: emulator-5554
emulator-5554
```

Then capture evidence for the screen you care about:

```bash
.agents/skills/07-device-verification/scripts/device_check.sh \
  --serial emulator-5554 --expect-text "Welcome back"
```

Expected on success (the pipeline logger may prefix the line):

```text
PASS serial=emulator-5554 nodes=42 crashes=0 report=app_workspace/.pipeline/reports/device-20261108T160542Z.json
```

Confirm the evidence mechanically before advancing:

```bash
jq -e '.status=="pass" and .screenshot.bytes>0 and .layout.nodes>0' \
  "$(ls -t app_workspace/.pipeline/reports/device-*.json | head -1)"
echo "G6 evidence OK"
```

## Script contract

### `device_up.sh`

| Flag | Effect |
|---|---|
| `--profile NAME` | Profile used when no AVD exists: `small_phone`, `medium_phone`, `medium_tablet`, `small_desktop`, `medium_desktop`, `large_desktop` |
| `--avd NAME` | Use exactly this AVD; start it when it is not running |
| `--serial SERIAL` | Use an already-connected device; never start an emulator |
| `--headless` | Start the AVD without a window (direct emulator binary; the CLI has no headless flag) |
| `--timeout SECS` | Boot timeout, default 300 |
| `--dry-run` | Print the plan and detected devices, change nothing |

It resolves `adb`, reuses or starts a target, waits for
`getprop sys.boot_completed` and the package manager, clears the crash buffer,
runs `android run --device=<serial> --debug`, and fails when a fresh
`FATAL EXCEPTION` appears. On failure it prints a diagnosis covering KVM,
missing system images, SDK write permission and unreachable devices.

### `device_check.sh`

Writes `artifacts/screen-<UTC>.png` (annotated), `artifacts/layout-<UTC>.json`
(flat hierarchy), `artifacts/crash-<UTC>.log`, and the G6 report. Exit 0 only
when capture, layout, requested assertions and the crash scan pass.

| Flag | Effect |
|---|---|
| `--serial SERIAL` | Target device; default is the first connected device |
| `--expect-text TEXT` | Fail unless the literal text appears in the hierarchy |
| `--expect-tag TAG` | Fail unless the test tag, content description or resource id appears |
| `--package NAME` | Count crash-buffer entries for this package |
| `--dry-run` | Print the plan and output paths |

Assertions run against the accessibility tree, not pixels. Compose test tags
only surface in the hierarchy when the debug build enables
`Modifier.semantics { testTagsAsResourceId = true }`; otherwise assert on text
or content description. Never edit production code just to make a selector
match.

## Release-mode spot check (do this once before G7)

Debug builds skip R8, so a green debug run says nothing about a minified
release. Install the minified build once and walk the riskiest screen:

```bash
./gradlew :app:assembleRelease
android install --apks=app/build/outputs/apk/release/app-release.apk --device=emulator-5554
android run --device=emulator-5554 --activity=.MainActivity
.agents/skills/07-device-verification/scripts/device_check.sh --serial emulator-5554
```

If the release build crashes where debug did not, the cause is almost always a
missing keep rule or a stripped constructor. Fix it with keep rules in
`proguard-rules.pro`; never disable minification to pass G6. Hand the evidence
to G7 instead of guessing.

## Perceive, decide, act, assert

Drive journeys the way a screen reader sees the app.

1. **Perceive**: `android layout --device=<serial> --flat -o artifacts/<j>.json`
   and `android screen capture --annotate --device=<serial> --output=artifacts/<j>.png`.
2. **Decide**: choose one node by visible text, then content description, then
   resource id. Coordinates are the last resort.
3. **Act**: `android input tap|text|swipe|scroll|key --device=<serial>` targets UI
   elements; for annotated `#N` overlays use
   `android screen resolve --screenshot=artifacts/<j>.png --string="tap #3"` and
   run the command it prints, adding `--device=<serial>`.
4. **Observe**: re-dump the hierarchy and prove the screen changed.
5. **Assert**: `device_check.sh --expect-text "..."` or repeat the journey from
   the start.
6. **Record**: keep one PNG per meaningful step and the final report; name steps
   in order (`journey-01-login.png`, `journey-02-invalid-password.png`, ...).

Read `references/agentic-e2e.md` for the full loop protocol, including loop
budgets, idle handling, failure recovery and a complete login journey.

## Loop limits

- At most 12 interaction steps per journey. If the goal is not reached, stop,
  write what you saw, and escalate.
- At most 3 attempts per failing action; identical failure twice means the
  selector or the app state assumption is wrong.
- At most 2 journeys per session without a human decision. Journeys are
  evidence, not exploration.
- If two consecutive hierarchy dumps are identical and the expected node is
  absent, the screen is idle and wrong: go back or reset instead of tapping
  blind.

## Evidence rules

- One report per verification run: `reports/device-<UTC>.json` from the script,
  never hand-written.
- Screenshots must come from the device. A pasted preview render in
  `artifacts/` is falsification.
- Crash evidence is quoted from `adb logcat -d -b crash`, not summarized away.
- Keep `artifacts/screen-*.png` and `layout-*.json` until G7 is signed off;
  they are the audit trail for visual regressions.

## Stop conditions

Stop and escalate instead of forcing progress when:

- no emulator can boot and no physical device is available (open an HD);
- install fails twice with the same `INSTALL_FAILED_*` code;
- the app crashes on launch after one keep-rule or configuration fix;
- the journey needs credentials, payments or permissions the spec does not
  define (product decision, open an HD);
- more than 12 steps or 3 attempts are consumed;
- the screen under test cannot be reached without mutating seed data that the
  spec does not allow.

## Do NOT

- Do NOT `adb shell input tap X Y` at hardcoded pixels; use element-targeted
  `android input` or `screen resolve` output. Pixels break on density, rotation,
  font scale and inset changes.
- Do NOT `adb install` as the primary install path; `android run` and
  `android install --apks=...` handle delta install, permissions and launch.
- Do NOT sleep for fixed seconds hoping for a frame; poll the hierarchy until
  the expected node appears.
- Do NOT assert on screenshots with image diffing for logic checks; assert on
  the accessibility tree and use images for human review.
- Do NOT leave stale crash-buffer evidence from a previous run and call it a
  regression; `device_up.sh` clears the buffer before launch.
- Do NOT mutate app sources, seed data or feature flags to make a journey pass.
- Do NOT invent `android journey`, `android test` or `android screenshot`
  subcommands; the CLI surface in this skill is the verified one.
- Do NOT mark G6 pass from a preview, an emulator that never reached the app, or
  a report you did not read.

## Troubleshooting

| Symptom | Action |
|---|---|
| `emulator start` exits immediately | Check `/dev/kvm` permissions, SDK writability, installed system images; run `device_up.sh --dry-run` and read the diagnosis |
| Boot never completes | Grow `--timeout`, retry `--headless`, check `artifacts/emulator-<avd>.log` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | `adb uninstall <package>` then rerun `device_up.sh` (a debug/release signature clash) |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | Remove another AVD or wipe data with the emulator tooling, then retry |
| App opens then closes | Read `adb logcat -d | grep -A 30 "FATAL EXCEPTION"`; fix the code, not the test |
| `device_check` cannot see text | Dump the hierarchy and read it; text may be a `content-desc` or split across nodes |
| Device offline in `adb devices` | `adb kill-server`, replug or restart the emulator, then re-run `device_up.sh` |
| Everything worked yesterday | Re-run the gate; never reuse yesterday's report |

## Accessibility gate (do this before G7)

- Every interactive element has a meaningful text or content description; icons
  without labels fail.
- TalkBack can traverse and activate the main journey: enable it, walk the flow,
  disable it, and record the result in `SESSION_STATE.md`.
- Large font and dark theme do not clip or hide critical actions. Optional
  device-side checks: `adb shell settings put system font_scale 1.3` and
  `adb shell cmd uimode night yes`.

## Handoff

When the report is `pass`, record in `SESSION_STATE.md`: target type, serial,
profile, journey name, report path, and any screens that remain visually
unverified. Set the next gate to G7 and notify the release skill. When the
report is `fail`, keep the artifacts, write the failure sentence, and either fix
the app (one change per iteration) or open an HD if a product decision blocks
you. Cross-reference the G5 report so a regression is attributable.
