// scripts/set-version.js

const fs = require('fs');
const path = require('path');

// The new version is passed as the first command-line argument
const newVersion = process.argv[2];
if (!newVersion) {
  console.error('Error: No version specified.');
  process.exit(1);
}

const mopsFilePath = path.join(__dirname, '..', 'mops.toml');
let mopsFileContent;

try {
  mopsFileContent = fs.readFileSync(mopsFilePath, 'utf8');
} catch (err) {
  console.error(`Error: Could not read mops.toml at ${mopsFilePath}`);
  process.exit(1);
}

// Use a regular expression to find and replace the version line.
// This is robust against whitespace changes.
// It looks for 'version', optional whitespace, '=', optional whitespace, and a quoted string.
const updatedContent = mopsFileContent.replace(
  /version\s*=\s*".*"/,
  `version = "${newVersion}"`
);

if (updatedContent === mopsFileContent) {
    console.error(`Error: Could not find 'version = "..."' in ${mopsFilePath} to replace.`);
    process.exit(1);
}

try {
  fs.writeFileSync(mopsFilePath, updatedContent, 'utf8');
  console.log(`Successfully updated mops.toml to version ${newVersion}`);
} catch (err) {
  console.error(`Error: Could not write to mops.toml at ${mopsFilePath}`);
  process.exit(1);
}