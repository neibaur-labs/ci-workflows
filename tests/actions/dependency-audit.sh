#!/usr/bin/env bash
# The dependency-audit action's step, run with the real node and stand-ins for
# pnpm and gh. The gh stand-in records every write it is asked to make.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step="$WORK/audit-issue.sh"
extract_step "$ROOT/.github/actions/dependency-audit/action.yml" "Audit and report" > "$step"
[ -s "$step" ] || { echo "step not found"; exit 2; }
report="$ROOT/packages/checks/bin/audit-issue.mjs"

mkdir -p "$WORK/bin"
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "$1" = audit ]; then cat "$FIX_AUDIT"; exit 1; fi' \
  'exit 2' > "$WORK/bin/pnpm"
# gh stand-in. Reads answer the way the real command would after --jq.
# Writes are appended to $GH_LOG as "<verb> <issue or title>" plus the body.
printf '%s\n' '#!/usr/bin/env bash' \
  'body=""; prev=""' \
  'for a in "$@"; do [ "$prev" = --body-file ] && body="$a"; prev="$a"; done' \
  'case "$1 $2" in' \
  '  "issue list") printf "%s" "$FAKE_EXISTING" ;;' \
  '  "issue view") printf "%s\n" "$FAKE_THREAD" ;;' \
  '  "issue create") echo "create" >> "$GH_LOG"; cat "$body" >> "$GH_LOG" ;;' \
  '  "issue comment") echo "comment $3" >> "$GH_LOG"; cat "$body" >> "$GH_LOG" ;;' \
  '  *) echo "unexpected gh call: $*" >> "$GH_LOG"; exit 2 ;;' \
  'esac' > "$WORK/bin/gh"
chmod +x "$WORK/bin/pnpm" "$WORK/bin/gh"

H='"1":{"github_advisory_id":"GHSA-aaaa-aaaa-aaaa","module_name":"left-pad-fixture","severity":"high","patched_versions":">=1.2.0","findings":[{"version":"1.1.0"}]}'
M='"2":{"github_advisory_id":"GHSA-cccc-cccc-cccc","module_name":"pad-fixture","severity":"moderate","patched_versions":">=3.1.0","findings":[{"version":"3.0.0"}]}'
ERR='{"error":{"code":"ERR_PNPM_AUDIT_BAD_RESPONSE","message":"fixture"}}'
audit() { echo "{\"advisories\":{$1},\"metadata\":{}}"; }

n=0
# run <name> <wanted exit> <audit json> <existing issue number or ""> <thread text>
# Sets OUT (step output) and LOG (what gh was asked to write).
run() {
  n=$((n + 1)); local tmp="$WORK/audit-tmp-$n" got
  mkdir -p "$tmp"; : > "$tmp/gh.log"
  echo "$3" > "$tmp/fix.json"
  OUT=$(PATH="$WORK/bin:$PATH" RUNNER_TEMP="$tmp" REPO="fixture/repo" RUN_URL="https://example.invalid/run/1" \
        REPORT="$report" GH_TOKEN="unused" GH_LOG="$tmp/gh.log" FIX_AUDIT="$tmp/fix.json" \
        FAKE_EXISTING="$4" FAKE_THREAD="$5" bash "$step" 2>&1); got=$?
  LOG=$(cat "$tmp/gh.log")
  expect "$1" "$2" "$got" "$OUT"
}
# check <name> <haystack> <must contain, or "" to require empty>
check() {
  if [ -z "$3" ]; then
    [ -z "$2" ] && expect "$1" 0 0 "" || expect "$1" 0 1 "$2"
  else
    printf '%s\n' "$2" | grep -qF -- "$3" && expect "$1" 0 0 "" || expect "$1" 0 1 "$2"
  fi
}

# The key the command gives the high-only fixture, for the "unchanged" case.
audit "$H" > "$WORK/key.json"
key=$(node "$report" "$WORK/key.json" "$WORK/key.md" | grep '^key=' | cut -d= -f2)
[ -n "$key" ] || { echo "could not compute a key"; exit 2; }

run "clean, no issue open" 0 "$(audit '')" "" ""
check "  writes nothing" "$LOG" ""

run "clean, issue open with advisories last reported" 0 "$(audit '')" "7" "body <!-- audit-key: $key -->"
check "  comments that it can be closed" "$LOG" "comment 7"
check "  marks the comment clean" "$LOG" "<!-- audit-key: clean -->"

run "clean, issue open and already told it is clean" 0 "$(audit '')" "7" "x <!-- audit-key: $key --> y <!-- audit-key: clean -->"
check "  writes nothing" "$LOG" ""

run "high advisory, no issue open" 0 "$(audit "$H")" "" ""
check "  creates the issue" "$LOG" "create"
check "  with the advisory row" "$LOG" '| `left-pad-fixture` | high | GHSA-aaaa-aaaa-aaaa | 1.1.0 | >=1.2.0 |'
check "  with the run link" "$LOG" "Run: https://example.invalid/run/1"
check "  with the key marker" "$LOG" "<!-- audit-key: $key -->"
check "  and warns" "$OUT" "::warning::High or critical advisories are open"

run "moderate advisory only, no issue open" 0 "$(audit "$M")" "" ""
check "  creates the issue" "$LOG" "### Moderate and low: fix within 30 days"
if printf '%s\n' "$OUT" | grep -q '::warning::'; then expect "  does not warn" 0 1 "$OUT"; else expect "  does not warn" 0 0 ""; fi

run "same advisories as the last report" 0 "$(audit "$H")" "7" "body <!-- audit-key: $key -->"
check "  writes nothing" "$LOG" ""
check "  says so" "$OUT" "unchanged since the last report"

run "advisories changed since the last report" 0 "$(audit "$H,$M")" "7" "body <!-- audit-key: $key -->"
check "  comments on the open issue" "$LOG" "comment 7"
check "  with both sections" "$LOG" "### Moderate and low: fix within 30 days"

run "issue open with no key yet" 0 "$(audit "$H")" "7" "an older body without a marker"
check "  comments on the open issue" "$LOG" "comment 7"

run "audit returns an error object" 1 "$ERR" "" ""
check "  writes nothing" "$LOG" ""
check "  fails closed" "$OUT" "failing closed"

finish
