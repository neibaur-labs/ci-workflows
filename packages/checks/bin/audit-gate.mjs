// Command-line entry for the audit gate. All decisions are in
// ../src/gate-report.ts, which is tested; this file only reads the two
// `pnpm audit --json` files and prints the result.
//
//   node packages/checks/bin/audit-gate.mjs pull-request <base.json> <head.json>
//   node packages/checks/bin/audit-gate.mjs branch <head.json>
//
// Needs Node 22.18 or later, which runs the TypeScript source directly.
import { readFileSync } from 'node:fs';
import process from 'node:process';
import { runGate } from '../src/gate-report.ts';

// A file that is missing or is not JSON reads as undefined, which the gate
// treats as "no advisory data" and fails closed.
const read = (path) => {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return undefined;
  }
};

const report = runGate(process.argv.slice(2), read);
for (const line of report.lines) process.stdout.write(`${line}\n`);
process.exitCode = report.exitCode;
