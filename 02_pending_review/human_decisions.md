# Human decisions queue (ASDD)

Single queue for everything the agent is **not allowed to guess**. One entry per
question, with options and a recommendation. The agent stops at the gate named in
the entry until it is answered.

Rules:

- Ids are sequential: `HD-001`, `HD-002`, … Never reuse an id.
- Only product/business/legal/money/identity questions belong here. Technical
  defaults are decided by the agent and recorded in `00_memory/DECISION_LOG.md`.
- Maximum **3 open blocking** entries at a time. Batch the rest as non-blocking.
- Every entry has a `Default if unanswered` so work can proceed when the question
  is non-blocking.
- When answered: move the row to **Resolved**, append a `DL-###` if the answer
  changes a technical choice, update `.pipeline/spec.json`, then remove the id
  from `STATE.json.blocking`.

Template for a new entry: `templates/decision_request.md`.

## Open

| Id | Date | Gate | Blocking | Question | Options (recommended first) | Default if unanswered | Impact |
|----|------|------|----------|----------|-----------------------------|-----------------------|--------|
| —  | —    | —    | —        | _none yet_ | — | — | — |

## Resolved

| Id | Resolved | Decision | DL | Applied in |
|----|----------|----------|----|------------|
| —  | —        | _none yet_ | — | — |

## Changelog

- `2026-11-08` — queue created empty. The pipeline starts at `G0` with no
  blocking decisions.
