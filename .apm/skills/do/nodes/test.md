---
name: test
description: Run relevant tests.
---

# Test

## Requires

- Implemented code
- Changes in current branch

## Ensures

- Tests pass
- New behavior is actually exercised

## Pattern

Instances [check-loop](../patterns/check-loop.md) with:

- `runner`: read `.agency/do.md` for `## Test command`, run relevant tests
- `fixer`: fix test failures
- Config: `max_attempts: 4`, `coverage_check: true`, `loop_artifacts: commit-per-fix`

## Strategies

Read `.agency/do.md` and look for a `## Test command` section. Run only the tests relevant to the code paths changed in
this PR.

Use `bash scripts/vcs-op diff-range <defaultBranch> --name-only` to identify changed files and determine which tests are
relevant.

If changes are purely internal with no user-facing impact, unit tests may suffice — skip e2e if no relevant scenarios
exist. If no test command is documented, skip with a note.

**Coverage gap check**: After the test command exits 0, confirm at least one of the tests run actually exercised the new
behavior (per the **implement** step's classification). A green run that didn't touch the changed code paths is a
coverage gap, not a pass. Refactor/docs/internal-cleanup diffs are exempt. If a gap is found, treat it as a real
failure: write the missing test, then loop through **fmt** → **commit** → **test**.

**Resolving coverage for black-box tests**: When the test command runs subprocess-style tests (e.g. bats) without
coverage instrumentation, resolve the coverage-gap check by **path intersection**: compare
`bash .../skills/do/scripts/vcs-op diff-names <defaultBranch>` (changed source files) against the test files' mirrored
paths. Test files live under `tests/` mirroring `.apm/` structure — a test at
`tests/unit/skills/do/scripts/do-results.bats` covers `.apm/skills/do/scripts/do-results`. If at least one test file
maps to a changed source file, the check is satisfied.

**Verify**: Tests pass (exit code 0) **and** the new behavior is covered, or the diff is exempt from the coverage check,
or no relevant tests to run.
**If failed** (max 4 attempts): Analyze the failure. If flaky, re-run. If real: fix → go to **fmt**, then retry.

## Delegation

```prose
let attempts_real = 0

loop:
  read .agency/do.md for "## Test command"
  if no command configured:
    return { verdict: "no-command-configured" }

  run tests relevant to changes (via bash scripts/vcs-op diff-range <defaultBranch> --name-only)
  if exit 0:
    if coverage_check:
      confirm new behavior is exercised via test logs
      if coverage gap:
        treat as real failure → write missing test → fmt → commit → continue
    return { verdict: "pass" }

  attempts_real += 1
  if attempts_real > 4:
    return { verdict: "failed-after-budget" }

  if flaky (passes on retry without fix):
    continue  # re-run without fixing

  fix the failure → fmt → commit
  continue  # re-run tests
```
