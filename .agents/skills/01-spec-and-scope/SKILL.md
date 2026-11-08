---
name: 01-spec-and-scope
description: Turns a natural-language app idea into a frozen, machine-readable spec and a gate-aware plan before any code exists. Use when starting a new app or a large feature, when requirements are vague or contradictory, when you need acceptance criteria, MVP scope cuts, non-goals, or a task plan mapped to pipeline gates. Triggers - new app, idea, requirements, scope, MVP, spec, acceptance criteria, plan, feature breakdown, what should we build, ambiguous request.
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Spec and scope (G1)

The most expensive agent failure is building the wrong app quickly. This skill
converts intent into two artifacts and refuses to proceed on ambiguity.

## Contract

- **Reads:** the user request, `00_memory/ARCHITECTURE.md`,
  `00_memory/TECH_STACK.md` (constraints only)
- **Writes:** `app_workspace/.pipeline/spec.json`,
  `app_workspace/.pipeline/plan.md`, updates `STATE.json` (`stage: G1`),
  may append `HD-###` to `02_pending_review/human_decisions.md`
- **Gate:** `G1`
- **Handoff:** `02-android-scaffold` (G2)

## Step 1 - Extract, then ask at most three questions

From the request, fill what you can. For each unknown, decide:

| Unknown kind | Action |
|---|---|
| Technical, reversible (package name, minSdk, theme seed, module layout) | Pick the default, log `DL`, continue |
| Technical, costly to reverse (backend vs local-only, auth provider, KMP) | Pick the default, flag in `plan.md` as "confirm before G3", continue |
| Product / business / legal / identity / money | **Block**, write `HD` via `09-human-review` |

Only ask what blocks the *next two gates*. A question about notifications does
not block scaffolding. Never exceed three blocking questions at once.

Sane defaults when unanswered: `minSdk 24` (official template default),
`targetSdk`/`compileSdk 36`, package `com.<org>.<app>` derived from the app
name, single-activity Compose app, no backend (local-first with a repository
interface that can be swapped), Material 3 dynamic color, light+dark, English
strings externalized in `strings.xml`.

## Step 2 - Write `spec.json`

Copy `assets/spec_template.json`, then make every field concrete. Shape:

```json
{
  "schema": 1,
  "app": { "name": "", "applicationId": "", "namespace": "",
           "minSdk": 24, "targetSdk": 36, "compileSdk": 36 },
  "product": { "pitch": "", "audience": "", "platforms": ["phone"] },
  "features": [
    { "id": "F1", "name": "", "priority": "must|should|could",
      "description": "",
      "acceptance": [ { "id": "AC-01", "given": "", "when": "", "then": "" } ],
      "screens": [ { "id": "S1", "name": "", "states": ["loading","empty","error","content"] } ],
      "data": [ { "entity": "", "fields": ["id:String"], "source": "local|remote|both" } ] }
  ],
  "nonGoals": [],
  "constraints": { "offlineFirst": true, "auth": "none", "analytics": "none",
                   "monetization": "none", "perfBudgetMs": 400 },
  "risks": [ { "id": "R1", "risk": "", "impact": "high|med|low", "mitigation": "" } ],
  "openDecisions": []
}
```

Hard rules:

- Every `must` feature has **at least one acceptance criterion** with a
  testable `then`. "Works well" is not a criterion.
- Acceptance ids are stable (`AC-01`, `AC-02`, ...) — later tests reference
  them by id in their name or KDoc.
- `nonGoals` is never empty. If you cannot name what you are *not* building,
  the scope is not bounded.
- No `TBD`, `TODO`, `<placeholder>`, or empty strings in a `must` feature.
  Validate before leaving G1:

```bash
python3 - <<'PY'
import json, re, sys
p = "app_workspace/.pipeline/spec.json"
s = json.load(open(p))
bad = re.compile(r"(TBD|TODO|<[^>]+>)", re.I)
raw = open(p).read()
assert not bad.search(raw), "placeholder left in spec.json"
must = [f for f in s["features"] if f["priority"] == "must"]
assert must, "no must-have feature"
for f in must:
    assert f.get("acceptance"), f"{f['id']} has no acceptance criteria"
assert s.get("nonGoals"), "nonGoals is empty"
print("spec ok:", len(s["features"]), "features,", sum(len(f.get('acceptance',[])) for f in s['features']), "criteria")
PY
```

## Step 3 - Cut an MVP that G2-G5 can actually finish

Order features by `priority`, then by dependency. The first vertical slice must
be **demoable end to end**: one screen, one real data path, one test, one
preview. Prefer "one feature done to the wire" over "five features at 40%".

Classify each feature as:

- **Slice 1 (G2-G5):** must-have, local data only, no third-party SDK.
- **Slice 2 (G5-G7):** must-have with network/auth/payments.
- **Later:** `should`/`could`, or anything needing a decision you have not got.

Anything in "Later" goes to `nonGoals` with the reason, not into code.

## Step 4 - Write `plan.md`

A plan is a checklist of gate-scoped tasks, each with the files it touches and
the evidence it produces. Template:

```markdown
# Plan - <app name>

## Slice 1 (target: G5)
- [ ] G2 scaffold: android create, modules, catalog pin  -> reports/scaffold-*.json
- [ ] G3 F1 data: Entity/Dao/Repository/UseCase + unit tests -> reports/domain-*.json
- [ ] G4 F1 ui: Screen + ViewModel + previews -> reports/ui-*.json
- [ ] G5 verify: build + test + lint + preview -> reports/verify-*.json

## Slice 2
- [ ] F2 ...

## Explicitly not doing (non-goals)
- ...
```

Keep `plan.md` in sync with `spec.json`; when they disagree, `spec.json` wins
and the plan is a bug.

## Step 5 - Initialize state

Set `STATE.json` to `{"stage":"G1","status":"pass","next_action":"Run 02-android-scaffold"}`,
or `"status":"blocked"` plus `blocking: [{"id":"HD-001","reason":"..."}]` when a
product question is open. Unblocking requires the answer, not a guess.

## Quality bar

- A competent developer who has never seen the app can implement `must`
  features from `spec.json` alone.
- Every screen in `screens` lists its non-happy states (loading/empty/error).
- Every entity names its source of truth and its offline story.
- Each risk has a mitigation that fits in this pipeline (test, abstraction,
  or scope cut).
- The plan's first four tasks map 1:1 to G2, G3, G4, G5.

## Anti-patterns

- **Do NOT** scaffold a project to "discover" requirements.
- **Do NOT** invent a backend, pricing model, or login requirement the user
  never mentioned.
- **Do NOT** write acceptance criteria that only you can verify by eye when a
  test could verify them.
- **Do NOT** enumerate 20 features in the first spec; a spec you cannot finish
  is a spec that fails.
- **Do NOT** let `nonGoals` be empty or a formality.
- **Do NOT** carry `TBD` markers past G1.

## Stop conditions

- A blocking `HD` is open → stop; do not start G2.
- The user's request implies a platform you cannot build here (iOS, server) →
  record it in `nonGoals`, ask if it is in scope, do not silently narrow.
- The request contradicts itself → write one `HD` listing the contradiction
  and the two readings, with a recommendation.
