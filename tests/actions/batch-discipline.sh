#!/usr/bin/env bash
# Batch discipline step of the security-scan action, against git histories.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step="$WORK/batch.sh"
extract_step "$ROOT/.github/actions/security-scan/action.yml" "Batch discipline" > "$step"
[ -s "$step" ] || { echo "step not found"; exit 2; }

n=0
new_repo() {
  n=$((n + 1)); repo="$WORK/batch-$n"
  new_git_repo "$repo"; cd "$repo" || exit 2
  mkdir -p packages/a/src packages/a/tests docs
  echo "export const a = 1;" > packages/a/src/index.ts
  echo "test a 1" > packages/a/tests/index.test.ts
  echo "old spec" > packages/a/src/old.spec.ts
  echo "docs" > docs/readme.md
  git add -A && git commit -q -m "base"
  base=$(git rev-parse HEAD)
  git checkout -q -b feature
}
commit() { git add -A && git commit -q -m "$1"; }

# run_case <name> <wanted exit> [base override] [must contain]
run_case() {
  local b="${3-$base}" h out got
  h=$(git rev-parse HEAD)
  # GitHub substitutes the two expressions before bash sees the script.
  sed -e "s|\${{ github.event.pull_request.base.sha }}|$b|" \
      -e "s|\${{ github.event.pull_request.head.sha }}|$h|" "$step" > "$WORK/batch-run.sh"
  if grep -q 'github.event' "$WORK/batch-run.sh"; then echo "substitution failed"; exit 2; fi
  out=$(bash "$WORK/batch-run.sh" 2>&1); got=$?
  expect "$1" "$2" "$got" "$out" "${4-}"
}

new_repo
mkdir -p packages/b/src packages/b/tests
echo "export const b = 1;" > packages/b/src/index.ts; echo "test b" > packages/b/tests/index.test.ts
commit "new test and new implementation in one commit"
run_case "new test + new implementation, one commit" 0

new_repo
mkdir -p packages/b/src packages/b/tests
echo "test b" > packages/b/tests/index.test.ts; commit "failing tests"
echo "export const b = 1;" > packages/b/src/index.ts; commit "implementation"
run_case "tests-first: new tests, then implementation" 0

new_repo
echo "test a 2" > packages/a/tests/index.test.ts; echo "export const a = 2;" > packages/a/src/index.ts
commit "both"
run_case "existing test + implementation, one commit" 1 "$base" "packages/a/tests/index.test.ts"

new_repo
echo "test a 2" > packages/a/tests/index.test.ts; commit "test"
echo "export const a = 2;" > packages/a/src/index.ts; commit "impl"
run_case "existing test changed first, implementation after" 0

new_repo
echo "export const a = 2;" > packages/a/src/index.ts; commit "impl"
echo "test a 2" > packages/a/tests/index.test.ts; commit "test"
run_case "implementation first, existing test changed after" 1

new_repo
git rm -q packages/a/tests/index.test.ts; echo "export const a = 2;" > packages/a/src/index.ts
commit "delete test with impl"
run_case "existing test deleted + implementation, one commit" 1

new_repo
git mv packages/a/tests/index.test.ts packages/a/tests/renamed.test.ts; echo "export const a = 2;" > packages/a/src/index.ts
commit "rename test with impl"
run_case "existing test renamed + implementation, one commit" 1

new_repo
echo "new spec" > packages/a/src/old.spec.ts; echo "export const a = 2;" > packages/a/src/index.ts
commit "spec beside source with impl"
run_case "existing .spec file under src + implementation, one commit" 1

new_repo
echo "test a 2" > packages/a/tests/index.test.ts; commit "test only"
run_case "only an existing test changes" 0

new_repo
echo "export const a = 2;" > packages/a/src/index.ts; commit "impl only"
run_case "only implementation changes" 0

new_repo
echo "more docs" > docs/readme.md; commit "docs"
run_case "docs only" 0

new_repo
echo "test a 2" > packages/a/tests/index.test.ts; echo "more docs" > docs/readme.md; commit "test and docs"
run_case "existing test + a non-implementation file, one commit" 0

new_repo
echo "feature work" > docs/feature.md; commit "feature docs"
git checkout -q main
echo "test a 9" > packages/a/tests/index.test.ts; echo "export const a = 9;" > packages/a/src/index.ts
commit "main moved: test and impl together"
newbase=$(git rev-parse HEAD)
git checkout -q feature
git merge -q --no-edit main
run_case "merge of main that carries test + implementation changes" 0 "$newbase"

new_repo
echo "export const a = 2;" > packages/a/src/index.ts; commit "impl"
git checkout -q main
echo "test a 9" > packages/a/tests/index.test.ts; commit "main moved: test"
newbase=$(git rev-parse HEAD)
git checkout -q feature
git merge -q --no-edit main
run_case "implementation, then a merge of main that changes a test" 0 "$newbase"

new_repo
echo "test a 2" > packages/a/tests/index.test.ts; echo "export const a = 2;" > packages/a/src/index.ts
commit "both"
run_case "not a pull request (empty base) skips" 0 ""

finish
