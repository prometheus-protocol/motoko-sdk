// vitest.config.ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    watch: false,
    projects: [
      {
        test: {
          name: 'e2e-tests',
          // Point to the global setup file
          globalSetup: './test/e2e/globalSetup.ts',
          // Optional: Set a longer timeout for E2E tests
          testTimeout: 60000,
          hookTimeout: 60_000,
          include: ['test/e2e/**/*.test.ts'],
        },
      },
      {
        test: {
          name: 'picjs-tests',
          // Point to the global setup file
          globalSetup: './test/picjs/globalSetup.ts',
          include: ['test/picjs/**/*.test.ts'],
        },
      },
    ],
  },
});
