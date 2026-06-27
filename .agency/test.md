# Test configuration

## Coverage gap resolution for black-box tests

This repo's tests run as subprocess-style black-box tests (bats) without coverage
instrumentation. Resolve the coverage-gap check from the `/do` test node by **path
intersection**: compare `bash .../skills/do/scripts/vcs-op diff-names <defaultBranch>`
(changed source files) against the test files' mirrored paths.

Test files live under `tests/` mirroring `.apm/` structure — a test at
`tests/unit/skills/do/scripts/do-results.bats` covers `.apm/skills/do/scripts/do-results`.
If at least one test file maps to a changed source file, the check is satisfied.
