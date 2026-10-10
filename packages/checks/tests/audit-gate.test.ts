import { describe, expect, test } from 'vitest';
import { auditGate, blockingAdvisories } from '../src/audit-gate.ts';

interface Advisory {
  github_advisory_id?: string;
  module_name?: string;
  severity: string;
  vulnerable_versions?: string;
}

// The shape `pnpm audit --json` prints: advisories keyed by a numeric id.
const audit = (...advisories: Advisory[]) => ({
  advisories: Object.fromEntries(advisories.map((entry, index) => [String(1000 + index), entry])),
  metadata: { vulnerabilities: {} },
});

const advisory = (id: string, moduleName: string, severity = 'high'): Advisory => ({
  github_advisory_id: id,
  module_name: moduleName,
  severity,
});

const first = advisory('GHSA-aaaa-aaaa-aaaa', 'left-pad-fixture');
const second = advisory('GHSA-bbbb-bbbb-bbbb', 'right-pad-fixture');

describe('auditGate', () => {
  test('passes when both sides are clean', () => {
    expect(auditGate(audit(), audit())).toEqual({
      fail: false,
      introduced: [],
      existing: [],
      errors: [],
    });
  });

  test('fails and names the advisory a pull request adds to a clean base', () => {
    const result = auditGate(audit(), audit(first));

    expect(result.fail).toBe(true);
    expect(result.introduced).toEqual(['GHSA-aaaa-aaaa-aaaa left-pad-fixture']);
    expect(result.existing).toEqual([]);
  });

  test('passes and reports an advisory that is on both sides', () => {
    const result = auditGate(audit(first), audit(first));

    expect(result.fail).toBe(false);
    expect(result.introduced).toEqual([]);
    expect(result.existing).toEqual(['GHSA-aaaa-aaaa-aaaa left-pad-fixture']);
  });

  test('fails and names only the new advisory when the base already has one', () => {
    const result = auditGate(audit(first), audit(first, second));

    expect(result.fail).toBe(true);
    expect(result.introduced).toEqual(['GHSA-bbbb-bbbb-bbbb right-pad-fixture']);
    expect(result.existing).toEqual(['GHSA-aaaa-aaaa-aaaa left-pad-fixture']);
  });

  test('fails on a second advisory against a package that is already flagged', () => {
    const other = advisory('GHSA-bbbb-bbbb-bbbb', 'left-pad-fixture');
    const result = auditGate(audit(first), audit(first, other));

    expect(result.fail).toBe(true);
    expect(result.introduced).toEqual(['GHSA-bbbb-bbbb-bbbb left-pad-fixture']);
  });

  test('passes when the pull request fixes an advisory', () => {
    expect(auditGate(audit(first), audit())).toEqual({
      fail: false,
      introduced: [],
      existing: [],
      errors: [],
    });
  });

  test.each(['moderate', 'low', 'info'])('ignores a new %s advisory', (severity) => {
    const result = auditGate(
      audit(),
      audit(advisory('GHSA-cccc-cccc-cccc', 'pad-fixture', severity)),
    );

    expect(result.fail).toBe(false);
    expect(result.introduced).toEqual([]);
  });

  test('fails on a new critical advisory', () => {
    const result = auditGate(
      audit(),
      audit(advisory('GHSA-cccc-cccc-cccc', 'pad-fixture', 'critical')),
    );

    expect(result.fail).toBe(true);
    expect(result.introduced).toEqual(['GHSA-cccc-cccc-cccc pad-fixture']);
  });

  test('treats a different vulnerable version of a flagged package as existing', () => {
    const base = audit({ ...first, vulnerable_versions: '<1.2.0' });
    const head = audit({ ...first, vulnerable_versions: '<1.3.0' });
    const result = auditGate(base, head);

    expect(result.fail).toBe(false);
    expect(result.existing).toEqual(['GHSA-aaaa-aaaa-aaaa left-pad-fixture']);
  });

  test('lists each advisory once, in sorted order', () => {
    const result = auditGate(audit(), audit(second, first, second));

    expect(result.introduced).toEqual([
      'GHSA-aaaa-aaaa-aaaa left-pad-fixture',
      'GHSA-bbbb-bbbb-bbbb right-pad-fixture',
    ]);
  });

  test('fails closed when the head audit is an error object', () => {
    const result = auditGate(audit(), { error: { code: 'ERR_PNPM_AUDIT_BAD_RESPONSE' } });

    expect(result.fail).toBe(true);
    expect(result.introduced).toEqual([]);
    expect(result.errors).toEqual(['pnpm audit returned no advisory data for the pull request']);
  });

  test('fails closed when the base audit is an error object', () => {
    const result = auditGate({ error: { code: 'ERR_PNPM_AUDIT_BAD_RESPONSE' } }, audit(first));

    expect(result.fail).toBe(true);
    expect(result.errors).toEqual(['pnpm audit returned no advisory data for the base branch']);
  });

  test('reports both sides when neither audit has advisory data', () => {
    expect(auditGate(undefined, 'not json').errors).toEqual([
      'pnpm audit returned no advisory data for the base branch',
      'pnpm audit returned no advisory data for the pull request',
    ]);
  });
});

describe('blockingAdvisories', () => {
  test('lists open high and critical advisories for a push with no base', () => {
    const head = audit(first, advisory('GHSA-cccc-cccc-cccc', 'pad-fixture', 'moderate'));

    expect(blockingAdvisories(head)).toEqual(['GHSA-aaaa-aaaa-aaaa left-pad-fixture']);
  });

  test('returns an empty list when advisories is null', () => {
    expect(blockingAdvisories({ advisories: null })).toEqual([]);
  });

  test('keeps an advisory that has no GitHub id or package name', () => {
    expect(blockingAdvisories(audit({ severity: 'high' }))).toEqual(['null null']);
  });

  test.each([
    ['null', null],
    ['an array', []],
    ['an object without advisories', { metadata: {} }],
    ['advisories that is not an object', { advisories: 'none' }],
    ['advisories that is an array', { advisories: [] }],
    ['an advisory that is not an object', { advisories: { '1000': 'broken' } }],
  ])('returns null for %s', (_name, value) => {
    expect(blockingAdvisories(value)).toBeNull();
  });
});
