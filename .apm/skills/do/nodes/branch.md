---
name: branch
kind: node
---

# branch

Create a descriptive feature branch from the default trunk.

## Requires

- `vcs_enabled` — caller flag
- `trunk` — from sync
- `vcs_backend` — from sync

## Ensures

- `branch` — overwrites the binding sync set; downstream nodes read the new feature-branch name

## Strategies

- **If `vcs_enabled` is `false`**: skip entirely with `status="skipped"` and `reason="--no-vcs"`. Stay on the current branch — do not create, commit, or push anything. Move to **implement**.
- Otherwise: create a descriptive feature branch from the default trunk using the VCS script: `vcs create-branch <name>`.
- That's it — just the local branch/bookmark. No commit, no push, no PR. The branch is pushed later in **commit**, and the PR is created in **create-pr** after all changes are done.

## Receipt

```
.../skills/do/scripts/do-results step-start branch
# under vcs_enabled == false, immediately:
.../skills/do/scripts/do-results step-end skipped "stayed on current branch" "--no-vcs"
# otherwise, after creating:
.../skills/do/scripts/do-results step-end passed "on feature branch <name>"
```

## Verify

On a feature branch (not master/main). Under `--no-vcs`, on whatever branch the user started on (verify via `vcs current-branch` ≠ `trunk`, **only** when not skipped).
