#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
# shellcheck source=/dev/null
. "${PIPELINE_ROOT}/scripts/lib/android_env.sh"

# device_up.sh - bring up exactly one Android target and launch the debug app.
# Gate: G6 (device verification). Idempotent: reuses a booted device or AVD.

PROFILE="medium_phone"
AVD=""
SERIAL=""
HEADLESS=0
DRY_RUN=0
BOOT_TIMEOUT=300
ADB=""

usage() {
  cat <<'EOF'
device_up.sh - boot or attach a device and run the debug app (pipeline gate G6).

Usage:
  scripts/device_up.sh [options]

Options:
  --profile NAME   Emulator profile used when no AVD exists.
                   One of: small_phone medium_phone medium_tablet
                           small_desktop medium_desktop large_desktop
                   Default: medium_phone
  --avd NAME       Use this existing AVD, starting it when it is not running
                   (overrides reuse of a different online device).
  --serial SERIAL  Use an already-connected device and start no emulator.
  --headless       Start the AVD without a window (direct emulator binary,
                   because `android emulator start` has no headless flag).
  --timeout SECS   Boot timeout in seconds. Default: 300
  --dry-run        Print the plan and detected environment, change nothing.
  -h, --help       Print this help and exit 0.

Exit 0 prints the device serial on the last stdout line. Any failure prints an
actionable diagnosis and exits non-zero.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --profile)
      [ "$#" -ge 2 ] || die "--profile needs a value (try --help)"
      PROFILE="$2"
      shift 2
      ;;
    --profile=*)
      PROFILE="${1#*=}"
      shift
      ;;
    --avd)
      [ "$#" -ge 2 ] || die "--avd needs a value (try --help)"
      AVD="$2"
      shift 2
      ;;
    --avd=*)
      AVD="${1#*=}"
      shift
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
    --headless)
      HEADLESS=1
      shift
      ;;
    --timeout)
      [ "$#" -ge 2 ] || die "--timeout needs a value in seconds (try --help)"
      BOOT_TIMEOUT="$2"
      shift 2
      ;;
    --timeout=*)
      BOOT_TIMEOUT="${1#*=}"
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

case "${PROFILE}" in
  small_phone|medium_phone|medium_tablet|small_desktop|medium_desktop|large_desktop) : ;;
  *) die "unsupported profile '${PROFILE}' (try --help for the list)" ;;
esac
case "${BOOT_TIMEOUT}" in
  ''|*[!0-9]*) die "--timeout must be a positive integer, got '${BOOT_TIMEOUT}'" ;;
esac

resolve_adb() {
  if [ -n "${ANDROID_SDK:-}" ] && [ -x "${ANDROID_SDK}/platform-tools/adb" ]; then
    ADB="${ANDROID_SDK}/platform-tools/adb"
  elif have adb; then
    ADB="$(command -v adb)"
  else
    ADB=""
  fi
}

online_serials() {
  "${ADB}" devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1 }'
}

first_online() {
  online_serials | sed -n '1p'
}

list_avds() {
  android_cli emulator list 2>/dev/null | awk '
    NF == 0 { next }
    /^[[:space:]]*([Nn]ame|[Aa]vailable|[Ee]mulators|[Pp]rofile|[Ss]tate|[Dd]evice)/ { next }
    /^[[:space:]]*(No |None|no |none)/ { next }
    /^[[:space:]]*[-=]+[[:space:]]*$/ { next }
    /^[[:space:]]*[>*#-][[:space:]]+/ { print $2; next }
    { print $1 }
  '
}

diagnose() {
  warn "---- device_up.sh diagnosis ----"
  if [ -z "${ANDROID_SDK:-}" ]; then
    warn "ANDROID_SDK is not set; run 'android info' and export the SDK path before booting emulators"
  elif [ ! -w "${ANDROID_SDK}" ]; then
    warn "SDK directory is not writable: ${ANDROID_SDK} (AVDs and images cannot be created; fix permissions or set ANDROID_SDK)"
  else
    log "SDK: ${ANDROID_SDK} (writable)"
  fi
  if [ -e /dev/kvm ]; then
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
      log "KVM: /dev/kvm present and accessible"
    else
      warn "KVM: /dev/kvm exists but is not accessible; add your user to the kvm group and re-login: sudo usermod -aG kvm \"\$USER\""
    fi
  else
    warn "KVM: /dev/kvm missing; hardware acceleration is unavailable. Use a physical device (--serial) or a KVM-capable host."
  fi
  if [ -n "${ANDROID_SDK:-}" ] && [ -d "${ANDROID_SDK}/system-images" ]; then
    log "system images: $(ls -1 "${ANDROID_SDK}/system-images" 2>/dev/null | tr '\n' ' ')"
  else
    warn "system images: none under ${ANDROID_SDK:-<sdk>}/system-images; install one in the SDK Manager, then rerun 'android emulator create ${PROFILE}'"
  fi
  if [ -n "${ADB}" ]; then
    warn "adb devices:"
    "${ADB}" devices 2>/dev/null || true
  else
    warn "adb: not found under ${ANDROID_SDK:-<sdk>}/platform-tools and not on PATH"
  fi
  warn "emulator log: ${ARTIFACTS_DIR}/emulator-*.log ; runtime log: ${ADB:-adb} -s <serial> logcat -d | tail -n 200"
  warn "next: inspect the plan with '${SCRIPT_DIR}/device_up.sh --dry-run', then retry with --headless or --serial <serial>"
}

fail() {
  warn "$*"
  diagnose
  exit 1
}

# Create an AVD when none exists, or reuse an existing one. Idempotent.
ensure_avd() {
  local avds selected
  avds="$(list_avds || true)"
  if [ -n "${AVD}" ]; then
    selected="$(printf '%s\n' "${avds}" | awk -v want="${AVD}" '$0 == want { print; exit }')"
    if [ -n "${selected}" ]; then
      log "using existing AVD '${AVD}'"
      return 0
    fi
    fail "AVD '${AVD}' is not listed by 'android emulator list'. Create it with: android emulator create ${PROFILE}"
  fi
  if [ -n "${avds}" ]; then
    AVD="$(printf '%s\n' "${avds}" | awk -v want="${PROFILE}" '$0 == want { print; exit }')"
    if [ -n "${AVD}" ]; then
      log "reusing AVD '${AVD}' (profile ${PROFILE})"
      return 0
    fi
    AVD="$(printf '%s\n' "${avds}" | sed -n '1p')"
    warn "no AVD named '${PROFILE}'; reusing the first listed AVD '${AVD}'"
    return 0
  fi
  log "no AVD found; creating one from profile '${PROFILE}'"
  android_cli emulator create "${PROFILE}" || fail "'android emulator create ${PROFILE}' failed (missing system image or unwritable SDK)"
  avds="$(list_avds || true)"
  AVD="$(printf '%s\n' "${avds}" | awk -v want="${PROFILE}" '$0 == want { print; exit }')"
  [ -n "${AVD}" ] || AVD="$(printf '%s\n' "${avds}" | sed -n '1p')"
  [ -n "${AVD}" ] || fail "emulator create reported success but no AVD is listed; run 'android emulator list'"
  log "created AVD '${AVD}'"
}

start_emulator() {
  local avd="$1" emu=""
  if [ "${HEADLESS}" -eq 1 ]; then
    if [ -n "${ANDROID_SDK:-}" ] && [ -x "${ANDROID_SDK}/emulator/emulator" ]; then
      emu="${ANDROID_SDK}/emulator/emulator"
    elif have emulator; then
      emu="$(command -v emulator)"
    fi
    if [ -n "${emu}" ]; then
      log "starting '${avd}' headless: ${emu} -avd ${avd} -no-window"
      nohup "${emu}" -avd "${avd}" -no-window -no-audio -no-boot-anim \
        -gpu swiftshader_indirect >"${ARTIFACTS_DIR}/emulator-${avd}.log" 2>&1 &
      log "emulator pid $! (log: ${ARTIFACTS_DIR}/emulator-${avd}.log)"
      return 0
    fi
    warn "--headless requested but no emulator binary was found; falling back to 'android emulator start' (a window may open)"
  fi
  log "starting '${avd}' with 'android emulator start' (waits for full boot)"
  android_cli emulator start "${avd}"
}

wait_for_boot() {
  local serial="$1" deadline booted
  deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
  log "waiting for ${serial} to finish booting (timeout ${BOOT_TIMEOUT}s)"
  while :; do
    booted="$("${ADB}" -s "${serial}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r ' || true)"
    if [ "${booted}" = "1" ]; then
      if "${ADB}" -s "${serial}" shell pm path android >/dev/null 2>&1; then
        log "${serial} is booted and the package manager responds"
        return 0
      fi
    fi
    if [ "$(date +%s)" -ge "${deadline}" ]; then
      return 1
    fi
    sleep 2
  done
}

discover_new_serial() {
  local before="$1" deadline s
  deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
  while :; do
    while IFS= read -r s; do
      [ -n "${s}" ] || continue
      case " ${before} " in
        *" ${s} "*) continue ;;
      esac
      printf '%s\n' "${s}"
      return 0
    done <<<"$(online_serials)"
    if [ "$(date +%s)" -ge "${deadline}" ]; then
      return 1
    fi
    sleep 2
  done
}

# Map a running emulator serial to its AVD name; physical devices are skipped.
is_avd_running() {
  local avd="$1" s name
  while IFS= read -r s; do
    [ -n "${s}" ] || continue
    case "${s}" in
      emulator-*) : ;;
      *) continue ;;
    esac
    name="$("${ADB}" -s "${s}" emu avd name 2>/dev/null | sed -n '1p' | tr -d '\r' || true)"
    if [ "${name}" = "${avd}" ]; then
      printf '%s\n' "${s}"
      return 0
    fi
  done <<<"$(online_serials)"
  return 1
}

wait_for_avd() {
  local avd="$1" deadline found
  deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
  while :; do
    found="$(is_avd_running "${avd}" || true)"
    if [ -n "${found}" ]; then
      printf '%s\n' "${found}"
      return 0
    fi
    if [ "$(date +%s)" -ge "${deadline}" ]; then
      return 1
    fi
    sleep 2
  done
}

resolve_adb

if [ "${DRY_RUN}" -eq 1 ]; then
  log "device_up.sh dry-run - nothing will be created, installed or launched"
  log "sdk=${ANDROID_SDK:-<unset>} adb=${ADB:-<missing>} profile=${PROFILE} avd=${AVD:-<auto>} headless=${HEADLESS} timeout=${BOOT_TIMEOUT}s"
  if [ -n "${ADB}" ]; then
    log "currently connected devices:"
    "${ADB}" devices 2>/dev/null | sed 's/^/  /' || true
  fi
  cat <<EOF
plan:
  1. require gradlew in ${APP_ROOT} (workspace check)
  2. --serial wins; --avd starts or reuses exactly that AVD; otherwise reuse an
     online device, else android emulator list -> create '${PROFILE}' when empty
  3. start '${AVD:-<first avd>}' (no AVD yet: create it from profile ${PROFILE})
  4. wait for 'getprop sys.boot_completed' == 1 on the selected serial
  5. clear the logcat crash buffer, then: android run --device=<serial> --debug
  6. fail when a FATAL EXCEPTION appears; print the serial on success
expected success output:
  device ready: emulator-5554
  emulator-5554
EOF
  exit 0
fi

require_app
if [ -z "${ADB}" ]; then
  fail "adb not found (expected ${ANDROID_SDK:-<sdk>}/platform-tools/adb). Run 'android info' or install platform-tools."
fi
mkdir -p "${ARTIFACTS_DIR}" "${REPORTS_DIR}"

if [ -n "${SERIAL}" ]; then
  if ! online_serials | awk -v want="${SERIAL}" '$0 == want { found = 1 } END { exit(found ? 0 : 1) }'; then
    fail "device '${SERIAL}' is not connected. Check 'adb devices', or omit --serial to boot an emulator."
  fi
  log "using connected device ${SERIAL}"
elif [ -n "${AVD}" ]; then
  RUNNING="$(is_avd_running "${AVD}" || true)"
  if [ -n "${RUNNING}" ]; then
    SERIAL="${RUNNING}"
    log "AVD '${AVD}' is already running as ${SERIAL}"
  else
    ensure_avd
    BEFORE="$(online_serials)"
    start_emulator "${AVD}" || fail "could not start AVD '${AVD}'"
    SERIAL="$(wait_for_avd "${AVD}" || true)"
    [ -n "${SERIAL}" ] || SERIAL="$(discover_new_serial "${BEFORE}" || true)"
    [ -n "${SERIAL}" ] || fail "AVD '${AVD}' started but no serial came online within ${BOOT_TIMEOUT}s"
    wait_for_boot "${SERIAL}" || fail "device ${SERIAL} did not finish booting within ${BOOT_TIMEOUT}s"
  fi
else
  SERIAL="$(first_online)"
  if [ -n "${SERIAL}" ]; then
    log "reusing already-connected device ${SERIAL} (pass --avd or --serial to pin a target)"
  else
    ensure_avd
    BEFORE="$(online_serials)"
    start_emulator "${AVD}" || fail "could not start AVD '${AVD}'"
    SERIAL="$(discover_new_serial "${BEFORE}" || true)"
    [ -n "${SERIAL}" ] || SERIAL="$(wait_for_avd "${AVD}" || true)"
    [ -n "${SERIAL}" ] || fail "no emulator serial appeared within ${BOOT_TIMEOUT}s after starting '${AVD}'"
    wait_for_boot "${SERIAL}" || fail "device ${SERIAL} did not finish booting within ${BOOT_TIMEOUT}s"
  fi
fi

log "clearing the crash buffer on ${SERIAL}"
"${ADB}" -s "${SERIAL}" logcat -c >/dev/null 2>&1 || warn "could not clear logcat buffer on ${SERIAL} (continuing)"

log "installing and launching the debug app: android run --device=${SERIAL} --debug"
android_app run --device="${SERIAL}" --debug || fail "'android run' failed on ${SERIAL}; fix the build error above before device verification"

# Let the first frame settle, then treat a fresh fatal exception as a failure.
sleep 4
FOCUS="$("${ADB}" -s "${SERIAL}" shell dumpsys window 2>/dev/null | sed -n 's/.*mCurrentFocus=\([^}]*\).*/\1/p' | sed -n '1p' || true)"
CRASHES="$("${ADB}" -s "${SERIAL}" logcat -d -b crash 2>/dev/null | grep -E 'FATAL EXCEPTION|ANR in ' | sed -n '1,5p' || true)"
if [ -n "${CRASHES}" ]; then
  printf '%s\n' "${CRASHES}" >&2
  fail "the app crashed immediately after launch (see crash buffer above)"
fi
if [ -n "${FOCUS}" ]; then
  log "foreground window: ${FOCUS}"
else
  warn "could not read the foreground window from dumpsys; verify visually with device_check.sh"
fi

log "device ready: ${SERIAL}"
printf '%s\n' "${SERIAL}"
