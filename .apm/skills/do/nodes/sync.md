---
name: sync
kind: node
---

# sync

Fetch origin, classify the forge, fast-forward (unless `--no-vcs`), detect VCS backend, and stash coordination state.

## Requires

- `vcs_enabled` — caller flag (default `true`)

## Ensures

- `forge`: `github` | `bitbucket` | `unknown`
- `branch`: current branch/bookmark name
- `trunk`: e.g. `master` or `main`
- `vcs_backend`: `git` | `jj`
- (side effect) origin fetched; if `vcs_enabled` and behind, fast-forwarded

## Strategies

- The `scripts/steps/sync` script encapsulates fetching, fast-forwarding, dirty-tree hinting, VCS backend detection, forge classification, and the do-results init+sync record. Don't reimplement; just invoke.
- Under `vcs_enabled == false`: fetch happens but the working tree is never touched.
- When the tree is dirty and `vcs_enabled` is `true` (git only; jj snapshots everything automatically): print a hint to stderr (no pause) suggesting `--no-vcs`; continue regardless. The hint:

  > _Dirty tree detected. Continuing will create a fresh branch on top of these changes. If you wanted the agent to extend your WIP in place without touching VCS, re-run with `--no-vcs`._

- Forge classification reads the origin remote URL via `vcs remote-url`:
  - `github.com` → `github`
  - `bitbucket.` (covers `bitbucket.org` and self-hosted servers like `bitbucket.juspay.net`) → `bitbucket`
  - otherwise → `unknown`

  Only `github` has an active PR/CI integration code path today. Bitbucket and unknown cause forge-dependent nodes (`branch`, `commit`, `create-pr`, `ci`, `evidence`) to skip gracefully. Bitbucket support is tracked in [srid/agency#10](https://github.com/srid/agency/issues/10).

## Receipt

**Special case.** The `scripts/steps/sync` script handles its own bookend internally — it calls `do-results init` then `do-results step sync passed ...`. The agent does **not** call `step-start sync` / `step-end sync` itself for this node.

After the script returns, the agent reads `forge=`, `branch=`, `trunk=`, `vcs_backend=` from stdout and re-stashes them via `do-results set forge ...`, `set vcs_enabled ...`, `set vcs_backend ...`, `set branch ...`, `set trunk ...` so downstream nodes can read them as bindings.

## Invocation

```
.../skills/do/scripts/steps/sync <vcs_enabled>
```

(Pass `true` or `false` for `<vcs_enabled>`.)

## Verify

Script exited 0 and printed four lines on stdout: `forge=<value>`, `branch=<value>`, `trunk=<value>`, `vcs_backend=<value>`. Sync silences `do-results`' own confirmation echoes so the protocol stays clean.

## Errors

- `script_exit_nonzero` — the sync script failed (network, VCS error, malformed remote URL). Halt the workflow with `do-results set status failed`. Do not proceed to research; coordination state is required.
