# ASDD question protocol

Reference for `09-human-review`. Defines how a question lives, where its state
is stored, and what the agent does when the human does not answer.

ASDD = Agentic Spec-Driven Development. The rule it protects: **assume
technically, never product**. A technical guess is recorded and reversible; a
product guess is a defect even when the code compiles.

## Vocabulary

| Term | Meaning |
|---|---|
| `DL-###` | Decision log entry, append-only, in `00_memory/DECISION_LOG.md` |
| `HD-###` | Human decision, queued in `02_pending_review/human_decisions.md` |
| Class A | Reversible technical default: decide, log, move on |
| Class B | Costly or irreversible technical choice: decide, log, flag, move on |
| Class C | Product, business, data, legal, UX intent, or mutually exclusive requirements: block |
| Blocking | A `blocking: yes` HD. Freezes its gate until answered |
| Default | The behavior applied when a non-blocking HD expires unanswered |
| Advance | The state transition allowed only by an evidence file in `app_workspace/.pipeline/reports/` |

## State machine

```
                 classify C
   (unknown) ───────────────► raised ──────────► needs-info
                                 │  ▲                 │
                                 │  └─────────────────┘
                                 │      (human asks back)
                                 ▼
                              answered ─────────► applied ─────► archived
                                 │                                  ▲
                                 │                                  │
                     expiry, non-blocking                          │
                                 └────────► assumed ───────────────┘
```

| State | Trigger | Actor | Artifact change |
|---|---|---|---|
| `raised` | Classification returns C, or B needing a veto | Agent | New row in `## Open`; detail block in `## Open details`; `STATE.json` `blocking[]` gets the id when `blocking: yes` |
| `needs-info` | The human asks for clarification, a screenshot, or a cost estimate | Agent answers in the detail block; state returns to `raised` | Detail block notes appended; no new id |
| `answered` | The human picks an option or writes one | Human | `Answer` and `Resolved (UTC)` filled; row still in `## Open` |
| `applied` | Agent encoded the answer | Agent | `spec.json` updated; `DL-###` appended; `STATE.json` `blocking[]` entry removed; row moved to `## Resolved` with `Applied as` |
| `assumed` | Expiry passed on a `blocking: no` HD | Agent | Default applied; `DL-###` with `source: default`; row moved to `## Resolved` with `Applied as` |
| `archived` | Optional compaction of long-resolved entries | Agent | Entry may move to an archive file; ids are never reused or renumbered |

Rules:

- One HD moves in one direction at a time. `raised → answered → applied` is the
  normal path; skipping `answered` means the agent answered its own question.
- `needs-info` never changes the id and never creates a second HD for the same
  decision.
- `assumed` is legal only for `blocking: no`. A blocking HD has no default that
  fires automatically; it waits, and the gate waits with it.
- `archived` never deletes the decision. The `DL-###` remains in the log forever.

## Where state lives

| Fact | File | Field |
|---|---|---|
| The question, options, recommendation | `02_pending_review/human_decisions.md` | Detail block under `## Open details` |
| The queue at a glance | same file | `## Open` and `## Resolved` tables |
| Whether the pipeline is stuck | `app_workspace/.pipeline/STATE.json` | `blocking: [{id, reason}]` |
| What the answer changed | `app_workspace/.pipeline/spec.json` | The affected acceptance criterion |
| Why the answer was chosen | `00_memory/DECISION_LOG.md` | New `DL-###` naming the `HD-###` |
| What happens next | `00_memory/SESSION_STATE.md` | Next action line |
| Proof the gate may advance | `app_workspace/.pipeline/reports/` | The gate's evidence file |

Do not store the same fact in two places with different wording. The queue
holds the question; `DECISION_LOG.md` holds the settled answer; `spec.json`
holds the testable constraint.

## Queue file shape

`02_pending_review/human_decisions.md` has one header, one `## Open` table, one
`## Resolved` table, and a detail section. Keep this shape; the bootstrap
copies `assets/decision_request.md` to `templates/decision_request.md` and
creates the queue from it.

```markdown
# Human decisions — <app-name>

<!-- One queue for the project. `## Open` rows freeze a gate. `## Resolved`
     rows are permanent: never delete or renumber them. -->

## Open

| ID | Raised (UTC) | Gate | Blocking | Question | Default if unanswered | Expires |
|---|---|---|---|---|---|---|

## Resolved

| ID | Resolved (UTC) | Answer | Applied as | Resolved by |
|---|---|---|---|---|

## Open details

## Resolved details
```

- `Blocking` holds `yes` or `no`; only `yes` rows appear in `STATE.json.blocking[]`.
- `Applied as` holds the `DL-###` written when the answer was encoded.
- A detail block starts under `## Open details`; on resolve it moves under
  `## Resolved details` with its answer fields filled. Block contents are
  append-only while open: notes and `needs-info` replies go at the bottom.

## `STATE.json` mapping

`blocking[]` is the machine-readable mirror of the `## Open` table, restricted
to `blocking: yes` entries.

Before raising a blocking HD:

```json
{
  "gate": "G1",
  "blocking": []
}
```

After raising two HDs, one blocking and one advisory:

```json
{
  "gate": "G1",
  "blocking": [
    { "id": "HD-001", "reason": "free-tier limit undefined; G1 acceptance cannot be written" }
  ]
}
```

`blocking: no` HDs may be tracked in the same array only if the consumer filters
on `blocking`, so the safe default is: **the array contains blocking entries
only**. Advisory flags stay in `human_decisions.md`.

On unblock, remove exactly one element and leave the rest:

```json
{ "gate": "G1", "blocking": [] }
```

Invariant to check before any gate advance: every id in `blocking[]` appears in
`## Open` with `blocking: yes`, and every `blocking: yes` row appears in
`blocking[]`. A mismatch is a defect, not a warning.

## Gate interaction

- A gate can only advance on an evidence file in
  `app_workspace/.pipeline/reports/`. A blocking HD means that file is not
  written. Nothing else about the gate changes.
- Non-blocking work continues: tests, docs, scaffolding, and any code that does
  not depend on the open answer.
- Never advance a gate "provisionally" and never annotate the evidence with a
  promise to fix later.
- On unblock, resume at the stage where you stopped. Do not replay earlier gates.

## Escalation when the human is unavailable

Define unavailability concretely: no answer across two consecutive agent
sessions, or the HD is past its expiry date.

| HD kind | Human unavailable | What NOT to do |
|---|---|---|
| `blocking: no` (class B) | At expiry, apply the stated default, append `DL-###` with `source: default`, move the HD to `## Resolved` as `assumed` | Do not silently choose a different option than the documented default |
| `blocking: yes` (class C) | Stop. Record the hold in `STATE.json` `blocking[]` and in `SESSION_STATE.md` next action. Produce no advance evidence | Do not guess, do not partially implement, do not mark the gate done |
| Ambiguous free-text answer | Re-ask once, citing the ambiguity and the specific options | Do not interpret it into a design |

Additional escalation rules:

- One reminder per session maximum; bundle it with the other open HDs.
- Never raise a second HD to work around an unanswered first one.
- If a blocking HD blocks all remaining work, report it as the session's only
  outcome: id, question, default, and the exact next legal action.
- Expiry is a date or a gate boundary, never "eventually". An HD without expiry
  is malformed.

## Hygiene

- Search the queue before raising: same feature, same answer, same words.
- 3 blocking HDs maximum, pipeline-wide. The cap applies to the whole queue, not
  per gate.
- Group by `spec.json` feature id so one human turn resolves a coherent theme.
- Total detail block under 40 lines; if it needs more, the question is too broad
  and must be split.
- Closed form only. If the answer could start with "it depends", split the
  question.

## Worked example

Scenario: a notes app, scaffold done, the agent is at `G1`.

### HD-001 — blocking, class C

While writing acceptance criteria the agent finds two spec lines: "notes are
private to the device" and "the user can restore notes on a new phone". Both
cannot be true without sync.

1. Classification: product intent (data privacy plus portability) → class C.
2. The agent raises `HD-001`, `blocking: yes`, expiry `G1 close`.

```markdown
## Open

| ID | Raised (UTC) | Gate | Blocking | Question | Default if unanswered | Expires |
|---|---|---|---|---|---|---|
| HD-001 | 2026-11-08T09:12:00Z | G1 | yes | Must notes survive reinstall on a new device? | none — gate stays frozen | G1 close |
```

Options: A local-only, no restore (smallest scope); B manual export/import file;
C automatic cloud sync (largest scope). Recommendation: B, because it satisfies
portability without accounts, legal exposure, or a backend. Default: none; the
question is blocking.

3. `STATE.json`:

```json
{ "gate": "G1", "blocking": [
  { "id": "HD-001", "reason": "notes portability vs device-local privacy; G1 acceptance cannot be finalised" }
] }
```

4. G1 evidence is not written. The agent finishes the parts of the spec that do
   not depend on the answer and stops.
5. Human answers at `2026-11-08T09:41:00Z`: "B — export/import is enough for v1."
6. Unblock:

```json
{ "gate": "G1", "blocking": [] }
```

`spec.json` gains a testable criterion: "the user can export all notes to a file
and import them on another device; no network calls are required." `DL-001` is
appended, quoting the answer and naming `HD-001`. The row moves to `## Resolved`
with `Applied as: DL-001`. `SESSION_STATE.md` next action becomes "finalise G1
acceptance criteria and write the G1 evidence file."

### HD-002 — non-blocking, class B

At `G3` the agent must choose the persistence layer for note bodies. It picks
Room 2.8.5 with generated schemas, logs `DL-002`, and raises `HD-002` with
`blocking: no`, expiry `G4 close`, default "Room 2.8.5, default schema export
directory".

Work proceeds through `G3` and `G4`. The human never answers. At `G4` close:

1. The default is already implemented, so nothing changes.
2. Append `DL-003`, `source: default`, referencing `HD-002`.
3. Move `HD-002` to `## Resolved` as `assumed`, with `Applied as: DL-003`.
4. `blocking[]` was never touched, so no gate was frozen.

Net effect: one gate frozen for 29 minutes on a real product question, one
technical choice recorded and vetoable, zero dead time.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `blocking[]` non-empty but `## Open` empty | Row moved before the state cleared | Remove the stale id, re-verify the invariant |
| HD answered in chat, absent from the queue | Raised only in conversation | Recreate the entry with the original timestamp, then apply |
| Two HDs for one decision | No search before raising | Merge into the older id, mark the newer `duplicate` |
| Gate advanced with a blocking HD open | Evidence written early | Delete the evidence file, restore the gate, re-run the stage tail |
| `DECISION_LOG.md` rewritten to "clean up" | History treated as draft | Restore, then supersede with a new `DL-###` |
| HD stays `open` with no expiry | Template not followed | Add expiry from the template; malformed entries count toward the cap |
