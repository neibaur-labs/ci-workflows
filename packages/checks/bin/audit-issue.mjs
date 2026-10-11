// Command-line entry for the weekly dependency audit. All decisions are in
// ../src/audit-issue.ts, which is tested; this file reads the audit file,
// writes the issue body, and prints three lines for the calling shell:
//
//   status=clean|open|no-data
//   blocking=true|false
//   key=<fingerprint of the open advisories, or "clean">
//
//   node packages/checks/bin/audit-issue.mjs <audit.json> <body.md>
//
// Needs Node 22.18 or later, which runs the TypeScript source directly.
import { readFileSync, writeFileSync } from 'node:fs';
import process from 'node:process';
import { auditIssue } from '../src/audit-issue.ts';

const [auditPath, bodyPath] = process.argv.slice(2);
if (auditPath === undefined || bodyPath === undefined || process.argv.length !== 4) {
  process.stdout.write('::error::usage: audit-issue <audit.json> <body.md>\n');
  process.exit(2);
}

let audit;
try {
  audit = JSON.parse(readFileSync(auditPath, 'utf8'));
} catch {
  audit = undefined;
}

const result = auditIssue(audit);
if (result.status === 'open') writeFileSync(bodyPath, `${result.body}\n`);
process.stdout.write(`status=${result.status}\n`);
process.stdout.write(
  `blocking=${result.status === 'open' && result.blocking ? 'true' : 'false'}\n`,
);
process.stdout.write(`key=${result.status === 'no-data' ? '' : result.key}\n`);
