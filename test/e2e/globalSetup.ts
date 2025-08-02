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

  try {
    // 1. Ensure the local DFX replica is running in the background.

    // 2. Deploy the canisters.
    // This will create new canister IDs for this specific test run.
    console.log('   - Deploying test canisters for the test environment...');
    // We capture stderr to show build output, which can be useful for debugging.
    const deployProcess = execAsync('dfx deploy test_public_mcp_server; dfx deploy test_private_mcp_server');
    deployProcess.child.stderr?.pipe(process.stderr);
    await deployProcess;
    console.log('   - Canisters deployed successfully.');

    // 3. Read the dynamically generated canister IDs.
    // Reading the canister_ids.json file is the most reliable way to get the IDs
    // after a fresh deployment.
    const canisterIdsPath = path.resolve('.dfx', 'local', 'canister_ids.json');
    const canisterIdsJson = await fs.readFile(canisterIdsPath, 'utf-8');
    const canisterIds = JSON.parse(canisterIdsJson);

    const publicCanisterId = canisterIds.test_public_mcp_server?.local;
    const privateCanisterId = canisterIds.test_private_mcp_server?.local;

    // 4. Get the replica port from the running DFX instance.
    const { stdout: portOutput } = await execAsync('dfx info webserver-port');
    const replicaPort = portOutput.trim();
    const replicaUrl = `http://127.0.0.1:${replicaPort}`;

    if (!publicCanisterId || !privateCanisterId || !replicaPort) {
      throw new Error('Failed to get canister IDs or replica port from DFX deployment.');
    }

    // --- Start the Mock Auth Server ---
    const HOST_IP = 'localhost';
    const MOCK_SERVER_PORT = 3001;
    const mockServer = new MockAuthServer(MOCK_SERVER_PORT, HOST_IP);
    await mockServer.start();

    const keyPath = path.join(__dirname, '.test-private-key.json');
    const envPath = path.join(__dirname, '.test.env');

    // --- Save the generated private key to a file ---
    const privateKeyJwk = await jose.exportJWK(mockServer.privateKey);
    await fs.writeFile(keyPath, JSON.stringify(privateKeyJwk));

    // 5. Write the details to a temporary environment file for the tests to use.
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
    console.log(`   - Mock Auth URL: ${mockServer.issuerUrl}`);

    // Return a teardown function that will run after all tests.
    return async () => {
      console.log('\n🧹 Performing global E2E teardown...');
      try {
        // Stop the mock auth server.
        await mockServer.stop();
        console.log(`   - Mock Auth Server stopped.`);

        // We capture stderr to show build output, which can be useful for debugging.
      const deployProcess = execAsync('dfx canister stop test_public_mcp_server && dfx canister delete test_public_mcp_server --no-withdrawal && dfx canister stop test_private_mcp_server && dfx canister delete test_private_mcp_server --no-withdrawal');
      deployProcess.child.stderr?.pipe(process.stderr);
      await deployProcess;
      console.log('   - Canisters stopped and deleted successfully.');

        

        // Clean up temporary files.
        await fs.unlink(envPath);
        await fs.unlink(keyPath);
        console.log('   - Temporary files cleaned up.');
      } catch (error) {
        console.error('Error during teardown:', error);
      } finally {
        console.log('✅ Global E2E teardown complete.');
      }
    };
  } catch (error) {
    console.error('❌ Fatal error during global E2E setup. Aborting tests.');
    console.error(error);
    process.exit(1); // Exit with an error code
  }
}