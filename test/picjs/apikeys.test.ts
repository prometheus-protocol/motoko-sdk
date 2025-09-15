import path from 'node:path';
import { PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@dfinity/candid';
import type { Actor } from '@dfinity/pic';
import { AnonymousIdentity, Identity } from '@dfinity/agent';
import { Principal } from '@dfinity/principal';
import { describe, it, expect, beforeAll, inject, afterAll } from 'vitest';

// --- Import Declarations ---
// Make sure the canister name here matches your dfx.json (e.g., 'test_api_key_mcp_server')
import {
  idlFactory as mcpServerIdlFactory,
  init as mcpServerInit,
} from '../../.dfx/local/canisters/test_api_key_mcp_server/service.did.js';
import type { _SERVICE as McpServerService } from '../../.dfx/local/canisters/test_api_key_mcp_server/service.did.js';

// --- Wasm Path ---
const MCP_SERVER_WASM_PATH = path.resolve(
  __dirname,
  '../../',
  '.dfx/local/canisters/test_api_key_mcp_server/test_api_key_mcp_server.wasm',
);

// --- Identities ---
const ownerIdentity: Identity = createIdentity('server-owner-principal');
const userIdentity: Identity = createIdentity('user-principal');

describe('MCP Server API Key Authentication', () => {
  let pic: PocketIc;
  let serverActor: Actor<McpServerService>;
  let serverCanisterId: Principal;

  beforeAll(async () => {
    const url = inject('PIC_URL');
    pic = await PocketIc.create(url);

    // Deploy only the MCP Server Canister for this focused test
    const serverFixture = await pic.setupCanister<McpServerService>({
      idlFactory: mcpServerIdlFactory,
      wasm: MCP_SERVER_WASM_PATH,
      sender: ownerIdentity.getPrincipal(),
      // The test server's init function takes no arguments
      arg: IDL.encode(mcpServerInit({ IDL }), []),
    });
    serverActor = serverFixture.actor;
    serverCanisterId = serverFixture.canisterId;
  });

  afterAll(async () => {
    await pic.tearDown();
  });

  it('should allow a tool call using a valid API key', async () => {
    // 1. As the server owner, create a new API key.
    // This key will be associated with the `userIdentity` principal.
    serverActor.setIdentity(ownerIdentity);
    const apiKey = await serverActor.create_api_key_for_testing(
      'Test Runner Key',
      ['test:scope'],
    );

    console.log('Generated API Key:', apiKey);

    expect(apiKey).toBeTypeOf('string');
    expect(apiKey.length).toBeGreaterThan(32);

    // 2. Prepare the JSON-RPC payload for the tool call.
    const rpcPayload = {
      jsonrpc: '2.0',
      method: 'tools/call',
      params: { name: 'get_weather', arguments: { location: 'Tokyo' } },
      id: 'api-key-test-1',
    };
    const body = new TextEncoder().encode(JSON.stringify(rpcPayload));

    // 3. Make the HTTP request with the 'x-api-key' header.
    // No identity is needed on the actor for this call, as auth is in the header.
    serverActor.setIdentity(new AnonymousIdentity());
    const httpResponse = await serverActor.http_request_update({
      method: 'POST',
      url: '/mcp',
      headers: [
        ['Content-Type', 'application/json'],
        ['x-api-key', apiKey], // Use the generated API key
      ],
      body,
      certificate_version: [],
    });

    // 4. Assert the response is successful.
    expect(httpResponse.status_code).toBe(200);
    const responseBody = JSON.parse(
      new TextDecoder().decode(httpResponse.body as Uint8Array),
    );
    expect(responseBody.result.isError).toBe(false);
    expect(responseBody.result.content[0].text).toContain('sunny');
  });

  it('should reject a tool call with an invalid API key', async () => {
    const rpcPayload = {
      jsonrpc: '2.0',
      method: 'tools/call',
      params: { name: 'get_weather', arguments: { location: 'Kyoto' } },
      id: 'api-key-test-2',
    };
    const body = new TextEncoder().encode(JSON.stringify(rpcPayload));

    const httpResponse = await serverActor.http_request_update({
      method: 'POST',
      url: '/mcp',
      headers: [
        ['Content-Type', 'application/json'],
        ['x-api-key', 'this-is-a-completely-invalid-key'], // Invalid key
      ],
      body,
      certificate_version: [],
    });

    // Assert the request was unauthorized.
    expect(httpResponse.status_code).toBe(401);
    const responseBody = JSON.parse(
      new TextDecoder().decode(httpResponse.body as Uint8Array),
    );
    expect(responseBody.error).toBe('Unauthorized');
  });

  it('should reject a tool call with no authentication headers', async () => {
    const rpcPayload = {
      jsonrpc: '2.0',
      method: 'tools/call',
      params: { name: 'get_weather', arguments: { location: 'Osaka' } },
      id: 'api-key-test-3',
    };
    const body = new TextEncoder().encode(JSON.stringify(rpcPayload));

    const httpResponse = await serverActor.http_request_update({
      method: 'POST',
      url: '/mcp',
      headers: [['Content-Type', 'application/json']], // No auth headers
      body,
      certificate_version: [],
    });

    // Assert the request was unauthorized.
    expect(httpResponse.status_code).toBe(401);
  });
});
