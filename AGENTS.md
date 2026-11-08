# AGENTS.md — Android agentic pipeline

This repository is an agentic pipeline for building Android apps from a prompt
to a release, end to end. If you are an agent reading this, follow it literally.

## Session ritual

1. Load the `00-pipeline-orchestrator` skill.
2. Read, in this order: `00_memory/SESSION_STATE.md`,
   `00_memory/TECH_STACK.md`, `app_workspace/.pipeline/STATE.json`,
   `app_workspace/.pipeline/spec.json` (if present).
3. Read `02_pending_review/human_decisions.md`; if a blocking `HD` is open, the
   only legal work is resolving it.
4. Continue from `STATE.json.next_action` with the skill that owns that gate.

Do not read the whole repository to get context. The four files above are the
context; everything else is loaded on demand by the skill that needs it.

## Non-negotiable rules

- **No evidence, no progress.** A gate passes only when its report file exists
  and says `pass`. Never claim a green build from memory.
- **Spec before code.** No scaffolding until `app_workspace/.pipeline/spec.json`
  exists with zero blocking decisions.
- **Official generator, official CLI.** Create projects with `android create`;
  build, install, run, screenshot, preview and analyze with the `android` CLI
  (`android build|install|run|preview|screen|layout|input|analyze|emulator`).
  Do not invent subcommands and do not hand-write Gradle files from memory.
- **AGP 9 means built-in Kotlin.** Never apply `org.jetbrains.kotlin.android`;
  kapt is incompatible — use KSP2.
- **Assume technical, never product.** Reversible technical defaults are decided
  and logged (`DL`). Product/business/legal/money questions block as `HD`.
- **One fix per iteration.** Three attempts on the same error class → escalate,
  do not thrash.
- **Never disable a check to pass a gate** (lint, tests, R8 keep rules).
- **Update memory as you go**: `DECISION_LOG.md` (append-only) for choices,
  `TECH_STACK.md` for versions (must match `gradle/libs.versions.toml`),
  `SESSION_STATE.md` at end of session.

## Layout

| Path | Purpose |
|---|---|
| `.agents/skills/00..10-*` | The pipeline skills (discovered by DSH and Android CLI) |
| `.agents/skills/testing-setup` | Official Google testing skill, installed via `android skills add` |
| `00_memory/` | Persistent project memory: architecture, versions, decisions, session state |
| `02_pending_review/` | Queue of human decisions (`HD-###`) that block the line |
| `app_workspace/` | The generated Android project (Gradle root) |
| `app_workspace/.pipeline/` | Machine state, spec, plan, evidence reports, artifacts |
| `scripts/` | `lib/android_env.sh`, `bootstrap.sh`, `doctor.sh` |
| `docs/` | Pipeline architecture, verified CLI/tooling inventory |

## Stage machine

`G0` intake → `G1` spec → `G2` scaffold → `G3` domain+data → `G4` ui →
`G5` build+test → `G6` device → `G7` release. Each gate has an owner skill and
an evidence file; see `00-pipeline-orchestrator`.

## Environment notes

- `android` CLI writes to `$HOME/.android/cli`; under a read-only sandbox the
  pipeline scripts redirect HOME to `.cache/android-cli-home`. SDK package
  installs still require real write access to the SDK.
- Gradle needs a writable `GRADLE_USER_HOME`; scripts fall back to
  `.cache/gradle-home` (first run downloads the distribution).
- AGP needs a writable Android user home for the debug keystore (`~/.android`).
  When HOME is read-only the scripts set `ANDROID_USER_HOME=.cache/android-user-home`;
  without it, `:app:validateSigningDebug` fails.
- JDK 17-25 is accepted: Gradle 9.1 has full Java 25 support and the template
  build was verified on JDK 25. AGP's toolchain still targets 17.
- Long builds and emulator starts should run as managed background jobs.
