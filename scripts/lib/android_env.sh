#!/usr/bin/env bash
# Shared environment and helpers for the Android agentic pipeline.
#
# Source it from any pipeline script:
#
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
#   . "${PIPELINE_ROOT}/scripts/lib/android_env.sh"
#
# It is read-only with respect to the project: it never edits sources, never
# installs SDK packages and never starts long-running services.

# Guard against double-sourcing.
if [ -n "${__ANDROID_ENV_SH__:-}" ]; then
  return 0 2>/dev/null || true
fi
__ANDROID_ENV_SH__=1

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
if [ -z "${PIPELINE_ROOT:-}" ]; then
  PIPELINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export PIPELINE_ROOT
APP_ROOT="${APP_ROOT:-${PIPELINE_ROOT}/app_workspace}"
STATE_DIR="${STATE_DIR:-${APP_ROOT}/.pipeline}"
REPORTS_DIR="${REPORTS_DIR:-${STATE_DIR}/reports}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${STATE_DIR}/artifacts}"
MEMORY_DIR="${MEMORY_DIR:-${PIPELINE_ROOT}/00_memory}"
REVIEW_DIR="${REVIEW_DIR:-${PIPELINE_ROOT}/02_pending_review}"
CACHE_DIR="${CACHE_DIR:-${PIPELINE_ROOT}/.cache}"
export APP_ROOT STATE_DIR REPORTS_DIR ARTIFACTS_DIR MEMORY_DIR REVIEW_DIR CACHE_DIR

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  __C_RESET=$'\033[0m'; __C_DIM=$'\033[2m'; __C_RED=$'\033[31m'
  __C_YEL=$'\033[33m'; __C_GRN=$'\033[32m'; __C_BLU=$'\033[34m'
else
  __C_RESET=""; __C_DIM=""; __C_RED=""; __C_YEL=""; __C_GRN=""; __C_BLU=""
fi

log()  { printf '%s[pipeline]%s %s\n'  "${__C_BLU}" "${__C_RESET}" "$*"; }
ok()   { printf '%s[ ok ]%s %s\n'      "${__C_GRN}" "${__C_RESET}" "$*"; }
warn() { printf '%s[warn]%s %s\n'      "${__C_YEL}" "${__C_RESET}" "$*" >&2; }
die()  { printf '%s[fail]%s %s\n'      "${__C_RED}" "${__C_RESET}" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Time and reports
# ---------------------------------------------------------------------------
utc_stamp() { date -u +%Y%m%dT%H%M%SZ; }
utc_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

ensure_state_dirs() { mkdir -p "${STATE_DIR}" "${REPORTS_DIR}" "${ARTIFACTS_DIR}"; }

# emit_report <file> ; JSON on stdin. Written atomically so a crashed script
# never leaves a half-written evidence file behind.
emit_report() {
  local out="$1" tmp
  mkdir -p "$(dirname "$out")"
  tmp="$(mktemp "${out}.XXXXXX")"
  cat >"${tmp}"
  mv -f "${tmp}" "${out}"
  log "report written: ${out}"
}

# ---------------------------------------------------------------------------
# Android SDK resolution
# ---------------------------------------------------------------------------
__first_existing_dir() {
  local c
  for c in "$@"; do
    [ -n "${c}" ] && [ -d "${c}" ] && { printf '%s' "${c}"; return 0; }
  done
  return 1
}

resolve_android_sdk() {
  local from_props=""
  if [ -f "${APP_ROOT}/local.properties" ]; then
    from_props="$(sed -n 's/^sdk\.dir=//p' "${APP_ROOT}/local.properties" 2>/dev/null | head -n1)"
  fi
  __first_existing_dir \
    "${ANDROID_SDK:-}" \
    "${ANDROID_HOME:-}" \
    "${ANDROID_SDK_ROOT:-}" \
    "${from_props}" \
    "${HOME:-}/Android/Sdk" \
    "${HOME:-}/Library/Android/sdk" \
    "/opt/android-sdk" \
    "/usr/lib/android-sdk" \
    "${PIPELINE_ROOT}/.cache/android-sdk" || return 1
}

ANDROID_SDK="$(resolve_android_sdk || true)"
export ANDROID_SDK
if [ -n "${ANDROID_SDK}" ]; then
  export ANDROID_HOME="${ANDROID_SDK}"
  export ANDROID_SDK_ROOT="${ANDROID_SDK}"
fi

adb_bin() {
  if [ -n "${ANDROID_SDK}" ] && [ -x "${ANDROID_SDK}/platform-tools/adb" ]; then
    printf '%s' "${ANDROID_SDK}/platform-tools/adb"
  elif have adb; then
    command -v adb
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Android CLI wrapper
# ---------------------------------------------------------------------------
# The CLI writes state under $HOME/.android/cli. Under a read-only HOME
# sandbox that fails with "Read-only file system", so fall back to a cache
# directory inside the pipeline.
__android_cli_home() {
  if [ -n "${ANDROID_CLI_HOME:-}" ]; then
    printf '%s' "${ANDROID_CLI_HOME}"
    return
  fi
  if [ -n "${HOME:-}" ] && mkdir -p "${HOME}/.android/cli" 2>/dev/null && [ -w "${HOME}/.android/cli" ]; then
    printf '%s' "${HOME}"
    return
  fi
  local ch="${CACHE_DIR}/android-cli-home"
  mkdir -p "${ch}/.android"
  # The CLI resolves AVDs from $HOME/.android/avd; mirror the real one so the
  # emulator commands keep seeing the user's devices under a read-only HOME.
  if [ -n "${HOME:-}" ] && [ -d "${HOME}/.android/avd" ] && [ ! -L "${ch}/.android/avd" ]; then
    ln -sfn "${HOME}/.android/avd" "${ch}/.android/avd"
  fi
  printf '%s' "${ch}"
}

android_cli() {
  have android || die "'android' (Android CLI) not found on PATH. Install it from https://developer.android.com/tools/agents and re-run."
  local -a sdk_args=()
  [ -n "${ANDROID_SDK}" ] && sdk_args=(--sdk="${ANDROID_SDK}")
  local cli_home
  cli_home="$(__android_cli_home)"
  HOME="${cli_home}" XDG_CACHE_HOME="${cli_home}/.cache" \
    android "${sdk_args[@]}" "$@"
}

# Project-scoped variant: `android build|install|run|preview|describe` resolve
# the Gradle workspace from the current directory, so they must run inside
# app_workspace, not at the pipeline root.
android_app() {
  require_app
  ( cd "${APP_ROOT}" && android_cli "$@" )
}

# ---------------------------------------------------------------------------
# Gradle wrapper
# ---------------------------------------------------------------------------
require_app() {
  if [ ! -x "${APP_ROOT}/gradlew" ]; then
    die "No Gradle wrapper at ${APP_ROOT}/gradlew. Run the '02-android-scaffold' skill (scripts/scaffold_project.sh) first, or point APP_ROOT at the project."
  fi
}

gradlew() {
  require_app

  # GRADLE_USER_HOME must be writable (caches, wrapper distribution).
  local guh="${GRADLE_USER_HOME:-}"
  if [ -z "${guh}" ]; then
    if [ -n "${HOME:-}" ] && { [ -d "${HOME}/.gradle" ] && [ -w "${HOME}/.gradle" ] || { mkdir -p "${HOME}/.gradle" 2>/dev/null && [ -w "${HOME}/.gradle" ]; }; }; then
      guh="${HOME}/.gradle"
    else
      guh="${CACHE_DIR}/gradle-home"
      mkdir -p "${guh}"
      warn "HOME is not writable; using GRADLE_USER_HOME=${guh} (first run downloads the Gradle distribution and dependencies)."
    fi
  fi

  # AGP also needs a writable Android user home for the debug keystore,
  # avd/ and analytics (it defaults to ~/.android). Without this, builds fail
  # at :app:validateSigningDebug under a read-only HOME sandbox.
  local auh="${ANDROID_USER_HOME:-}"
  if [ -z "${auh}" ] && [ -n "${HOME:-}" ] && [ -w "${HOME}" ]; then
    auh="${HOME}/.android"
    mkdir -p "${auh}" 2>/dev/null || true
  fi
  if [ -z "${auh}" ] || [ ! -w "${auh}" ]; then
    auh="${CACHE_DIR}/android-user-home"
    mkdir -p "${auh}"
    warn "HOME is not writable; using ANDROID_USER_HOME=${auh} (debug keystore lives here)."
  fi

  ( cd "${APP_ROOT}" \
      && ANDROID_USER_HOME="${auh}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${auh}/.config}" \
         GRADLE_USER_HOME="${guh}" ./gradlew --console=plain "$@" )
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
# Devices currently visible to adb (serial per line).
adb_devices() {
  local adb
  adb="$(adb_bin)" || return 1
  "${adb}" devices | awk 'NR>1 && $2=="device" {print $1}'
}

# Latest file matching a glob under $REPORTS_DIR, else empty.
latest_report() {
  local pattern="${1:-*.json}"
  # shellcheck disable=SC2012
  ls -1t "${REPORTS_DIR}"/${pattern} 2>/dev/null | head -n1 || true
}

pipeline_summary() {
  printf 'pipeline_root=%s\napp_root=%s\nandroid_sdk=%s\nandroid_cli=%s\n' \
    "${PIPELINE_ROOT}" "${APP_ROOT}" "${ANDROID_SDK:-<unresolved>}" \
    "$(command -v android || echo '<missing>')"
}
