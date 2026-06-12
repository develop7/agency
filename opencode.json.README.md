# `opencode.json`

This file declares the `vcs` MCP server for the opencode host. It is
**hand-managed** (no `apm install` step produces it) and is the canonical
project-level config for VCS/forge operations.

## Fields

- `mcp.vcs.type = "local"` — the vcs-mcp binary is a local stdio server.
- `mcp.vcs.command` — the argv the host spawns. Currently a `nix run` wrapper
  that fetches and builds the binary at a pinned ref; can be simplified to
  a bare `vcs-mcp` argv once the binary is on `$PATH` (e.g. via
  `cargo install`).
- `mcp.vcs.command[5]` — the `--allow-tools` comma-separated list. See
  **Allowlist source of truth** below.
- `mcp.vcs.cwd = "."` — server's working directory; relative to the host's
  CWD, which the opencode host sets to the project root.
- `mcp.vcs.enabled = true` — operator override to disable the server
  without removing the entry.

## Allowlist source of truth

The `--allow-tools` line names the operations the agent may call. The
**source of truth** for which operations the workflow needs is the
`mcp__vcs__*` call sites in the post-migration skill markdown:

- `.apm/skills/do/SKILL.md`
- `.apm/skills/do/nodes/*.md`
- `.apm/skills/forge-pr/SKILL.md`
- (any other skill that calls a `mcp__vcs__*` tool)

When a future commit adds a `mcp__vcs__<tool>` call to a skill, the
matching tool name must also be added to the `--allow-tools` list in
`opencode.json`. **Drift between call sites and allowlist is a safety
violation** — a missing allowlist entry causes the call to fail; an
unintended entry re-exposes a tool the workflow doesn't audit.

The agent instructions rule at
`.apm/instructions/apm-sources.instructions.md` (the section titled
"`opencode.json` — VCS / forge MCP server (hand-managed)") carries the
same rule for agent-facing readers.

## Schema

The file conforms to the opencode host's MCP config schema
(`https://opencode.ai/docs/mcp-servers`). The top-level `mcp` key is the
host's. There is no per-project schema validation in CI; the host parses
the file at startup and reports errors there.
