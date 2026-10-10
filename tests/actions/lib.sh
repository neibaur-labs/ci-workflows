#!/usr/bin/env bash
# Shared helpers for the action tests. Every test runs the step text exactly
# as it is written in an action.yml, so what is tested is what ships.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${ACTION_TEST_TMP:-$(mktemp -d)}"
PASS=0
WRONG=0

# extract_step <action.yml> <step name prefix> : prints the step's run block.
extract_step() {
  awk -v name="    - name: $2" '
    index($0, name) == 1 { instep = 1; next }
    instep && /^    - name: / { exit }
    instep && /^      run: [|>]/ { inrun = 1; next }
    inrun && /^ {0,7}[^ ]/ { exit }
    inrun { sub(/\r$/, ""); sub(/^        /, ""); print }
  ' "$1"
}

# new_git_repo <dir> : an empty repository with a fixture identity.
new_git_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main .
  git -C "$1" config user.email "fixture@example.invalid"
  git -C "$1" config user.name "fixture"
  git -C "$1" config commit.gpgsign false
  git -C "$1" config core.autocrlf false
}

# expect <name> <wanted exit> <actual exit> <output> [must contain] [must not contain]
expect() {
  local ok=1
  [ "$3" = "$2" ] || ok=0
  [ -z "${5-}" ] || printf '%s\n' "$4" | grep -qF -- "$5" || ok=0
  [ -z "${6-}" ] || ! printf '%s\n' "$4" | grep -qF -- "$6" || ok=0
  if [ "$ok" = 1 ]; then
    PASS=$((PASS + 1)); echo "ok    [$3] $1"
  else
    WRONG=$((WRONG + 1)); echo "WRONG [$3, wanted $2] $1"; printf '%s\n' "$4" | sed 's/^/        /'
  fi
}

finish() {
  echo "RESULT: $PASS ok, $WRONG wrong"
  [ "$WRONG" = 0 ]
}
