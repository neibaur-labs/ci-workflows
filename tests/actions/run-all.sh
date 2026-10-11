#!/usr/bin/env bash
# Runs every action test in this folder. Each one executes the step text
# exactly as written in an action.yml, against fixtures, including the paths
# that must fail. A new test file is picked up without editing this one.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
ran=0
for file in "$here"/*.sh; do
  t="$(basename "$file" .sh)"
  case "$t" in lib | run-all) continue ;; esac
  echo "== $t"
  ran=$((ran + 1))
  ACTION_TEST_TMP="$(mktemp -d)" bash "$file" || failed=1
done
[ "$ran" -gt 0 ] || { echo "No action tests found."; exit 1; }
[ "$failed" = 0 ] && echo "All $ran action tests passed." || { echo "Action tests FAILED."; exit 1; }
