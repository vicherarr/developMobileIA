#!/usr/bin/env bash
# doctor.sh - environment diagnosis for the Android agentic pipeline.
#
# Usage:
#   scripts/doctor.sh [--json] [--strict]
#
# Options:
#   --json     Machine-readable output (for agents)
#   --strict   Exit 1 when any check fails (warnings still exit 0)
#   -h, --help Show this help
#
# Exit codes: 0 healthy (or warnings only), 1 failures in --strict mode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
. "${PIPELINE_ROOT}/scripts/lib/android_env.sh"

usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

JSON=0; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json)   JSON=1; shift ;;
    --strict) STRICT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

RESULTS=()
FAILS=0
WARNS=0

record() { # record <level> <name> <detail> <fix>
  RESULTS+=("$1|$2|$3|$4")
  case "$1" in
    fail) FAILS=$((FAILS + 1)) ;;
    warn) WARNS=$((WARNS + 1)) ;;
  esac
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
  record ok bash "bash ${BASH_VERSION}" ""
else
  record warn bash "bash ${BASH_VERSION} (4+ recommended)" "upgrade bash"
fi

if have android; then
  CLI_VERSION="$(android_cli -V 2>/dev/null | tail -n1 || true)"
  record ok android-cli "${CLI_VERSION:-installed}" ""
else
  record fail android-cli "not found on PATH" "install from https://developer.android.com/tools/agents then run 'android update'"
fi

if [ -n "${ANDROID_SDK}" ] && [ -d "${ANDROID_SDK}" ]; then
  record ok android-sdk "${ANDROID_SDK}" ""
else
  record fail android-sdk "not found" "set ANDROID_HOME or install the SDK"
fi

if [ -n "${ANDROID_SDK}" ]; then
  PLATFORMS="$(ls -1 "${ANDROID_SDK}/platforms" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
  if [ -n "$PLATFORMS" ]; then
    record ok platforms "${PLATFORMS}" ""
  else
    record fail platforms "none installed" "android sdk install platforms;android-36"
  fi
  BUILDTOOLS="$(ls -1 "${ANDROID_SDK}/build-tools" 2>/dev/null | tail -n1)"
  if [ -n "$BUILDTOOLS" ]; then
    record ok build-tools "${BUILDTOOLS}" ""
  else
    record warn build-tools "none installed" "android sdk install build-tools;36.0.0"
  fi
  if [ -x "${ANDROID_SDK}/platform-tools/adb" ]; then
    record ok adb "${ANDROID_SDK}/platform-tools/adb" ""
  else
    record warn adb "missing" "android sdk install platform-tools"
  fi
  if [ -w "${ANDROID_SDK}" ]; then
    record ok sdk-writable "SDK is writable" ""
  else
    record warn sdk-writable "SDK is read-only (package installs will fail)" "run outside the sandbox or fix permissions"
  fi
  if [ -x "${ANDROID_SDK}/emulator/emulator" ]; then
    AVDS="$( "${ANDROID_SDK}/emulator/emulator" -list-avds 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
    record ok emulator "${AVDS:-no AVDs yet}" ""
  else
    record warn emulator "not installed" "android sdk install emulator; android emulator create medium_phone"
  fi
fi

JAVA_LINE="$(java -version 2>&1 | head -n1 || true)"
JAVA_V="$(printf '%s' "$JAVA_LINE" | sed 's/.*version "\([0-9]*\).*/\1/' || true)"
# Gradle 9.1 ships full Java 25 support and AGP 9 needs >= 17; 17-25 is good.
if [ -n "${JAVA_V:-}" ] && [ "$JAVA_V" -ge 17 ] 2>/dev/null && [ "$JAVA_V" -le 25 ] 2>/dev/null; then
  record ok jdk "JDK ${JAVA_V} (${JAVA_LINE})" ""
elif [ -n "${JAVA_V:-}" ] && [ "$JAVA_V" -gt 25 ] 2>/dev/null; then
  record warn jdk "JDK ${JAVA_V} is newer than this Gradle/AGP validates" "set JAVA_HOME to a JDK 17-25"
else
  record fail jdk "JDK ${JAVA_V:-unknown} - AGP 9 needs 17+" "install JDK 17+ and set JAVA_HOME"
fi

if [ -x "${APP_ROOT}/gradlew" ]; then
  record ok gradle-wrapper "present in app_workspace" ""
else
  record warn gradle-wrapper "no project yet (expected before G2)" "run the 02-android-scaffold script at G2"
fi

if [ -x "${CEILING_DEV_KVM:-/dev/kvm}" ]; then
  record ok kvm "/dev/kvm available (hardware acceleration)" ""
else
  record warn kvm "/dev/kvm missing (emulator will be slow or fail)" "enable virtualization, or use a physical device"
fi

SKILLS="$(find "${PIPELINE_ROOT}/.agents/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
if [ "${SKILLS:-0}" -ge 11 ]; then
  record ok skills "${SKILLS} skills discovered" ""
else
  record warn skills "only ${SKILLS} skills found (expected 11+)" "check .agents/skills layout: <root>/<name>/SKILL.md"
fi

for f in ARCHITECTURE.md TECH_STACK.md DECISION_LOG.md SESSION_STATE.md; do
  [ -f "${MEMORY_DIR}/${f}" ] || record warn "memory" "missing 00_memory/${f}" "run scripts/bootstrap.sh"
done

DEVICES="$(adb_devices 2>/dev/null | tr '\n' ' ' | sed 's/ *$//' || true)"
if [ -n "$DEVICES" ]; then
  record ok devices "${DEVICES}" ""
else
  record warn devices "no device connected" "android emulator start <avd> or plug a device"
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [ "$JSON" -eq 1 ]; then
  python3 - "$FAILS" "$WARNS" "$PIPELINE_ROOT" "${RESULTS[@]}" <<'PY'
import json, sys
fails, warns, root = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
items = []
for raw in sys.argv[4:]:
    level, name, detail, fix = raw.split("|", 3)
    items.append({"level": level, "check": name, "detail": detail, "fix": fix})
print(json.dumps({
    "schema": 1, "pipeline_root": root,
    "status": "fail" if fails else ("warn" if warns else "pass"),
    "failures": fails, "warnings": warns, "checks": items,
}, indent=2))
PY
else
  printf '\n%sAndroid pipeline doctor%s  (%s)\n\n' "${__C_BLU}" "${__C_RESET}" "${PIPELINE_ROOT}"
  for raw in "${RESULTS[@]}"; do
    IFS='|' read -r level name detail fix <<<"$raw"
    case "$level" in
      ok)   icon="${__C_GRN}ok  ${__C_RESET}" ;;
      warn) icon="${__C_YEL}warn${__C_RESET}" ;;
      fail) icon="${__C_RED}fail${__C_RESET}" ;;
    esac
    printf '  [%s] %-16s %s\n' "$icon" "$name" "$detail"
    [ -n "$fix" ] && printf '        %s-> %s%s\n' "${__C_DIM}" "$fix" "${__C_RESET}"
  done
  printf '\n  %d failure(s), %d warning(s)\n\n' "$FAILS" "$WARNS"
  if [ "$FAILS" -gt 0 ]; then
    printf '  Fix failures before G2. See docs/CAPABILITIES.md.\n\n'
  elif [ "$WARNS" -gt 0 ]; then
    printf '  Warnings are expected before G2 (no project yet).\n\n'
  else
    printf '  Environment healthy. Next: 01-spec-and-scope (G1).\n\n'
  fi
fi

if [ "$STRICT" -eq 1 ] && [ "$FAILS" -gt 0 ]; then
  exit 1
fi
exit 0
