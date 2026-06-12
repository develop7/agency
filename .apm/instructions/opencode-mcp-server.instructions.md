---
description: The project-root opencode.json declares the vcs-mcp MCP server (curated --allow-tools allowlist). Edit the file directly; the schema is the opencode host's own.
applyTo: "opencode.json"
---

## `opencode.json` — VCS / forge MCP server (hand-managed)

This repo declares the `vcs` MCP server (the `vcs-mcp` binary from
[`develop7/vcs-toolkit-rs`](https://github.com/develop7/vcs-toolkit-rs) branch
`staging-good_stuff`, fork of [`ZelAnton/vcs-toolkit-rs`](https://github.com/ZelAnton/vcs-toolkit-rs))
in `opencode.json` at the project root. The server replaces the in-repo
`scripts/vcs-op` bash dispatcher and the inline `gh` heredoc calls in the
`/do` skill — the agent drives VCS and forge operations through typed MCP
tools (`repo_*`, `forge_*`) instead of raw shell.

The `--allow-tools` allowlist is the load-bearing safety property: only the
eight operations the `/do` workflow actually uses are callable. The
`SKILL.md:531-536` "Never amend, rebase, or force-push" rule is enforced by
the seam, not by prompt-following. The `repo_checkout`,
`repo_create_worktree`, `repo_try_merge`, and the `repo.git()` / `repo.jj()`
escape hatches are not in the allowlist, so the agent cannot reach them.

**To edit:** modify `opencode.json` directly. There is no generator for this
file — it's hand-written and committed. The schema is the opencode host's
own (see `https://opencode.ai/docs/mcp-servers`); the `mcp` key is the
relevant one.

**To install the binary:** `nix run 'github:develop7/vcs-toolkit-rs/staging-good_stuff#vcs-mcp'`
runs the binary but doesn't leave it in a well-known directory on `$PATH`.
Point the opencode host at it via a `nix run`-style wrapper command
(see the `command` field's `nix` invocation below), or install via
`cargo install vcs-mcp --git https://github.com/develop7/vcs-toolkit-rs --branch staging-good_stuff`
once the upstream release lands and the binary is on `$PATH`.
