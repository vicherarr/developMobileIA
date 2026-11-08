# Decision Log — <app-name>

<!--
Append-only. Bootstrap copies this file to `00_memory/DECISION_LOG.md`.

Rules:
- One entry per decision. Never edit, delete, reorder, or renumber an entry.
- To change a past decision, append a new `DL-###` with `Supersedes: DL-###`
  and flip the old entry's `Status` line to `superseded by DL-###`.
  Nothing else about the old entry changes.
- Ids are monotonic: DL-001, DL-002, ... Never reuse an id.
- Reasoning is recorded once, here. Do not restate it in SESSION_STATE.md.
- Keep each entry under ~20 lines. If it needs more, split the decision.
- No secrets, keys, or personal data.
-->

| Field | Value |
|---|---|
| Last id issued | `DL-000` |
| Entries | `0` |
| Convention | `DL-###`, append-only |

## Index

<!-- Newest first. Five columns, one line each. Full reasoning lives in the entry. -->

| ID | Date | Gate | Title | Status | Supersedes |
|---|---|---|---|---|---|
| `DL-000` | `<YYYY-MM-DD>` | `<G0..G7>` | `<short title>` | `accepted` | — |

<!-- Status vocabulary: accepted | superseded by DL-### | deprecated.
     A decision that is merely implemented is still `accepted`. -->

## Entry template

<!-- Copy this block for each new decision, below `## Entries`. -->

### DL-000 — <imperative title, 60 characters max>

| Field | Value |
|---|---|
| Date | `<YYYY-MM-DD>` |
| Gate | `<G0..G7>` |
| Class | `<A reversible technical>` or `<B costly technical>` |
| Status | `accepted` |
| Supersedes | `<DL-###>` or `nothing` |
| Source | `<HD-###>` or `<agent default>` |

**Context** — <the constraint that forced a choice, in one or two sentences.>

**Decision** — <what was chosen, in one sentence.>

**Alternatives** — <what was rejected and the one-line reason each.>

**Consequences** — <what this makes easy, what it makes hard, what it forbids.>

**Evidence** — `<path under app_workspace/.pipeline/reports/>` or `<PR/commit>`

## Entries

<!-- Append new entries above this line, oldest first inside the section.
     Escaping rule: never rewrite an existing entry to "clean it up". -->

<!--
Worked example of a filled entry — delete this comment when the first real
entry lands; keep the visible template above.

### DL-001 — Use manual constructor injection instead of Hilt

| Field | Value |
|---|---|
| Date | 2026-11-08 |
| Gate | G2 |
| Class | B costly technical |
| Status | accepted |
| Supersedes | nothing |
| Source | HD-002 |

**Context** — The scaffold has no DI framework and the first ViewModel is about
to be written. Adding Hilt means KSP, an annotation processor, and a plugin
applied to every module; it is cheap now and expensive to unwind later.

**Decision** — Use manual constructor injection with an `AppContainer` created
in the `Application` class. Hilt stays available as an opt-in recorded in
`TECH_STACK.md`.

**Alternatives** — Hilt 2.60.1 + KSP 2.3.13: rejected for v1 because it adds a
codegen step and a plugin to every module before the app has more than one
screen. Koin: rejected — dependency of a library, not a platform need.

**Consequences** — Adding a dependency touches `AppContainer` and the ViewModel
factory, nothing else. If DI complexity grows past ten hand-written factories,
revisit with a new entry that supersedes this one.

**Evidence** — `reports/G2-scaffold-evidence.md`
-->
