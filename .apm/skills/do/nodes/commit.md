---
name: commit
description: Create the primary feature commit and push.
---

# Commit

## Requires

- `--no-vcs` flag
- Formatted code

## Ensures

- Primary feature commit on feature branch
- Branch pushed to remote

## Strategies

Create a NEW commit (never amend) with a conventional commit message for the primary implementation. This node uses
the **sweep** commit policy — it discovers the paths to commit from the working tree (it has no record of which files
the feature touched; implement/fmt/docs ran in earlier nodes).

Follow the **sweep commit recipe** in `SKILL.md` §commit (canonical, 6 steps: `repo_status` → curate-with-renames →
exclude → empty-check → `repo_commit`+`repo_push` → under-commit guard). **Re-read the canonical each run; do not
execute from this summary** — the rename projection (`Renamed → [old_path, new_path]`) and exclude-matching rules are
load-bearing and live only there.

The commit does not touch the git staging area — the toolkit's `mcp__vcs__repo_commit` is `git commit --only -- <paths>`
(git) / `jj commit <filesets>` (jj), committing the named paths directly.

**Verify**: `bash scripts/vcs-op log-head` shows a new commit on the feature branch, pushed to remote; **or** the
recipe reported `empty-after-exclude`.
