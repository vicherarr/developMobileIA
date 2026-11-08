---
name: 09-human-review
description: "Classify every open question as a reversible technical default, a costly technical choice, or a product/business intent gap, then either decide-and-log a DL or block the gate with an HD in 02_pending_review/human_decisions.md. Use when an assumption is needed, requirements are ambiguous, a spec gap or conflict appears, a blocker or pending review must be recorded, an ASDD gate cannot advance, the user asks a question or leaves one unanswered, or before resuming after a decision. Triggers: ambiguity, decision, assumption, blocker, review, pending, ASDD, spec gap, conflict, human decision, HD-###, DL-###, unanswered question, stop and ask, memory, architecture record, tech stack, decision log, session state, handoff, context."
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Human Review (ASDD gatekeeper)

ASDD = Agentic Spec-Driven Development. The agent writes the code; the human owns the intent.
This skill is the only legal path from an unknown to a line of code.

## Core rule

**Assume technically. Never assume product.**

Infer anything a competent Android engineer would infer from the repo, the spec, and the web.
Infer nothing about business intent: who the user is, what they pay for, what the law requires, what the brand allows, what "done" means to the customer.

Before writing code that depends on an unknown, classify the unknown. There are exactly three classes.

## Classify the unknown

| Class | Test | Action | Blocking | Artifact |
|---|---|---|---|---|
| **A** — reversible technical default | Undo costs less than one commit and touches no public contract | Decide, continue, log | No | `DL-###` |
| **B** — irreversible or expensive technical choice | Reversing needs a migration, a rewrite, or a new dependency; or it leaks into a public API, schema, or on-disk format | Decide, log, flag for review, keep going | No | `DL-###` + `HD-###` (`blocking: no`) |
| **C** — product, business, data, legal, UX intent, or mutually exclusive requirements | A wrong answer produces the right code for the wrong product | Stop at the gate | Yes | `HD-###` (`blocking: yes`) |

| Situation | Class | Why |
|---|---|---|
| Package layout, file naming, sealed class vs enum | A | Reversible, internal |
| Wire `core-ktx` 1.18.0 or `activity-compose` 1.13.0 into the catalog | A | Already pinned by the scaffold |
| Room vs DataStore for the main store | B | Schema and migration cost |
| Manual DI vs Hilt | B | Pervasive, but the pipeline default is manual + `AppContainer`; pick the default and flag |
| Token storage: plain file vs Keystore-backed | B, or C when the data is regulated | Legal exposure decides which |
| Free-tier limits, pricing, entitlements | C | Business |
| Sign-in providers, account deletion behavior | C | Legal, UX, and data at once |
| "Works offline" against two contradictory spec lines | C | Mutually exclusive requirements |
| Whether to show a splash screen | A | Reversible UX default |
| User-facing copy, tone, locale coverage | C | Product voice |

Borderline rules:

- A technical choice that is expensive **and** the human will care about is still class B. Decide, log, flag, keep moving.
- Never upgrade B to C "to be safe". A blocked gate costs more than a well-documented migration.
- Never downgrade C to B because the answer "seems obvious". Obvious to you is a guess about the customer.
- One requirement that two spec lines cannot both satisfy is class C even when both lines are technical.

## Cost/benefit test

Ask once, before writing any HD: **would a wrong guess cost more than one question?**

Do not block when any of these is true:

- The repo, `app_workspace/.pipeline/spec.json`, or official documentation already answers it. Go read, then decide.
- The answer is reversible within one commit.
- Both plausible answers produce the same code for the current gate.
- It is a style preference with no product or cost consequence.
- You can hide it behind one interface and swap it later at near-zero cost.

Block when the guess would ship the wrong product, break a contract, or force a migration.

## Record technical decisions (class A and B)

1. Decide.
2. Append `DL-###` to `00_memory/DECISION_LOG.md` using the format owned by `10-project-memory`. One entry per decision. Never edit an old entry; supersede it with a new id.
3. For class B only, also raise `HD-###` with `blocking: no` so the human can veto.
4. Continue the current gate. A class B flag never stops work.

Search `DECISION_LOG.md` before writing, and never open a second DL for an already recorded decision.

## Write a human decision

The queue is `02_pending_review/human_decisions.md`. The single-entry template is `02_pending_review/templates/decision_request.md`, sourced from this skill's `assets/decision_request.md`. The bootstrap copies it; do not invent a different shape.

For each HD write two artifacts:

- **Row** in the `## Open` table: id, ISO-8601 UTC timestamp, gate, `blocking`, a one-line closed question, default-if-unanswered, expiry.
- **Detail block** under `## Open details`, copied from `assets/decision_request.md` and stripped of its guidance comments.

Required fields, in this order:

| Field | Rule |
|---|---|
| ID | `HD-###`, next integer, never reused, never renumbered |
| Raised | ISO-8601 UTC, e.g. `2026-11-08T14:22:00Z` |
| Gate | `G0`–`G7` plus the `spec.json` feature id |
| Blocking | `yes` for class C, `no` for a class B flag |
| Question | one sentence, closed form, ends in `?` |
| Options | 2–4, each with consequence, tradeoff, and cost |
| Recommendation | one option plus one sentence why |
| Default if unanswered | the exact behavior, never the word "continue" |
| Impact | files, modules, features, gates affected |
| Expiry | gate close date or ISO date |
| Answer, Applied as | filled only on resolve |

Rules for options:

- 2–4 only. One option is not a choice; five is homework.
- Each option states the consequence for the product, not the implementation detail.
- The recommendation is mandatory. "Up to you" wastes the human's turn.
- The default is mandatory and must be the choice you would make alone. An unanswered question means the default, applied on schedule.

## Batch, never spray

- Keep at most **3** blocking HDs open across the whole pipeline.
- Group by feature, not by the order you discovered the questions.
- One HD equals one decision. Never bundle two independent choices in one entry.
- Class B flags do not count against the cap.
- If a fourth blocking question appears, downgrade the cheapest to a documented default and reclassify it as B.
- Reuse an open HD when a new question has the same answer. Never duplicate a question already in `## Open`.

## Phrase it closed

Good: "Should free users see ads, and if so on which screens?"
Bad: "How should monetization work?"

- Closed form, answerable with an option label.
- No essays, no "what do you think", no design brief, no code.
- State the default explicitly so the human can accept it with one word.
- State what it unblocks, e.g. "unblocks the G1 acceptance criteria".
- No jargon the human must decode.

## Block correctly

- Enter the id and reason in `app_workspace/.pipeline/STATE.json` and set the top-level `status` to `blocked`:
  `"blocking": [{"id": "HD-001", "reason": "free-tier limit undefined"}]`
- Mirror the same id in `app_workspace/.pipeline/spec.json` `openDecisions[]` with its `default` and `blocking: true`.
- Do not write the evidence file that advances the gate. No evidence, no advance.
- Do stop useful non-blocking work: finish scaffolding, tests, and docs that do not depend on the answer.
- Do not open a new gate, do not "temporarily guess and fix later", do not mark work done.

## Unblock

1. Read the answer in `02_pending_review/human_decisions.md`.
2. If the answer is a new option, re-classify and re-ask once. Never interpret a free-text answer into a design.
3. Update `app_workspace/.pipeline/spec.json`: write the answer as a testable constraint or acceptance criterion, then drop the id from `openDecisions[]`.
4. Append a `DL-###` that references the `HD-###` and quotes the answer.
5. Remove that entry from `"blocking"` in `STATE.json`, leave the others intact, and restore `status` to `in_progress` only when the array is empty.
6. Move the HD row from `## Open` to `## Resolved` with answer, resolve timestamp, and `Applied as: DL-###`.
7. Update `00_memory/SESSION_STATE.md` next action.
8. Resume at the stage you stopped, not from zero.

Never resolve an HD you did not raise. Never answer your own blocking question.

## Anti-patterns

| Do NOT | Why |
|---|---|
| Ask what the repo, spec, or docs already answer | Wastes the human's scarcest resource |
| Block on naming, formatting, or library preference | Reversible; class A, decide it |
| Silently guess pricing, auth, legal, or retention | Ships the wrong product |
| Ask the same question twice in different words | Erodes trust in the queue |
| Ask without options or a recommendation | Turns a decision into an essay |
| Raise an HD with no default | Makes the human do your thinking |
| Report the question only in chat | Lost at the next session |
| Leave resolved HDs in `## Open` | Inflates the blocking count |
| Keep working quietly past a blocking HD | Corrupts the gate contract |
| Reopen or edit an old `DL-###` | History must stay immutable |

## Contract

**Reads** — `02_pending_review/human_decisions.md`; `02_pending_review/templates/decision_request.md`; `app_workspace/.pipeline/STATE.json`; `app_workspace/.pipeline/spec.json`; `00_memory/DECISION_LOG.md`; `00_memory/SESSION_STATE.md`; the current gate's evidence in `app_workspace/.pipeline/reports/`.

**Writes** — `02_pending_review/human_decisions.md` (append the row and detail block; move rows to Resolved); `00_memory/DECISION_LOG.md` (append only); `app_workspace/.pipeline/STATE.json` (`blocking[]`); `00_memory/SESSION_STATE.md` (next action); `assets/decision_request.md` only when maintaining this skill.

**Gate** — all gates `G0`–`G7`. Primary entry points are `G0` intake and `G1` spec; class B flags may appear at any gate. A `blocking: yes` HD freezes its gate: no evidence file, no advance.

**Handoff** — return to the orchestrator: open HD ids and count, the frozen gate, the next action that becomes legal after each answer, and the `DL` ids written. Mirror the same facts in `SESSION_STATE.md`. The full question state machine, the `STATE.json` mapping, and the unavailable-human escalation rules live in `references/asdd-protocol.md`.

## Done checklist

- [ ] Every unknown of this step is classified A, B, or C.
- [ ] Every class A and B decision has a `DL-###` in `DECISION_LOG.md`.
- [ ] Every class B decision has a `blocking: no` HD with a default and an expiry.
- [ ] Open blocking HDs are at most 3, each with 2–4 options, recommendation, default, impact, and expiry.
- [ ] `STATE.json` `blocking[]` matches the `## Open` table exactly.
- [ ] No evidence file was written for a frozen gate.
