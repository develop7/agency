---
name: commit
kind: node
---

# commit

Create the primary feature commit and push the branch. One-shot.

## Requires

- `vcs_enabled` — caller flag
- `branch` — from sync (current) or branch (new feature branch)

## Ensures

- `primary_commit_rev` — revision id of the new commit (absent when `vcs_enabled` is `false`)
- (side effect) feature branch pushed to remote with `vcs push`

## Strategies

- **If `vcs_enabled` is `false`**: skip with `status="skipped"` and `reason="--no-vcs"`. Move to **hickey-lowy**. The working-tree changes stay uncommitted — that is the point.
- Otherwise: create a NEW commit (never amend) with a conventional commit message for the primary implementation. Push to the feature branch with `vcs push`.
- This is the **primary feature commit**. Downstream **hickey-lowy** and **police** nodes produce their own follow-up commits — one per finding or violation addressed — which keeps the PR history a readable progression of "what was built, then what was refined" rather than a single opaque squash.

## Receipt

```
.../skills/do/scripts/do-results step-start commit
# under vcs_enabled == false, immediately:
.../skills/do/scripts/do-results step-end skipped "no commit; working tree unchanged" "--no-vcs"
# otherwise, after committing + pushing:
.../skills/do/scripts/do-results step-end passed "primary commit <rev> pushed to origin/<branch>"
```

## Verify

- Under `vcs_enabled == false`: skipped, no VCS operations performed.
- Otherwise: `vcs commits-since-base` shows a new commit on the feature branch, and it's pushed to remote (verify via `vcs current-revision` matching the remote).

## Errors

- `push_failed` — halt workflow. The branch is local-only and the rest of the workflow assumes it's pushed.
