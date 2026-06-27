apm_cmd := "uvx --from 'git+https://github.com/microsoft/apm' apm"
repo := justfile_directory()

mod website "website/mod.just"

# Install apm dependencies and regenerate .claude/ from .apm/ sources
apm:
    {{ apm_cmd }} install

# Run apm security audit
apm-audit:
    {{ apm_cmd }} audit

# Verify .claude/ stays in sync with .apm/ sources
apm-sync: apm apm-audit
    @if ! git diff --quiet; then \
        echo "ERROR: working tree has uncommitted changes after apm install"; \
        git diff --stat; \
        exit 1; \
    fi

# Run all bats tests (unit + integration)
test:
    REPO_ROOT={{ repo }} bats -r tests/

# Run unit tests only (black-box, no VCS fixtures)
test-unit:
    REPO_ROOT={{ repo }} bats -r tests/unit/

# Run integration tests (real git fixtures)
test-integration:
    REPO_ROOT={{ repo }} bats -r tests/integration/

# Run shellcheck on all .apm/ bash scripts
# SC2148/SC1113/SC2096: scripts are intentionally shebang-less (run via `bash script`)
lint:
    find .apm/scripts .apm/hooks/scripts .apm/skills/do/scripts \
        -type f ! -name '*.ncl' \
        -exec shellcheck --shell=bash --exclude=SC2148,SC1113,SC2096 {} +

# Full CI: tests + lint
ci: test lint
