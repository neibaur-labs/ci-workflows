# ci-workflows

Shared GitHub Actions for the `neibaur-labs` and `neibaur` repositories:
security checks and the dependency advisory gate. One tested copy lives here,
and each repository calls it at a pinned commit.

This repository holds no secrets, credentials, or deployment configuration.

## Actions

### `security-scan`

Five checks, in one step of your own job:

- **Secret scan** with gitleaks over the full git history.
- **SAST** with Semgrep (`p/default`).
- **Forbidden patterns**: `eval(`, `new Function`, `child_process`,
  `dangerouslySetInnerHTML` under `apps`, `packages`, and `src`.
- **Invisible-payload scan**: zero-width and bidirectional-override characters.
- **Batch discipline**: in a pull request, a change to an existing test must be
  in its own commit, ahead of every implementation commit. New tests may
  arrive with new code.

```yaml
jobs:
  security:
    name: security
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha>
        with: { fetch-depth: 0 }
      - uses: neibaur-labs/ci-workflows/.github/actions/security-scan@<sha>
```

The checkout needs `fetch-depth: 0`: the secret scan and batch discipline read
history.

### `audit-gate`

Fails a pull request that introduces a high or critical advisory. It runs
`pnpm audit` on the base branch and on the pull request and compares them.
Advisories already on the base branch are printed as warnings and do not
block. If `pnpm audit` returns no advisory data, it fails closed.

```yaml
      - uses: pnpm/action-setup@<sha>
      - uses: actions/setup-node@<sha>
        with: { node-version: 22, cache: pnpm }
      - uses: neibaur-labs/ci-workflows/.github/actions/audit-gate@<sha>
```

It needs pnpm and Node 22.18 or later, and a checkout with `fetch-depth: 0`.

## Why actions and not reusable workflows

A job that calls a reusable workflow reports its check as
`caller / called job`. The repositories here are required to pass a check
named exactly `security`. A composite action runs as a step inside the
repository's own `security` job, so the check name does not change.

## Pinning

Reference an action by full commit SHA, never by branch. A change here then
reaches a repository only through a pull request that moves the SHA, which
Dependabot can open.

## How it is tested

- `packages/checks` is the decision logic of the audit gate, with unit tests
  (`pnpm test`).
- `tests/actions/` extracts each step's script from the `action.yml` files and
  runs that exact text against fixtures, including the cases that must fail.
  `bash tests/actions/run-all.sh` runs them; the gitleaks test needs Docker.
- The `security` job of this repository's own CI runs both actions from the
  checkout.

## Development

```sh
pnpm install --frozen-lockfile
pnpm validate
bash tests/actions/run-all.sh
```
