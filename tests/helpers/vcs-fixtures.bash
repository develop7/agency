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
# jj tests skip via per-test `command -v jj || skip`. The helpers below
# fold that guard in so callers don't repeat it 27× — bats `skip` exits
# the process, so a skip inside a helper is safe.

# Initialize a jj repo (colocated by default) and skip the test if jj
# isn't available. Leaves @ as an empty working change. Use when a test
# needs a jj repo but no base change/bookmark yet (e.g. base-absent
# error paths, remote-url before any commit).
mk_jj_repo() {
  command -v jj >/dev/null || skip "jj not installed"
  jj git init 2>/dev/null || skip "jj git init failed"
}

# Create a base change with a bookmark in the current jj repo. Calls
# mk_jj_repo first (so callers don't repeat the guard), then describes @,
# creates the bookmark, and leaves @ on the base change. Parameterized
# by bookmark name (default: main) and commit message (default: base).
mk_jj_base_change() {
  local bookmark="${1:-main}" msg="${2:-base}"
  mk_jj_repo
  echo "hello" > README.md
  jj describe -m "$msg"
  jj bookmark create "$bookmark" -r @
}

# Create a bare remote at $TEST_DIR/remote.git, point origin at it, and
# push the named bookmark. jj has no origin/HEAD concept, so no head-pinning.
# The `add || set-url` fallback handles the case where jj inherited origin
# from an existing git repo (colocated init).
mk_jj_remote_fixture() {
  local bookmark="${1:-main}"
  git init -q --bare "$TEST_DIR/remote.git"
  jj git remote add origin "$TEST_DIR/remote.git" 2>/dev/null || \
    jj git remote set-url origin "$TEST_DIR/remote.git"
  jj git push --bookmark "$bookmark" 2>/dev/null
}

# ── state seeding (sole writer of test .do-results.json base field) ────

# Write `.do-results.json` with the given base value. The single source
# of the test base-state shape — if state_get's schema changes, one edit
# here, not five hand-rolled `echo '{"base":…}'` sites. Pass "" to seed
# an absent base (for error-path tests).
seed_base() {
  echo "{\"base\":\"$1\"}" > .do-results.json
}