#!/usr/bin/env bats
# Integration tests for vcs-op — the semantic VCS dispatcher.
# Uses real git repos (temp) as fixtures. jj arms are skipped when jj isn't
# available or can't be set up in the temp dir.

setup() {
  load "$REPO_ROOT/tests/helpers/setup.bash"
  load "$REPO_ROOT/tests/helpers/git-fixtures.bash"
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
  mk_initial_commit

  run bash "$VCS_OP" dirty
  [ "$status" -eq 1 ]
}

@test "dirty: exit 0 on uncommitted changes" {
  mk_initial_commit
  echo "changed" > file.txt

  run bash "$VCS_OP" dirty
  [ "$status" -eq 0 ]
}

# ─── head-revision ────────────────────────────────────────────────────

@test "head-revision returns current branch name" {
  mk_initial_commit
  git checkout -q -b feature-x

  run bash "$VCS_OP" head-revision
  [ "$status" -eq 0 ]
  [ "$output" = "feature-x" ]
}

# ─── head-commit-sha ──────────────────────────────────────────────────

@test "head-commit-sha returns a SHA" {
  mk_initial_commit
  sha=$(git rev-parse HEAD)

  run bash "$VCS_OP" head-commit-sha
  [ "$status" -eq 0 ]
  [ "$output" = "$sha" ]
}

# ─── default-branch ───────────────────────────────────────────────────

@test "default-branch returns master when origin/HEAD is unset" {
  mk_initial_commit

  run bash "$VCS_OP" default-branch
  [ "$status" -eq 0 ]
  [ "$output" = "master" ]
}

@test "default-branch returns main when origin/HEAD points to main" {
  mk_initial_commit
  git branch -m master main
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

  run bash "$VCS_OP" default-branch
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

# ─── branch ───────────────────────────────────────────────────────────

@test "branch creates a new branch from origin/base" {
  mk_initial_commit
  mk_remote_fixture

  run bash "$VCS_OP" branch feat-test master
  [ "$status" -eq 0 ]

  git rev-parse --verify feat-test
}

# ─── commit ───────────────────────────────────────────────────────────

@test "commit stages and commits all changes" {
  mk_initial_commit
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
  mk_initial_commit

  run bash "$VCS_OP" log-head
  [ "$status" -eq 0 ]
  [[ "$output" == *"initial"* ]]
}

# ─── log-range ────────────────────────────────────────────────────────

@test "log-range shows commits between base and HEAD" {
  mk_initial_commit
  mk_remote_fixture

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
  mk_initial_commit
  mk_remote_fixture

  git checkout -q -b feature
  echo "world" > file2.txt
  git add file2.txt
  git commit -q -m "add file2"

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
