#!/usr/bin/env bash
# The gitleaks step of the security-scan action, run with Docker exactly as
# written, on a clean fixture and on one whose history holds a made-up key
# that was committed and then deleted. Skipped when Docker is not available,
# unless REQUIRE_DOCKER=1 (set in CI), in which case that is a failure.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if ! docker info > /dev/null 2>&1; then
  if [ "${REQUIRE_DOCKER-}" = 1 ]; then echo "Docker is required but not available"; exit 1; fi
  echo "SKIPPED: Docker is not available, so the gitleaks step was not run."
  exit 0
fi
step="$WORK/gitleaks.sh"
extract_step "$ROOT/.github/actions/security-scan/action.yml" "Secret scan (gitleaks)" > "$step"
[ -s "$step" ] || { echo "step not found"; exit 2; }

# run <name> <wanted exit> <repo dir>
run() {
  local out got src="$3"
  # On Windows (Git Bash) Docker needs a Windows path for the mount, and the
  # shell must not rewrite the container path /repo. Neither applies on Linux.
  if command -v cygpath > /dev/null 2>&1; then src=$(cygpath -m "$3"); fi
  sed -e "s|\${{ github.workspace }}|$src|" "$step" > "$WORK/gitleaks-run.sh"
  if grep -q 'github\.' "$WORK/gitleaks-run.sh"; then echo "substitution failed"; exit 2; fi
  out=$(MSYS_NO_PATHCONV=1 bash "$WORK/gitleaks-run.sh" 2>&1); got=$?
  expect "$1" "$2" "$got" "$out"
}

clean="$WORK/leaks-clean"
new_git_repo "$clean"
echo "hello" > "$clean/readme.txt"
git -C "$clean" add -A && git -C "$clean" commit -q -m base
run "clean history passes" 0 "$clean"

dirty="$WORK/leaks-dirty"
new_git_repo "$dirty"
echo "hello" > "$dirty/readme.txt"
git -C "$dirty" add -A && git -C "$dirty" commit -q -m base
# A made-up value shaped like an AWS access key id and secret. Not a credential.
id="AKIA$(head -c 64 /dev/urandom | base64 | tr -dc 'A-Z2-7' | head -c 16)"
secret="$(head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
printf 'aws_access_key_id = %s\naws_secret_access_key = %s\n' "$id" "$secret" > "$dirty/settings.ini"
git -C "$dirty" add -A && git -C "$dirty" commit -q -m "add settings"
git -C "$dirty" rm -q settings.ini && git -C "$dirty" commit -q -m "remove settings"
run "key committed and later deleted fails" 1 "$dirty"

finish
