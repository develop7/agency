# Shared VCS-fixture helpers for integration tests (git + jj).
# Loaded via:  load "$REPO_ROOT/tests/helpers/vcs-fixtures.bash"
# Requires setup_test_dir to have run first (uses $TEST_DIR).

# ── git ────────────────────────────────────────────────────────────────

# Create an initial commit with a tracked file in the current git repo.
# Assumes git config (user.email, user.name) is already set.
mk_initial_commit() {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"
}

# Create a bare remote at $TEST_DIR/remote.git, point origin at it,
# push the current branch, and pin origin/HEAD.
mk_remote_fixture() {
  git init -q --bare "$TEST_DIR/remote.git"
  git remote set-url origin "$TEST_DIR/remote.git"
  git push -q origin master 2>/dev/null
  git remote set-head origin -a 2>/dev/null
}

# ── jj ─────────────────────────────────────────────────────────────────
# jj tests skip via per-test `command -v jj || skip` — these helpers are
# only called from inside non-skipped jj tests, so they can assume jj is
# on PATH and a jj repo has been initialized (`jj git init`).

# Create a base change with a bookmark in the current jj repo.
# Run after `jj git init`. Parameterized by bookmark name (default: main).
# Leaves @ on the base change with the bookmark pointing at it, and writes
# a `.do-results.json` with `base` set so vcs-op ops that read base work.
mk_jj_base_change() {
  local bookmark="${1:-main}"
  echo "hello" > README.md
  jj describe -m "base"
  jj bookmark create "$bookmark" -r @
  echo "{\"base\":\"$bookmark\"}" > .do-results.json
}

# Create a bare remote at $TEST_DIR/remote.git, point origin at it, and
# push the named bookmark. jj has no origin/HEAD concept, so no head-pinning.
mk_jj_remote_fixture() {
  local bookmark="${1:-main}"
  git init -q --bare "$TEST_DIR/remote.git"
  jj git remote add origin "$TEST_DIR/remote.git" 2>/dev/null || \
    jj git remote set-url origin "$TEST_DIR/remote.git"
  jj git push --bookmark "$bookmark" 2>/dev/null
}