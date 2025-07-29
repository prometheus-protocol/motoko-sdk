#!/bin/sh

# This script is run by Husky on pre-commit.
# It checks if the commit message contains "[skip hooks]".
# If it does, it exits successfully without running tests.
# This is used to prevent the release commit from re-triggering the test suite.

# The commit message file path is passed as the first argument by the git hook.
COMMIT_MSG_FILE=$1

if grep -q "\[skip hooks\]" "$COMMIT_MSG_FILE"; then
  echo "Release commit detected, skipping pre-commit hooks."
  exit 0
fi

echo "Running pre-commit tests..."
# This command runs the actual tests.
# It assumes you have a "test" script in your package.json.
npm test