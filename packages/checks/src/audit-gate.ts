export interface AuditGateResult {
  /** True when the pull request must not pass the check. */
  readonly fail: boolean;
  /** Advisories on the head that the base does not have. */
  readonly introduced: readonly string[];
  /** Advisories present on both sides. Reported, never blocking. */
  readonly existing: readonly string[];
  /** Reasons the gate failed closed. */
  readonly errors: readonly string[];
}

const BLOCKING_SEVERITIES = new Set<unknown>(['high', 'critical']);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

// A missing id or name prints as "null", as it does in jq.
function label(value: unknown): string {
  return typeof value === 'string' ? value : 'null';
}

/**
 * The high and critical advisories in one `pnpm audit --json` result, each as
 * "<advisory id> <package name>", sorted and without duplicates. The installed
 * version is left out on purpose: moving between two vulnerable versions of a
 * package is not a new advisory.
 *
 * Returns null when the result carries no usable advisory data (pnpm printed
 * an error object, or the shape is not what pnpm prints), so the caller can
 * fail closed.
 */
export function blockingAdvisories(audit: unknown): readonly string[] | null {
  if (!isRecord(audit) || !('advisories' in audit)) return null;
  const advisories = audit.advisories ?? {};
  if (!isRecord(advisories)) return null;

  const keys = new Set<string>();
  for (const advisory of Object.values(advisories)) {
    if (!isRecord(advisory)) return null;
    if (!BLOCKING_SEVERITIES.has(advisory.severity)) continue;
    keys.add(`${label(advisory.github_advisory_id)} ${label(advisory.module_name)}`);
  }
  return [...keys].sort();
}

/**
 * Compares the base branch's audit with the pull request's. The gate fails
 * only for a high or critical advisory the pull request introduces, or when
 * either side has no advisory data.
 */
export function auditGate(base: unknown, head: unknown): AuditGateResult {
  const baseKeys = blockingAdvisories(base);
  const headKeys = blockingAdvisories(head);

  const errors: string[] = [];
  if (baseKeys === null) errors.push('pnpm audit returned no advisory data for the base branch');
  if (headKeys === null) errors.push('pnpm audit returned no advisory data for the pull request');
  if (baseKeys === null || headKeys === null) {
    return { fail: true, introduced: [], existing: [], errors };
  }

  const onBase = new Set(baseKeys);
  const introduced = headKeys.filter((key) => !onBase.has(key));
  const existing = headKeys.filter((key) => onBase.has(key));
  return { fail: introduced.length > 0, introduced, existing, errors };
}
