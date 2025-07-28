// vitest.config.ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Point to the global setup file
    globalSetup: './test/e2e/globalSetup.ts',
    // Optional: Set a longer timeout for E2E tests
    testTimeout: 60000,
    hookTimeout: 60_000,
  },
});