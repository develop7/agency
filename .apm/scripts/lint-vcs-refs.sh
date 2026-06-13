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
SKILLS_DIR="$APM_DIR/skills"

# Patterns that look like executable instructions to an LLM agent
# (backtick-wrapped commands, or standalone command instructions).
#
# Two groups:
#   * VCS patterns (raw git/jj) — predate the vcs-mcp migration. The
#     canonical read-side seam is `scripts/vcs-op` (the toolkit's
#     vcs-mcp 0.2.0 doesn't model diff-range, diff-names, log-range,
#     log-head, new-files, default-branch, remote-url, head-revision,
#     head-commit-sha — the workflow's review-pass queries). vcs-op
#     also handles the branch-creation op (the toolkit's
#     repo_create_worktree doesn't fit the workflow's "stay in the
#     same working copy" model). Both groups are called via
#     `bash scripts/vcs-op <op>` and are NOT flagged here.
#   * Forge patterns (raw gh/glab/tea) — added in the vcs-mcp
#     migration. The canonical seam is `mcp__vcs__forge_*` tool
#     calls (mcp__vcs__forge_pr_create, mcp__vcs__forge_pr_comment,
#     mcp__vcs__forge_pr_edit). Raw `gh pr create` / `gh pr comment` /
#     `gh pr edit` invocations belong to the migration. `gh release
#     create`, `gh workflow run`, and `gh api` for release-asset
#     upload (used in the example `.agency/do.md` at README.md:124)
#     stay in the allow list — the toolkit doesn't model those
#     operations.
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
  # Forge patterns — raw gh/glab/tea invocations the workflow uses today.
  # The migration replaces these with `mcp__vcs__forge_*` tool calls.
  'gh pr create'
  'gh pr edit'
  'gh pr comment'
  'gh pr view'
  'gh pr merge'
  'gh pr close'
  'glab mr '
  'tea pr create'
  'tea comment'
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

check_file() {
  local file="$1"
  local pattern="$2"

  # Non-strict skips: allow git/jj references in these files where they
  # appear as documented fallback examples, not as executable instructions.
  if [ "$strict" = false ]; then
    case "$file" in
      */do/SKILL.md)        return ;;
      */talk/SKILL.md)      return ;;
    esac
  fi

  if grep -n "$pattern" "$file" 2>/dev/null; then
    violations=$((violations + 1))
  fi
}

for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  for pattern in "${PATTERNS[@]}"; do
    if grep -q "$pattern" "$skill_file" 2>/dev/null; then
      echo "::error file=$skill_file::Raw VCS command pattern '$pattern' found. Use \`.../skills/do/scripts/vcs-op\` instead." >&2
      check_file "$skill_file" "$pattern"
    fi
  done
done

# ── Allowlist drift check ─────────────────────────────────────────────────────
# The `opencode.json` `--allow-tools` allowlist is the runtime gate for MCP
# tool calls. The workflow's skill markdown references MCP tools by name (e.g.
# `mcp__vcs__repo_commit`, `mcp__vcs__forge_pr_view`). When a tool is referenced
# in the prose but is NOT in the allowlist, the agent's call fails at runtime
# — a documented safety violation (see
# `.apm/instructions/apm-sources.instructions.md:30-44`). This check greps the
# prose for `mcp__vcs__<tool>` references, extracts the tool name, and verifies
# each is in the allowlist.

if [ -f "$APM_DIR/../opencode.json" ]; then
  allowlist_tools="$(grep -oE -- '(repo|forge)_[a-z_]+' "$APM_DIR/../opencode.json" | sort -u)"
  for skill_file in "$SKILLS_DIR"/*/SKILL.md "$SKILLS_DIR"/*/nodes/*.md; do
    [ -f "$skill_file" ] || continue
    # Non-strict skips for files that document tools without calling them.
    case "$skill_file" in
      */do/SKILL.md)        continue ;;  # orchestrates; tool refs are descriptive
      */talk/SKILL.md)      continue ;;
      */apm-sources.instructions.md) continue ;;  # documents the rule
      */opencode-mcp-server*)    continue ;;  # documents the seam
    esac
    # Find every `mcp__vcs__<tool>` reference; check the tool name is in the allowlist.
    # `|| true` guards against `set -euo pipefail` exiting when grep finds nothing
    # (which it doesn't for files like code-police/SKILL.md that never reference MCP tools).
    referenced_tools="$(grep -oE 'mcp__vcs__(repo|forge)_[a-z_]+' "$skill_file" 2>/dev/null | sed 's|^mcp__vcs__||' | sort -u || true)"
    [ -z "$referenced_tools" ] && continue
    for tool in $referenced_tools; do
      if ! printf '%s\n' "$allowlist_tools" | grep -qxF "$tool"; then
        echo "::error file=$skill_file::MCP tool \`mcp__vcs__$tool\` referenced but not in opencode.json --allow-tools. Drift between call sites and allowlist is a safety violation — add '$tool' to the --allow-tools list, or remove the prose reference." >&2
        violations=$((violations + 1))
      fi
    done
  done
fi

if [ "$violations" -gt 0 ]; then
  echo "Found $violations raw VCS/forge command pattern(s) in skill files." >&2
  echo "Replace with \`.../skills/do/scripts/vcs-op <semantic-op>\` or \`mcp__vcs__forge_*\` calls." >&2
  exit 1
fi

echo "No raw VCS commands found in skill files."
