# HD-### — <one-line question, closed form>

- **Date:** `<YYYY-MM-DDThh:mm:ssZ>`
- **Gate / stage:** `G?` — `<stage name>`
- **Blocking:** `yes` (the line stops) | `no` (proceed with the default)
- **Owner:** `<human role>`
- **Expires:** `<YYYY-MM-DD>` or `none`

## Context

Two or three sentences: why this cannot be decided by the agent, and what
changes depending on the answer. Link the spec feature (`F?`) and the affected
files.

## Options

| # | Option | What it means | Cost / risk | Recommended |
|---|---|---|---|---|
| 1 | `<option>` | `<concrete behaviour>` | `<cost>` | ✅ |
| 2 | `<option>` | `<concrete behaviour>` | `<cost>` | |
| 3 | `<option>` | `<concrete behaviour>` | `<cost>` | |

## Recommendation

Option `<n>`, because `<reason tied to the spec or constraints>`.

## Default if unanswered

`<option n>` — applied only if this entry is non-blocking. If blocking, nothing
happens until the answer arrives.

## Impact if wrongly assumed

- Files: `<paths>`
- Features: `F?`
- Reversibility: `trivial | moderate | expensive`
- User-visible: `<yes/no + what>`

## Answer

<!-- Filled by the human. Free text is fine, but "option 2" is enough. -->

`<pending>`

## Applied

<!-- Filled by the agent after applying the answer. -->

- [ ] `spec.json` updated
- [ ] `DL-###` appended to `00_memory/DECISION_LOG.md`
- [ ] id removed from `STATE.json.blocking`
- [ ] row moved to **Resolved** in `02_pending_review/human_decisions.md`
