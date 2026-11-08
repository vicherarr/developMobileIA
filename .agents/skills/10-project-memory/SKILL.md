---
name: 10-project-memory
description: "Maintain the four-file memory layer that keeps an Android build cheap to resume — ARCHITECTURE.md, TECH_STACK.md, DECISION_LOG.md, and SESSION_STATE.md — with strict ownership, a fixed session read order, append-only decision history, version-drift control against gradle/libs.versions.toml, and a handoff checklist. Use at session start and end, before delegating to a subagent, after any dependency or version change, when writing a decision record, when the architecture changes, or when context feels bloated. Triggers: memory, architecture record, tech stack, decision log, session state, handoff, context, token budget, read order, resume, versions, drift, libs.versions.toml, what did we decide."
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Project Memory (context economy)

Memory exists so the next context window does not re-derive the project.
One fact, one file, written once, read on demand. Everything else is token burn.

## Four files, four owners

All four live in `00_memory/`. They are copied from this skill's `assets/` once, at bootstrap, and never regenerated.

| File | Holds | Mutability | Write trigger | Never holds |
|---|---|---|---|---|
| `ARCHITECTURE.md` | Patterns, module boundaries, data flow, UI conventions, invariants | Stable, edited rarely | A pattern or boundary changes | Versions, decision history, current task |
| `TECH_STACK.md` | Pinned versions, rationale, upgrade rules | One edit per version change | Any dependency, SDK, or toolchain change | Feature scope, migration steps |
| `DECISION_LOG.md` | Append-only `DL-###` entries | Append only, immutable | Whenever a decision is made | Edits, deletions, reordering |
| `SESSION_STATE.md` | Current gate, next action, open HDs, files touched | Rewritten every session | Session start and session end | Stable architecture, history |

A fact that belongs to `spec.json` stays in `spec.json`. Do not mirror the spec here; link to it.

## Session ritual

Read in this order, stop as soon as the next action is clear:

1. `00_memory/SESSION_STATE.md` — gate, next action, blockers.
2. `00_memory/TECH_STACK.md` — what versions you may assume.
3. `app_workspace/.pipeline/STATE.json` — machine truth: stage, status, `blocking`, `next_action`.
4. `app_workspace/.pipeline/spec.json` — the scope of the next action only.
5. The specific source files that action will touch.

Hard rules:

- Never read the whole `app_workspace/` tree. No recursive dump, no `find | xargs cat`, no "let me see the project".
- Use targeted reads, `glob`, and `grep`. Search for a symbol, not for a directory.
- Cap: the files you will edit plus at most 2 context files per step. Exception: a deliberate architecture review, which is a different task with its own budget.
- Do not re-read a file already read this session unless something changed it.
- Do not paste `00_memory/*` wholesale into a subagent prompt. Quote the 3–10 lines it needs.

Session start checklist:

- [ ] `SESSION_STATE.md` read; gate and next action recorded.
- [ ] `TECH_STACK.md` read; no version assumption contradicts it.
- [ ] `spec.json` read for the current feature only.
- [ ] The current gate's evidence file exists in `app_workspace/.pipeline/reports/`, or its absence is the task.
- [ ] Open `HD` ids noted from the queue; blocking ones respected.

## Write rules

| File | Rule | Format |
|---|---|---|
| `ARCHITECTURE.md` | Update only when a pattern, module boundary, data flow, or convention changes. Date the change in the changelog section. Never describe a feature | Sections from `assets/ARCHITECTURE.template.md` |
| `TECH_STACK.md` | Single source of truth for versions. Every pinned version gets a one-line rationale. Update in the same change as the version bump | Table from `assets/TECH_STACK.template.md` |
| `DECISION_LOG.md` | Append only. One entry per decision. Never delete, renumber, or rewrite. Supersede with a new id and `Supersedes: DL-###` | Entry format from `assets/DECISION_LOG.template.md` |
| `SESSION_STATE.md` | Rewrite, do not append. Under 60 lines. Volatile facts only | Form from `assets/SESSION_STATE.template.md` |

Additional rules:

- No duplication across files. A version appears in `TECH_STACK.md` and in `gradle/libs.versions.toml`; nowhere else. A decision appears in `DECISION_LOG.md`; `SESSION_STATE.md` may reference its id but never restate the reasoning.
- No secrets, keys, tokens, signing passwords, or personal data. Reference the environment variable, never its value.
- No generated noise: no lockfiles, no build output, no full logs, no `git status` dumps, no screenshots as text.
- Quote evidence paths, not evidence content: `reports/G3-domain-evidence.md`, not a log excerpt.
- Write in the past tense for decisions, present tense for architecture, future tense for the next action.

## Drift control

After any dependency, SDK, or toolchain change, `00_memory/TECH_STACK.md` and `gradle/libs.versions.toml` must be reconciled **in the same change**. A mismatch is a defect and must be fixed before the gate's evidence file is written.

Checklist:

- [ ] Every row in the `TECH_STACK.md` table that ships has a matching catalog entry, and every shipped catalog entry has a row.
- [ ] SDK levels (`compileSdk`, `targetSdk`, `minSdk`) and the JVM toolchain appear in the module build file as well as the table; reconcile all three.
- [ ] Gradle wrapper version matches the `TECH_STACK.md` row.
- [ ] AGP 9 constraints respected: built-in Kotlin (never apply `org.jetbrains.kotlin.android`), kapt incompatible → KSP2, Gradle ≥ 9.1.0, JDK 17. A change that breaks one is a defect even if the build passes locally.
- [ ] DI default preserved: manual constructor injection plus `AppContainer`. Hilt + KSP is opt-in and needs a `DL-###` before adoption.

Scaffold baseline you must not contradict:

| Item | Version |
|---|---|
| AGP | 9.0.1 |
| Gradle wrapper | 9.1.0 |
| Kotlin (Compose compiler plugin) | 2.3.20 |
| Compose BOM | 2026.03.01 |
| compileSdk / targetSdk / minSdk | 36 / 36 / 24 |
| JVM toolchain | 17 |
| Navigation 3 | `navigation3-runtime`, `navigation3-ui` 1.0.1; `lifecycle-viewmodel-navigation3` 2.10.0 |
| `androidx.core:core-ktx` | 1.18.0 |
| `androidx.activity:activity-compose` | 1.13.0 |
| AndroidX lifecycle | 2.10.0 |

## Token economy

| Task | Read, in order | Do not read |
|---|---|---|
| Add a screen | `SESSION_STATE.md`, `TECH_STACK.md`, `spec.json`, one existing UI file of the same kind | Whole feature package, old reports |
| Add or change a repository | `SESSION_STATE.md`, `ARCHITECTURE.md` data-flow section, one data file, `spec.json` feature | All of `core/`, Room schema history |
| Bump a dependency | `TECH_STACK.md`, `gradle/libs.versions.toml`, the consuming build file | Source trees |
| Fix a build failure | The failing report in `.pipeline/reports/`, the one implicated file, `TECH_STACK.md` only if the failure is version-shaped | Everything else |
| New feature end to end | `SESSION_STATE.md`, `spec.json`, `ARCHITECTURE.md` | `DECISION_LOG.md` in full; read only the ids referenced by `spec.json` |
| Write a `DL` | Last 30 lines of `DECISION_LOG.md` | The rest of the log |
| Handoff | `SESSION_STATE.md`, the queue's `## Open` table | Source files |
| Release or quality pass | `05-build-test-loop` and `08-release-and-quality` evidence, `TECH_STACK.md` | Feature source |

## Handoff protocol

End of every session:

- [ ] `SESSION_STATE.md` rewritten: gate, next action (one executable sentence), open `HD` ids, files touched, evidence paths.
- [ ] New `DL` ids appended to `DECISION_LOG.md`.
- [ ] `TECH_STACK.md` reconciled with `gradle/libs.versions.toml`.
- [ ] Evidence files listed by path; no gate claimed without one.
- [ ] Anything a fresh context would guess wrong is written down. Everything else is omitted.

Handoff to a subagent — tell it exactly:

- Gate, goal, and acceptance criteria (quote them; do not point at paths it must read).
- Allowed write paths and forbidden paths.
- Exact read set as file paths.
- The `ARCHITECTURE.md` invariants that constrain the change, quoted.
- Whether it may touch `00_memory/`. Default: no.

What the subagent must write back:

- Files changed, with one line each.
- `DL` and `HD` ids it raised, with one-line reasons.
- Evidence path it produced, or why it produced none.
- Next action and any blocker, in one sentence.

Merge its report into `SESSION_STATE.md` yourself. Do not let a subagent edit memory unless the task is memory maintenance.

## Contract

**Reads** — `00_memory/SESSION_STATE.md`, `00_memory/TECH_STACK.md`, `00_memory/ARCHITECTURE.md`, `00_memory/DECISION_LOG.md` tail, `app_workspace/.pipeline/spec.json`, `gradle/libs.versions.toml`, and only the source files the next action touches.

**Writes** — `00_memory/SESSION_STATE.md` (every session); `00_memory/DECISION_LOG.md` (append); `00_memory/TECH_STACK.md` and `00_memory/ARCHITECTURE.md` (on their triggers only). Templates in `assets/` are copied to `00_memory/` by the bootstrap and are not edited at runtime.

**Gate** — runs inside every gate as a precondition and a postcondition. At gate close, memory must match the evidence: reconciling `TECH_STACK.md` and the catalog is part of the gate, not a follow-up.

**Handoff** — this skill owns the "what the next session knows" surface. Any stage that ends must leave `SESSION_STATE.md` executable by a fresh context with no conversation history.

## Do NOT

- Do not treat `DECISION_LOG.md` as editable prose. Append and supersede, nothing else.
- Do not write the same fact into two memory files.
- Do not copy versions into `ARCHITECTURE.md`, `SESSION_STATE.md`, or feature docs.
- Do not let `SESSION_STATE.md` grow into a diary; history belongs in the decision log.
- Do not store secrets, signing material, or personal data.
- Do not read the repository to "get oriented".
- Do not claim a gate advanced without an evidence file recorded here.
- Do not leave a session without a next action that a stranger could execute.
