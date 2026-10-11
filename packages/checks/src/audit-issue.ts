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

export function auditIssue(audit: unknown): AuditIssue {
  throw new Error(`not implemented: ${typeof audit}`);
}
