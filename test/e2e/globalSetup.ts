import * as fs from 'fs/promises';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
import { MockAuthServer } from './mockAuthServer';
import * as jose from 'jose';

const execAsync = promisify(exec);

// This function runs once before all test suites.
export async function setup() {
  console.log('\n🚀 Performing global E2E setup...');

  // 1. Get the canister ID from DFX.
  // This is more robust than reading canister_ids.json directly.
  const { stdout: publicCanisterIdOutput } = await execAsync('dfx canister id public_mcp_server');
  const publicCanisterId = publicCanisterIdOutput.trim();

  const { stdout: privateCanisterIdOutput } = await execAsync('dfx canister id private_mcp_server');
  const privateCanisterId = privateCanisterIdOutput.trim();

  // 2. Get the replica port from DFX.
  const { stdout: portOutput } = await execAsync('dfx info webserver-port');
  const replicaPort = portOutput.trim();
  const replicaUrl = `http://127.0.0.1:${replicaPort}`;

  if (!publicCanisterId || !replicaPort) {
    throw new Error('Failed to get canister ID or replica port from DFX.');
  }

  // --- Start the Mock Auth Server ---
  const HOST_IP = 'localhost'; // Replace with your IP
  const MOCK_SERVER_PORT = 3001;
  const mockServer = new MockAuthServer(MOCK_SERVER_PORT, HOST_IP);
  await mockServer.start();

  const keyPath = path.join(__dirname, '.test-private-key.json');
  const envPath = path.join(__dirname, '.test.env');
  
  // --- Save the generated private key to a file ---
  const privateKeyJwk = await jose.exportJWK(mockServer.privateKey);
  await fs.writeFile(keyPath, JSON.stringify(privateKeyJwk));

  // 3. Write the details to a temporary environment file.
  const envContent = `
E2E_REPLICA_URL=${replicaUrl}
E2E_CANISTER_ID_PUBLIC=${publicCanisterId}
E2E_CANISTER_ID_PRIVATE=${privateCanisterId}
E2E_MOCK_AUTH_SERVER_URL=${mockServer.issuerUrl}
  `;
  await fs.writeFile(envPath, envContent.trim());

  console.log('✅ Global E2E setup complete. Environment is ready.');
  console.log(`   - Canister ID (Public): ${publicCanisterId}`);
  console.log(`   - Canister ID (Private): ${privateCanisterId}`);
  console.log(`   - Replica URL: ${replicaUrl}`);

  // Return a teardown function that will run after all tests.
  return async () => {
    console.log('\n🧹 Performing global E2E teardown...');
    await fs.unlink(envPath);
    console.log('✅ Global E2E teardown complete.');
    await mockServer.stop();
    console.log(`Mock Auth Server stopped at ${mockServer.issuerUrl}`);
    await fs.unlink(keyPath);
    console.log(`Private key file deleted: ${keyPath}`);
    console.log('All temporary files cleaned up.');
  };
}