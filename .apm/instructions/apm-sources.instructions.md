---
description: "Pointers to where the project's VCS/forge and agent-config seams live. Two rules: (1) edit .apm/ sources, not generated dirs; (2) edit opencode.json directly — it's hand-managed, not generated."
applyTo: ".agents/**,.claude/**,.opencode/**,opencode.json"
---

## Generated Files — Do Not Edit Directly

> **This rule only applies if an `.apm/` directory exists somewhere in the project.** If there is no `.apm/` directory at any level, `.claude/` and `.opencode/` files are vendored directly and can be edited in place. To locate it, search for a directory matching `**/.apm/` from the project root.

Everything under `.agents/` (opencode skills), `.claude/`, and `.opencode/` is **generated** from `.apm/` sources by APM. Direct edits will be overwritten on the next `apm install` run. **Edit the matching source under `.apm/` instead** — these directories are deploy artifacts, not sources of truth.

To modify agent configuration, find the `.apm/` directory (it may be at the project root or nested under a subdirectory such as `agents/.apm/`), edit the source files there, then run `apm install` to regenerate.

**For Codex / opencode targets, also run `apm compile -t codex,opencode`** (or whichever subset applies) — `install` regenerates the runtime folders but does not produce the project-root `AGENTS.md` that those hosts read. Claude reads `.claude/` natively, so no compile step is needed when `claude` is the only target.

## `opencode.json` — VCS / forge MCP server (hand-managed)

This repo declares the `vcs` MCP server (the `vcs-mcp` binary from
[`develop7/vcs-toolkit-rs`](https://github.com/develop7/vcs-toolkit-rs) branch
`staging-good_stuff`, fork of [`ZelAnton/vcs-toolkit-rs`](https://github.com/ZelAnton/vcs-toolkit-rs))
in `opencode.json` at the project root. The server replaces the in-repo
`scripts/vcs-op` bash dispatcher and the inline `gh` heredoc calls in the
`/do` skill — the agent drives VCS and forge operations through typed MCP
tools (`repo_*`, `forge_*`) instead of raw shell.

`opencode.json` is **hand-managed**, not generated. There is no `apm install`
step that produces it. To change the binary path, the allowlist, the
`enabled` toggle, or any other field, edit the file directly.

### The `--allow-tools` allowlist — source of truth is the workflow, not this file

The `--allow-tools` line names the operations the agent may call. The
**source of truth** for which operations the workflow needs is the
`mcp__vcs__*` call sites in the post-migration skill markdown:
- `.apm/skills/do/SKILL.md`
- `.apm/skills/do/nodes/*.md`
- `.apm/skills/forge-pr/SKILL.md`
- (any other skill that calls a `mcp__vcs__*` tool)

When a future commit adds a `mcp__vcs__<tool>` call to a skill, the
matching tool name must also be added to the `opencode.json` `--allow-tools`
comma-separated list. **Drift between call sites and allowlist is a safety
violation** — a missing allowlist entry causes the call to fail; an
unintended entry re-exposes a tool the workflow doesn't audit.

(Stage B of the vcs-mcp migration will replace this manual sync with a
derivation step: a Nickel query over the skill markdowns emits the
allowlist into a generated record, so the allowlist becomes a derived
view. Until then, the human-sync rule above is the source of truth.)

### Install methods

The `command` array in `opencode.json` uses `nix run` to fetch and run the
vcs-mcp binary at the pinned fork ref. Alternatives, in case nix is not
available on the host:

- `cargo install vcs-mcp --git https://github.com/develop7/vcs-toolkit-rs --branch staging-good_stuff` — installs the binary to `~/.cargo/bin/`, which is on `$PATH` by default. Once the binary is on `$PATH`, the `command` array in `opencode.json` can be simplified to `["vcs-mcp", "--allow-tools", "..."]`.

(Both methods run the same binary; `nix run` does not leave it on `$PATH`,
so it's a per-invocation fetch. The cargo path leaves a persistent
binary, which is preferable for hosts that re-spawn the MCP server
frequently.)
