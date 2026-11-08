---
name: 00-pipeline-orchestrator
description: Entry point for building an Android app end to end with this pipeline. Use it at the start of any session and whenever you need to decide which stage comes next, check a gate, write pipeline state, resume after a blocker, or delegate work to subagents. Defines the stage machine (G0-G7), the artifact contract between skills, evidence requirements, loop budgets, and escalation rules. Triggers - build an app, new feature, continue, resume, next step, where are we, pipeline state, gate, plan, orchestrate, subagents.
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Pipeline orchestrator

You are the control plane. You do not write product code in this skill; you
decide **what happens next, with which skill, and whether it is allowed to
count as done**. Every claim of progress needs a file on disk.

## Contract

- **Reads:** `00_memory/SESSION_STATE.md`, `00_memory/TECH_STACK.md`,
  `app_workspace/.pipeline/STATE.json`, `app_workspace/.pipeline/spec.json`,
  `02_pending_review/human_decisions.md`
- **Writes:** `app_workspace/.pipeline/STATE.json`, `app_workspace/.pipeline/plan.md`,
  `00_memory/SESSION_STATE.md`, append-only `00_memory/DECISION_LOG.md`
- **Gate:** all of them (it owns the machine)
- **Handoff:** the stage-specific skill named in the routing table below

## Stage machine

| Gate | Name | Owner skill | Exit evidence (file that must exist) |
|---|---|---|---|
| G0 | Intake | `10-project-memory` | `00_memory/SESSION_STATE.md` refreshed |
| G1 | Spec and scope | `01-spec-and-scope` | `.pipeline/spec.json` + `plan.md`, zero blocking `HD` |
| G2 | Scaffold | `02-android-scaffold` | `reports/scaffold-<UTC>.json` with `"status":"pass"` |
| G3 | Domain and data | `03-domain-and-data` | `reports/domain-<UTC>.json` (unit tests green) |
| G4 | UI | `04-ui-compose` | `reports/ui-<UTC>.json` (previews render) |
| G5 | Build and test loop | `05-build-test-loop` | `reports/verify-<UTC>.json` with `"status":"pass"` |
| G6 | Device verification | `07-device-verification` | `reports/device-<UTC>.json` + PNGs in `artifacts/` |
| G7 | Release and quality | `08-release-and-quality` | `reports/quality-<UTC>.json` with `"status":"pass"` |

Rules that make the machine trustworthy:

1. **No evidence, no advance.** A stage is `pass` only if the evidence file
   exists and its `status` field says so. Never mark a gate from memory or
   from a previous summary.
2. **Gates can regress.** A change after G5 reopens G5. Do not "remember" a
   green build; re-run the loop.
3. **One gate at a time.** Do not start G4 while G3 is red unless the
   dependency is genuinely independent (state the reason in `STATE.json`).
4. **Blocking questions stop the line.** If `STATE.json.blocking` is
   non-empty, the only legal work is answering it (see `09-human-review`).
5. **Rewriting state is cheap; faking it is fatal.** Update `STATE.json`
   after every gate transition, not at the end of the session.

## State file

`app_workspace/.pipeline/STATE.json` is the machine-readable truth:

```json
{
  "schema": 1,
  "project": "todo-moteros",
  "stage": "G4",
  "status": "in_progress",
  "updated_at": "2026-11-08T16:05:42Z",
  "gates": {
    "G1": { "status": "pass", "evidence": ".pipeline/spec.json" },
    "G2": { "status": "pass", "evidence": "reports/scaffold-20261108T154001Z.json" },
    "G3": { "status": "pass", "evidence": "reports/domain-20261108T155512Z.json" },
    "G4": { "status": "in_progress" }
  },
  "blocking": [],
  "next_action": "Implement HomeScreen + HomeViewModel, then run 05-build-test-loop",
  "files_touched": ["app/src/main/java/.../ui/home/HomeScreen.kt"]
}
```

Write it with the `write` tool (whole file), keeping it under ~60 lines. It is
a dashboard, not a log.

## Routing table

| The user asks for | Load | Notes |
|---|---|---|
| "build me an app", "new project", unclear requirements | `01-spec-and-scope` | never scaffold before G1 |
| "create the project", "add a module", "set up Gradle" | `02-android-scaffold` | template + version catalog are fixed here |
| "add data", "Room", "API", "repository", "offline", "sync" | `03-domain-and-data` | |
| "add a screen", "design this UI", "ViewModel", "navigation" | `04-ui-compose` | |
| "it doesn't compile", "run the tests", "fix the build" | `05-build-test-loop` | always the loop, not ad-hoc Gradle |
| "write tests", "coverage", "screenshot tests", "flaky" | `06-testing-strategy` | |
| "does it work on the device", "show me", "emulator", "screenshot" | `07-device-verification` | |
| "release", "R8", "APK size", "Play Store", "signing" | `08-release-and-quality` | |
| a requirement is ambiguous or contested | `09-human-review` | product intent is never guessed |
| "where were we", "save context", "handoff" | `10-project-memory` | |
| a decision spans several stages | this skill | plan first, then delegate |

Also available: `testing-setup` (official Google skill, bundled in
`.agents/skills/`). Prefer it for deep testing-strategy detail; prefer
`06-testing-strategy` for this pipeline's gates and evidence format.

## Workflow per gate

1. **Read state** — `STATE.json`, `SESSION_STATE.md`, and the previous gate's
   evidence file. Nothing else yet.
2. **Load the owner skill** for the current stage and follow it literally.
3. **Produce evidence** — run the stage's verification command; write the
   report. Partial success is failure.
4. **Update state** — gate status, evidence path, `next_action`,
   `files_touched`.
5. **Report to the human** in <= 6 lines: what changed, evidence path, what is
   next, blockers. No narration of tool calls.

## Parallelism with subagents

Use subagents when the work is **independent and file-disjoint**, otherwise do
it yourself.

Good fan-out:

- One subagent per feature slice (`auth/`, `profile/`, `feed/`) — each owns its
  own package and test files.
- Research subagents (version checks, API docs) — they only return text.
- Review subagents (read-only audit of a diff) — they never write.

Never fan out when:

- Two agents would edit the same file (build files, `libs.versions.toml`,
  `STATE.json`, navigation graph).
- The work is a sequential fix loop — the loop must see its own output.
- The task needs the whole conversation's context.

Every subagent brief must include: exact file paths it may write, the pipeline
contract, the gate it serves, the evidence format, and "do not touch other
files". After a fan-out, the orchestrator (you) runs the gate verification
itself. Subagent claims are not evidence.

## Loop budgets

| Loop | Budget | On exhaustion |
|---|---|---|
| Build/test repair attempts per distinct error class | 3 | stop, write `HD`, attach the last 100 log lines |
| Screenshot/preview iterations | 4 | keep the render, flag to human |
| Agentic device journey steps | 12 | abort journey, capture screen, report |
| Full G5 re-runs in one session | 5 | stop and reassess scope with the human |

A "distinct error class" is the exception type + the failing task, not the
message text. Repeating the same doomed command is the main way agents burn
tokens; count and stop.

## Token economy

- Read `SESSION_STATE.md` first; it should already contain the answer to
  "where are we".
- Read `TECH_STACK.md` before touching any dependency; never grep the whole
  tree for versions.
- Read only the files you will edit, plus their direct interface (interface,
  state class, DAO). Do not read entire modules for context.
- Use `grep`/`rg` for symbols and `read` with offsets for big files.
- Prefer `./gradlew <task> --console=plain -q` and read the report path it
  prints, not the full log.

## Stop conditions

Stop and write a blocking `HD` when:

- A product/business decision is required and guessing is expensive
  (pricing, auth model, data retention, legal, payments, identity).
- Two requirements are mutually exclusive or the spec contradicts itself.
- The environment cannot satisfy the spec (SDK/API level unavailable, no
  usable device, missing signing material) and there is no safe workaround.
- A loop budget is exhausted.

Do not stop for: style choices, library-name preferences, "should I add a
test" (yes), or anything you can verify in the repo or in official docs via
`android docs search "<topic>"`.

## Definition of done

- `STATE.json.stage == "G7"` and `status == "pass"`.
- Evidence files for G2, G5, G6, G7 exist and say `pass`.
- `00_memory/TECH_STACK.md` matches `gradle/libs.versions.toml`.
- `DECISION_LOG.md` contains every non-obvious choice made along the way.
- `SESSION_STATE.md` tells the next session exactly how to continue.
- A release artifact path is recorded, and `human_decisions.md` has no open
  blocking entries.
