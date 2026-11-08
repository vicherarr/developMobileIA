#!/usr/bin/env bash
# bootstrap.sh - prepare the pipeline kit and optionally link it into a project.
#
# Usage:
#   scripts/bootstrap.sh [--link-into <dir>] [--no-doctor] [--force]
#
# Options:
#   --link-into <dir>  Create <dir>/.agents -> kit/.agents so DSH and Android CLI
#                      discover the skills from another project root.
#   --no-doctor        Skip the environment diagnosis.
#   --force            Re-point an existing .agents symlink.
#   -h, --help         Show this help
#
# Exit codes: 0 ok, 1 failure, 2 usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
. "${PIPELINE_ROOT}/scripts/lib/android_env.sh"

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

LINK_INTO=""; RUN_DOCTOR=1; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --link-into) LINK_INTO="${2:-}"; shift 2 ;;
    --no-doctor) RUN_DOCTOR=0; shift ;;
    --force)     FORCE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; die "unknown option: $1" ;;
  esac
done

# ---------------------------------------------------------------------------
# 1. Directories
# ---------------------------------------------------------------------------
ensure_state_dirs
mkdir -p "${CACHE_DIR}" "${PIPELINE_ROOT}/02_pending_review/templates"
ok "state directories ready: ${STATE_DIR}"

# ---------------------------------------------------------------------------
# 2. Memory files (never overwrite existing content)
# ---------------------------------------------------------------------------
TEMPLATES="${PIPELINE_ROOT}/.agents/skills/10-project-memory/assets"
declare -A MAP=(
  [ARCHITECTURE.md]="ARCHITECTURE.template.md"
  [TECH_STACK.md]="TECH_STACK.template.md"
  [DECISION_LOG.md]="DECISION_LOG.template.md"
  [SESSION_STATE.md]="SESSION_STATE.template.md"
)
for target in "${!MAP[@]}"; do
  tpl="${TEMPLATES}/${MAP[$target]}"
  dst="${MEMORY_DIR}/${target}"
  if [ -f "$dst" ]; then
    continue
  elif [ -f "$tpl" ]; then
    mkdir -p "${MEMORY_DIR}"
    cp "$tpl" "$dst"
    ok "created 00_memory/${target} from template"
  else
    warn "missing template ${tpl} (run 'android skills add <name>' or restore the kit)"
  fi
done

# ---------------------------------------------------------------------------
# 3. Optional link into another project root
# ---------------------------------------------------------------------------
if [ -n "$LINK_INTO" ]; then
  [ -d "$LINK_INTO" ] || die "target directory does not exist: ${LINK_INTO}"
  LINK_INTO="$(cd "$LINK_INTO" && pwd)"
  target_link="${LINK_INTO}/.agents"

  if [ -e "$target_link" ] && [ ! -L "$target_link" ]; then
    die "${target_link} already exists and is not a symlink. Merge manually or choose another directory."
  fi
  if [ -L "$target_link" ] && [ "$FORCE" -eq 0 ]; then
    current="$(readlink "$target_link")"
    if [ "$current" != "${PIPELINE_ROOT}/.agents" ]; then
      die "${target_link} already points to ${current}. Re-run with --force to repoint it."
    fi
  fi

  ln -sfn "${PIPELINE_ROOT}/.agents" "$target_link"
  ok "linked ${target_link} -> ${PIPELINE_ROOT}/.agents"

  agents_md="${LINK_INTO}/AGENTS.md"
  if [ ! -e "$agents_md" ]; then
    cat >"$agents_md" <<EOF
# AGENTS.md

This project uses the Android agentic pipeline at \`${PIPELINE_ROOT}\`.

Skills are exposed through \`.agents/skills/\` (symlinked). Start every session
with the \`00-pipeline-orchestrator\` skill and follow its contract:

- Memory: \`${PIPELINE_ROOT}/00_memory/\`
- Human decision queue: \`${PIPELINE_ROOT}/02_pending_review/human_decisions.md\`
- Android project: \`${PIPELINE_ROOT}/app_workspace/\`

No evidence file, no progress.
EOF
    ok "created ${agents_md}"
  fi

  if [ ! -d "${LINK_INTO}/.git" ]; then
    warn "no .git in ${LINK_INTO}: DSH resolves the project root as the cwd. Run 'git init' there for stable skill discovery."
  fi
fi

# ---------------------------------------------------------------------------
# 4. Diagnosis
# ---------------------------------------------------------------------------
if [ "$RUN_DOCTOR" -eq 1 ]; then
  "${SCRIPT_DIR}/doctor.sh" || true
fi

# ---------------------------------------------------------------------------
# 5. Next steps
# ---------------------------------------------------------------------------
cat <<'EOF'
Next steps
  1. Open this folder (or the linked project root) in DeepSeek Harness.
  2. Say: "Build <your app idea>. Start at the spec and take it to G5."
     The agent loads 00-pipeline-orchestrator and writes .pipeline/spec.json.
  3. Then it runs 02-android-scaffold and 05-build-test-loop.
  4. At G6: 07-device-verification. At G7: 08-release-and-quality.
EOF
