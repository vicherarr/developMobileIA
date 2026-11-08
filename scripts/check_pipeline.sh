#!/usr/bin/env bash
# check_pipeline.sh - self-lint for the kit: skills, scripts, contracts, CLI usage.
#
# Usage:
#   scripts/check_pipeline.sh [--quiet]
#
# Options:
#   --quiet    Only print failures
#   -h, --help Show this help
#
# Exit codes: 0 clean, 1 problems found.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
. "${PIPELINE_ROOT}/scripts/lib/android_env.sh"

QUIET=0
case "${1:-}" in
  -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --quiet)   QUIET=1 ;;
  "")        : ;;
  *)         printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

PROBLEMS=0
say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
bad() { PROBLEMS=$((PROBLEMS + 1)); printf '%s\n' "$*"; }

# ---------------------------------------------------------------------------
# Skills: frontmatter, naming, contract, size
# ---------------------------------------------------------------------------
say "== skills =="
REPORT="$(mktemp)"
python3 - "$PIPELINE_ROOT" >"$REPORT" <<'PY'
import glob, os, re, sys
try:
    import yaml
except ImportError:
    print("warn|pyyaml not installed: frontmatter checks skipped")
    raise SystemExit(0)
root = sys.argv[1]
for p in sorted(glob.glob(os.path.join(root, ".agents/skills/*/SKILL.md"))):
    d = os.path.basename(os.path.dirname(p))
    raw = open(p, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", raw, re.S)
    if not m:
        print(f"fail|{d}: missing YAML frontmatter")
        continue
    try:
        fm = yaml.safe_load(m.group(1))
    except Exception as e:
        print(f"fail|{d}: invalid YAML: {e}")
        continue
    if not isinstance(fm, dict):
        print(f"fail|{d}: frontmatter is not a mapping")
        continue
    name, desc = fm.get("name"), fm.get("description") or ""
    body = len(raw) - m.end()
    if name != d:
        print(f"fail|{d}: name '{name}' must equal the directory name")
    elif not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name):
        print(f"fail|{d}: name is not kebab-case")
    elif not desc:
        print(f"fail|{d}: missing description")
    elif len(desc) > 1024:
        print(f"fail|{d}: description is {len(desc)} chars (max 1024)")
    elif body > 24000:
        print(f"warn|{d}: body is {body} chars (move detail to references/)")
    elif "## Contract" not in raw and d != "testing-setup":
        print(f"fail|{d}: missing '## Contract' section")
    else:
        print(f"ok|{d} ({len(desc)} desc / {body} body)")
PY
while IFS='|' read -r level msg; do
  case "$level" in
    fail) bad "  ${msg}" ;;
    warn) say "  warn ${msg}" ;;
    ok)   say "  ok   ${msg}" ;;
    *)    say "  ${level} ${msg}" ;;
  esac
done <"$REPORT"
rm -f "$REPORT"

# ---------------------------------------------------------------------------
# Scripts: syntax, executable, --help, shared env lib
# ---------------------------------------------------------------------------
say ""
say "== scripts =="
shopt -s nullglob
for f in "${PIPELINE_ROOT}"/scripts/*.sh "${PIPELINE_ROOT}"/.agents/skills/*/scripts/*.sh; do
  rel="${f#"${PIPELINE_ROOT}"/}"
  if ! bash -n "$f" 2>/dev/null; then
    bad "  syntax error: ${rel}"
    continue
  fi
  if [ ! -x "$f" ]; then
    bad "  not executable: ${rel}"
    continue
  fi
  if grep -q -- '--help' "$f" && ! "$f" --help >/dev/null 2>&1; then
    bad "  --help fails (wrong PIPELINE_ROOT depth?): ${rel}"
    continue
  fi
  if ! grep -q 'scripts/lib/android_env.sh' "$f"; then
    bad "  does not source scripts/lib/android_env.sh: ${rel}"
    continue
  fi
  say "  ok   ${rel}"
done

# ---------------------------------------------------------------------------
# Android CLI usage: refuse unknown subcommands
# ---------------------------------------------------------------------------
say ""
say "== CLI usage =="
KNOWN="analyze|auth|build|completion|create|describe|device|docs|emulator|help|info|init|input|install|layout|preview|profiler|run|screen|sdk|signals|skills|studio|update"
# Only look at command contexts: backticked `android <cmd>` and lines that start
# with the CLI. Negation lines ("do NOT invent `android journey`") are ignored.
HITS="$(
  grep -rhE '(`android |^[[:space:]]*android )[a-z][a-z-]+' --include=*.md --include=*.sh \
    "${PIPELINE_ROOT}/.agents/skills" "${PIPELINE_ROOT}/docs" 2>/dev/null \
  | grep -viE 'invent|no existe|not exist|never|do not' \
  | grep -oE '(`android |^[[:space:]]*android )[a-z][a-z-]+' \
  | sed -E 's/.*android[[:space:]]+//' | sort -u | grep -vE "^(${KNOWN})$" || true
)"
if [ -n "$HITS" ]; then
  while IFS= read -r sub; do
    [ -n "$sub" ] && bad "  unknown android subcommand: '${sub}'"
  done <<<"$HITS"
else
  say "  ok   no unknown subcommands"
fi

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
say ""
say "== layout =="
for required in AGENTS.md README.md 00_memory/ARCHITECTURE.md 00_memory/TECH_STACK.md \
  00_memory/DECISION_LOG.md 00_memory/SESSION_STATE.md 02_pending_review/human_decisions.md \
  app_workspace/.pipeline/STATE.json; do
  if [ -f "${PIPELINE_ROOT}/${required}" ]; then
    say "  ok   ${required}"
  else
    bad "  missing: ${required}"
  fi
done

say ""
if [ "$PROBLEMS" -eq 0 ]; then
  say "pipeline check: clean"
  exit 0
fi
printf 'pipeline check: %d problem(s)\n' "$PROBLEMS"
exit 1
