---
name: sync
description: Fetch origin, populate forge identity + capability map, initialize workflow state.
---

# Sync

## Requires

- `--no-vcs` flag (parsed by `do-driver init`)

## Ensures

- `forge` — `github` | `gitlab` | `gitea` | `unknown` (forge identity, for diagnostic/display)
- `forgeCapabilities` — flat capability map from `mcp__vcs__forge_info`:
  `{ prCreate, prComment, prEdit, prChecks, prMerge, issueCreate, authed }` (each `Bool`)
- `branch` — current branch name
- `defaultBranch` — origin HEAD ref name

## Strategies

The sync step has two parts: the **agent** calls the `mcp__vcs__forge_info` MCP tool, then
invokes the **bash script** with the JSON result. The script cannot call MCP tools itself
(bash has no MCP client), so the agent is the bridge.

### 1. Call the MCP tool

```
mcp__vcs__forge_info
```

The tool returns a JSON object of shape:

```json
{
  "kind": "github",
  "capabilities": {
    "prCreate": true,
    "prComment": true,
    "prEdit": true,
    "prChecks": true,
    "prMerge": true,
    "issueCreate": true,
    "authed": true
  }
}
```

`kind` is one of `"github" | "gitlab" | "gitea" | "unknown"`. The `capabilities` are the
intersection of "the CLI ships this command" and "the CLI is authenticated" — a `true`
value means the workflow can call the matching `forge_*` MCP tool.

### 2. Run the sync script with the JSON

```
bash .../skills/do/scripts/steps/sync <noVcs> --forge-info '<the JSON from step 1>'
```

The script:

- Detects the VCS (`.jj/` → `jj`, `.git/` → `git`, else `unknown`) via `mcp__vcs__repo_info` (the tool returns `{backend, root, cwd, forge}` — read `backend` for git/jj).
- Fetches the default remote (`git fetch origin` / `jj git fetch`).
- Pins `origin/HEAD` (git only).
- If `--no-vcs` is **not** set and the branch is behind origin (ahead-count 0), fast-forwards
  with `git pull --ff-only`. Under `--no-vcs`, fetch happens but the working tree is not touched —
  uncommitted work is preserved.
- Prints the dirty-tree hint to stderr (no pause) when the tree is dirty and `--no-vcs` is not set:

  > _Dirty tree detected. Continuing will create a fresh branch on top of these changes. If
  > you wanted the agent to extend your WIP in place without touching git, re-run with
  > `--no-vcs`._
- Parses the `--forge-info` JSON to extract `kind` (forge identity) and `capabilities` (the
  capability map). Writes both into `.do-results.json` via `do-results set`.
- Prints `vcs=`, `forge=`, `forgeCapabilities=<json>`, `branch=`, `defaultBranch=` on stdout
  for downstream steps.

**Why the agent calls the MCP tool, not bash:** the bash script has no MCP client
in-process. The agent harness (Claude Code, opencode, Codex) is the runtime that
speaks stdio JSON-RPC; the bash script is a state-writer that takes the agent's
result as a CLI arg.

**Why the workflow reasons about capabilities, not the kind string:** the
`create-pr` skip predicate is `state.noVcs || !state.forgeCapabilities.prCreate`,
not `state.forge != 'github'`. The capability is the load-bearing field; the
identity is for display. A future forge (Bitbucket, etc.) is wired in by adding
its capabilities to the static map in the vcs-forge facade — the workflow
doesn't change.

**Verify**: Script exited 0 and printed `vcs=`, `forge=`, `forgeCapabilities=`,
`branch=`, `defaultBranch=` lines on stdout. (Sync silences `do-results`' own
confirmation echoes so the protocol stays clean.)
