# Decision log

Append-only. Never rewrite or delete an entry; supersede it with a new one that
references the old id. One entry per decision, newest at the bottom.

Format:

```
## DL-### — <short title>
- Date: <YYYY-MM-DD>
- Gate: <G0..G7>
- Status: accepted | superseded by DL-### | provisional
- Context: <why a decision was needed>
- Decision: <what we do>
- Alternatives: <what we did not do>
- Consequences: <cost, risk, follow-up>
```

---

## DL-001 — Skills live in `.agents/skills/`
- Date: 2026-11-08
- Gate: G0
- Status: accepted
- Context: The initial sketch used `01_skills/<stage>/SKILL.md`. DSH discovers
  skills only one level deep in fixed roots (`.dsh/skills`, `.agents/skills`,
  `~/.dsh/skills`, `~/.agents/skills`); nested `**/SKILL.md` are ignored.
  Android CLI installs official skills into `.agents/skills/<name>/`.
- Decision: All pipeline skills live in `.agents/skills/<numbered-slug>/`, which
  both DSH and Android CLI read. A symlink at the project root
  (`.agents -> kit/.agents`) makes them visible when the kit is not the root.
- Alternatives: `.dsh/skills` (DSH-only), duplicate copies per tool.
- Consequences: any new skill must be a direct child of `.agents/skills/`; the
  numbered prefixes are ordering only and must stay kebab-case.

## DL-002 — Start from the official generator, never hand-written Gradle
- Date: 2026-11-08
- Gate: G2
- Status: accepted
- Context: Agents routinely produce plausible but non-building Gradle files.
- Decision: `android create` (template `empty-activity`) is the only way a
  project is created; post-processing is limited to `local.properties`,
  `.gitignore`, `gradle.properties` defaults and `rootProject.name`.
- Alternatives: copy-paste a template repo; hand-write the build.
- Consequences: the template's version set (AGP 9.0.1 / Gradle 9.1.0 / Kotlin
  2.3.20 / Compose BOM 2026.03.01) is the safe baseline; upgrades are separate
  gated changes.

## DL-003 — AGP 9 with built-in Kotlin, KSP2 only
- Date: 2026-11-08
- Gate: G2
- Status: accepted
- Context: AGP 9 enables built-in Kotlin and makes kapt incompatible.
- Decision: never apply `org.jetbrains.kotlin.android`; annotation processing
  uses KSP2 (`com.google.devtools.ksp`). Hilt and Room are configured for KSP.
- Alternatives: opt out of built-in Kotlin (removed in AGP 10).
- Consequences: some older libraries that require kapt are excluded by design.

## DL-004 — Evidence gates instead of "it works"
- Date: 2026-11-08
- Gate: G0
- Status: accepted
- Context: Agent self-reports are unreliable; token-wasting regressions happen
  when a build is assumed green.
- Decision: every gate writes a JSON report under
  `app_workspace/.pipeline/reports/` with a `status` field; the orchestrator
  advances only on `status: pass`. Gates can regress and are re-verified.
- Alternatives: conversational status only.
- Consequences: slightly more disk writes; dramatically fewer false positives.

## DL-005 — Manual DI by default, Hilt opt-in
- Date: 2026-11-08
- Gate: G3
- Status: provisional
- Context: Hilt adds build complexity, KSP coupling and failure modes that hurt
  an agent loop; most pipeline apps start small.
- Decision: constructor injection + `AppContainer` until the graph exceeds ~30
  bindings or the team already standardizes on Hilt.
- Alternatives: Hilt, Koin, Anvil.
- Consequences: switching later is a mechanical refactor; revisit at G7.

## DL-006 — Screenshot testing: Roborazzi first, AGP test suites when stable
- Date: 2026-11-08
- Gate: G5
- Status: accepted
- Context: the standalone `com.android.compose.screenshot` plugin is deprecated;
  Google recommends AGP test suites, which are still experimental (AGP 9.5+).
- Decision: use `android preview render` for zero-config visual checks and
  Roborazzi for regression baselines on the JVM; adopt AGP test suites once the
  project is on AGP 9.5+ and the API is stable.
- Alternatives: Paparazzi (LayoutLib), instrumented screenshot tests.
- Consequences: one extra test dependency; no emulator needed for visual diffs.
