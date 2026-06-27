#!/usr/bin/env bats
# Integration tests for vcs-op — the semantic VCS dispatcher.
# Uses real git repos (temp) as fixtures. jj arms are skipped when jj isn't
# available or can't be set up in the temp dir.

setup() {
  load "$REPO_ROOT/tests/helpers/setup.bash"
  setup_test_dir

  VCS_OP="$(apm_script skills/do/scripts/vcs-op)"

  # Create a real git fixture repo
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git remote add origin https://github.com/example/repo.git
}

teardown() {
  teardown_test_dir
}

# ─── detect ───────────────────────────────────────────────────────────

@test "detect returns git in a git repo" {
  run bash "$VCS_OP" detect
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "detect honors VCS_OVERRIDE" {
  VCS_OVERRIDE=jj run bash "$VCS_OP" detect
  [ "$status" -eq 0 ]
  [ "$output" = "jj" ]
}

@test "detect returns unknown outside any repo" {
  cd /tmp
  VCS_OVERRIDE= run bash "$VCS_OP" detect
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

# ─── dirty ────────────────────────────────────────────────────────────

@test "dirty: exit 1 on clean tree" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"

  run bash "$VCS_OP" dirty
  [ "$status" -eq 1 ]
}

@test "dirty: exit 0 on uncommitted changes" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"
  echo "changed" > file.txt

  run bash "$VCS_OP" dirty
  [ "$status" -eq 0 ]
}

# ─── head-revision ────────────────────────────────────────────────────

@test "head-revision returns current branch name" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"
  git checkout -q -b feature-x

  run bash "$VCS_OP" head-revision
  [ "$status" -eq 0 ]
  [ "$output" = "feature-x" ]
}

# ─── head-commit-sha ──────────────────────────────────────────────────

@test "head-commit-sha returns a SHA" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"
  sha=$(git rev-parse HEAD)

  run bash "$VCS_OP" head-commit-sha
  [ "$status" -eq 0 ]
  [ "$output" = "$sha" ]
}

# ─── default-branch ───────────────────────────────────────────────────

@test "default-branch returns master when origin/HEAD is unset" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"

  run bash "$VCS_OP" default-branch
  [ "$status" -eq 0 ]
  [ "$output" = "master" ]
}

@test "default-branch returns main when origin/HEAD points to main" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"
  git branch -m master main
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

  run bash "$VCS_OP" default-branch
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

# ─── branch ───────────────────────────────────────────────────────────

@test "branch creates a new branch from origin/base" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"

  # vcs-op branch does: git branch <name> origin/<base>
  # We need origin/<base> to exist. Create a bare repo and push.
  git init -q --bare "$TEST_DIR/remote.git"
  git remote set-url origin "$TEST_DIR/remote.git"
  git push -q origin master 2>/dev/null
  git remote set-head origin -a 2>/dev/null

  run bash "$VCS_OP" branch feat-test master
  [ "$status" -eq 0 ]

  git rev-parse --verify feat-test
}

# ─── commit ───────────────────────────────────────────────────────────

@test "commit stages and commits all changes" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"
  echo "world" > file2.txt

  run bash "$VCS_OP" commit "feat: add file2"
  [ "$status" -eq 0 ]

  run git log -1 --oneline
  [[ "$output" == *"feat: add file2"* ]]

  # file2.txt should be committed
  git cat-file -e HEAD:file2.txt
}

# ─── log-head ─────────────────────────────────────────────────────────

@test "log-head returns one-line log of HEAD" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial commit"

  run bash "$VCS_OP" log-head
  [ "$status" -eq 0 ]
  [[ "$output" == *"initial commit"* ]]
}

# ─── log-range ────────────────────────────────────────────────────────

@test "log-range shows commits between base and HEAD" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"

  # Set up a remote so origin/master ref exists
  git init -q --bare "$TEST_DIR/remote.git"
  git remote set-url origin "$TEST_DIR/remote.git"
  git push -q origin master 2>/dev/null

  git checkout -q -b feature
  echo "world" > file2.txt
  git add file2.txt
  git commit -q -m "add file2"

  run bash "$VCS_OP" log-range master
  [ "$status" -eq 0 ]
  [[ "$output" == *"add file2"* ]]
  [[ "$output" != *"initial"* ]]
}

# ─── diff-names ───────────────────────────────────────────────────────

@test "diff-names shows changed files" {
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "initial"
  git checkout -q -b feature
  echo "world" > file2.txt
  git add file2.txt
  git commit -q -m "add file2"

  # diff-names uses origin/<base>...HEAD — needs origin ref
  git init -q --bare "$TEST_DIR/remote.git"
  git remote set-url origin "$TEST_DIR/remote.git"
  git push -q origin master 2>/dev/null

  run bash "$VCS_OP" diff-names master
  [ "$status" -eq 0 ]
  [[ "$output" == *"file2.txt"* ]]
}

# ─── error paths ──────────────────────────────────────────────────────

@test "unknown operation errors with available ops list" {
  run bash "$VCS_OP" frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown operation 'frobnicate'"* ]]
  [[ "$output" == *"Available:"* ]]
}

@test "no-VCS operations exit 1 with message" {
  cd /tmp
  VCS_OVERRIDE= run bash "$VCS_OP" fetch
  [ "$status" -eq 1 ]
  [[ "$output" == *"no VCS detected"* ]]
}

# ─── jj arms (skipped when jj isn't available) ────────────────────────

@test "jj: detect in jj colocated repo" {
  command -v jj >/dev/null || skip "jj not installed"
  jj git init --colocate -q 2>/dev/null || skip "jj git init failed"

  VCS_OVERRIDE= run bash "$VCS_OP" detect
  [ "$status" -eq 0 ]
  [[ "$output" == "jj" ]]
}
