#!/usr/bin/env bash
# The reusable dependabot-auto-merge workflow. Its decision step is run exactly
# as written in the workflow, against fixture metadata, including the cases
# that must NOT arm. Structural guards check the workflow's rails.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
wf="$ROOT/.github/workflows/dependabot-auto-merge.yml"

# step_run <step name prefix> : prints the run block of a job step. Job steps
# sit at six spaces, so lib.sh's extract_step (action steps) does not apply.
step_run() {
  awk -v name="      - name: $1" '
    index($0, name) == 1 { instep = 1; next }
    instep && /^      - name: / { exit }
    instep && /^        run: [|>]/ { inrun = 1; next }
    inrun && /^ {0,9}[^ ]/ { exit }
    inrun { sub(/\r$/, ""); sub(/^          /, ""); print }
  ' "$wf"
}

step="$WORK/decide.sh"
step_run "Decide whether to arm" > "$step"
[ -s "$step" ] || { echo "decide step not found"; exit 2; }

UP=version-update:semver
# dep <name> <update type minor|patch|major> <new version>
dep() { printf '{"dependencyName":"%s","updateType":"%s-%s","newVersion":"%s"}' "$1" "$UP" "$2" "$3"; }
json() { local IFS=,; echo "[$*]"; }

n=0
# decide <name> <wanted arm> <ARMED> <ECOSYSTEM> <UPDATE_TYPE> <DEPS_JSON>
# Wanted "fail" means the step must exit non-zero.
decide() {
  n=$((n + 1)); local tmp="$WORK/dam-$n" got out arm
  mkdir -p "$tmp"; : > "$tmp/out"
  out="$(cd "$tmp" && ARMED="$3" ECOSYSTEM="$4" UPDATE_TYPE="$5" DEPS_JSON="$6" \
    GITHUB_OUTPUT="$tmp/out" bash "$step" 2>&1)"; got=$?
  arm="$(sed -n 's/^arm=//p' "$tmp/out")"
  if [ "$2" = fail ]; then
    expect "$1" 1 "$got" "$out"
  else
    expect "$1" 0 "$got" "$out"
    expect "$1 -> arm=$2" 0 "$([ "$arm" = "$2" ] && echo 0 || echo 1)" "arm=$arm"
  fi
}

# npm: the behaviour that already ships.
decide "npm minor, default armed" true npm npm_and_yarn "$UP-minor" "$(json "$(dep a minor 1.3.0)")"
decide "npm patch" true npm npm_and_yarn "$UP-patch" "$(json "$(dep a patch 1.2.4)")"
decide "npm group of minors and patches" true npm npm_and_yarn "$UP-minor" "$(json "$(dep a minor 1.3.0)" "$(dep b patch 2.0.1)")"
decide "npm major" false npm npm_and_yarn "$UP-major" "$(json "$(dep a major 2.0.0)")"
decide "npm group with one major (highest says major)" false npm npm_and_yarn "$UP-major" "$(json "$(dep a minor 1.3.0)" "$(dep b major 3.0.0)")"
decide "npm group where an entry is major but highest says minor" false npm npm_and_yarn "$UP-minor" "$(json "$(dep a minor 1.3.0)" "$(dep b major 3.0.0)")"
decide "npm prerelease target" false npm npm_and_yarn "$UP-minor" "$(json "$(dep a minor 1.3.0-beta.1)")"
decide "npm v-prefixed stable version" true npm npm_and_yarn "$UP-patch" "$(json "$(dep a patch v1.2.4)")"
decide "unknown update type" false npm npm_and_yarn "version-update:semver-prerelease" "$(json "$(dep a minor 1.3.0)")"
decide "empty update type" false npm npm_and_yarn "" "$(json "$(dep a minor 1.3.0)")"

# uv: uv.lock and pyproject.toml updates report the ecosystem "uv".
decide "uv minor, uv not armed (default)" false npm uv "$UP-minor" "$(json "$(dep requests minor 2.33.0)")"
decide "uv minor, uv armed" true "npm,uv" uv "$UP-minor" "$(json "$(dep requests minor 2.33.0)")"
decide "uv patch, only uv armed" true uv uv "$UP-patch" "$(json "$(dep requests patch 2.32.5)")"
decide "uv major, uv armed" false "npm,uv" uv "$UP-major" "$(json "$(dep django major 6.0)")"
decide "uv two-part version" true uv uv "$UP-minor" "$(json "$(dep django minor 5.2)")"
decide "uv PEP 440 release candidate" false uv uv "$UP-minor" "$(json "$(dep requests minor 2.33.0rc1)")"
decide "uv PEP 440 alpha" false uv uv "$UP-minor" "$(json "$(dep requests minor 2.33.0a1)")"
decide "uv PEP 440 dev release" false uv uv "$UP-patch" "$(json "$(dep requests patch 2.32.5.dev1)")"
decide "uv mixed group with a major" false uv uv "$UP-major" "$(json "$(dep a minor 1.3.0)" "$(dep b major 2.0.0)")"

# Maven: pom.xml updates report the ecosystem "maven".
decide "maven minor, maven not armed" false "npm,uv" maven "$UP-minor" "$(json "$(dep spring minor 6.2.0)")"
decide "maven minor, maven armed" true "npm,maven" maven "$UP-minor" "$(json "$(dep spring minor 6.2.0)")"
decide "maven patch with .RELEASE qualifier" true maven maven "$UP-patch" "$(json "$(dep spring patch 5.3.9.RELEASE)")"
decide "maven jre flavor" true maven maven "$UP-minor" "$(json "$(dep guava minor 33.5.0-jre)")"
decide "maven SNAPSHOT" false maven maven "$UP-minor" "$(json "$(dep lib minor 2.1.0-SNAPSHOT)")"
decide "maven milestone" false maven maven "$UP-minor" "$(json "$(dep lib minor 2.1.0-M1)")"
decide "maven RC" false maven maven "$UP-patch" "$(json "$(dep lib patch 2.0.1-RC2)")"
decide "maven major" false maven maven "$UP-major" "$(json "$(dep lib major 3.0.0)")"

# Never armed, however the caller configures it.
decide "GitHub Actions minor, every ecosystem armed" false "npm,uv,maven" github_actions "$UP-minor" "$(json "$(dep actions/checkout minor 7.1.0)")"
decide "ecosystem pip is not armed" false "npm,uv,maven" pip "$UP-minor" "$(json "$(dep requests minor 2.33.0)")"
decide "listing github-actions is a configuration error" fail "npm,github-actions" npm_and_yarn "$UP-minor" "$(json "$(dep a minor 1.3.0)")"
decide "listing an unknown ecosystem is a configuration error" fail "npm,cargo" npm_and_yarn "$UP-minor" "$(json "$(dep a minor 1.3.0)")"
decide "nothing armed" false "" npm_and_yarn "$UP-minor" "$(json "$(dep a minor 1.3.0)")"
decide "armed list tolerates spaces" true "npm, uv" uv "$UP-minor" "$(json "$(dep a minor 1.3.0)")"

# Missing or damaged metadata never arms.
decide "no dependency list" false npm npm_and_yarn "$UP-minor" ""
decide "empty dependency list" false npm npm_and_yarn "$UP-minor" "[]"
decide "dependency list is not JSON" false npm npm_and_yarn "$UP-minor" "not json"
decide "entry without a version" false npm npm_and_yarn "$UP-minor" '[{"dependencyName":"a","updateType":"version-update:semver-minor"}]'

# Metadata is data: a hostile dependency name is never run.
decide "hostile dependency name" true npm npm_and_yarn "$UP-minor" "$(json "$(dep '$(touch pwned)' minor 1.3.0)")"
[ ! -e "$WORK/dam-$n/pwned" ] && expect "hostile name was not executed" 0 0 "" || expect "hostile name was not executed" 0 1 "pwned exists"

# Structure: the rails around the decision.
expect "reusable via workflow_call" 0 "$(grep -qE '^  workflow_call:' "$wf"; echo $?)" ""
expect "ecosystems input defaults to npm" 0 "$(grep -qE "^        default: 'npm'" "$wf"; echo $?)" ""
expect "no pull_request_target trigger" 0 "$(grep -qE '^\s*pull_request_target:' "$wf"; echo $((1 - $?)))" ""
expect "no checkout of PR code" 0 "$(grep -qE 'actions/checkout' "$wf"; echo $((1 - $?)))" ""
expect "top-level permissions are empty" 0 "$(grep -qE '^permissions: \{\}' "$wf"; echo $?)" ""
expect "arms with --auto --squash" 0 "$(grep -qF 'gh pr merge --auto --squash' "$wf"; echo $?)" ""
expect "only Dependabot-authored PRs" 0 "$(grep -qF "github.event.pull_request.user.login == 'dependabot[bot]'" "$wf"; echo $?)" ""
for s in "Decide whether to arm" "Enable auto-merge" "Summary"; do
  run_text="$(step_run "$s")"
  expect "step '$s' has a script" 0 "$([ -n "$run_text" ]; echo $?)" ""
  expect "step '$s' interpolates nothing into its script" 0 "$(printf '%s' "$run_text" | grep -qF '${{'; echo $((1 - $?)))" ""
done
finish
