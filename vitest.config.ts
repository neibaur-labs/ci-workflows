import { defineConfig } from 'vitest/config';
import type { ProjectConfig } from 'vitest/node';

// tune per project (terminal-run uses 90 for engine packages)
const thresholds = { lines: 80, branches: 80 };

const pkg = (name: string, root: string): ProjectConfig => ({
  test: {
    name,
    root,
    include: ['tests/**/*.test.ts'],
    environment: 'node',
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      thresholds,
    },
  },
});

export default defineConfig({
  test: {
    projects: [pkg('checks', 'packages/checks')],
  },
});
