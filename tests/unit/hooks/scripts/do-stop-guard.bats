#!/usr/bin/env bats
# Unit tests for do-stop-guard.sh — the /do stop-prevention hook.
# Black-box: sets CLAUDE_PROJECT_DIR, creates fixture .do-results.json, asserts on stdout.

setup() {
  load "$REPO_ROOT/tests/helpers/setup.bash"
  setup_test_dir
  GUARD="$(apm_script hooks/scripts/do-stop-guard.sh)"
  export CLAUDE_PROJECT_DIR="$TEST_DIR"
}

teardown() {
  teardown_test_dir
}

run_guard() {
  run bash "$GUARD"
}

@test "no .do-results.json: exit 0, empty stdout (approve)" {
  rm -f .do-results.json
  run_guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "active=working: emits block JSON" {
  echo '{"active":"working"}' > .do-results.json
  run_guard
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *'"reason":"/do workflow still running'* ]]
}

@test "active=completed: exit 0, empty stdout (approve)" {
  echo '{"active":"completed"}' > .do-results.json
  run_guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "active=waiting: exit 0, empty stdout (approve)" {
  echo '{"active":"waiting"}' > .do-results.json
  run_guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "active field absent: exit 0, empty stdout (approve)" {
  echo '{"workflow":"do","steps":[]}' > .do-results.json
  run_guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "malformed JSON: emits block JSON with parse_error reason" {
  echo '{not valid json' > .do-results.json
  run_guard
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *'Could not parse .do-results.json'* ]]
}
