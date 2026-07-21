apm_cmd := "uvx --from 'git+https://github.com/microsoft/apm' apm"
repo := justfile_directory()

# Wrap recipes in `nix develop` when not already inside a nix shell, so
# `just test` works identically inside and outside `nix develop`. Same
# idiom as website/mod.just (just's module system can't share `:=`
# variables across modules, so the one-liner is duplicated).
# --accept-flake-config: the root flake is untrusted on first run; carrying
# this flag here means CI jobs and local runs can't forget it.
nix_shell := if env('IN_NIX_SHELL', '') != '' { '' } else { 'nix develop ' + repo + ' --accept-flake-config -c' }

mod website "website/mod.just"

# Fail loud if a tool the recipes need is missing from the devShell.
# Converts silent test-skips (e.g. jj not on PATH → 22 jj tests skip)
# into a CI failure. Wired as a prerequisite of every tool-using recipe
# so CI's `just test` / `just lint` / `just apm-sync` all run it first.
# Binary→package map and rationale live in flake.nix's devShell — keep
# both lists aligned.
check-env:
    {{ nix_shell }} bash -c 'for t in bats jq jj nickel shellcheck just uv uvx; do command -v "$t" >/dev/null || { echo "missing from devShell: $t" >&2; exit 1; }; done'

# Install apm dependencies and regenerate .claude/ from .apm/ sources
apm: check-env
    {{ nix_shell }} {{ apm_cmd }} install

# Run apm security audit
apm-audit: check-env
    {{ nix_shell }} {{ apm_cmd }} audit

# Verify .claude/ stays in sync with .apm/ sources
apm-sync: apm apm-audit
    @if ! git diff --quiet; then \
        echo "ERROR: working tree has uncommitted changes after apm install"; \
        git diff --stat; \
        exit 1; \
    fi

# Run all bats tests (unit + integration)
test: check-env
    REPO_ROOT={{ repo }} {{ nix_shell }} bats -r tests/

# Run unit tests only (black-box, no VCS fixtures)
test-unit: check-env
    REPO_ROOT={{ repo }} {{ nix_shell }} bats -r tests/unit/

# Run integration tests (real git fixtures)
test-integration: check-env
    REPO_ROOT={{ repo }} {{ nix_shell }} bats -r tests/integration/

# Run shellcheck on all .apm/ bash scripts
# SC2148/SC1113/SC2096: scripts are intentionally shebang-less (run via `bash script`)
# SC1091: scripts source lib/state.sh via a runtime $SCRIPT_DIR path shellcheck can't follow statically
lint: check-env
    {{ nix_shell }} find .apm/scripts .apm/hooks/scripts .apm/skills/do/scripts tests/helpers \
        -type f ! -name '*.ncl' \
        -exec shellcheck --shell=bash --exclude=SC2148,SC1113,SC2096,SC1091 {} +

# Full CI: tests + lint (check-env runs as a prerequisite of test/lint)
ci: test lint