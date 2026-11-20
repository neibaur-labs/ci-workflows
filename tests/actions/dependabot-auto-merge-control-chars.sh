#!/usr/bin/env bash
# A control character inside a target version must never be cleaned away into
# a valid-looking version. Runs the decision step of the dependabot-auto-merge
# workflow as written.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
wf="$ROOT/.github/workflows/dependabot-auto-merge.yml"
step="$WORK/decide.sh"
awk -v name="      - name: Decide whether to arm" '
  index($0, name) == 1 { instep = 1; next }
  instep && /^      - name: / { exit }
  instep && /^        run: [|>]/ { inrun = 1; next }
  inrun && /^ {0,9}[^ ]/ { exit }
  inrun { sub(/\r$/, ""); sub(/^          /, ""); print }
' "$wf" > "$step"
[ -s "$step" ] || { echo "decide step not found"; exit 2; }

n=0
# arm_for <new version as a JSON string body>
arm_for() {
  n=$((n + 1)); local tmp="$WORK/cc-$n"
  mkdir -p "$tmp"; : > "$tmp/out"
  (cd "$tmp" && ARMED=npm ECOSYSTEM=npm_and_yarn UPDATE_TYPE=version-update:semver-minor \
    DEPS_JSON="[{\"dependencyName\":\"a\",\"updateType\":\"version-update:semver-minor\",\"newVersion\":\"$1\"}]" \
    GITHUB_OUTPUT="$tmp/out" bash "$step" > /dev/null 2>&1)
  sed -n 's/^arm=//p' "$tmp/out"
}

got="$(arm_for '1.3.0')"
expect "plain version arms" 0 "$([ "$got" = true ]; echo $?)" "arm=$got"
got="$(arm_for '1.2\r3')"
expect "carriage return inside a version does not arm" 0 "$([ "$got" = false ]; echo $?)" "arm=$got"
got="$(arm_for '1.3.0\r')"
expect "trailing carriage return does not arm" 0 "$([ "$got" = false ]; echo $?)" "arm=$got"
got="$(arm_for '1.3.0\n9.9.9')"
expect "newline inside a version does not arm" 0 "$([ "$got" = false ]; echo $?)" "arm=$got"
got="$(arm_for 'evil\n1.3.0')"
expect "junk line before a valid version does not arm" 0 "$([ "$got" = false ]; echo $?)" "arm=$got"
finish
