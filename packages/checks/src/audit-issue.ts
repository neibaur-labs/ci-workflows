export type AuditIssue =
  /** pnpm audit returned no usable advisory data: the caller fails closed. */
  | { readonly status: 'no-data' }
  /** Nothing is open. */
  | { readonly status: 'clean'; readonly key: 'clean' }
  | {
      readonly status: 'open';
      /** True when a high or critical advisory is open. */
      readonly blocking: boolean;
      /** Changes only when the set of open advisories changes. */
      readonly key: string;
      /** Markdown for the tracking issue, without the key marker. */
      readonly body: string;
    };

interface Row {
  readonly rank: number;
  readonly line: string;
}

// Most severe first. Anything else, such as "info", is not reported.
const RANK = new Map<unknown, number>([
  ['critical', 0],
  ['high', 1],
  ['moderate', 2],
  ['low', 3],
]);
const BLOCKING_BELOW = 2;
const HEADER = [
  '| Package | Severity | Advisory | Installed | Patched |',
  '| --- | --- | --- | --- | --- |',
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function text(value: unknown): string {
  return typeof value === 'string' && value !== '' ? value : '-';
}

function installed(findings: unknown): string {
  if (!Array.isArray(findings)) return '-';
  const versions = new Set<string>();
  for (const finding of findings) {
    if (isRecord(finding) && typeof finding.version === 'string') versions.add(finding.version);
  }
  return versions.size > 0 ? [...versions].sort().join(', ') : '-';
}

// FNV-1a, 32 bit. A short fingerprint of the rows, not a security measure.
function fingerprint(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

/**
 * Turns one `pnpm audit --json` result into the body of the weekly tracking
 * issue. High and critical advisories carry the 7-day deadline; moderate and
 * low ones are listed with a 30-day target and are never gated.
 */
export function auditIssue(audit: unknown): AuditIssue {
  if (!isRecord(audit) || !('advisories' in audit)) return { status: 'no-data' };
  const advisories = audit.advisories ?? {};
  if (!isRecord(advisories)) return { status: 'no-data' };

  const rows = new Map<string, Row>();
  for (const advisory of Object.values(advisories)) {
    if (!isRecord(advisory)) return { status: 'no-data' };
    const rank = RANK.get(advisory.severity);
    if (rank === undefined) continue;
    const line = `| \`${text(advisory.module_name)}\` | ${text(advisory.severity)} | ${text(
      advisory.github_advisory_id,
    )} | ${installed(advisory.findings)} | ${text(advisory.patched_versions)} |`;
    rows.set(line, { rank, line });
  }
  if (rows.size === 0) return { status: 'clean', key: 'clean' };

  const sorted = [...rows.values()].sort(
    (a, b) => a.rank - b.rank || (a.line < b.line ? -1 : a.line > b.line ? 1 : 0),
  );
  const blocking = sorted.filter((row) => row.rank < BLOCKING_BELOW).map((row) => row.line);
  const other = sorted.filter((row) => row.rank >= BLOCKING_BELOW).map((row) => row.line);

  const sections = ['The weekly audit of `pnpm-lock.yaml` on the default branch reports:'];
  if (blocking.length > 0) {
    sections.push(
      '### High and critical: fix within 7 days of a patched version',
      [...HEADER, ...blocking].join('\n'),
      'These do not block unrelated pull requests. An advisory fix is exempt from the 7-day release age (see the dependency rules in `AGENTS.md`).',
    );
  }
  if (other.length > 0) {
    sections.push(
      '### Moderate and low: fix within 30 days',
      [...HEADER, ...other].join('\n'),
      'These are listed so they have an owner. No check is gated on them.',
    );
  }
  return {
    status: 'open',
    blocking: blocking.length > 0,
    key: fingerprint(sorted.map((row) => row.line).join('\n')),
    body: sections.join('\n\n'),
  };
}
