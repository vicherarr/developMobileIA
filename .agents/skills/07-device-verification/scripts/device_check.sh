#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
# shellcheck source=/dev/null
. "${PIPELINE_ROOT}/scripts/lib/android_env.sh"

# device_check.sh - capture visual + UI-tree evidence for the running app and
# emit the G6 report. Read-only with respect to sources; writes only into
# .pipeline/artifacts and .pipeline/reports.

SERIAL=""
EXPECT_TEXT=""
EXPECT_TAG=""
PACKAGE=""
DRY_RUN=0
ADB=""

usage() {
  cat <<'EOF'
device_check.sh - verify the app that is currently on screen (pipeline gate G6).

Usage:
  scripts/device_check.sh [options]

Options:
  --serial SERIAL        Target device. Default: first device from `adb devices`.
  --expect-text TEXT     Fail unless TEXT appears in the flat UI hierarchy JSON.
  --expect-tag TAG       Fail unless TAG appears in the UI hierarchy JSON
                         (Compose testTag / content-desc / resource-id substring).
  --package NAME         Only count crash-buffer entries for this app package.
  --dry-run              Print the plan and output paths, change nothing.
  -h, --help             Print this help and exit 0.

Always writes:
  artifacts/screen-<UTC>.png        annotated screenshot (overlay numbers #1..#N)
  artifacts/screen-<UTC>.log        stdout of `android screen capture`
  artifacts/layout-<UTC>.json       `android layout --flat` UI hierarchy
  artifacts/crash-<UTC>.log         `adb logcat -d -b crash` dump
  reports/device-<UTC>.json         evidence: status pass|fail

Exit 0 only when capture, layout, requested assertions and crash scan all pass.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --serial)
      [ "$#" -ge 2 ] || die "--serial needs a value (try --help)"
      SERIAL="$2"
      shift 2
      ;;
    --serial=*)
      SERIAL="${1#*=}"
      shift
      ;;
    --expect-text)
      [ "$#" -ge 2 ] || die "--expect-text needs a value (try --help)"
      EXPECT_TEXT="$2"
      shift 2
      ;;
    --expect-text=*)
      EXPECT_TEXT="${1#*=}"
      shift
      ;;
    --expect-tag)
      [ "$#" -ge 2 ] || die "--expect-tag needs a value (try --help)"
      EXPECT_TAG="$2"
      shift 2
      ;;
    --expect-tag=*)
      EXPECT_TAG="${1#*=}"
      shift
      ;;
    --package)
      [ "$#" -ge 2 ] || die "--package needs a value (try --help)"
      PACKAGE="$2"
      shift 2
      ;;
    --package=*)
      PACKAGE="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -*)
      die "unknown option: $1 (try --help)"
      ;;
    *)
      die "unexpected argument: $1 (try --help)"
      ;;
  esac
done

resolve_adb() {
  if [ -n "${ANDROID_SDK:-}" ] && [ -x "${ANDROID_SDK}/platform-tools/adb" ]; then
    ADB="${ANDROID_SDK}/platform-tools/adb"
  elif have adb; then
    ADB="$(command -v adb)"
  else
    ADB=""
  fi
}

json_escape() {
  printf '%s' "${1-}" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

STAMP="$(utc_stamp)"
SCREENSHOT="${ARTIFACTS_DIR}/screen-${STAMP}.png"
SCREENSHOT_LOG="${ARTIFACTS_DIR}/screen-${STAMP}.log"
LAYOUT_JSON="${ARTIFACTS_DIR}/layout-${STAMP}.json"
CRASH_LOG="${ARTIFACTS_DIR}/crash-${STAMP}.log"
REPORT="${REPORTS_DIR}/device-${STAMP}.json"
GENERATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

resolve_adb

if [ "${DRY_RUN}" -eq 1 ]; then
  log "device_check.sh dry-run - nothing will be captured or written"
  log "sdk=${ANDROID_SDK:-<unset>} adb=${ADB:-<missing>} serial=${SERIAL:-<auto>} package=${PACKAGE:-<any>}"
  if [ -z "${SERIAL}" ] && [ -n "${ADB}" ]; then
    log "attached devices:"
    "${ADB}" devices 2>/dev/null | sed 's/^/  /' || true
  fi
  cat <<EOF
plan:
  1. android screen capture --annotate --device=<serial> --output=${SCREENSHOT}
  2. android layout --device=<serial> --flat -o ${LAYOUT_JSON}
  3. checks: screenshot present, layout present$( [ -n "${EXPECT_TEXT}" ] && printf ', text "%s"' "${EXPECT_TEXT}" )$( [ -n "${EXPECT_TAG}" ] && printf ', tag "%s"' "${EXPECT_TAG}" )
  4. adb logcat -d -b crash -> ${CRASH_LOG}, count fatal entries
  5. emit ${REPORT} with status pass|fail
expected success output:
  PASS serial=<serial> nodes=<n> crashes=0
EOF
  exit 0
fi

require_app
if [ -z "${ADB}" ]; then
  die "adb not found (expected ${ANDROID_SDK:-<sdk>}/platform-tools/adb). Run 'android info' or install platform-tools."
fi
mkdir -p "${ARTIFACTS_DIR}" "${REPORTS_DIR}"

if [ -z "${SERIAL}" ]; then
  SERIAL="$("${ADB}" devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1; exit }' || true)"
  [ -n "${SERIAL}" ] || die "no connected device. Boot one first: scripts/device_up.sh (or pass --serial)"
  log "auto-selected device ${SERIAL}"
fi
if ! "${ADB}" devices 2>/dev/null | awk -v want="${SERIAL}" 'NR > 1 && $2 == "device" && $1 == want { found = 1 } END { exit(found ? 0 : 1) }'; then
  die "device '${SERIAL}' is not connected (check 'adb devices')"
fi

CHECKS=""
ERRORS=0
WARNINGS=0

add_check() {
  local name="$1" status="$2" detail="$3" item
  item="$(printf '{"name":"%s","status":"%s","detail":"%s"}' \
    "$(json_escape "${name}")" "$(json_escape "${status}")" "$(json_escape "${detail}")")"
  if [ -z "${CHECKS}" ]; then
    CHECKS="${item}"
  else
    CHECKS="${CHECKS},${item}"
  fi
  case "${status}" in
    fail) ERRORS=$((ERRORS + 1)) ;;
    warn) WARNINGS=$((WARNINGS + 1)) ;;
  esac
}

SHOT_BYTES=0
LAYOUT_BYTES=0
NODES=0
FOCUS=""

# 1. Annotated screenshot: overlay numbers let the agent address nodes by #N.
if android_app screen capture --annotate --device="${SERIAL}" --output="${SCREENSHOT}" >"${SCREENSHOT_LOG}" 2>&1; then
  if [ -s "${SCREENSHOT}" ]; then
    SHOT_BYTES="$(wc -c <"${SCREENSHOT}" | tr -d ' ')"
    add_check "screenshot" "pass" "annotated capture ${SHOT_BYTES} bytes -> ${SCREENSHOT}"
    log "screenshot: ${SCREENSHOT} (${SHOT_BYTES} bytes)"
  else
    add_check "screenshot" "fail" "capture exited 0 but ${SCREENSHOT} is missing or empty"
    warn "screenshot file is empty: ${SCREENSHOT}"
  fi
else
  add_check "screenshot" "fail" "android screen capture failed; see ${SCREENSHOT_LOG}"
  warn "screen capture failed; see ${SCREENSHOT_LOG}"
fi

# 2. UI hierarchy JSON: the accessibility tree is the primary selection source.
if android_app layout --device="${SERIAL}" --flat -o "${LAYOUT_JSON}" >/dev/null 2>&1; then
  if [ -s "${LAYOUT_JSON}" ]; then
    LAYOUT_BYTES="$(wc -c <"${LAYOUT_JSON}" | tr -d ' ')"
    NODES="$(grep -o '"class"' "${LAYOUT_JSON}" 2>/dev/null | wc -l | tr -d ' ' || true)"
    add_check "layout" "pass" "flat hierarchy ${NODES} nodes, ${LAYOUT_BYTES} bytes -> ${LAYOUT_JSON}"
    log "layout: ${LAYOUT_JSON} (${NODES} nodes)"
  else
    add_check "layout" "fail" "layout command exited 0 but ${LAYOUT_JSON} is missing or empty"
    warn "layout file is empty: ${LAYOUT_JSON}"
  fi
else
  add_check "layout" "fail" "android layout failed; retry with 'android layout --device=${SERIAL}'"
  warn "layout dump failed"
fi

# 3. Optional assertions against the accessibility tree, never against pixels.
if [ -n "${EXPECT_TEXT}" ]; then
  if [ -s "${LAYOUT_JSON}" ] && grep -qF -- "${EXPECT_TEXT}" "${LAYOUT_JSON}"; then
    add_check "expect-text" "pass" "found text \"${EXPECT_TEXT}\" in layout JSON"
    log "assertion passed: text \"${EXPECT_TEXT}\""
  else
    add_check "expect-text" "fail" "text \"${EXPECT_TEXT}\" not found in ${LAYOUT_JSON}"
    warn "assertion FAILED: text \"${EXPECT_TEXT}\" not visible"
  fi
fi
if [ -n "${EXPECT_TAG}" ]; then
  if [ -s "${LAYOUT_JSON}" ] && grep -qF -- "${EXPECT_TAG}" "${LAYOUT_JSON}"; then
    add_check "expect-tag" "pass" "found tag/desc/id \"${EXPECT_TAG}\" in layout JSON"
    log "assertion passed: tag \"${EXPECT_TAG}\""
  else
    add_check "expect-tag" "fail" "tag \"${EXPECT_TAG}\" not found in ${LAYOUT_JSON}"
    warn "assertion FAILED: tag \"${EXPECT_TAG}\" not exposed (Compose tags need testTagsAsResourceId in debug)"
  fi
fi

# 4. Crash evidence from the dedicated crash buffer.
if "${ADB}" -s "${SERIAL}" logcat -d -b crash >"${CRASH_LOG}" 2>/dev/null; then
  CRASH_COUNT=0
  if [ -n "${PACKAGE}" ]; then
    CRASH_COUNT="$(grep -cF "Process: ${PACKAGE}" "${CRASH_LOG}" 2>/dev/null || true)"
  else
    CRASH_COUNT="$(grep -cE 'FATAL EXCEPTION|ANR in ' "${CRASH_LOG}" 2>/dev/null || true)"
  fi
  if [ "${CRASH_COUNT}" -gt 0 ]; then
    add_check "crash-scan" "fail" "${CRASH_COUNT} crash entries in the logcat crash buffer (${CRASH_LOG})"
    warn "crash entries found: ${CRASH_COUNT} (see ${CRASH_LOG})"
  else
    add_check "crash-scan" "pass" "no crash entries for ${PACKAGE:-this device}"
    log "crash scan: clean"
  fi
else
  add_check "crash-scan" "warn" "could not read the logcat crash buffer; crash status unknown"
  warn "could not read logcat crash buffer"
fi

# 5. Foreground evidence helps attribute the screenshot in review.
FOCUS="$("${ADB}" -s "${SERIAL}" shell dumpsys window 2>/dev/null | sed -n 's/.*mCurrentFocus=\([^}]*\).*/\1/p' | sed -n '1p' || true)"
if [ -n "${FOCUS}" ]; then
  log "foreground window: ${FOCUS}"
else
  add_check "foreground" "warn" "mCurrentFocus not readable; confirm the app is in front before trusting the screenshot"
fi

CRASH_LINES=""
CRASH_EMITTED=0
if [ "${CRASH_COUNT:-0}" -gt 0 ] && [ -s "${CRASH_LOG}" ]; then
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    [ "${CRASH_EMITTED}" -lt 20 ] || break
    esc="$(json_escape "${line}")"
    if [ -z "${CRASH_LINES}" ]; then
      CRASH_LINES="\"${esc}\""
    else
      CRASH_LINES="${CRASH_LINES},\"${esc}\""
    fi
    CRASH_EMITTED=$((CRASH_EMITTED + 1))
  done <"${CRASH_LOG}"
fi

if [ "${ERRORS}" -gt 0 ]; then
  STATUS="fail"
else
  STATUS="pass"
fi

REPORT_TMP="${REPORT}.tmp.$$"
cat >"${REPORT_TMP}" <<JSON
{
  "schema": 1,
  "gate": "G6",
  "kind": "device-verification",
  "status": "${STATUS}",
  "timestamp": "$(json_escape "${STAMP}")",
  "generated_utc": "$(json_escape "${GENERATED}")",
  "serial": "$(json_escape "${SERIAL}")",
  "package": "$(json_escape "${PACKAGE}")",
  "screenshot": {
    "path": "$(json_escape "${SCREENSHOT}")",
    "bytes": ${SHOT_BYTES},
    "annotated": true,
    "capture_log": "$(json_escape "${SCREENSHOT_LOG}")"
  },
  "layout": {
    "path": "$(json_escape "${LAYOUT_JSON}")",
    "bytes": ${LAYOUT_BYTES},
    "nodes": ${NODES},
    "format": "flat-json"
  },
  "focus": "$(json_escape "${FOCUS}")",
  "assertions": {
    "expect_text": "$(json_escape "${EXPECT_TEXT}")",
    "expect_tag": "$(json_escape "${EXPECT_TAG}")"
  },
  "checks": [${CHECKS}],
  "crashes": {
    "count": ${CRASH_COUNT:-0},
    "raw_log": "$(json_escape "${CRASH_LOG}")",
    "lines": [${CRASH_LINES}]
  },
  "counts": {
    "errors": ${ERRORS},
    "warnings": ${WARNINGS}
  }
}
JSON
emit_report "${REPORT}" <"${REPORT_TMP}"
rm -f "${REPORT_TMP}"

if have jq; then
  jq -e . "${REPORT}" >/dev/null 2>&1 || warn "report is not valid JSON: ${REPORT}"
fi

if [ "${STATUS}" = "pass" ]; then
  log "PASS serial=${SERIAL} nodes=${NODES} crashes=${CRASH_COUNT:-0} report=${REPORT}"
  exit 0
fi
warn "FAIL serial=${SERIAL} errors=${ERRORS} warnings=${WARNINGS} report=${REPORT}"
exit 1
