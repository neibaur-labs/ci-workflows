#!/usr/bin/env bash
# The audit-gate action's step, run with the real node and a stand-in pnpm
# that prints fixture audit data for the base or the head.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step="$WORK/gate.sh"
extract_step "$ROOT/.github/actions/audit-gate/action.yml" "Audit gate" > "$step"
[ -s "$step" ] || { echo "step not found"; exit 2; }
gate="$ROOT/packages/checks/bin/audit-gate.mjs"

mkdir -p "$WORK/bin"
printf '%s\n' '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  install) exit 0 ;;' \
  '  audit) case "$PWD" in */base) cat "$FIX_BASE" ;; *) cat "$FIX_HEAD" ;; esac; exit 1 ;;' \
  'esac' \
  'exit 2' > "$WORK/bin/pnpm"
chmod +x "$WORK/bin/pnpm"

repo="$WORK/gate-repo"
new_git_repo "$repo"; cd "$repo" || exit 2
echo '{"name":"fixture","private":true}' > package.json
echo "lockfileVersion: '9.0'" > pnpm-lock.yaml
git add -A && git commit -q -m base
sha=$(git rev-parse HEAD)

A='"1":{"github_advisory_id":"GHSA-aaaa-aaaa-aaaa","module_name":"left-pad-fixture","severity":"high"}'
A2='"1":{"github_advisory_id":"GHSA-aaaa-aaaa-aaaa","module_name":"left-pad-fixture","severity":"high","findings":[{"version":"1.1.0"}]}'
B='"2":{"github_advisory_id":"GHSA-bbbb-bbbb-bbbb","module_name":"right-pad-fixture","severity":"critical"}'
M='"3":{"github_advisory_id":"GHSA-cccc-cccc-cccc","module_name":"pad-fixture","severity":"moderate"}'
ERR='{"error":{"code":"ERR_PNPM_AUDIT_BAD_RESPONSE","message":"fixture"}}'
audit() { echo "{\"advisories\":{$1},\"metadata\":{}}"; }

n=0
# run <name> <wanted exit> <base json> <head json> <base sha> [must contain] [must not contain]
run() {
  n=$((n + 1)); local tmp="$WORK/gate-tmp-$n" out got
  mkdir -p "$tmp"
  echo "$3" > "$tmp/fix-base.json"; echo "$4" > "$tmp/fix-head.json"
  out=$(PATH="$WORK/bin:$PATH" RUNNER_TEMP="$tmp" BASE_SHA="$5" GATE="$gate" \
        FIX_BASE="$tmp/fix-base.json" FIX_HEAD="$tmp/fix-head.json" bash "$step" 2>&1); got=$?
  expect "$1" "$2" "$got" "$out" "${6-}" "${7-}"
}

run "clean on both sides" 0 "$(audit '')" "$(audit '')" "$sha" "Audit gate OK: this change introduces no"
run "clean base, pull request adds a high advisory" 1 "$(audit '')" "$(audit "$A")" "$sha" \
    "::error::This change introduces a high or critical advisory: GHSA-aaaa-aaaa-aaaa left-pad-fixture"
run "same advisory on both sides" 0 "$(audit "$A")" "$(audit "$A")" "$sha" \
    "::warning::Advisory already on the base branch (not blocking): GHSA-aaaa-aaaa-aaaa left-pad-fixture" "::error::"
run "base has one, pull request adds a second" 1 "$(audit "$A")" "$(audit "$A,$B")" "$sha" \
    "::error::This change introduces a high or critical advisory: GHSA-bbbb-bbbb-bbbb right-pad-fixture" \
    "advisory: GHSA-aaaa-aaaa-aaaa"
run "pull request fixes an advisory" 0 "$(audit "$A")" "$(audit '')" "$sha" "Audit gate OK" "::warning::"
run "pull request adds a moderate advisory" 0 "$(audit '')" "$(audit "$M")" "$sha" "Audit gate OK" "GHSA-cccc"
run "different vulnerable version of a flagged package" 0 "$(audit "$A")" "$(audit "$A2")" "$sha" \
    "::warning::Advisory already on the base branch" "::error::"
run "push to main with an open advisory" 0 "$(audit '')" "$(audit "$A")" "" \
    "::warning::Open advisory on this branch: GHSA-aaaa-aaaa-aaaa left-pad-fixture"
run "push to main, audit returns an error object" 1 "$(audit '')" "$ERR" "" "failing closed"
run "error object for the pull request" 1 "$(audit '')" "$ERR" "$sha" "for the pull request; failing closed"
run "error object for the base" 1 "$ERR" "$(audit "$A")" "$sha" "for the base branch; failing closed"

# With no gate command there is no verdict: the step must stop, never pass.
gate="$WORK/does-not-exist.mjs"
run "gate command missing" 1 "$(audit '')" "$(audit '')" "$sha" "" "Audit gate OK"

finish
