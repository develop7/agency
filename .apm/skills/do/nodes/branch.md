---
name: branch
description: Create a descriptive feature branch from origin/defaultBranch.
---

# Branch

## Requires

- `--no-vcs` flag
- `defaultBranch` from sync

## Ensures

- Feature branch checked out

## Strategies

Read `vcs` and `defaultBranch` from `.do-results.json`. Then:

```
bash .../skills/do/scripts/vcs-op branch <descriptive-name> <defaultBranch>
```

The script handles the VCS-specific details: git creates `git branch <name> origin/<default>`; jj creates `jj new <default>` followed by `jj bookmark create <name> -r @`.

That's it — just the local branch. No commit, no push, no PR. The branch is pushed later in **commit**, and the PR is created in **create-pr** after all changes are done.

**Verify**: `bash scripts/vcs-op head-revision` returns the new branch name (not master/main).
