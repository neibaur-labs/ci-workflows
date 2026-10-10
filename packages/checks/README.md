# checks

The decision logic of the `audit-gate` action, as tested code.

- `src/audit-gate.ts` compares two `pnpm audit --json` results, the base branch
  and the pull request, and reports the high or critical advisories the pull
  request introduces. It runs no process and reads no file: the caller
  supplies the parsed JSON.
- `src/gate-report.ts` turns that result into the lines the check prints and
  its exit code.
- `bin/audit-gate.mjs` is the command the action calls. It reads the two files
  and prints the report. It needs Node 22.18 or later.

  ```sh
  node packages/checks/bin/audit-gate.mjs pull-request base.json head.json
  node packages/checks/bin/audit-gate.mjs branch head.json
  ```
