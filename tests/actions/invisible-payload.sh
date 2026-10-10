#!/usr/bin/env bash
# Invisible-payload and forbidden-pattern steps of the security-scan action.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
action="$ROOT/.github/actions/security-scan/action.yml"
invisible="$WORK/invisible.sh"; forbidden="$WORK/forbidden.sh"
extract_step "$action" "Invisible-payload scan" > "$invisible"
extract_step "$action" "Forbidden pattern check" > "$forbidden"
[ -s "$invisible" ] && [ -s "$forbidden" ] || { echo "step not found"; exit 2; }

n=0
# check <step file> <name> <wanted exit> <printf body, or NONE for no source dir>
check() {
  n=$((n + 1)); local d="$WORK/scan-$n" out got
  mkdir -p "$d"
  if [ "$4" != NONE ]; then
    mkdir -p "$d/packages/a/src"
    # The body is a printf format on purpose: it carries the byte escapes.
    # shellcheck disable=SC2059
    printf "$4\n" > "$d/packages/a/src/index.ts"
  fi
  out=$(cd "$d" && bash "$1" 2>&1); got=$?
  expect "$2" "$3" "$got" "$out"
}

check "$invisible" "zero-width space U+200B" 1 "const a = 'x\xe2\x80\x8by';"
check "$invisible" "zero-width joiner U+200D" 1 "const a = 'x\xe2\x80\x8dy';"
check "$invisible" "bidi override U+202E" 1 "const a = 'x\xe2\x80\xaey';"
check "$invisible" "word joiner U+2060" 1 "const a = 'x\xe2\x81\xa0y';"
check "$invisible" "bidi isolate U+2066" 1 "const a = 'x\xe2\x81\xa6y';"
check "$invisible" "byte-order mark U+FEFF" 1 "\xef\xbb\xbfconst a = 1;"
check "$invisible" "accents and CJK pass" 0 "const a = 'caf\xc3\xa9 \xe5\xa5\xbd\xe9\x9d\xa2\xe6\x9d\xa1';"
check "$invisible" "en dash and curly quote pass" 0 "const a = 'a\xe2\x80\x93b\xe2\x80\x99c';"
check "$invisible" "no source directories" 0 NONE

check "$forbidden" "eval call" 1 "const a = eval('1');"
check "$forbidden" "Function constructor" 1 "const a = new Function('return 1');"
check "$forbidden" "process spawning module" 1 "import { exec } from 'node:child_process';"
check "$forbidden" "React raw HTML prop" 1 "const a = { dangerouslySetInnerHTML: {} };"
check "$forbidden" "ordinary code passes" 0 "export const evaluate = (a: number) => a + 1;"
check "$forbidden" "no source directories" 0 NONE

out=$(cd "$ROOT" && bash "$invisible" 2>&1); expect "this repository, invisible-payload scan" 0 "$?" "$out"
out=$(cd "$ROOT" && bash "$forbidden" 2>&1); expect "this repository, forbidden patterns" 0 "$?" "$out"

finish
