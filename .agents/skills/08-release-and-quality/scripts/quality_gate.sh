#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
# shellcheck source=/dev/null
. "${PIPELINE_ROOT}/scripts/lib/android_env.sh"

# quality_gate.sh - pre-release gate (G7). Builds release + lint + unit tests,
# analyzes size/R8 evidence, scans for forbidden release patterns and emits
# reports/quality-<UTC>.json. Never edits sources: outputs go to
# .pipeline/artifacts and .pipeline/reports only.

SKIP_ANALYZE=0
DRY_RUN=0
WRITE_BASELINE=0
SIZE_LIMIT_PCT="${SIZE_LIMIT_PCT:-10}"

usage() {
  cat <<'EOF'
quality_gate.sh - run the G7 pre-release quality gate and emit evidence.

Usage:
  scripts/quality_gate.sh [options]

Options:
  --skip-analyze          Skip `android analyze` (size/R8 evidence is then absent).
  --write-baseline        Overwrite artifacts/size-baseline.json with this build.
  --size-limit-pct N      Allowed APK growth vs the baseline. Default: 10
  --dry-run               Print the plan and detected paths, change nothing.
  -h, --help              Print this help and exit 0.

Runs:
  ./gradlew :app:assembleRelease :app:lintRelease :app:testDebugUnitTest
  android analyze <apk> --analysis=optimization -f json
  android analyze <apk> --analysis=basic -f json
Static scans (read-only): hardcoded secrets, android:exported on components with
intent filters, usesCleartextTraffic, debuggable in release, targetSdk, signing
hygiene, R8 keep-rule warnings.

Writes:
  reports/quality-<UTC>.json          status pass|fail + findings
  artifacts/analyze-*-<UTC>.json      raw android analyze output
  artifacts/quality-gradle-<UTC>.log  gradle output
  artifacts/size-baseline.json        created on first run, or with --write-baseline

The script exits 0 only when gradle succeeds and no error-severity finding exists.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --skip-analyze)
      SKIP_ANALYZE=1
      shift
      ;;
    --write-baseline)
      WRITE_BASELINE=1
      shift
      ;;
    --size-limit-pct)
      [ "$#" -ge 2 ] || die "--size-limit-pct needs a value (try --help)"
      SIZE_LIMIT_PCT="$2"
      shift 2
      ;;
    --size-limit-pct=*)
      SIZE_LIMIT_PCT="${1#*=}"
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

case "${SIZE_LIMIT_PCT}" in
  ''|*[!0-9.]*) die "--size-limit-pct must be a number, got '${SIZE_LIMIT_PCT}'" ;;
esac

json_escape() {
  printf '%s' "${1-}" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

STAMP="$(utc_stamp)"
GENERATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REPORT="${REPORTS_DIR}/quality-${STAMP}.json"
GRADLE_LOG="${ARTIFACTS_DIR}/quality-gradle-${STAMP}.log"
ANALYZE_OPT="${ARTIFACTS_DIR}/analyze-optimization-${STAMP}.json"
ANALYZE_BASIC="${ARTIFACTS_DIR}/analyze-basic-${STAMP}.json"
BASELINE="${ARTIFACTS_DIR}/size-baseline.json"
APK_PREFERRED="${APP_ROOT}/app/build/outputs/apk/release/app-release.apk"
AAB_PATH="${APP_ROOT}/app/build/outputs/bundle/release/app-release.aab"
MAPPING_PATH="${APP_ROOT}/app/build/outputs/mapping/release/mapping.txt"

FINDINGS=""
ERRORS=0
WARNINGS=0

add_finding() {
  local severity="$1" check="$2" detail="$3" item
  item="$(printf '{"severity":"%s","check":"%s","detail":"%s"}' \
    "$(json_escape "${severity}")" "$(json_escape "${check}")" "$(json_escape "${detail}")")"
  if [ -z "${FINDINGS}" ]; then
    FINDINGS="${item}"
  else
    FINDINGS="${FINDINGS},${item}"
  fi
  case "${severity}" in
    error) ERRORS=$((ERRORS + 1)) ;;
    warn) WARNINGS=$((WARNINGS + 1)) ;;
  esac
}

# --- static scanners -------------------------------------------------------

scan_secrets() {
  local hits
  hits="$(grep -rIniE '(-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----|AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,}|(api[_-]?key|client[_-]?secret|access[_-]?token|password)[[:space:]]*[:=][[:space:]]*"[^"]{8,}")' \
    "${APP_ROOT}/app/src" 2>/dev/null | awk -F: '$1 ~ /\.(kt|kts|java|xml|properties|toml)$/' | sed -n '1,20p' || true)"
  [ -z "${hits}" ] && return 0
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    case "${line}" in
      */src/test/*|*/src/androidTest/*) add_finding "warn" "hardcoded-secret" "${line}" ;;
      *) add_finding "error" "hardcoded-secret" "${line}" ;;
    esac
  done <<<"${hits}"
}

scan_exported() {
  local manifest="$1"
  awk '
    BEGIN { in_comp = 0; has_filter = 0; exported = 0; start = 0; buf = "" }
    function reset() { in_comp = 0; has_filter = 0; exported = 0; start = 0; buf = "" }
    {
      if (in_comp == 0 && match($0, /<(activity|activity-alias|service|receiver|provider)([ \t>]|$)/)) {
        in_comp = 1; has_filter = 0; exported = 0; start = FNR; buf = $0
        while (buf !~ />/ && (getline line) > 0) { buf = buf " " line }
        if (buf ~ /android:exported=/) { exported = 1 }
        if (buf ~ /<intent-filter/) { has_filter = 1 }
        if (buf ~ /\/>/ || buf ~ /<\/(activity|activity-alias|service|receiver|provider)>/) {
          if (has_filter == 1 && exported == 0) {
            printf "%s:%d component with an intent-filter is missing android:exported\n", FILENAME, start
          }
          reset()
        }
        next
      }
      if (in_comp == 1) {
        if ($0 ~ /android:exported=/) { exported = 1 }
        if ($0 ~ /<intent-filter/) { has_filter = 1 }
        if ($0 ~ /<\/(activity|activity-alias|service|receiver|provider)>/) {
          if (has_filter == 1 && exported == 0) {
            printf "%s:%d component with an intent-filter is missing android:exported\n", FILENAME, start
          }
          reset()
        }
      }
    }
  ' "${manifest}" 2>/dev/null || true
}

scan_manifests() {
  local m hits exported deb
  for m in "${APP_ROOT}"/app/src/*/AndroidManifest.xml; do
    [ -f "${m}" ] || continue
    hits="$(grep -n 'usesCleartextTraffic="true"' "${m}" 2>/dev/null || true)"
    if [ -n "${hits}" ]; then
      add_finding "error" "cleartext-traffic" "${hits}"$'\n'"${m}"
    fi
    deb="$(grep -n 'android:debuggable="true"' "${m}" 2>/dev/null || true)"
    if [ -n "${deb}" ]; then
      add_finding "error" "debuggable-release" "${m}: android:debuggable=\"true\" in a release path"
    fi
    exported="$(scan_exported "${m}")"
    if [ -n "${exported}" ]; then
      while IFS= read -r line; do
        [ -n "${line}" ] || continue
        add_finding "error" "manifest-exported" "${line}"
      done <<<"${exported}"
    fi
  done

  # The merged release manifest is stronger evidence than the source manifests.
  local merged
  merged="$(find "${APP_ROOT}/app/build/intermediates/merged_manifests" -name AndroidManifest.xml 2>/dev/null | awk '/release/ { print; exit }' || true)"
  if [ -n "${merged}" ] && [ -f "${merged}" ]; then
    if grep -q 'android:debuggable="true"' "${merged}" 2>/dev/null; then
      add_finding "error" "debuggable-release" "${merged}: debuggable=true in the merged release manifest"
    fi
    if grep -q 'usesCleartextTraffic="true"' "${merged}" 2>/dev/null; then
      add_finding "error" "cleartext-traffic" "${merged}: usesCleartextTraffic=true in the merged release manifest"
    fi
  else
    add_finding "warn" "merged-manifest" "no merged release manifest found; run :app:assembleRelease to produce evidence"
  fi
}

scan_sdk_levels() {
  local build_file="" target
  if [ -f "${APP_ROOT}/app/build.gradle.kts" ]; then
    build_file="${APP_ROOT}/app/build.gradle.kts"
  elif [ -f "${APP_ROOT}/app/build.gradle" ]; then
    build_file="${APP_ROOT}/app/build.gradle"
  else
    add_finding "warn" "sdk-levels" "no app/build.gradle(.kts) found; cannot confirm targetSdk"
    return 0
  fi
  target="$(grep -hoE 'targetSdk(Version)?[[:space:]]*[=:]?[[:space:]]*[0-9]+' "${build_file}" | sed -n '1p' | grep -oE '[0-9]+$' || true)"
  if [ -z "${target}" ]; then
    add_finding "warn" "sdk-levels" "targetSdk not found in ${build_file}; confirm it explicitly"
  elif [ "${target}" -lt 36 ]; then
    add_finding "warn" "sdk-levels" "targetSdk ${target} < 36; Play requires a recent target API level (baseline: 36)"
  else
    add_finding "info" "sdk-levels" "targetSdk ${target}"
  fi
}

scan_signing() {
  local props="${APP_ROOT}/keystore.properties"
  if [ -f "${props}" ]; then
    if [ -f "${APP_ROOT}/.gitignore" ] && grep -qxF 'keystore.properties' "${APP_ROOT}/.gitignore" 2>/dev/null; then
      add_finding "info" "signing-hygiene" "keystore.properties present and git-ignored"
    else
      add_finding "error" "signing-hygiene" "keystore.properties exists but is not listed in app_workspace/.gitignore; never commit signing material"
    fi
  else
    add_finding "info" "signing-hygiene" "no keystore.properties: release signing must come from CI/Play App Signing or be added before upload"
  fi
  if ! grep -rqs 'signingConfig' "${APP_ROOT}/app/build.gradle.kts" "${APP_ROOT}/app/build.gradle" 2>/dev/null; then
    add_finding "warn" "signing-config" "no signingConfig for release; the release AAB is not uploadable until signing is configured"
  fi
}

scan_r8_warnings() {
  local hits
  [ -f "${GRADLE_LOG}" ] || return 0
  hits="$(grep -E 'Missing class|can.t find referenced class|R8: .*warning' "${GRADLE_LOG}" 2>/dev/null | sed -n '1,10p' || true)"
  if [ -n "${hits}" ]; then
    while IFS= read -r line; do
      [ -n "${line}" ] || continue
      add_finding "warn" "r8-keep-rules" "${line}"
    done <<<"${hits}"
  fi
}

find_apk() {
  if [ -f "${APK_PREFERRED}" ]; then
    printf '%s\n' "${APK_PREFERRED}"
    return 0
  fi
  { ls -1 "${APP_ROOT}"/app/build/outputs/apk/release/*.apk 2>/dev/null || true; } | sed -n '1p'
}

if [ "${DRY_RUN}" -eq 1 ]; then
  log "quality_gate.sh dry-run - nothing will be built, analyzed or written"
  log "app_root=${APP_ROOT} report=${REPORT} baseline=${BASELINE} size_limit_pct=${SIZE_LIMIT_PCT}"
  log "apk=${APK_PREFERRED} aab=${AAB_PATH} mapping=${MAPPING_PATH}"
  cat <<EOF
plan:
  1. require gradlew in ${APP_ROOT}
  2. gradlew :app:assembleRelease :app:lintRelease :app:testDebugUnitTest -> ${GRADLE_LOG}
  3. locate APK/AAB, record byte sizes, compare with ${BASELINE}
  4. android analyze <apk> --analysis=optimization -f json -> ${ANALYZE_OPT}
  5. android analyze <apk> --analysis=basic -f json        -> ${ANALYZE_BASIC}
  6. static scans: secrets, android:exported + intent-filter, cleartext, debuggable,
     targetSdk, signing hygiene, R8 keep-rule warnings
  7. emit ${REPORT} with status pass|fail and the findings list
expected success output:
  PASS report=${REPORT}
  status: pass
EOF
  exit 0
fi

require_app
mkdir -p "${ARTIFACTS_DIR}" "${REPORTS_DIR}"

log "gradle: :app:assembleRelease :app:lintRelease :app:testDebugUnitTest"
GRADLE_STATUS=0
gradlew :app:assembleRelease :app:lintRelease :app:testDebugUnitTest >"${GRADLE_LOG}" 2>&1 || GRADLE_STATUS=$?
tail -n 20 "${GRADLE_LOG}" 2>/dev/null | sed 's/^/  /' || true
if [ "${GRADLE_STATUS}" -eq 0 ]; then
  log "gradle: ok (log: ${GRADLE_LOG})"
else
  add_finding "error" "gradle" "gradle exited ${GRADLE_STATUS}; see ${GRADLE_LOG}"
  warn "gradle failed with exit code ${GRADLE_STATUS}"
fi

LINT_ERRORS="$(grep -oE 'Lint found [0-9]+ error' "${GRADLE_LOG}" 2>/dev/null | sed -n '1p' || true)"
if [ -n "${LINT_ERRORS}" ]; then
  add_finding "error" "lint" "${LINT_ERRORS} (fix lint errors before G7)"
fi
scan_r8_warnings

APK="$(find_apk)"
AAB_BYTES=0
APK_BYTES=0
if [ -n "${APK}" ] && [ -f "${APK}" ]; then
  APK_BYTES="$(wc -c <"${APK}" | tr -d ' ')"
  add_finding "info" "artifact-apk" "${APK} (${APK_BYTES} bytes)"
  log "apk: ${APK} (${APK_BYTES} bytes)"
else
  add_finding "error" "artifact-missing" "no release APK at ${APK_PREFERRED}; run :app:assembleRelease"
  warn "release APK missing"
fi
if [ -f "${AAB_PATH}" ]; then
  AAB_BYTES="$(wc -c <"${AAB_PATH}" | tr -d ' ')"
  add_finding "info" "artifact-aab" "${AAB_PATH} (${AAB_BYTES} bytes)"
  log "aab: ${AAB_PATH} (${AAB_BYTES} bytes)"
else
  add_finding "warn" "artifact-missing" "no release AAB at ${AAB_PATH}; Play uploads need :app:bundleRelease"
fi

if [ "${SKIP_ANALYZE}" -eq 1 ]; then
  add_finding "warn" "analyze" "--skip-analyze used: no size/R8 optimization evidence in this report"
elif [ -n "${APK}" ] && [ -f "${APK}" ]; then
  if android_app analyze "${APK}" --analysis=optimization -f json >"${ANALYZE_OPT}" 2>&1; then
    add_finding "info" "analyze-optimization" "raw output ${ANALYZE_OPT}"
  else
    add_finding "error" "analyze-optimization" "android analyze --analysis=optimization failed; see ${ANALYZE_OPT}"
  fi
  if android_app analyze "${APK}" --analysis=basic -f json >"${ANALYZE_BASIC}" 2>&1; then
    add_finding "info" "analyze-basic" "raw output ${ANALYZE_BASIC}"
  else
    add_finding "error" "analyze-basic" "android analyze --analysis=basic failed; see ${ANALYZE_BASIC}"
  fi
fi

# --- size baseline ---------------------------------------------------------
BASELINE_BYTES=""
GROWTH_PCT=""
BASELINE_WRITTEN="false"
if [ "${APK_BYTES}" -gt 0 ]; then
  if [ -f "${BASELINE}" ]; then
    BASELINE_BYTES="$(sed -n 's/.*"apk_bytes"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "${BASELINE}" | sed -n '1p')"
    if [ -n "${BASELINE_BYTES}" ] && [ "${BASELINE_BYTES}" -gt 0 ]; then
      GROWTH_PCT="$(awk -v p="${BASELINE_BYTES}" -v c="${APK_BYTES}" 'BEGIN { printf "%.2f", (c - p) * 100 / p }')"
      if [ "${WRITE_BASELINE}" -eq 1 ]; then
        add_finding "info" "size-baseline" "baseline replaced with this build (previous ${BASELINE_BYTES} bytes, growth ${GROWTH_PCT}%)"
      elif awk -v g="${GROWTH_PCT}" -v l="${SIZE_LIMIT_PCT}" 'BEGIN { exit((g + 0) > (l + 0) ? 0 : 1) }'; then
        add_finding "error" "size-regression" "APK grew ${GROWTH_PCT}% vs baseline (${BASELINE_BYTES} -> ${APK_BYTES} bytes, limit ${SIZE_LIMIT_PCT}%)"
      else
        add_finding "info" "size-budget" "APK growth ${GROWTH_PCT}% vs baseline (${BASELINE_BYTES} -> ${APK_BYTES} bytes, limit ${SIZE_LIMIT_PCT}%)"
      fi
    else
      add_finding "warn" "size-baseline" "baseline ${BASELINE} has no readable apk_bytes; rewrite it with --write-baseline"
    fi
  fi
  if [ ! -f "${BASELINE}" ] || [ "${WRITE_BASELINE}" -eq 1 ]; then
    printf '{"schema":1,"generated_utc":"%s","apk":"%s","apk_bytes":%s,"aab_bytes":%s}\n' \
      "${GENERATED}" "$(json_escape "${APK}")" "${APK_BYTES}" "${AAB_BYTES}" >"${BASELINE}"
    BASELINE_WRITTEN="true"
    add_finding "info" "size-baseline" "wrote ${BASELINE} (${APK_BYTES} bytes)"
  fi
fi

scan_secrets
scan_manifests
scan_sdk_levels
scan_signing

if [ -f "${MAPPING_PATH}" ]; then
  add_finding "info" "r8-mapping" "mapping file present: ${MAPPING_PATH} (keep it for Play deobfuscation)"
else
  add_finding "warn" "r8-mapping" "no ${MAPPING_PATH}; confirm R8/minify actually ran on the release build"
fi

if [ "${ERRORS}" -gt 0 ] || [ "${GRADLE_STATUS}" -ne 0 ]; then
  STATUS="fail"
else
  STATUS="pass"
fi

REPORT_TMP="${REPORT}.tmp.$$"
cat >"${REPORT_TMP}" <<JSON
{
  "schema": 1,
  "gate": "G7",
  "kind": "quality-gate",
  "status": "${STATUS}",
  "timestamp": "$(json_escape "${STAMP}")",
  "generated_utc": "$(json_escape "${GENERATED}")",
  "app_root": "$(json_escape "${APP_ROOT}")",
  "build": {
    "command": "./gradlew :app:assembleRelease :app:lintRelease :app:testDebugUnitTest",
    "exit_code": ${GRADLE_STATUS},
    "log": "$(json_escape "${GRADLE_LOG}")"
  },
  "artifacts": {
    "apk": "$(json_escape "${APK}")",
    "apk_bytes": ${APK_BYTES},
    "aab": "$(json_escape "${AAB_PATH}")",
    "aab_bytes": ${AAB_BYTES},
    "mapping": "$(json_escape "${MAPPING_PATH}")",
    "analyze_optimization": "$(json_escape "${ANALYZE_OPT}")",
    "analyze_basic": "$(json_escape "${ANALYZE_BASIC}")"
  },
  "size": {
    "baseline_path": "$(json_escape "${BASELINE}")",
    "baseline_apk_bytes": "${BASELINE_BYTES}",
    "apk_bytes": ${APK_BYTES},
    "growth_pct": "${GROWTH_PCT}",
    "limit_pct": ${SIZE_LIMIT_PCT},
    "baseline_written": ${BASELINE_WRITTEN}
  },
  "findings": [${FINDINGS}],
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
  log "PASS report=${REPORT} errors=0 warnings=${WARNINGS} apk_bytes=${APK_BYTES}"
  printf 'status: pass\n'
  exit 0
fi
warn "FAIL report=${REPORT} errors=${ERRORS} warnings=${WARNINGS} gradle_exit=${GRADLE_STATUS}"
printf 'status: fail\n'
exit 1
