#!/usr/bin/env bash
# Lint: check that skill markdown files don't contain raw VCS commands
# where they should use the VCS-agnostic `scripts/vcs-op` dispatcher instead.
# Only checks executable-instruction patterns (commands an LLM agent would run
# during a workflow), not prose or examples.
#
# Usage:
#   lint-vcs-refs.sh [--strict]
#
#   --strict  Fail on any raw git command (including prose). Default: fail
#             only on executable-instruction patterns.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${SKILLS_DIR:-"$APM_DIR/skills"}"

# Patterns that look like executable instructions to an LLM agent
# (backtick-wrapped commands, or standalone command instructions)
PATTERNS=(
  'git diff '
  'git push '
  'git log '
  'git commit '
  'git add '
  'git branch '
  'git rev-parse '
  'git symbolic-ref '
  'git status --porcelain'
  'git remote get-url'
  'git pull --ff-only'
  'git remote set-head'
  'jj diff '
  'jj log '
  'jj bookmark '
  'jj git fetch'
  'jj git push'
  'jj git remote'
  'jj describe'
  'jj new '
  'jj file list'
)

extra_args=()
strict=false
for arg in "$@"; do
  case "$arg" in
    --strict) strict=true ;;
    *) extra_args+=("$arg") ;;
  esac
done

violations=0

# When not in strict mode, allow git commands in:
# - talk/SKILL.md (talk mode allows all git commands except mutations)
# - do/SKILL.md (the do workflow orchestrates vcs-op; git references
#   are in prose describing vcs-op's internal behavior, not instructions
#   for the agent to execute directly)

# Non-strict skips: allow git/jj references in these files where they
# appear as documented fallback examples, not as executable instructions.
is_exempt() {
  [ "$strict" = false ] || return 1
  case "$1" in
    */do/SKILL.md)    return 0 ;;
    */talk/SKILL.md)  return 0 ;;
    *)                return 1 ;;
  esac
}

for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  is_exempt "$skill_file" && continue
  for pattern in "${PATTERNS[@]}"; do
    if grep -q "$pattern" "$skill_file" 2>/dev/null; then
      echo "::error file=$skill_file::Raw VCS command pattern '$pattern' found. Use \`.../skills/do/scripts/vcs-op\` instead." >&2
      grep -n "$pattern" "$skill_file" 2>/dev/null
      violations=$((violations + 1))
    fi
  done
done

if [ "$violations" -gt 0 ]; then
  echo "Found $violations raw VCS command pattern(s) in skill files." >&2
  echo "Replace with \`.../skills/do/scripts/vcs-op <semantic-op>\` calls." >&2
  exit 1
fi

echo "No raw VCS commands found in skill files."
