import { describe, test, expect, beforeAll } from 'vitest';
import { fetch } from 'cross-fetch';
import * as dotenv from 'dotenv';
import * as path from 'path';

dotenv.config({ path: path.resolve(__dirname, '.test.env') });

// --- Test Configuration ---
const canisterId = process.env.E2E_CANISTER_ID_PUBLIC!;
const replicaUrl = process.env.E2E_REPLICA_URL!;
const mcpPath = '/mcp';

// Helper to create a valid JSON-RPC request payload.
const createRpcPayload = (method: string, params: any, id: number) => ({
  jsonrpc: '2.0',
  method,
  params,
  id,
});

// --- Test Suite ---
describe('MCP Lifecycle', () => {
  beforeAll(() => {
    if (!canisterId || !replicaUrl) {
      throw new Error('E2E environment variables not set.');
    }
  });

  test('should handle the initialize handshake', async () => {
    // Arrange: Construct the `initialize` request payload according to the spec.
    const initializeParams = {
      protocolVersion: '2025-06-18',
      capabilities: {
        roots: {},
        sampling: {},
        elicitation: {},
      },
      clientInfo: {
        name: 'E2ETestClient',
        title: 'E2E Test Client',
        version: '0.1.0',
      },
    };
    const payload = createRpcPayload('initialize', initializeParams, 1);

    // Construct the fetch URL and options
    const url = new URL(mcpPath, replicaUrl);
    url.searchParams.set('canisterId', canisterId);

    // Act: Send the request to the canister.
    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer FAKE_TOKEN',
      },
      body: JSON.stringify(payload),
    });

    // Assert: Check the successful response.
    expect(response.status).toBe(200);
    const json = await response.json();

    // --- NEW ASSERTIONS ---
    expect(json.id).toBe(1);
    expect(json.error).toBeUndefined(); // No error should be present.

    const result = json.result;
    expect(result.protocolVersion).toBe('2025-06-18');
    expect(result.serverInfo.name).toBe('MCP-Motoko-Server');
  });

  test('should accept the initialized notification', async () => {
    // Arrange: The 'initialized' notification has no params.
    // Its method name is special: "notifications/initialized".
    const payload = {
      jsonrpc: '2.0',
      method: 'notifications/initialized',
      // No 'id' or 'params' for a notification
    };

    const url = new URL(mcpPath, replicaUrl);
    url.searchParams.set('canisterId', canisterId);

    // Act: Send the notification.
    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer FAKE_TOKEN',
      },
      body: JSON.stringify(payload),
    });

    // Assert: The server accepted the notification successfully.
    expect(response.status).toBe(200);
    const json = await response.json();

    // The server sends a null result, which the client ignores.
    // The important part is that there is no `error` field.
    expect(json.result).toBeNull();
    expect(json.error).toBeUndefined();
  });
});