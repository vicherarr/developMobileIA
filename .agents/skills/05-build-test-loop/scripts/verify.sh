#!/usr/bin/env bash
# verify.sh - the G5 closed loop: build -> unit tests -> lint -> previews.
#
# Produces app_workspace/.pipeline/reports/verify-<UTC>.json and exits non-zero
# if any required step fails. Safe to re-run; it never edits sources.
#
# Usage:
#   scripts/verify.sh [options]
#
# Options:
#   --only <list>     Comma list of steps: build,test,lint,preview (default: all)
#   --no-lint         Skip lint
#   --no-preview      Skip preview discovery
#   --preview-render  Also render previews to PNGs (slow; writes artifacts/)
#   --require-preview Treat a preview failure as blocking (default: advisory)
#   --timeout <secs>  Per-step timeout (default: 0 = none)
#   --dry-run         Print the commands only
#   -h, --help        Show this help
#
# Exit codes: 0 all requested steps passed, 1 at least one failed, 2 usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
# shellcheck source=/dev/null
. "${PIPELINE_ROOT}/scripts/lib/android_env.sh"

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

ONLY="build,test,lint,preview"
DO_PREVIEW_RENDER=0
PREVIEW_REQUIRED=0
TIMEOUT=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --only)           ONLY="${2:-}"; shift 2 ;;
    --no-lint)        ONLY="$(printf '%s' "$ONLY" | tr ',' '\n' | grep -v '^lint$' | paste -sd, -)"; shift ;;
    --no-preview)     ONLY="$(printf '%s' "$ONLY" | tr ',' '\n' | grep -v '^preview$' | paste -sd, -)"; shift ;;
    --preview-render) DO_PREVIEW_RENDER=1; shift ;;
    --require-preview) PREVIEW_REQUIRED=1; shift ;;
    --timeout)        TIMEOUT="${2:-0}"; shift 2 ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage >&2; die "unknown option: $1" ;;
  esac
done

wants() { printf '%s' ",${ONLY}," | grep -q ",$1,"; }

ensure_state_dirs
require_app
STAMP="$(utc_stamp)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

declare -a STEP_NAMES=() STEP_STATUS=() STEP_SECS=() STEP_LOGS=()
OVERALL=0

run_step() {
  local name="$1"; shift
  local log="${WORK}/${name}.log" start end status
  log "==> ${name}: $*"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: %s\n' "$*"
    STEP_NAMES+=("$name"); STEP_STATUS+=("dry-run"); STEP_SECS+=("0"); STEP_LOGS+=("")
    return 0
  fi
  start="$(date +%s)"
  set +e
  if [ "$TIMEOUT" -gt 0 ] && have timeout; then
    timeout "$TIMEOUT" bash -c 'set -uo pipefail; . "$0/scripts/lib/android_env.sh"; "$@"' \
      "$PIPELINE_ROOT" "$@" >"$log" 2>&1
  else
    "$@" >"$log" 2>&1
  fi
  status=$?
  set -e
  end="$(date +%s)"
  STEP_NAMES+=("$name"); STEP_SECS+=("$((end - start))")
  if [ "$status" -eq 0 ]; then
    STEP_STATUS+=("pass"); STEP_LOGS+=("")
    ok "${name} passed ($((end - start))s)"
  else
    STEP_STATUS+=("fail"); STEP_LOGS+=("$log")
    OVERALL=1
    warn "${name} FAILED (exit ${status})"
    tail -n 12 "$log" | sed 's/^/     /' >&2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------
BUILD_FAILED=0
if wants build; then
  run_step build gradlew :app:assembleDebug
  if [ "${STEP_STATUS[0]:-pass}" = "fail" ]; then BUILD_FAILED=1; fi
fi

if wants test; then
  if [ "$BUILD_FAILED" -eq 1 ]; then
    STEP_NAMES+=("test"); STEP_STATUS+=("skipped"); STEP_SECS+=("0"); STEP_LOGS+=("")
    warn "test skipped: build failed"
  else
    run_step test gradlew :app:testDebugUnitTest
  fi
fi

if wants lint; then
  run_step lint gradlew :app:lintDebug
fi

if wants preview; then
  run_step preview android_app preview list -f json
  if [ "$DO_PREVIEW_RENDER" -eq 1 ] && [ "$OVERALL" -eq 0 ]; then
    run_step preview_render android_app preview render -o "${ARTIFACTS_DIR}/previews" -f json
  fi
fi

# ---------------------------------------------------------------------------
# Collect evidence
# ---------------------------------------------------------------------------
collect() {
  python3 - "$APP_ROOT" "${WORK}" "$@" <<'PY'
import glob, json, os, re, sys

app, work = sys.argv[1], sys.argv[2]
names = sys.argv[3::2]
statuses = sys.argv[4::2]
steps = []
for i, n in enumerate(names):
    steps.append({"name": n, "status": statuses[i]})

def parse_unit():
    total = fail = err = skip = 0
    files = glob.glob(os.path.join(app, "**/build/test-results/testDebugUnitTest/TEST-*.xml"), recursive=True)
    for f in files:
        try:
            head = open(f, encoding="utf-8", errors="ignore").read(4000)
        except OSError:
            continue
        for attr, acc in (("tests", "total"), ("failures", "fail"), ("errors", "err"), ("skipped", "skip")):
            m = re.search(attr + r'="(\d+)"', head)
            if m:
                v = int(m.group(1))
                if acc == "total": total += v
                elif acc == "fail": fail += v
                elif acc == "err": err += v
                else: skip += v
    return {"tests": total, "failures": fail, "errors": err, "skipped": skip,
            "result_files": len(files)}, (total > 0)

def parse_lint():
    out = {"errors": 0, "warnings": 0, "report": None}
    txt = glob.glob(os.path.join(app, "**/build/reports/lint-results-debug.txt"), recursive=True)
    if txt:
        out["report"] = os.path.relpath(txt[0], app)
        body = open(txt[0], encoding="utf-8", errors="ignore").read()
        out["errors"] = len(re.findall(r"^.*: Error:", body, re.M))
        out["warnings"] = len(re.findall(r"^.*: Warning:", body, re.M))
    sarif = glob.glob(os.path.join(app, "**/build/reports/lint-results-debug.sarif"), recursive=True)
    if sarif:
        try:
            data = json.load(open(sarif[0]))
            results = data.get("runs", [{}])[0].get("results", [])
            out["errors"] = sum(1 for r in results if r.get("level") == "error")
            out["warnings"] = sum(1 for r in results if r.get("level") == "warning")
        except Exception:
            pass
    return out

def parse_previews():
    for n, s in zip(names, statuses):
        if n == "preview" and s == "pass":
            log = os.path.join(work, "preview.log")
            try:
                data = json.load(open(log))
            except Exception:
                try:
                    data = json.loads(open(log).read())
                except Exception:
                    return {"count": None, "note": "unparsed output"}
            if isinstance(data, list):
                return {"count": len(data)}
            if isinstance(data, dict):
                for k in ("previews", "items", "results"):
                    if isinstance(data.get(k), list):
                        return {"count": len(data[k])}
            return {"count": None, "note": "unexpected shape"}
    return {"count": None, "note": "not requested or failed"}

apks = glob.glob(os.path.join(app, "app/build/outputs/apk/debug/*.apk"))
unit, unit_ran = parse_unit()
doc = {
    "schema": 1,
    "gate": "G5",
    "steps": steps,
    "unit_tests": unit,
    "lint": parse_lint(),
    "previews": parse_previews(),
    "apk": os.path.relpath(apks[0], app) if apks else None,
    "environment": {"android_sdk": os.environ.get("ANDROID_SDK", ""), "app_root": app},
}

# Status is derived from every source of truth, not just process exit codes:
# a task can be configured to ignore test failures, and lint errors matter even
# when the lint task does not fail the build.
advisory = os.environ.get("PREVIEW_ADVISORY") == "1"
raw_failed = [s["name"] for s in steps if s["status"] not in ("pass", "skipped", "dry-run")]
if advisory:
    advisory_failed = [n for n in raw_failed if n in ("preview", "preview_render")]
    failed_steps = [n for n in raw_failed if n not in ("preview", "preview_render")]
else:
    advisory_failed = []
    failed_steps = raw_failed
failed_tests = unit["failures"] + unit["errors"]
failed_lint = doc["lint"]["errors"]
doc["status"] = "fail" if (failed_steps or failed_tests or failed_lint) else "pass"
doc["advisory_failures"] = advisory_failed
doc["reasons"] = (
    [{"kind": "step", "step": s} for s in failed_steps]
    + ([{"kind": "unit_tests", "count": failed_tests}] if failed_tests else [])
    + ([{"kind": "lint_errors", "count": failed_lint}] if failed_lint else [])
    + ([{"kind": "advisory", "step": s} for s in advisory_failed])
)
json.dump(doc, sys.stdout, indent=2)
PY
}

ARGS=()
for i in "${!STEP_NAMES[@]}"; do ARGS+=("${STEP_NAMES[$i]}" "${STEP_STATUS[$i]}"); done

if [ "$DRY_RUN" -eq 1 ]; then
  log "dry-run complete; nothing written"
  exit 0
fi

REPORT="${REPORTS_DIR}/verify-${STAMP}.json"

export PREVIEW_ADVISORY=$([ "$PREVIEW_REQUIRED" -eq 1 ] && echo "0" || echo "1")
collect "${ARGS[@]}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
d["timestamp"] = sys.argv[1]
print(json.dumps(d, indent=2))
' "$(utc_iso)" | emit_report "$REPORT"

STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["status"])' "$REPORT")"
[ "$STATUS" = "pass" ] || OVERALL=1

# Failure summary with triage hints.
if [ "$STATUS" = "fail" ]; then
  echo
  warn "G5 is open. Triage table: .agents/skills/05-build-test-loop/references/failure-triage.md"
  for i in "${!STEP_NAMES[@]}"; do
    if [ "${STEP_STATUS[$i]}" = "fail" ]; then
      printf '  - %-14s %s\n' "${STEP_NAMES[$i]}" "${STEP_LOGS[$i]}"
    fi
  done
  python3 - "$REPORT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
u, lint = d.get("unit_tests", {}), d.get("lint", {})
if u.get("failures") or u.get("errors"):
    print(f"  - unit tests      {u.get('tests', 0)} run, "
          f"{u.get('failures', 0)} failed, {u.get('errors', 0)} errored")
if lint.get("errors"):
    print(f"  - lint            {lint['errors']} error(s) -> {lint.get('report')}")
PY
  printf '\nNext: read the first error in the log above, apply ONE fix, re-run.\n'
  exit 1
fi

ok "G5 evidence: ${REPORT}"
printf '  unit tests: %s run / %s failed\n' \
  "$(python3 -c 'import json;d=json.load(open("'"$REPORT"'"));print(d["unit_tests"]["tests"])')" \
  "$(python3 -c 'import json;d=json.load(open("'"$REPORT"'"));print(d["unit_tests"]["failures"]+d["unit_tests"]["errors"])')"
ADVISORY="$(python3 -c 'import json,sys;print(",".join(json.load(open(sys.argv[1])).get("advisory_failures",[])))' "$REPORT")"
if [ -n "$ADVISORY" ]; then
  echo
  warn "advisory step(s) failed: ${ADVISORY} (not blocking G5)"
  warn "known Android CLI bug 1.1.16717390: 'preview list/render' fails with"
  warn "'Illegal entry path escaping destination directory: gradle-build-system'. Workarounds:"
  warn "  - android update   (then retry)"
  warn "  - use Roborazzi/Paparazzi for visual regressions (06-testing-strategy)"
  warn "  - re-run with --require-preview once the CLI is fixed"
fi
printf '  next: 07-device-verification (G6) or continue the next feature slice\n'
