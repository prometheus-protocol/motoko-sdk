#!/bin/sh

# This script is run by Husky on pre-commit.
# It checks if the SKIP_HOOKS environment variable is set to "true".
# If it is, it exits successfully without running tests.
# This is used to prevent the release commit from re-triggering the test suite in CI.

if [ "$SKIP_HOOKS" = "true" ]; then
  echo "SKIP_HOOKS is set. Skipping pre-commit hooks."
  exit 0
fi

echo "Running pre-commit tests..."
npm test