#!/usr/bin/env bash
# Runs every action test. Each one executes the step text exactly as written
# in an action.yml, against fixtures, including the paths that must fail.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for t in batch-discipline invisible-payload audit-gate gitleaks; do
  echo "== $t"
  ACTION_TEST_TMP="$(mktemp -d)" bash "$here/$t.sh" || failed=1
done
[ "$failed" = 0 ] && echo "All action tests passed." || { echo "Action tests FAILED."; exit 1; }
