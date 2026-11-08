<!--
Single human-decision entry template.

Bootstrap copies this file to `02_pending_review/templates/decision_request.md`.
To raise a decision: copy this block into `02_pending_review/human_decisions.md`
under "## Open details", add the matching row to the "## Open" table, and
delete every HTML comment from the filled copy. Keep the order of the fields.

Rules: ids are HD-001, HD-002, ... monotonic and never reused. Timestamps are
ISO-8601 UTC. 2–4 options. A recommendation and a default are mandatory.
Blocking entries are capped at 3 open at once.
-->

## HD-000 — <short imperative title, 60 characters max>

| Field | Value |
|---|---|
| ID | `HD-000` |
| Raised (UTC) | `<YYYY-MM-DDThh:mm:ssZ>` |
| Gate | `<G0..G7>` |
| Feature | `<spec.json feature id>` |
| Blocking | `<yes>` or `<no>` |
| Class | `<C product/business/data/legal/UX>` or `<B costly technical>` |
| Expires | `<gate close>` or `<YYYY-MM-DD>` |
| Default if unanswered | <exact behavior the agent will take> |
| Impact | <files, modules, features, gates> |
| Status | `open` |

**Question** (closed form, one sentence, ends in `?`)

> <Question.>

### Options

<!-- 2–4 options. Each states the consequence, a tradeoff, and a rough cost. -->

| # | Option | What it means | Tradeoff | Cost |
|---|---|---|---|---|
| A | <label> | <consequence for the product> | <what gets worse> | <S/M/L> |
| B | <label> | <consequence for the product> | <what gets worse> | <S/M/L> |
| C | <label> | <consequence for the product> | <what gets worse> | <S/M/L> |

### Recommendation

**<A/B/C>** — <one sentence: why this option wins for this project>.

### Default if unanswered

On `<expiry date>` or at gate close, proceed with **<option>**. Record `DL-###`
with `source: default`, mark this entry `assumed`, and move it to Resolved.
<State any part that must stay untouched until the human answers.>

### What it unblocks

<acceptance criterion, screen, module, or gate that cannot proceed.>

### Answer

<!-- Human fills exactly one line. Free text is allowed only as a new option. -->

**Answer:** `<A | B | C | new option>`

**Resolved (UTC):** `<YYYY-MM-DDThh:mm:ssZ>`

**Applied as:** `DL-###`

### Resolution notes

<!-- Agent fills on unblock: what changed, where, and the next legal action. -->

<Files updated, decision recorded, gate resumed.>
