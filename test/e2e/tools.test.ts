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

describe('MCP Tools', () => {
  beforeAll(() => {
    if (!canisterId || !replicaUrl) {
      throw new Error('E2E environment variables not set.');
    }
  });

  test('should list available tools via tools/list', async () => {
    // Arrange: The `tools/list` method takes no parameters.
    const payload = createRpcPayload('tools/list', {}, 1);

    const url = new URL(mcpPath, replicaUrl);
    url.searchParams.set('canisterId', canisterId);

    // Act
    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer FAKE_TOKEN',
      },
      body: JSON.stringify(payload),
    });

    // Assert: Check for a successful response.
    expect(response.status).toBe(200);
    const json = await response.json();

    // Assert the JSON-RPC wrapper is correct.
    expect(json.id).toBe(1);
    expect(json.error).toBeUndefined();

    // Assert the payload (`result`).
    // The spec says the result is an object with a `tools` key.
    const result = json.result;

    expect(Array.isArray(result.tools)).toBe(true);
    expect(result.tools.length).toBe(1);

    // Assert the content of the first tool.
    const weatherTool = result.tools[0];
    expect(weatherTool.name).toBe('get_weather');
    expect(weatherTool.description).toBe('Get current weather information for a location');

    expect(weatherTool.outputSchema).toBeDefined();
    expect(weatherTool.outputSchema.type).toBe('object');
    expect(weatherTool.outputSchema.properties.report.type).toBe('string');
    
    // Assert the schema is correct.
    expect(weatherTool.inputSchema.type).toBe('object');
    expect(weatherTool.inputSchema.properties.location.type).toBe('string');
    expect(weatherTool.inputSchema.required[0]).toBe('location');
  });

  test('should call a tool with arguments via tools/call', async () => {
    // Arrange: The `tools/call` method takes a tool name and arguments.
    const params = {
      name: 'get_weather',
      arguments: {
        location: 'Tokyo',
      },
    };
    const payload = createRpcPayload('tools/call', params, 2);

    const url = new URL(mcpPath, replicaUrl);
    url.searchParams.set('canisterId', canisterId);

    // Act
    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer FAKE_TOKEN',
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
    expect(result.isError).toBe(false);
    expect(Array.isArray(result.content)).toBe(true);
    expect(result.content.length).toBe(1);

    // Assert the content of the first content block.
    const contentBlock = result.content[0];
    expect(contentBlock.type).toBe('text');
    expect(contentBlock.text).toContain('Tokyo');
    expect(contentBlock.text).toContain('sunny');
  });

  test('should return a protocol error for an unknown tool', async () => {
    // Arrange
    const params = { name: 'get_stock_price', arguments: { ticker: 'ACME' } };
    const payload = createRpcPayload('tools/call', params, 3);
    const url = new URL(mcpPath, replicaUrl);
    url.searchParams.set('canisterId', canisterId);

    // Act
    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer FAKE_TOKEN',
      },
      body: JSON.stringify(payload),
    });

    // Assert
    expect(response.status).toBe(200);
    const json = await response.json();
    // Assert this is a proper JSON-RPC protocol error, not a tool result.
    expect(json.result).toBeUndefined();
    expect(json.error).toBeDefined();
    expect(json.error.code).toBe(-32602); // "Invalid params" is the code our server uses for handler #err results.
    expect(json.error.message).toContain('Unknown tool: get_stock_price');
  });

});