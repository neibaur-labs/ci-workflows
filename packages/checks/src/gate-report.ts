import { auditGate, blockingAdvisories } from './audit-gate.ts';

export interface GateReport {
  /** 0 passes the check, 1 fails it, 2 means the command was called wrongly. */
  readonly exitCode: 0 | 1 | 2;
  /** Lines to print, including GitHub `::error::` and `::warning::` commands. */
  readonly lines: readonly string[];
}

/** Reads and parses one `pnpm audit --json` file; undefined when it cannot. */
export type ReadAudit = (path: string) => unknown;

const USAGE =
  '::error::usage: audit-gate pull-request <base.json> <head.json> | audit-gate branch <head.json>';

function pullRequestReport(base: unknown, head: unknown): GateReport {
  const result = auditGate(base, head);
  if (result.errors.length > 0) {
    return {
      exitCode: 1,
      lines: result.errors.map((error) => `::error::${error}; failing closed.`),
    };
  }
  const lines = [
    ...result.existing.map(
      (key) => `::warning::Advisory already on the base branch (not blocking): ${key}`,
    ),
    ...result.introduced.map(
      (key) => `::error::This change introduces a high or critical advisory: ${key}`,
    ),
  ];
  if (result.fail) return { exitCode: 1, lines };
  return {
    exitCode: 0,
    lines: [...lines, 'Audit gate OK: this change introduces no high or critical advisory.'],
  };
}

function branchReport(head: unknown): GateReport {
  const open = blockingAdvisories(head);
  if (open === null) {
    return {
      exitCode: 1,
      lines: ['::error::pnpm audit returned no advisory data for this branch; failing closed.'],
    };
  }
  return {
    exitCode: 0,
    lines: [
      ...open.map((key) => `::warning::Open advisory on this branch: ${key}`),
      'Not a pull request; nothing to compare.',
    ],
  };
}

/**
 * The audit gate as a command. The mode is explicit so that a missing base
 * file can never be mistaken for "not a pull request" and pass.
 *
 *   pull-request <base.json> <head.json>   compare, fail on what the head adds
 *   branch <head.json>                     report what is open, never fail on it
 */
export function runGate(args: readonly string[], read: ReadAudit): GateReport {
  const [mode, first, second, ...rest] = args;
  if (mode === 'pull-request' && first !== undefined && second !== undefined && rest.length === 0) {
    return pullRequestReport(read(first), read(second));
  }
  if (mode === 'branch' && first !== undefined && second === undefined) {
    return branchReport(read(first));
  }
  return { exitCode: 2, lines: [USAGE] };
}
