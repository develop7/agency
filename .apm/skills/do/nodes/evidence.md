---
name: evidence
description: Attach empirical evidence to the PR (opt-in).
---

# Evidence

## Requires

- `--minimal` flag
- `--no-vcs` flag
- `forgeCapabilities` from sync
- CI passed

## Ensures

- Evidence posted as PR comment (if configured)

## Strategies

Read `.agency/do.md` and look for a `## PR evidence` section. If missing or empty, skip with status `skipped` and reason `"no PR evidence section in .agency/do.md"`.

**If `!state.forgeCapabilities.prComment` (the forge can't post PR comments)**: Skip
with status `skipped` and reason:

- `"unsupported forge (no vcs-mcp toolkit recognition)"` when `state.forge = 'unknown`.
- `"non-<forge.kind> forge: <forge.kind>"` otherwise.

(Bitbucket comment wiring is tracked in #10.)

**If the section is present and the forge supports PR comments**:

The section is project-specific and free-form: inline prose, pointer to another file, script reference, or any combination. Read it, then **spawn a sub-agent** (`Agent`/`task` with `subagent_type: "general-purpose"`) so the capture work doesn't pollute `/do`'s main context.

The sub-agent prompt should include:

- The literal section content from `.agency/do.md`.
- Standard PR context: PR URL, branch name, base branch, current commit SHA, and `bash scripts/vcs-op diff-range <defaultBranch> --name-only` (read-side seam — the toolkit's `repo_diff_range` is a real gap that vcs-op still covers).
- An explicit instruction that the sub-agent's job is to return a single block of markdown suitable for posting under a `## Evidence` heading.

After the sub-agent returns, post its output as one PR comment using:

```
mcp__vcs__forge_pr_comment
  number: <the PR number>
  body: "## Evidence\n\n<markdown>"
```

The toolkit's `guard_argv_field` rejects `--`-prefixed bodies; backticks and
`$` survive unescaped in the body string. Embed image/asset URLs inline in
the markdown — `mcp__vcs__forge_pr_comment` cannot attach files.

**Verify**: Either the step was skipped per the rules above, or a `## Evidence` PR comment exists (verifiable via `mcp__vcs__forge_pr_view` with the PR number, then inspecting the response's comment list).
