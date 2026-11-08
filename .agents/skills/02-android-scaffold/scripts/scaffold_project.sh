#!/usr/bin/env bash
# scaffold_project.sh - create the Android project for G2 using Android CLI.
#
# Works with both Android CLI bundle variants:
#   legacy : create --name --minSdk -o            (empty dir only, no --force)
#   current: create --name --min-sdk --application-id --namespace --output --force
#
# It always generates into a staging directory and merges the result into
# app_workspace, so an existing .pipeline/ or README never blocks creation.
# Package identity is normalized after generation (the legacy bundle ignores
# application-id/namespace), and success is validated by artifacts, not by the
# CLI exit code (the legacy bundle exits 0 even when creation fails).
#
# Usage:
#   scripts/scaffold_project.sh [options]
#
# Options:
#   --name "<App Name>"      Override the app name (default: spec.json app.name)
#   --app-id <id>            Override applicationId/namespace (default: spec.json)
#   --min-sdk <n>            Override minSdk (default: spec.json or template)
#   --compile-sdk <n>        Override compileSdk (default: spec.json or template)
#   --target-sdk <n>         Override targetSdk (default: spec.json or template)
#   --template <name>        Android CLI template (default: empty-activity)
#   --no-build               Skip the verification build
#   --force                  Replace an existing Gradle project (keeps .pipeline/)
#   --dry-run                Print the plan, change nothing
#   -h, --help               Show this help
#
# Exit codes: 0 ok, 1 failure, 2 usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
# shellcheck source=/dev/null
. "${PIPELINE_ROOT}/scripts/lib/android_env.sh"

usage() {
  awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "${BASH_SOURCE[0]}"
}

NAME=""; APP_ID=""; MIN_SDK=""; COMPILE_SDK=""; TARGET_SDK=""; TEMPLATE="empty-activity"
DO_BUILD=1; FORCE=0; DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --name)      NAME="${2:-}"; shift 2 ;;
    --app-id)    APP_ID="${2:-}"; shift 2 ;;
    --min-sdk)   MIN_SDK="${2:-}"; shift 2 ;;
    --compile-sdk) COMPILE_SDK="${2:-}"; shift 2 ;;
    --target-sdk)  TARGET_SDK="${2:-}"; shift 2 ;;
    --template)  TEMPLATE="${2:-}"; shift 2 ;;
    --no-build)  DO_BUILD=0; shift ;;
    --force)     FORCE=1; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; die "unknown option: $1" ;;
  esac
done

ensure_state_dirs
SPEC="${STATE_DIR}/spec.json"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
[ "$DRY_RUN" -eq 1 ] || have android || die "Android CLI not found. See https://developer.android.com/tools/agents"
[ "$DRY_RUN" -eq 1 ] || have python3  || die "python3 is required to read spec.json"
[ -n "${ANDROID_SDK}" ] || die "Android SDK not found. Set ANDROID_HOME or install the SDK (android sdk install)."

if [ -f "$SPEC" ] && have python3; then
  [ -n "$NAME" ]    || NAME="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["app"]["name"])' "$SPEC")"
  [ -n "$APP_ID" ]  || APP_ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["app"]["applicationId"])' "$SPEC")"
  [ -n "$MIN_SDK" ] || MIN_SDK="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["app"].get("minSdk",""))' "$SPEC")"
  [ -n "$COMPILE_SDK" ] || COMPILE_SDK="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["app"].get("compileSdk",""))' "$SPEC")"
  [ -n "$TARGET_SDK" ]  || TARGET_SDK="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["app"].get("targetSdk",""))' "$SPEC")"
fi
[ -n "$NAME" ]   || die "Missing app name: pass --name or write ${SPEC} (G1)."
[ -n "$APP_ID" ] || APP_ID="com.example.$(printf '%s' "$NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
MIN_SDK="${MIN_SDK:-24}"

if [ -x "${APP_ROOT}/gradlew" ] && [ "$FORCE" -eq 0 ]; then
  die "${APP_ROOT} already contains a Gradle project. Re-run with --force to replace it (keeps .pipeline/)."
fi

# Capability probe: the installed bundle may be the legacy signature.
CREATE_HELP=""
if have android; then
  CREATE_HELP="$(android_cli create -h 2>&1 || true)"
fi
has_flag() { printf '%s' "$CREATE_HELP" | grep -q -- "$1"; }

cli_interface="current"
has_flag '--application-id' || cli_interface="legacy"

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

CREATE_ARGS=(create --name="$NAME" -o="$STAGE")
if has_flag '--min-sdk'; then
  CREATE_ARGS+=("--min-sdk=${MIN_SDK}")
elif has_flag '--minSdk'; then
  CREATE_ARGS+=("--minSdk=${MIN_SDK}")
fi
if [ "$cli_interface" = "current" ]; then
  CREATE_ARGS+=("--application-id=${APP_ID}" "--namespace=${APP_ID}")
fi
[ "$TEMPLATE" != "empty-activity" ] && CREATE_ARGS+=("$TEMPLATE")

log "scaffolding '${NAME}' (${APP_ID}) into ${APP_ROOT}"
log "CLI interface: ${cli_interface}; staging: ${STAGE}"
log "android ${CREATE_ARGS[*]}"

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'DRY-RUN: android --sdk=%s %s\n' "${ANDROID_SDK:-<sdk>}" "${CREATE_ARGS[*]}"
  printf 'DRY-RUN: normalize package to %s, merge staging into %s\n' "$APP_ID" "$APP_ROOT"
  printf 'DRY-RUN: compileSdk=%s targetSdk=%s minSdk=%s (spec overrides template)\n' \
    "${COMPILE_SDK:-<template>}" "${TARGET_SDK:-<template>}" "$MIN_SDK"
  printf 'DRY-RUN: write local.properties, .gitignore, gradle.properties, report\n'
  if [ "$DO_BUILD" -eq 1 ]; then
    printf 'DRY-RUN: android build :app@debug (verification)\n'
  fi
  exit 0
fi

if [ ! -w "${ANDROID_SDK}" ]; then
  warn "Android SDK at ${ANDROID_SDK} is not writable. 'android create' may need to download its templates package."
fi

# ---------------------------------------------------------------------------
# Create (exit code is unreliable; validate artifacts)
# ---------------------------------------------------------------------------
CREATE_LOG="$(mktemp)"
set +e
android_cli "${CREATE_ARGS[@]}" 2>&1 | tee "$CREATE_LOG"
set -e

if [ ! -f "${STAGE}/gradlew" ] || [ ! -f "${STAGE}/settings.gradle.kts" ]; then
  warn "android create did not produce a Gradle project. Tail:"
  tail -n 30 "$CREATE_LOG" >&2
  emit_report "${REPORTS_DIR}/scaffold-$(utc_stamp).json" <<JSON
{"schema":1,"gate":"G2","status":"fail","step":"android_create","cli_interface":"${cli_interface}","app":"${NAME}","application_id":"${APP_ID}","timestamp":"$(utc_iso)","error":"android create produced no Gradle project","log_tail":$(python3 -c 'import json,sys;print(json.dumps(open(sys.argv[1]).read().splitlines()[-30:]))' "$CREATE_LOG")}
JSON
  exit 1
fi
rm -f "$CREATE_LOG"
chmod +x "${STAGE}/gradlew"

# ---------------------------------------------------------------------------
# Normalize package identity inside staging (legacy bundle ignores it)
# ---------------------------------------------------------------------------
GENERATED_ID="$(sed -n 's/^ *namespace *= *"\([^"]*\)".*/\1/p' "${STAGE}/app/build.gradle.kts" 2>/dev/null | head -n1)"
GENERATED_ID="${GENERATED_ID:-com.example.myapplication}"

if [ "$GENERATED_ID" != "$APP_ID" ]; then
  log "normalizing package: ${GENERATED_ID} -> ${APP_ID}"
  python3 - "$STAGE" "$GENERATED_ID" "$APP_ID" <<'PY'
import os, sys

root, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
old_path = old.replace(".", os.sep)
new_path = new.replace(".", os.sep)
text_ext = {".kt", ".kts", ".java", ".xml", ".toml", ".pro", ".properties", ".gradle", ".json"}

# 1. Move package directories (deepest first so parents stay valid).
for dirpath, dirnames, _ in os.walk(root):
    for d in list(dirnames):
        full = os.path.join(dirpath, d)
        if full.endswith(os.sep + old_path):
            # Replace only the trailing package path: <base>/com/example/old
            # becomes <base>/com/example/app (never <parent>/com/example/app).
            base = full[: -len(old_path)]
            target = base + new_path
            if os.path.abspath(full) == os.path.abspath(target):
                continue
            os.makedirs(target, exist_ok=True)
            for entry in os.listdir(full):
                os.replace(os.path.join(full, entry), os.path.join(target, entry))
            os.rmdir(full)
            # Prune now-empty ancestors left behind by the old package.
            p = os.path.dirname(full)
            while p != root and os.path.isdir(p) and not os.listdir(p):
                os.rmdir(p)
                p = os.path.dirname(p)
            if d in dirnames:
                dirnames.remove(d)

# 2. Rewrite references in text files.
for dirpath, _, files in os.walk(root):
    for f in files:
        if os.path.splitext(f)[1] not in text_ext:
            continue
        path = os.path.join(dirpath, f)
        try:
            src = open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        if old in src:
            open(path, "w", encoding="utf-8").write(src.replace(old, new))
PY
fi

# Enforce applicationId/namespace even when the bundle accepted only one.
if [ -f "${STAGE}/app/build.gradle.kts" ]; then
  sed -i -E "s/^( *namespace *= *\")[^\"]*(\")/\1${APP_ID}\2/; s/^( *applicationId *= *\")[^\"]*(\")/\1${APP_ID}\2/" \
    "${STAGE}/app/build.gradle.kts"
fi

# Honor compileSdk/targetSdk from the spec. The CLI template may ship a newer
# compileSdk than the pinned AGP supports (e.g. 37 with AGP 9.0.1, whose ceiling
# is 36.1), so the spec is the source of truth when it declares a value.
if [ -f "${STAGE}/app/build.gradle.kts" ]; then
  [ -n "$COMPILE_SDK" ] && sed -i -E "s/^( *)compileSdk *= *[0-9]+/\1compileSdk = ${COMPILE_SDK}/" "${STAGE}/app/build.gradle.kts"
  [ -n "$TARGET_SDK" ]  && sed -i -E "s/^( *)targetSdk *= *[0-9]+/\1targetSdk = ${TARGET_SDK}/"  "${STAGE}/app/build.gradle.kts"
fi

# Align the Gradle root project name with the spec.
if [ -f "${STAGE}/settings.gradle.kts" ]; then
  python3 - "$STAGE/settings.gradle.kts" "$NAME" <<'PY'
import re, sys
path, name = sys.argv[1], sys.argv[2]
src = open(path).read()
new = re.sub(r'rootProject\.name\s*=\s*"[^"]*"',
             'rootProject.name = "%s"' % name.replace('"', ''), src, count=1)
if new != src:
    open(path, "w").write(new)
PY
fi

# ---------------------------------------------------------------------------
# Replace the project in app_workspace, preserving pipeline state
# ---------------------------------------------------------------------------
if [ "$FORCE" -eq 1 ]; then
  log "--force: removing previous Gradle project files (keeping .pipeline/ and README.md)"
  ( cd "$APP_ROOT" && rm -rf app core feature build.gradle.kts settings.gradle.kts \
      gradle gradlew gradlew.bat gradle.properties .gitignore )
fi

# Keep our app_workspace README when the template ships one too.
README_BAK=""
if [ -f "${APP_ROOT}/README.md" ] && [ -f "${STAGE}/README.md" ]; then
  README_BAK="$(mktemp)"
  cp "${APP_ROOT}/README.md" "$README_BAK"
fi

cp -a "${STAGE}/." "${APP_ROOT}/"

if [ -n "$README_BAK" ]; then
  cp "$README_BAK" "${APP_ROOT}/README.md"
  rm -f "$README_BAK"
fi

# ---------------------------------------------------------------------------
# Deterministic post-processing (idempotent)
# ---------------------------------------------------------------------------
printf 'sdk.dir=%s\n' "$ANDROID_SDK" >"${APP_ROOT}/local.properties"
log "wrote local.properties (sdk.dir)"

touch "${APP_ROOT}/.gitignore"
for entry in '.gradle/' 'build/' 'local.properties' '.idea/' '.kotlin/' '.pipeline/reports/' '.pipeline/artifacts/' '*.iml' '.DS_Store' 'captures/'; do
  grep -qxF "$entry" "${APP_ROOT}/.gitignore" 2>/dev/null || printf '%s\n' "$entry" >>"${APP_ROOT}/.gitignore"
done

prop() {
  local f="${APP_ROOT}/gradle.properties" k="$1" v="$2"
  touch "$f"
  grep -qE "^${k}=" "$f" || printf '%s=%s\n' "$k" "$v" >>"$f"
}
prop org.gradle.caching         true
prop org.gradle.parallel        true
prop org.gradle.jvmargs         "-Xmx4g -Dfile.encoding=UTF-8"
prop kotlin.code.style          official
prop android.nonTransitiveRClass true

# ---------------------------------------------------------------------------
# Verify the build (the actual G2 evidence)
# ---------------------------------------------------------------------------
BUILD_STATUS="skipped"
BUILD_TAIL=""
if [ "$DO_BUILD" -eq 1 ]; then
  log "verifying with: android build :app@debug"
  BUILD_LOG="$(mktemp)"
  set +e
  android_app build ':app@debug' 2>&1 | tee "$BUILD_LOG"
  BUILD_RC=${PIPESTATUS[0]}
  set -e
  if [ "$BUILD_RC" -eq 0 ] && ls "${APP_ROOT}"/app/build/outputs/apk/debug/*.apk >/dev/null 2>&1; then
    BUILD_STATUS="pass"
  else
    BUILD_STATUS="fail"
    BUILD_TAIL="$(tail -n 40 "$BUILD_LOG")"
  fi
  rm -f "$BUILD_LOG"
fi

AGP="$(sed -n 's/^androidGradlePlugin *= *"\(.*\)"/\1/p' "${APP_ROOT}/gradle/libs.versions.toml" 2>/dev/null | head -n1)"
KOTLIN="$(sed -n 's/^kotlin *= *"\(.*\)"/\1/p' "${APP_ROOT}/gradle/libs.versions.toml" 2>/dev/null | head -n1)"
COMPOSE_BOM="$(sed -n 's/^androidxComposeBom *= *"\(.*\)"/\1/p' "${APP_ROOT}/gradle/libs.versions.toml" 2>/dev/null | head -n1)"
GRADLE_WRAPPER="$(sed -n 's/.*gradle-\([0-9.]*\)\(-bin\)\?\.zip/\1/p' "${APP_ROOT}/gradle/wrapper/gradle-wrapper.properties" 2>/dev/null | head -n1)"
JAVA_V="$(java -version 2>&1 | head -n1 | sed 's/.*version "\([^"]*\)".*/\1/')"

STATUS="pass"
[ "$BUILD_STATUS" = "fail" ] && STATUS="fail"
[ "$BUILD_STATUS" = "skipped" ] && STATUS="partial"

emit_report "${REPORTS_DIR}/scaffold-$(utc_stamp).json" <<JSON
{
  "schema": 1,
  "gate": "G2",
  "status": "${STATUS}",
  "app": $(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$NAME"),
  "application_id": "${APP_ID}",
  "template": "${TEMPLATE}",
  "cli_interface": "${cli_interface}",
  "project_root": "app_workspace",
  "versions": {
    "agp": "${AGP}",
    "kotlin": "${KOTLIN}",
    "compose_bom": "${COMPOSE_BOM}",
    "gradle_wrapper": "${GRADLE_WRAPPER}",
    "jdk": "${JAVA_V}"
  },
  "sdk_levels": { "min": "${MIN_SDK}", "compile": "${COMPILE_SDK:-template}", "target": "${TARGET_SDK:-template}" },
  "android_sdk": "${ANDROID_SDK}",
  "build": { "status": "${BUILD_STATUS}", "task": ":app@debug" },
  "timestamp": "$(utc_iso)"
}
JSON

if [ "$STATUS" = "fail" ]; then
  printf '%s\n' "$BUILD_TAIL" >&2
  die "Scaffold created but the verification build failed. Fix with 05-build-test-loop (do not advance to G3)."
fi

ok "scaffold complete: ${APP_ROOT} (${STATUS})"
log "next: pin versions in 00_memory/TECH_STACK.md, then run the 03-domain-and-data skill"
