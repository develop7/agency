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

Create a NEW commit (never amend) with a conventional commit message for the primary implementation. The commit does not touch the git staging area — the toolkit's `mcp__vcs__repo_commit` is `git commit --only -- <paths>`, which commits the working-tree content directly.

```
mcp__vcs__repo_commit
  paths: ["."]
  message: "<conventional commit message>"
```

Then push the feature branch (the toolkit's `mcp__vcs__repo_push` is `git push -u origin <branch>` for the first push):

```
mcp__vcs__repo_push
  branch: "<feature branch name>"
```

This is the **primary feature commit**. Downstream **hickey-lowy** and **police** steps produce their own follow-up commits — one per finding or violation addressed — which keeps the PR history a readable progression of "what was built, then what was refined" rather than a single opaque squash.

**Verify**: `bash scripts/vcs-op log-head` (the read-side seam for the commit log) shows a new commit on the feature branch, and it's pushed to remote.
