# Agent-driven end-to-end journeys (G6)

A journey is a sequence of perceive → decide → act → assert steps that proves
one user-visible behavior on a real device. Android CLI has no journey
subcommand and there is no recorded macro: the agent is the driver. This file defines the
loop protocol, selector strategy, budgets, evidence rules and a complete login
example.

## Contract

- A journey proves one sentence from the spec, for example: "a valid login lands
  on the task list" or "an invalid password shows an inline error".
- Inputs: a booted device (`scripts/device_up.sh`), a built and installed app,
  and the spec sentence you are checking.
- Outputs: ordered PNGs in `.pipeline/artifacts/`, the final
  `reports/device-<UTC>.json`, and a one-line result in `SESSION_STATE.md`.
- One journey per behavior. Do not chain "login, create task, edit, delete,
  share" into a single 30-step run; a failure becomes unattributable.

## The loop

```text
perceive  -> capture hierarchy + annotated screenshot
decide    -> pick exactly one target node by priority ladder
act       -> run one element-targeted input command
observe   -> re-dump hierarchy, confirm the expected change
assert    -> check text/node or continue the journey
record    -> keep artifacts, note the step number
```

Rules:

1. Never act on a screen you have not dumped in this step.
2. Never run two taps before observing the result of the first.
3. If observation fails, do not retry blindly; diagnose (see recovery table).
4. Record the step number in the artifact filename so the transcript is
   reconstructible from files alone.

## Perception

```bash
android layout --device=emulator-5554 --flat -o artifacts/journey-03-list.json
android screen capture --annotate --device=emulator-5554 --output=artifacts/journey-03-list.png
```

Expected: `layout` writes a JSON hierarchy; `screen capture` writes a PNG with
numbered overlays and prints the capture path. Use `--full` instead of `--flat`
only when you need parent/child nesting to disambiguate duplicated text.

Read the hierarchy for these fields:

| Field | Use |
|---|---|
| `text` | Primary selector for labels, titles, buttons |
| `content-desc` | Selector for icon buttons; also accessibility evidence |
| `resource-id` | Stable selector for View-based screens |
| `class` | Distinguish `android.widget.EditText` from a label |
| `bounds` | Compare layout changes; never hand-compute tap points from it |
| `clickable` / `enabled` | Confirm the target is actionable before tapping |

Prefer `layout` over the screenshot for selection: text is exact, while pixels
move with density, font scale, insets and animation frames.

## Decision: selector ladder

Try selectors in this order and stop at the first that uniquely matches:

1. Exact visible `text` ("Sign in").
2. Exact `content-desc` ("Sign in button").
3. `resource-id` (`com.example.app:id/sign_in`).
4. Text plus class when a label and a button share words.
5. Child text under a clickable ancestor (tap the ancestor, not the text).
6. Annotated overlay `#N` from the current capture.
7. Raw coordinates: last resort, never hardcoded, never reused across steps.

Two matches means the selector is ambiguous: add context (parent text, index,
resource id) or scroll the target into view. Do not tap the first of two
candidates and hope.

Compose specifics:

- `Modifier.testTag("x")` appears in the hierarchy only when the debug build
  enables `Modifier.semantics { testTagsAsResourceId = true }` on a parent.
- Decorative icons need `contentDescription = null`; interactive icons need a
  real description. If a control exposes neither text nor description, that is
  an accessibility bug: fix the app rather than selecting by coordinates.
- Text inside a merged semantics node may be concatenated ("Welcome back Demo").
  Match a distinctive substring, not the whole line.

## Act

`android input` commands target UI elements; `screen resolve` converts an
annotated `#N` into concrete coordinates.

```bash
# 1. Resolve the annotated number against the current capture.
android screen resolve --screenshot=artifacts/journey-01-login.png --string="tap #4"

# 2. Run the command it prints, adding the device flag.
android input tap --device=emulator-5554 ...

# 3. Text entry, then assert the field content in a fresh hierarchy.
android input text --device=emulator-5554 "demo@example.com"
```

Because the exact targeting flags differ between CLI builds, run
`android input --help` once and use the flags it documents. Two invariants never
change: the screenshot passed to `screen resolve` must be the latest one, and a
resolved coordinate is valid only for the screen state it was captured from.

For long lists, scroll rather than tapping off-screen coordinates:

```bash
android input scroll --device=emulator-5554 ...
android input swipe --device=emulator-5554 ...
```

Keyboard and system keys:

```bash
android input key --device=emulator-5554 KEYCODE_BACK
android input key --device=emulator-5554 KEYCODE_ENTER
```

## Waiting and idle

Never `sleep 5` and assume. Poll:

```bash
for i in 1 2 3 4 5 6; do
  android layout --device=emulator-5554 --flat -o /tmp/h.json
  if grep -qF "Your tasks" /tmp/h.json; then break; fi
  sleep 0.5
done
```

- Node timeout: 10 seconds; screen transition timeout: 30 seconds.
- Two identical dumps plus an absent node means the screen is idle and wrong.
- Disable animations on emulator targets to remove frame races:

```bash
adb -s emulator-5554 shell settings put global window_animation_scale 0
adb -s emulator-5554 shell settings put global transition_animation_scale 0
adb -s emulator-5554 shell settings put global animator_duration_scale 0
```

This changes device settings only, never the app. Do not add sleeps to
compensate for a screen that is genuinely stuck.

## Loop budget

| Resource | Limit | On exhaustion |
|---|---|---|
| Interaction steps per journey | 12 | Stop, record state, escalate |
| Attempts per failing action | 3 | Stop, change approach or escalate |
| Hierarchies per step | 2 | Use the second dump; do not loop |
| Journeys per session without an HD | 2 | Ask the human which behavior matters |
| Wall-clock per journey | 5 minutes of agent time | Stop and report the blocker |

Escalation is a first-class outcome. A documented "cannot reach the list screen,
error state stays visible, evidence at `journey-07.png`" is worth more than ten
extra blind taps.

## Evidence recording

- `journey-01-login.png`, `journey-02-invalid.png`, `journey-03-list.png`:
  ordered, annotated captures.
- `journey-01-login.json`, ...: the hierarchy used at that step.
- The final `device_check.sh` run writes `reports/device-<UTC>.json`; run it on
  the terminal screen of the journey so the report's screenshot matches the
  asserted state.
- `SESSION_STATE.md` gets one line: journey name, steps used, pass/fail, report
  path, and the device serial.

Do not delete failed-journey artifacts. They are the evidence for the failure.

## Failure recovery

| Observation | Likely cause | Action |
|---|---|---|
| Expected node absent, dump stable | Wrong screen or stale data | Go back once (`KEYCODE_BACK`), re-dump, then escalate |
| Tap had no effect | Target not clickable, overlay, or keyboard covering it | Re-dump, check `clickable`, dismiss keyboard or scroll |
| Node visible but text differs | Locale, truncation, font scale | Match a substring; record the actual text in evidence |
| Dialog or permission prompt | First-run flow or runtime permission | Handle it as part of the journey if the spec allows; otherwise escalate as an HD |
| Crash or ANR | App bug or missing R8 keep rule | Capture `adb logcat -d -b crash`, stop the journey, fix the app |
| Keyboard stays open | IME covering the target | `KEYCODE_BACK` to dismiss, re-dump before tapping |
| Empty state instead of list | Backend/seed data missing | Check the spec's seed rules; do not fabricate data |

Never swallow a failure by asserting on a different screen that happens to be
visible. The journey's assertion must match the spec sentence.

## Worked example: login flow

Spec sentence: "A valid login shows the task list; an invalid password shows an
inline error."

### Step 1 - bring up the target

```bash
.agents/skills/07-device-verification/scripts/device_up.sh --profile medium_phone
# stdout last line:
emulator-5554
```

Reasoning: reuse or boot one target; the app is installed and launched in debug.

### Step 2 - perceive the first screen

```bash
android layout --device=emulator-5554 --flat -o artifacts/journey-01-login.json
android screen capture --annotate --device=emulator-5554 --output=artifacts/journey-01-login.png
.agents/skills/07-device-verification/scripts/device_check.sh \
  --serial emulator-5554 --expect-text "Welcome back"
```

Expected: the check passes; the hierarchy contains an email field, a password
field and a "Sign in" button. The annotated PNG labels them `#1..#5`.

### Step 3 - wrong password path

Resolve and tap the password field, type a wrong password, then tap "Sign in".

```bash
android screen resolve --screenshot=artifacts/journey-01-login.png --string="tap #3"
android input tap --device=emulator-5554 ...
android input text --device=emulator-5554 "not-the-password"
android screen resolve --screenshot=artifacts/journey-01-login.png --string="tap #5"
android input tap --device=emulator-5554 ...
sleep 1
android layout --device=emulator-5554 --flat -o artifacts/journey-02-error.json
```

Expected: a stable inline error. Assert it, do not eyeball it:

```bash
.agents/skills/07-device-verification/scripts/device_check.sh \
  --serial emulator-5554 --expect-text "Invalid email or password"
# PASS ... nodes=... crashes=0 ... journey-02-error.png
```

### Step 4 - valid login

Re-dump after the error, clear the password, enter the valid value and submit.
Numbers come from the latest capture, not step 2.

```bash
android layout --device=emulator-5554 --flat -o artifacts/journey-03-fields.json
android screen capture --annotate --device=emulator-5554 --output=artifacts/journey-03-fields.png
android screen resolve --screenshot=artifacts/journey-03-fields.png --string="tap #3"
android input tap --device=emulator-5554 ...
android input text --device=emulator-5554 "demo@example.com"
android screen resolve --screenshot=artifacts/journey-03-fields.png --string="tap #5"
android input tap --device=emulator-5554 ...
```

### Step 5 - assert the destination

```bash
for i in 1 2 3 4 5 6; do
  android layout --device=emulator-5554 --flat -o artifacts/journey-04-list.json
  grep -qF "Your tasks" artifacts/journey-04-list.json && break
  sleep 0.5
done
.agents/skills/07-device-verification/scripts/device_check.sh \
  --serial emulator-5554 --expect-text "Your tasks"
```

Expected: `PASS`, screenshot on the task list, zero crashes. Record the journey
as passing with 8 interaction steps (within budget), then move to G7.

If "Your tasks" never appears and the hierarchy is stable on the login screen,
stop: the journey failed. Keep `journey-04-list.json`, record the visible text,
and escalate with the actual screen rather than tapping again.

## Accessibility checks inside a journey

- Every tap target also has a text or content description in the dump.
- Touch targets are at least 48dp; on a `medium_phone` that is roughly 48px at
  the emulator's density, so flag suspiciously small bounds.
- Enable TalkBack manually for the final pass; the accessibility tree you assert
  against is the same one TalkBack reads.
- Temporarily raise the font scale (`adb shell settings put system font_scale 1.3`),
  re-dump, and confirm nothing critical clips. Reset with `1.0`.

## Anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| `adb shell input tap 540 1200` | Breaks on density, rotation, insets and font scale |
| Fixed `sleep` between actions | Slow when idle, flaky when busy |
| Reusing `#N` from an old capture | Overlay numbers are per-capture |
| Asserting on a screenshot diff | Visual noise, not behavior; use the tree |
| Editing the app to make the selector match | Hides the bug; selectors should follow the tree |
| `adb install` instead of `android run` | Skips delta install and launch handling |
| Retrying the same tap 5 times | Masks a real state problem; escalate |
| Ignoring the crash buffer | A "passing" journey with a background crash is not passing |

## Handoff to G7

A journey is done when the terminal screen is asserted, crash-clean and backed
by `reports/device-<UTC>.json`. Write the result and the artifact paths to
`SESSION_STATE.md`, then hand the release skill a note listing the riskiest
screen to spot-check on a minified build.
