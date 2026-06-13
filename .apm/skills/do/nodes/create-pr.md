---
name: create-pr
description: Open a draft PR on the configured forge (GitHub today).
---

# Create PR

## Requires

- `--no-vcs` flag
- `forgeCapabilities` from sync
- Primary feature commit pushed

## Ensures

- Draft PR exists
- hickey/lowy findings posted as PR comment

## Strategies

**If `!state.forgeCapabilities.prCreate`** (the forge can't open a PR — e.g. unknown, Gitea):
Skip with status `skipped` and reason:

- `"unsupported forge (no vcs-mcp toolkit recognition)"` when `state.forge = 'unknown`.
- `"non-<forge.kind> forge: <forge.kind>"` otherwise.

Proceed to **ci**. (Bitbucket `bkt pr edit` wiring is tracked in #10.)

**If `state.forgeCapabilities.prCreate`** (the forge can open a PR — GitHub today):

Check whether a PR already exists for this branch:

```
mcp__vcs__forge_pr_view
  number: <current PR number, if known>
```

If `mcp__vcs__forge_pr_view` errors with "not found" (the toolkit surfaces this as
`Error::InvalidInput` for missing PRs), there's no PR yet.

**If no PR exists** (first run, normal path):

1. Create a draft PR:

   ```
   mcp__vcs__forge_pr_create
     title: "<the title>"
     body: "<the body markdown>"
     source: "<current branch name>"
     target: "<default branch name>"
   ```

   **MANDATORY**: Load the `forge-pr` skill (via Skill tool) BEFORE writing the PR title/body.

2. **Post hickey/lowy results**: Post the hickey and lowy analysis as a PR comment:

   ```
   mcp__vcs__forge_pr_comment
     number: <the new PR number>
     body: "## [Hickey/Lowy](https://kolu.dev/blog/hickey-lowy/) Analysis\n\n<markdown>"
   ```

   **Format the comment with a leading findings ledger.** Compose a single table from both sub-agents' Actions sections:

   ```md
   ## [Hickey/Lowy](https://kolu.dev/blog/hickey-lowy/) Analysis

   | # | Lens   | Finding                                  | Disposition         |
   |---|--------|------------------------------------------|---------------------|
   | 1 | Hickey | viewportDimensions complects two roles   | Fixed in this PR    |
   | 2 | Lowy   | useViewport encapsulates ghost concern   | Fixed in this PR    |
   | 3 | Lowy   | clipboard.ts named after a consumer      | ⚠️ **No-op**        |

   ### Hickey rationale
   <prose>

   ### Lowy rationale
   <prose>
   ```

   The toolkit's `forge_pr_comment.body` parameter takes the markdown body as a
   string; the tool's `guard_argv_field` rejects `--`-prefixed bodies (the
   fork's second-line-of-defence argv guard). Empty body is a real value (passes
   through). The same No-op rendering rule from the design doc applies:
   **Render every No-op as `⚠️ **No-op**`** so the reviewer's eye lands on it.

**If PR already exists** (followup runs, `--from` entry points):

Re-check the PR title/body against current scope. If scope changed, update via:

```
mcp__vcs__forge_pr_edit
  number: <the PR number>
  title: "<new title, or omit to leave title alone>"
  body: "<new body, or omit to leave body alone>"
```

(At least one of `title` or `body` must be set per the toolkit's contract; the
facade rejects both-absent with `invalid_params` BEFORE any spawn.)

**Why this runs before `ci`**: The draft PR is the canonical home for CI status. Opening it before CI runs means CI
checks land directly on the PR, reviewers see the run history as it happens, and a failing run doesn't leave an orphaned
branch with red statuses and no PR to explain them.

**Verify**: `mcp__vcs__forge_pr_view` succeeds with the new PR's number; PR title/body matches the delivered scope;
hickey/lowy findings posted if any.
