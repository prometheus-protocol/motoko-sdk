import path from 'node:path';
import { PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@dfinity/candid';
import type { Actor, DeferredActor } from '@dfinity/pic';
import { Identity } from '@dfinity/agent';
import { Principal } from '@dfinity/principal';
import { describe, it, expect, beforeAll, inject, afterAll } from 'vitest';
import * as jose from 'jose';
import { sha256 } from '@noble/hashes/sha2.js';
import { readFile } from 'node:fs/promises';

// --- Import Declarations ---
import {
  idlFactory as mcpServerIdlFactory,
  init as mcpServerInit,
} from '../../.dfx/local/canisters/test_beacon_mcp_server/service.did.js';
import type { _SERVICE as McpServerService } from '../../.dfx/local/canisters/test_beacon_mcp_server/service.did.js';

import {
  idlFactory as trackerIdlFactory,
  init as trackerInit,
} from '../../.dfx/local/canisters/usage_tracker/service.did.js';
import type { _SERVICE as UsageTrackerService } from '../../.dfx/local/canisters/usage_tracker/service.did.js';

// --- Wasm Paths ---

const MCP_SERVER_WASM_PATH = path.resolve(
  __dirname,
  '../../',
  '.dfx/local/canisters/test_beacon_mcp_server/test_beacon_mcp_server.wasm',
);
const USAGE_TRACKER_WASM_PATH = path.resolve(
  __dirname,
  '../../',
  '.dfx/local/canisters/usage_tracker/usage_tracker.wasm',
);

// --- Identities & Constants ---
const serverOwnerIdentity: Identity = createIdentity('server-owner-principal');
const userIdentity: Identity = createIdentity('user-principal');
const trackerAdminIdentity: Identity = createIdentity('tracker-admin');
const MOCK_ISSUER_URL = 'https://mock-auth-server.com';
const MOCK_KID = 'test-key-2025';
const BEACON_INTERVAL_S = 10;

describe('MCP Server Beacon SDK via HTTP Gateway', () => {
  let pic: PocketIc;
  let serverActor: DeferredActor<McpServerService>; // Use DeferredActor for HTTP tests
  let serverCanisterId: Principal;
  let trackerActor: Actor<UsageTrackerService>;
  let trackerCanisterId: Principal;
  let jwtKeyPair: jose.GenerateKeyPairResult;
  let serverWasmHash: Uint8Array;

  beforeAll(async () => {
    const url = inject('PIC_URL');
    pic = await PocketIc.create(url);
    jwtKeyPair = await jose.generateKeyPair('ES256');

    await pic.setTime(new Date());

    // 1. Deploy the UsageTracker Canister
    const trackerFixture = await pic.setupCanister<UsageTrackerService>({
      idlFactory: trackerIdlFactory,
      wasm: USAGE_TRACKER_WASM_PATH,
      sender: trackerAdminIdentity.getPrincipal(),
      arg: IDL.encode(trackerInit({ IDL }), []),
    });
    trackerActor = trackerFixture.actor;
    trackerCanisterId = trackerFixture.canisterId;

    // Deploy the MCP Server Canister
    const serverFixture = await pic.setupCanister<McpServerService>({
      idlFactory: mcpServerIdlFactory,
      wasm: MCP_SERVER_WASM_PATH,
      sender: serverOwnerIdentity.getPrincipal(),
      arg: IDL.encode(mcpServerInit({ IDL }), [
        [
          {
            beaconCanisterId: trackerCanisterId,
            beaconIntervalSec: BEACON_INTERVAL_S,
          },
        ],
      ]),
    });
    serverCanisterId = serverFixture.canisterId;
    // Use createDeferredActor for handling HTTP outcalls
    serverActor = pic.createDeferredActor(
      mcpServerIdlFactory,
      serverCanisterId,
    );

    // 3. Add the server's Wasm hash to the tracker's allowlist
    const wasm = await readFile(MCP_SERVER_WASM_PATH);
    serverWasmHash = sha256(wasm);
    trackerActor.setIdentity(trackerAdminIdentity);
    await trackerActor.add_approved_wasm_hash(serverWasmHash);
  });

  afterAll(async () => {
    await pic.tearDown();
  });

  const performAuthenticatedRequest = async (rpcPayload: object) => {
    // --- Define URLs for clarity ---
    const MOCK_JWKS_URL = `${MOCK_ISSUER_URL}/.well-known/jwks.json`;
    const MOCK_DISCOVERY_URL = `${MOCK_ISSUER_URL}/.well-known/oauth-authorization-server`;

    // 1. Create the JWT.
    const resourceServerUrl = new URL('http://127.0.0.1:4943');
    resourceServerUrl.searchParams.set('canisterId', serverCanisterId.toText());
    const token = await new jose.SignJWT({ scope: 'openid' })
      .setProtectedHeader({ alg: 'ES256', kid: MOCK_KID })
      .setIssuer(MOCK_ISSUER_URL)
      .setAudience(resourceServerUrl.toString())
      .setSubject(userIdentity.getPrincipal().toText())
      .setExpirationTime('1h')
      .sign(jwtKeyPair.privateKey);

    const body = new TextEncoder().encode(JSON.stringify(rpcPayload));

    // 2. Initiate the update call WITHOUT awaiting it (the deferred pattern).
    const resultPromise = await serverActor.http_request_update({
      method: 'POST',
      url: '/mcp',
      headers: [
        ['Content-Type', 'application/json'],
        ['Authorization', `Bearer ${token}`],
      ],
      body,
      certificate_version: [],
    });

    // 3. Enter a loop to process all pending HTTP outcalls until there are none left.
    while (true) {
      // Advance the IC state to let the canister run until it's awaiting an outcall.
      await pic.tick(3);
      const httpRequests = await pic.getPendingHttpsOutcalls();

      // If there are no more pending requests, the canister is done with its async work.
      // This correctly handles the case where no outcall is made.
      if (httpRequests.length === 0) {
        break;
      }

      // Process each pending request.
      for (const request of httpRequests) {
        let responseBody: Uint8Array;

        // SMART LOGIC: Decide which mock response to send based on the URL.
        if (request.url === MOCK_DISCOVERY_URL) {
          const discoveryResponse = {
            issuer: MOCK_ISSUER_URL,
            jwks_uri: MOCK_JWKS_URL,
          };
          responseBody = new TextEncoder().encode(
            JSON.stringify(discoveryResponse),
          );
        } else if (request.url === MOCK_JWKS_URL) {
          const publicJwk = await jose.exportJWK(jwtKeyPair.publicKey);
          const jwksResponse = { keys: [{ ...publicJwk, kid: MOCK_KID }] };
          responseBody = new TextEncoder().encode(JSON.stringify(jwksResponse));
        } else {
          // If the canister requests an unexpected URL, fail the test loudly.
          throw new Error(
            `Test received unexpected HTTP outcall for URL: ${request.url}`,
          );
        }

        // Mock the response for the current request.
        await pic.mockPendingHttpsOutcall({
          requestId: request.requestId,
          subnetId: request.subnetId,
          response: {
            type: 'success',
            statusCode: 200,
            headers: [['Content-Type', 'application/json']],
            body: responseBody,
          },
        });
      }
    }

    // 4. Now that all outcalls are mocked and the canister has finished its work,
    // we can finally await the original promise to get the final result.
    return await resultPromise();
  };

  it('should track an authenticated tool call and send the beacon', async () => {
    // 1. Make the tool call via an authenticated HTTP request.
    const rpcPayload = {
      jsonrpc: '2.0',
      method: 'tools/call',
      params: { name: 'get_balance', arguments: {} },
      id: 1,
    };
    const httpResponse = await performAuthenticatedRequest(rpcPayload);
    const responseBody = JSON.parse(
      new TextDecoder().decode(httpResponse.body as Uint8Array),
    );

    expect(responseBody.result.isError).toBe(false);

    // 2. At this point, the tracker should still have no metrics.
    let metrics = await trackerActor.get_metrics_for_server(serverCanisterId);
    expect(metrics).toEqual([]);

    // 3. Advance time and fire the beacon.
    await pic.advanceTime(BEACON_INTERVAL_S * 1_000 + 100); // Add a bit of buffer
    await pic.tick(3);

    // 4. Now, the tracker should have the metrics from the call.
    const metricsResult =
      await trackerActor.get_metrics_for_server(serverCanisterId);
    expect(metricsResult).not.toEqual([]);
    const metricsData = metricsResult[0];
    expect(metricsData).toBeDefined();
    expect(metricsData?.total_invocations).toBe(1n);

    const userInvocations = metricsData?.invocations_by_user.find(
      ([p, _]) => p.toText() === userIdentity.getPrincipal().toText(),
    );
    expect(userInvocations?.[1]).toBe(1n);
  });
});
