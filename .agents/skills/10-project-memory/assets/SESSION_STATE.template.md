# Session State — <app-name>

<!--
Volatile state for the next context window. Bootstrap copies this file to
`00_memory/SESSION_STATE.md`.

Rules:
- Rewritten at the end of every session; do not append history.
- Under 60 lines. If it grows, move the durable fact to ARCHITECTURE.md,
  TECH_STACK.md, or DECISION_LOG.md and delete it here.
- Must be executable by an agent with zero conversation history.
- No reasoning, no logs, no version tables. Reference paths and ids instead.
- If the next action depends on an unanswered question, say so explicitly.
-->

| Field | Value |
|---|---|
| Gate | `<G0..G7>` — `<gate name>` |
| Stage status | `<not started>` / `<in progress>` / `<blocked>` / `<done>` |
| Session | `<YYYY-MM-DDThh:mm:ssZ>` |
| Last evidence | `<reports/G<N>-<name>.md>` |

## Next action

<!-- One sentence, imperative, executable without reading anything else.
     Bad: "continue with UI". Good: "Add the AddNoteScreen composable to
     feature/notes and wire its Nav3 entry in :app navigation host." -->

> <Next action.>

## Blocking

<!-- Mirror of STATE.json blocking[]. If empty, write "none". -->

| HD | Reason | Since |
|---|---|---|
| `<HD-###>` | `<what cannot proceed>` | `<YYYY-MM-DD>` |

## Open, non-blocking

<!-- Class B flags awaiting a veto. Empty is normal. -->

| HD | Default in effect | Expires |
|---|---|---|
| `<HD-###>` | `<behavior currently implemented>` | `<YYYY-MM-DD or G# close>` |

## Files touched this session

<!-- Path → one-line change. Enough to re-orient, not a diff. -->

| Path | Change |
|---|---|
| `<app_workspace/...>` | `<what changed>` |

## Evidence written

| Gate | Report | Status |
|---|---|---|
| `<G#>` | `<app_workspace/.pipeline/reports/G#-<name>.md>` | `<pass/fail/partial>` |

## Read set for the next session

<!-- Exact files, in order. Keeps the next context from enumerating the tree. -->

1. `00_memory/SESSION_STATE.md` (this file)
2. `00_memory/TECH_STACK.md`
3. `app_workspace/.pipeline/spec.json` — feature `<id>`
4. `<the one or two source files the next action edits>`

## Environment notes

<!-- Only facts that change behavior: SDK path, device id, JDK, offline flag,
     known-broken command. No secrets. -->

- JDK: `17`
- Gradle wrapper: `9.1.0`
- Device: `<emulator or serial>` / `<none>`
- Known issue: `<one line>` or `none`

## Handoff note

> <One or two sentences a fresh agent needs that is not obvious from the next
> action: what was tried and rejected, what to avoid re-reading, where the
> half-finished work is.>
