#!/bin/sh

# This script is run by Husky on pre-commit.
# It checks if the commit message contains "[skip hooks]".
# If it does, it exits successfully without running tests.
# This is used to prevent the release commit from re-triggering the test suite.

# The commit message is in .git/COMMIT_EDITMSG during the pre-commit phase.
COMMIT_MSG_FILE=".git/COMMIT_EDITMSG"

# Check if the commit message file exists.
if [ ! -f "$COMMIT_MSG_FILE" ]; then
  echo "Could not find commit message file. Running tests by default."
  npm test
  # Exit with the same status code as the test command
  exit $?
fi

# Check the content of the file for our skip phrase.
if grep -q "\[skip hooks\]" "$COMMIT_MSG_FILE"; then
  echo "Release commit detected, skipping pre-commit hooks."
  exit 0
fi

echo "Running pre-commit tests..."
npm test