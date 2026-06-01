---
name: sync
description: Fetch origin, detect forge, initialize workflow state.
---

# Sync

## Requires

- `--no-vcs` flag (parsed by `do-driver init`)

## Ensures

- `forge` — `github`, `bitbucket`, or `unknown`
- `branch` — current branch name
- `defaultBranch` — origin HEAD ref name

## Strategies

Run the `scripts/steps/sync` script in this skill's directory, passing `true` or `false` for `--no-vcs`:

```
.../skills/do/scripts/steps/sync <noGit>
```

The script:

- Fetches `origin` and pins `origin/HEAD`
- If `--no-vcs` is **not** set and the branch is behind origin (ahead-count 0), fast-forwards with `git pull --ff-only`. Under `--no-vcs`, fetching happens but the working tree is not touched — uncommitted work is preserved.
- Prints the dirty-tree hint to stderr (no pause) when the tree is dirty and `--no-vcs` is not set:

  > _Dirty tree detected. Continuing will create a fresh branch on top of these changes. If you wanted the agent to extend your WIP in place without touching git, re-run with `--no-vcs`._

- Classifies the forge from `scripts/vcs-op remote-url` — `github.com` → `github`, `bitbucket.` (covers `bitbucket.org` and self-hosted servers like `bitbucket.juspay.net`) → `bitbucket`, otherwise `unknown`.
- Calls `scripts/do-results init <forge> <noGit>` then `scripts/do-results step sync passed ...`.
- Prints `forge=<value>`, `branch=<value>`, `defaultBranch=<value>` on stdout for downstream steps.

**Only `github` has an active code path today.** Both `bitbucket` and `unknown` cause forge-dependent steps (PR creation, PR comments, PR edits, CI status) to skip gracefully. Bitbucket support is planned — see [srid/agency#10](https://github.com/srid/agency/issues/10).

**Verify**: Script exited 0 and printed `forge=`, `branch=`, `defaultBranch=` lines on stdout. (Sync silences `do-results`' own confirmation echoes so the protocol stays clean.)
