---
name: 05-build-test-loop
description: Runs the deterministic build-test-lint-preview loop that decides whether G5 is green, and triages compile, Gradle, test, lint and preview failures with one fix per iteration. Use whenever code changed, the build breaks, tests fail, lint reports errors, previews do not render, or before declaring any feature done. Triggers - build failed, compile error, gradle error, run tests, red tests, lint, ktlint, detekt, verify, is it green, fix the build, CI.
metadata:
  author: TodoMoteros
  version: "1.0"
---

# Build and test loop (G5)

Green is a measurement, not an opinion. This skill is the only sanctioned way to
claim that code works on the JVM.

## Contract

- **Reads:** the changed sources, `app_workspace/.pipeline/spec.json`,
  `00_memory/TECH_STACK.md`
- **Writes:** `app_workspace/.pipeline/reports/verify-<UTC>.json`,
  `.pipeline/artifacts/previews/**` (optional), fix commits in source files
- **Gate:** `G5`
- **Handoff:** `07-device-verification` (G6) or the next feature slice

## Run the loop

```bash
.agents/skills/05-build-test-loop/scripts/verify.sh            # build + test + lint + preview list
.agents/skills/05-build-test-loop/scripts/verify.sh --no-lint  # fast iteration
.agents/skills/05-build-test-loop/scripts/verify.sh --preview-render  # also render PNGs
.agents/skills/05-build-test-loop/scripts/verify.sh --require-preview # make previews blocking
```

Equivalently, step by step (same order, same meaning):

| # | Step | Command | Pass means |
|---|---|---|---|
| 1 | Build | `./gradlew :app:assembleDebug` | APK produced, no compile errors |
| 2 | Unit tests | `./gradlew :app:testDebugUnitTest` | 0 failures, 0 errors, >0 tests when logic exists |
| 3 | Lint | `./gradlew :app:lintDebug` | 0 errors (warnings allowed but triaged) |
| 4 | Previews (advisory) | `android preview list -f json` | inventory lists every screen state; blocks only with `--require-preview` |
| 5 | Visual (advisory) | `android preview render -o .pipeline/artifacts/previews -f json` | PNG per preview, no render error |

Evidence: `reports/verify-<UTC>.json` with `status: pass`, per-step statuses,
unit-test counts, lint counts, preview count and the APK path. The script exits
non-zero when the gate is open — never hand-write this report.

**Previews are advisory by default.** `build`, `test` and `lint` decide G5;
`preview list`/`render` can fail for reasons outside the project (CLI packs,
network, host). Pass `--require-preview` when the environment is known good and
you want a blocking visual inventory.

## Loop discipline

The loop is cheap; thrashing is expensive.

1. **Read the first error, not the whole log.** Gradle prints the root cause
   near the failing task; the first `e:` / `FAILURE:` block is the one to fix.
2. **One hypothesis, one change, one re-run.** Bundling fixes makes causality
   unknowable.
3. **Count distinct error classes.** Three attempts on the same class → stop,
   read the docs (`android docs search "<exact message>"`), or escalate with an
   `HD`. Do not retry the same command hoping for a different result.
4. **Never disable a check to pass the gate.** Suppressing lint, `@Suppress`,
   `-Xskip-metadata-version-check`, or deleting a failing test is not a fix; it
   is evidence tampering.
5. **Re-run from the failing step** (`--only build` / `--only test`) while
   iterating, then the full loop before declaring green.
6. **A flaky test is a bug.** Fix determinism (clock, dispatcher, ordering,
   animation), not the assertion.

## Fast triage

| Error class | Where to look | Typical fix |
|---|---|---|
| `Unresolved reference: X` | the imported symbol vs the dependency | missing catalog alias / wrong package; add dependency via catalog, not inline version |
| `Cannot access 'X': it is internal` | module boundaries | don't reach into another module's internals; expose a public API |
| `Type mismatch` / `None of the following functions can be called` | call site | wrong argument type (e.g. `StateFlow` vs `State`, `List` vs `ImmutableList`) |
| `Class 'X' is not abstract and does not implement abstract member` | interface change | implement the new member or fix the interface |
| `Unresolved reference: R` | namespace/resource | check `namespace` in `build.gradle.kts` and resource name casing |
| `Duplicate class` | mixed versions | align via BOM or `resolutionStrategy`; find with `./gradlew :app:dependencies` |
| `Execution failed for task ':app:kspDebugKotlin'` | Room/Hilt annotation | read the KSP message; usually a missing `@Entity`/`@Inject` or a wrong type |
| `Room ... cannot find setter/field` | entity | annotate with `@ColumnInfo`, `@PrimaryKey`, or add a no-arg constructor |
| `SerializationException: Serializer for class 'X' is not found` | `@Serializable` missing or plugin not applied | add annotation + `kotlin-serialization` plugin |
| `Compose: @Composable invocations can only happen from ...` | composable called from non-composable | pass a lambda/state instead |
| `IllegalStateException: CompositionLocal ... not present` | theme/provider | wrap the preview/test in the app theme |
| `android preview` → `Illegal entry path escaping destination directory: gradle-build-system` | Android CLI 1.1.16717390 bug unpacking its gradle pack (zip-slip guard) | non-blocking; `android update`, or use Roborazzi/Paparazzi for visual regressions |
| `Lint Error: ...` | lint report | fix, or (rarely) suppress with a written `DL` and a TODO |
| `OutOfMemoryError` in Gradle | heap | raise `org.gradle.jvmargs`, use `--no-daemon` once |
| `SDK location not found` | `local.properties` | re-run scaffold post-processing |
| `Unsupported class file major version` | JDK mismatch | use JDK 17+ for AGP 9 |

Deeper catalogue with diagnosis commands: `references/failure-triage.md`.

## Reading logs efficiently

```bash
./gradlew :app:assembleDebug --console=plain 2>&1 | grep -E "^e: |FAILURE:|Caused by:" | head -n 20
```

- `e:` = Kotlin compile error, `w:` = warning (ignore during the loop).
- `What went wrong:` section = the actionable part.
- Test HTML report: `app/build/reports/tests/testDebugUnitTest/index.html`;
  XML is easier to parse: `app/build/test-results/testDebugUnitTest/*.xml`.
- Lint: `app/build/reports/lint-results-debug.txt` (or `.sarif`).

Do not paste entire Gradle logs into the conversation; extract the signature
and the file:line.

## What "green" must cover

- Every `must` acceptance criterion (`AC-*`) in the spec has at least one test
  that can fail. A criterion with no test is an open gate even if the build is
  green.
- New screen states (loading/empty/error/content) each have a preview.
- Public logic has a unit test; the ViewModel state machine has a test with a
  fake dependency (see `06-testing-strategy`).
- No new lint **errors**. Warnings must be either fixed or recorded.
- Deterministic: the loop passes twice in a row without cleaning.

## Anti-patterns

- **Do NOT** run `./gradlew clean` reflexively; it hides incremental bugs and
  wastes minutes.
- **Do NOT** claim success from a `--dry-run`, from an IDE-less "looks right",
  or because "the code is simple".
- **Do NOT** edit `build/` outputs or hand-write an APK.
- **Do NOT** add `-Xlint:none`, `abortOnError = false`, or `suppressWarnings`
  to move the gate.
- **Do NOT** loop more than 3 times on one error class without new information.
- **Do NOT** leave the workspace red at the end of a session; if you must,
  record it in `SESSION_STATE.md` as an open blocker.

## Stop conditions

- Same error persists after 3 informed attempts → write a blocking `HD` with
  the log excerpt and the two most likely causes.
- Failure is environmental (SDK/JDK/network/disk) and cannot be fixed inside
  the project → `HD` (environment), stop the line.
- The fix requires a product decision (e.g. remove a feature to make tests
  pass) → `HD`, never silently cut scope.
- A dependency must be upgraded to proceed → treat as a separate gated change
  (`02-android-scaffold` version rules), not a sneaky bump inside a fix.
