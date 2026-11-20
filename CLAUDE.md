# CLAUDE.md

@AGENTS.md

The imported AGENTS.md above is the binding contract for all work in this
repository. Read it fully before acting. Key reminders:

- Run `pnpm validate` before opening any PR.
- Tests first: commit failing tests, then implementation.
- One concern per PR (two if tightly coupled). No line cap; 20,000-line ceiling.
- Also run `bash tests/actions/run-all.sh` (the gitleaks test needs Docker).
  The `lint`, `typecheck`, `test`, `build`, and `security` checks must pass
  before any pull request.
- Every caller pins this repository by commit SHA. Release only through the
  `releasing-shared-ci` skill in a maintainer-started session; never move or
  delete a tag.
- Commit and push your own work to feature branches. Protected paths
  (`.github/**`, `AGENTS.md`, `CLAUDE.md`, `LICENSE`, and the skill paths) are committed and pushed by you
  too when the maintainer started the session, in their own commits and listed
  in the PR description. Unattended runs never commit them: they leave a patch
  in the PR description (AGENTS.md §3).
- Dependency changes are allowed: make and verify them, then wait for explicit
  authorization or hand off the commit (AGENTS.md §4).
- Never read secret-bearing files. Never change repo settings or rulesets
  directly; draft them instead. The one exception is the auto-merge opt-in
  setting in neibaur-labs/agent-ops GOVERNANCE.md §11, in a maintainer-started session.
- Never push to `main`; never approve or force-push; close a pull request only
  as neibaur-labs/agent-ops GOVERNANCE.md §12 allows. Never merge, except in a
  maintainer-started session under neibaur-labs/agent-ops GOVERNANCE.md §11
  (ready, checks green, mergeable, no bypass). Unattended runs never merge.
