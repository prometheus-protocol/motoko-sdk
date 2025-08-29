import { describe, test, expect, beforeAll } from 'vitest';
import { fetch } from 'cross-fetch';
import * as dotenv from 'dotenv';
import * as path from 'path';

dotenv.config({ path: path.resolve(__dirname, '.test.env') });

const canisterId = process.env.E2E_CANISTER_ID_PUBLIC!;
const replicaUrl = process.env.E2E_REPLICA_URL!;
const mcpPath = '/mcp';

const createRpcPayload = (method: string, params: any, id: number) => ({
  jsonrpc: '2.0',
  method,
  params,
  id,
});

describe('MCP Resources', () => {
  beforeAll(() => {
    if (!canisterId || !replicaUrl) {
      throw new Error('E2E environment variables not set.');
    }
  });

  test('should list available resources via resources/list', async () => {
    // Arrange: The `resources/list` method takes no parameters.
    const payload = createRpcPayload('resources/list', {}, 1);

    const url = new URL(mcpPath, replicaUrl);
    url.searchParams.set('canisterId', canisterId);

    // Act
    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer FAKE_TOKEN',
      },
      body: JSON.stringify(payload),
    });
    // Assert: Check for a successful response.
    expect(response.status).toBe(200);
    const json = await response.json();

    // Assert the JSON-RPC wrapper is correct.
    expect(json.id).toBe(1);
    expect(json.error).toBeUndefined();

    // Assert the payload (`result`) is correct.
    const result = json.result;
    expect(Array.isArray(result.resources)).toBe(true);
    expect(result.resources.length).toBe(2);

    // Assert the content of the first resource matches our canister state.
    const firstResource = result.resources[0];
    expect(firstResource.uri).toBe('file:///main.py');
    expect(firstResource.name).toBe('main.py');
    expect(firstResource.description).toBe(
      'Contains the main logic of the application.',
    );
  });

  test('should read the content of a specific resource via resources/read', async () => {
    // Arrange
    const params = { uri: 'file:///main.py' };
    const payload = createRpcPayload('resources/read', params, 2);
    const url = new URL(mcpPath, replicaUrl);
    url.searchParams.set('canisterId', canisterId);

    // Act
    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer FAKE_TOKEN',
      },
      body: JSON.stringify(payload),
    });

    // Assert: Check for a successful response.
    expect(response.status).toBe(200);
    const json = await response.json();

    // Assert the JSON-RPC wrapper is correct.
    expect(json.id).toBe(2);
    expect(json.error).toBeUndefined();

    // Assert the spec-compliant payload (`result`).
    const result = json.result;
    expect(Array.isArray(result.contents)).toBe(true);
    expect(result.contents.length).toBe(1);

    // Assert the content of the first content block.
    const contentBlock = result.contents[0];
    expect(contentBlock.uri).toBe('file:///main.py');
    expect(contentBlock.name).toBe('main.py');
    expect(contentBlock.mimeType).toBe('text/x-python');
    expect(contentBlock.text).toBe("print('Hello from main.py!')");
  });
});
