import * as fs from 'fs/promises';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

// This function runs once before all test suites.
export async function setup() {
  console.log('\n🚀 Performing global E2E setup...');

  // 1. Get the canister ID from DFX.
  // This is more robust than reading canister_ids.json directly.
  const { stdout: canisterIdOutput } = await execAsync('dfx canister id mcp_server');
  const canisterId = canisterIdOutput.trim();

  // 2. Get the replica port from DFX.
  const { stdout: portOutput } = await execAsync('dfx info webserver-port');
  const replicaPort = portOutput.trim();
  const replicaUrl = `http://127.0.0.1:${replicaPort}`;

  if (!canisterId || !replicaPort) {
    throw new Error('Failed to get canister ID or replica port from DFX.');
  }

  // 3. Write the details to a temporary environment file.
  const envContent = `
E2E_REPLICA_URL=${replicaUrl}
E2E_CANISTER_ID=${canisterId}
  `;
  const envPath = path.join(__dirname, '.test.env');
  await fs.writeFile(envPath, envContent.trim());

  console.log('✅ Global E2E setup complete. Environment is ready.');
  console.log(`   - Canister ID: ${canisterId}`);
  console.log(`   - Replica URL: ${replicaUrl}`);

  // Return a teardown function that will run after all tests.
  return async () => {
    console.log('\n🧹 Performing global E2E teardown...');
    await fs.unlink(envPath);
    console.log('✅ Global E2E teardown complete.');
  };
}