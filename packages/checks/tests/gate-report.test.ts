import { describe, expect, test } from 'vitest';
import { runGate } from '../src/gate-report.ts';

const advisory = (id: string, moduleName: string, severity = 'high') => ({
  github_advisory_id: id,
  module_name: moduleName,
  severity,
});

const audit = (...advisories: ReturnType<typeof advisory>[]) => ({
  advisories: Object.fromEntries(advisories.map((entry, index) => [String(1000 + index), entry])),
});

const first = advisory('GHSA-aaaa-aaaa-aaaa', 'left-pad-fixture');
const second = advisory('GHSA-bbbb-bbbb-bbbb', 'right-pad-fixture', 'critical');

// Stands in for reading files: a path that is not listed cannot be read.
const files = (contents: Record<string, unknown>) => (path: string) => contents[path];

describe('runGate pull-request', () => {
  test('passes when the pull request introduces nothing', () => {
    const read = files({ 'base.json': audit(), 'head.json': audit() });

    expect(runGate(['pull-request', 'base.json', 'head.json'], read)).toEqual({
      exitCode: 0,
      lines: ['Audit gate OK: this change introduces no high or critical advisory.'],
    });
  });

  test('fails and names each advisory the pull request introduces', () => {
    const read = files({ 'base.json': audit(), 'head.json': audit(second, first) });

    expect(runGate(['pull-request', 'base.json', 'head.json'], read)).toEqual({
      exitCode: 1,
      lines: [
        '::error::This change introduces a high or critical advisory: GHSA-aaaa-aaaa-aaaa left-pad-fixture',
        '::error::This change introduces a high or critical advisory: GHSA-bbbb-bbbb-bbbb right-pad-fixture',
      ],
    });
  });

  test('warns about an advisory already on the base branch and passes', () => {
    const read = files({ 'base.json': audit(first), 'head.json': audit(first) });

    expect(runGate(['pull-request', 'base.json', 'head.json'], read)).toEqual({
      exitCode: 0,
      lines: [
        '::warning::Advisory already on the base branch (not blocking): GHSA-aaaa-aaaa-aaaa left-pad-fixture',
        'Audit gate OK: this change introduces no high or critical advisory.',
      ],
    });
  });

  test('warns about the existing advisory and fails on the new one', () => {
    const read = files({ 'base.json': audit(first), 'head.json': audit(first, second) });

    expect(runGate(['pull-request', 'base.json', 'head.json'], read)).toEqual({
      exitCode: 1,
      lines: [
        '::warning::Advisory already on the base branch (not blocking): GHSA-aaaa-aaaa-aaaa left-pad-fixture',
        '::error::This change introduces a high or critical advisory: GHSA-bbbb-bbbb-bbbb right-pad-fixture',
      ],
    });
  });

  test('fails closed when the head file cannot be read', () => {
    const read = files({ 'base.json': audit() });

    expect(runGate(['pull-request', 'base.json', 'head.json'], read)).toEqual({
      exitCode: 1,
      lines: [
        '::error::pnpm audit returned no advisory data for the pull request; failing closed.',
      ],
    });
  });

  test('fails closed when the base audit is an error object', () => {
    const read = files({ 'base.json': { error: { code: 'ERR_FIXTURE' } }, 'head.json': audit() });

    expect(runGate(['pull-request', 'base.json', 'head.json'], read)).toEqual({
      exitCode: 1,
      lines: ['::error::pnpm audit returned no advisory data for the base branch; failing closed.'],
    });
  });

  test('reads the base from the first path and the head from the second', () => {
    const read = files({ 'one.json': audit(first), 'two.json': audit() });

    expect(runGate(['pull-request', 'one.json', 'two.json'], read).exitCode).toBe(0);
    expect(runGate(['pull-request', 'two.json', 'one.json'], read).exitCode).toBe(1);
  });
});

describe('runGate branch', () => {
  test('warns about open advisories and passes, with nothing to compare', () => {
    const read = files({ 'head.json': audit(first) });

    expect(runGate(['branch', 'head.json'], read)).toEqual({
      exitCode: 0,
      lines: [
        '::warning::Open advisory on this branch: GHSA-aaaa-aaaa-aaaa left-pad-fixture',
        'Not a pull request; nothing to compare.',
      ],
    });
  });

  test('passes quietly on a clean branch', () => {
    expect(runGate(['branch', 'head.json'], files({ 'head.json': audit() }))).toEqual({
      exitCode: 0,
      lines: ['Not a pull request; nothing to compare.'],
    });
  });

  test('fails closed when the audit cannot be read', () => {
    expect(runGate(['branch', 'head.json'], files({}))).toEqual({
      exitCode: 1,
      lines: ['::error::pnpm audit returned no advisory data for this branch; failing closed.'],
    });
  });
});

describe('runGate usage', () => {
  // A missing base path must never be read as "not a pull request".
  test.each([
    [[]],
    [['pull-request']],
    [['pull-request', 'base.json']],
    [['pull-request', 'base.json', 'head.json', 'extra.json']],
    [['branch']],
    [['branch', 'head.json', 'base.json']],
    [['head.json', 'base.json']],
  ])('rejects %j with exit code 2', (args) => {
    const report = runGate(args, files({ 'base.json': audit(), 'head.json': audit() }));

    expect(report.exitCode).toBe(2);
    expect(report.lines).toEqual([
      '::error::usage: audit-gate pull-request <base.json> <head.json> | audit-gate branch <head.json>',
    ]);
  });
});
