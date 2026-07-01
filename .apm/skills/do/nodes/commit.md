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
bash .../skills/do/scripts/vcs-op commit "<message>" <file1> <file2> ...
bash .../skills/do/scripts/vcs-op push <branch>
```

**Pass the files that belong to this feature** — the files you changed during **implement**. The script stages only those files (git: explicit `git add <files>`) or splits unrelated working-copy changes into a separate revision above the feature commit (jj: `jj split` + `jj rebase`), so the commit contains only the feature changes. Unrelated changes are preserved, not discarded.

Git: `git add -- <files>` + `git commit -m "..."`. Jujutsu: `jj describe -m "..."`, then if there are unrelated files in the working copy: `jj split <unrelated> -m "chore: unrelated changes"`, `jj rebase -r @- -A @` (move the unrelated revision above the feature commit), move the bookmark to `@` (the feature commit), `jj new <bookmark>` (create a fresh `@` on top of the feature). If there are no unrelated files, degenerates to `jj describe && jj new` + bookmark move. `vcs-op push` sets upstream on first push (git).

**Jujutsu gotcha: `jj new` moves `@` to a new empty change; `jj new --no-edit` does NOT.** If you need to start a new change (e.g. followup work on top of existing WIP before calling `vcs-op commit`), use bare `jj new`. `--no-edit` creates a new change but keeps editing the current one — almost never what the workflow wants; using it by accident means subsequent edits land in the existing change, not the new one, and the workflow has no place to put the new work.

This is the **primary feature commit**. Downstream **hickey-lowy** and **police** steps produce their own follow-up commits — one per finding or violation addressed — which keeps the PR history a readable progression of "what was built, then what was refined" rather than a single opaque squash.

**Verify**: `bash scripts/vcs-op log-head` shows a new commit on the feature branch, and it's pushed to remote.
