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

Create a NEW commit (never amend) with a conventional commit message for the primary implementation, then push:

```
bash .../skills/do/scripts/vcs-op commit "<message>"
bash .../skills/do/scripts/vcs-op push <branch>
```

Git: `git add -A` + `git commit -m "..."`. Jujutsu: auto-snapshots the working copy, `jj describe -m "..."`, then `jj new` to start a fresh change. `vcs-op commit` walks the parent chain to find the bookmark and moves it to `@-` so the subsequent `vcs-op push <bookmark>` lands on the new commit; `vcs-op push` sets upstream on first push (git).

**Jujutsu gotcha: `jj new` moves `@` to a new empty change; `jj new --no-edit` does NOT.** If you need to start a new change (e.g. followup work on top of existing WIP before calling `vcs-op commit`), use bare `jj new`. `--no-edit` creates a new change but keeps editing the current one — almost never what the workflow wants; using it by accident means subsequent edits land in the existing change, not the new one, and the workflow has no place to put the new work.

This is the **primary feature commit**. Downstream **hickey-lowy** and **police** steps produce their own follow-up commits — one per finding or violation addressed — which keeps the PR history a readable progression of "what was built, then what was refined" rather than a single opaque squash.

**Verify**: `bash scripts/vcs-op log-head` shows a new commit on the feature branch, and it's pushed to remote.
