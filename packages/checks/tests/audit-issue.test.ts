import { describe, expect, test } from 'vitest';
import { auditIssue } from '../src/audit-issue.ts';

interface Entry {
  github_advisory_id: string;
  module_name: string;
  severity: string;
  patched_versions?: string;
  findings?: { version: string }[];
}

const audit = (...entries: Entry[]) => ({
  advisories: Object.fromEntries(entries.map((entry, index) => [String(1000 + index), entry])),
});

const high: Entry = {
  github_advisory_id: 'GHSA-aaaa-aaaa-aaaa',
  module_name: 'left-pad-fixture',
  severity: 'high',
  patched_versions: '>=1.2.0',
  findings: [{ version: '1.1.0' }, { version: '1.0.0' }, { version: '1.1.0' }],
};
const critical: Entry = {
  github_advisory_id: 'GHSA-bbbb-bbbb-bbbb',
  module_name: 'right-pad-fixture',
  severity: 'critical',
  patched_versions: '>=2.0.1',
  findings: [{ version: '2.0.0' }],
};
const moderate: Entry = {
  github_advisory_id: 'GHSA-cccc-cccc-cccc',
  module_name: 'pad-fixture',
  severity: 'moderate',
  patched_versions: '>=3.1.0',
  findings: [{ version: '3.0.0' }],
};
const low: Entry = {
  github_advisory_id: 'GHSA-dddd-dddd-dddd',
  module_name: 'another-fixture',
  severity: 'low',
  patched_versions: '<0.0.0',
  findings: [{ version: '0.5.0' }],
};

const open = (value: unknown) => {
  const result = auditIssue(value);
  if (result.status !== 'open') throw new Error(`expected open, got ${result.status}`);
  return result;
};

describe('auditIssue', () => {
  test('reports clean when there are no advisories', () => {
    expect(auditIssue(audit())).toEqual({ status: 'clean', key: 'clean' });
    expect(auditIssue({ advisories: null })).toEqual({ status: 'clean', key: 'clean' });
  });

  test.each([
    ['an error object', { error: { code: 'ERR_FIXTURE' } }],
    ['undefined', undefined],
    ['advisories that is not an object', { advisories: 'none' }],
    ['an advisory that is not an object', { advisories: { '1000': 'broken' } }],
  ])('reports no data for %s', (_name, value) => {
    expect(auditIssue(value)).toEqual({ status: 'no-data' });
  });

  test('lists a high advisory with its installed versions and the 7-day rule', () => {
    const result = open(audit(high));

    expect(result.blocking).toBe(true);
    expect(result.body).toContain('### High and critical: fix within 7 days');
    expect(result.body).toContain(
      '| `left-pad-fixture` | high | GHSA-aaaa-aaaa-aaaa | 1.0.0, 1.1.0 | >=1.2.0 |',
    );
    expect(result.body).not.toContain('### Moderate and low');
  });

  test('lists moderate and low advisories in their own section, not as blocking', () => {
    const result = open(audit(moderate, low));

    expect(result.blocking).toBe(false);
    expect(result.body).toContain('### Moderate and low: fix within 30 days');
    expect(result.body).toContain(
      '| `pad-fixture` | moderate | GHSA-cccc-cccc-cccc | 3.0.0 | >=3.1.0 |',
    );
    expect(result.body).toContain(
      '| `another-fixture` | low | GHSA-dddd-dddd-dddd | 0.5.0 | <0.0.0 |',
    );
    expect(result.body).not.toContain('### High and critical');
  });

  test('puts both sections in one body, most severe first', () => {
    const body = open(audit(low, moderate, high, critical)).body;
    const order = ['right-pad-fixture', 'left-pad-fixture', 'pad-fixture', 'another-fixture'].map(
      (name) => body.indexOf(`\`${name}\``),
    );

    expect(order.every((position) => position >= 0)).toBe(true);
    expect([...order].sort((a, b) => a - b)).toEqual(order);
    expect(body.indexOf('### High and critical')).toBeLessThan(
      body.indexOf('### Moderate and low'),
    );
  });

  test('ignores the info severity', () => {
    expect(auditIssue(audit({ ...low, severity: 'info' }))).toEqual({
      status: 'clean',
      key: 'clean',
    });
  });

  test('prints a dash for a missing patched version and missing findings', () => {
    const body = open(
      audit({
        github_advisory_id: 'GHSA-eeee-eeee-eeee',
        module_name: 'bare-fixture',
        severity: 'high',
      }),
    ).body;

    expect(body).toContain('| `bare-fixture` | high | GHSA-eeee-eeee-eeee | - | - |');
  });

  test('lists the same advisory once when pnpm reports it under two ids', () => {
    const body = open(audit(high, high)).body;

    expect(body.split('GHSA-aaaa-aaaa-aaaa').length - 1).toBe(1);
  });

  test('gives the same key for the same advisories in any order', () => {
    expect(open(audit(high, moderate)).key).toBe(open(audit(moderate, high)).key);
  });

  test('changes the key when an advisory is added, removed, or changes version', () => {
    const base = open(audit(high, moderate)).key;

    expect(open(audit(high)).key).not.toBe(base);
    expect(open(audit(high, moderate, low)).key).not.toBe(base);
    expect(open(audit({ ...high, findings: [{ version: '1.1.1' }] }, moderate)).key).not.toBe(base);
  });

  test('uses a key that is safe inside an HTML comment and is never "clean"', () => {
    const key = open(audit(high)).key;

    expect(key).toMatch(/^[0-9a-f]{8}$/);
  });
});
