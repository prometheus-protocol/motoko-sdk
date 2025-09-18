/// test/payments.pic.test.ts

import path from 'node:path';
import { PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@dfinity/candid';
import type { Actor, DeferredActor } from '@dfinity/pic';
import { Identity } from '@dfinity/agent';
import { Principal } from '@dfinity/principal';
import {
  describe,
  test,
  expect,
  beforeAll,
  inject,
  afterAll,
  afterEach,
  beforeEach,
  it,
} from 'vitest';
import * as jose from 'jose';

// --- Import Declarations ---
// Your MCP Server Canister
import {
  idlFactory as mcpServerIdlFactory,
  init as mcpServerInit,
} from '../../.dfx/local/canisters/test_paid_mcp_server/service.did.js';
import type { _SERVICE as McpServerService } from '../../.dfx/local/canisters/test_paid_mcp_server/service.did.js';

// A standard ICRC-1/2 Ledger Canister
import {
  idlFactory as ledgerIdlFactory,
  init as ledgerInit,
} from '../../.dfx/local/canisters/icrc1_ledger/service.did.js';
import type { _SERVICE as LedgerService } from '../../.dfx/local/canisters/icrc1_ledger/service.did.js';

// --- Wasm Paths ---
// Update these paths to match your project structure
const MCP_SERVER_WASM_PATH = path.resolve(
  __dirname,
  '../../',
  '.dfx/local/canisters/test_paid_mcp_server/test_paid_mcp_server.wasm',
);
const LEDGER_WASM_PATH = path.resolve(
  __dirname,
  '../../',
  '.dfx/local/canisters/icrc1_ledger/icrc1_ledger.wasm.gz',
);

// --- Identities ---
const serverOwnerIdentity: Identity = createIdentity('server-owner-principal');
const userIdentity: Identity = createIdentity('user-principal');
const minterIdentity: Identity = createIdentity('minter');

const MOCK_ISSUER_URL = 'https://mock-auth-server.com';
const MOCK_KID = 'test-key-2025'; // Key ID for the JWT
const mcpUrl = '/mcp';

describe('MCP Server Monetization', () => {
  let pic: PocketIc;
  let serverActor: DeferredActor<McpServerService>;
  let serverCanisterId: Principal;
  let ledgerActor: Actor<LedgerService>;
  let ledgerCanisterId: Principal;
  let jwtKeyPair: jose.GenerateKeyPairResult;

  const userStartingBalance = 100_000_000n; // 1 full token if decimals=8
  const toolCost = 1_000_000n; // 0.01 tokens if decimals=8
  const transferFee = 10_000n; // As defined in ledgerInit
  const approvalFee = 10_000n; // Assume same fee for approval transactions

  beforeAll(async () => {
    // 1. Deploy the ICRC-1/2 Ledger Canister, owned by the server owner
    const url = inject('PIC_URL'); // 1. Get the URL from the global setup.
    // 2. Connect a client to the server.
    pic = await PocketIc.create(url);
    jwtKeyPair = await jose.generateKeyPair('ES256');

    const ledgerFixture = await pic.setupCanister<LedgerService>({
      idlFactory: ledgerIdlFactory,
      wasm: LEDGER_WASM_PATH,
      sender: minterIdentity.getPrincipal(),
      arg: IDL.encode(ledgerInit({ IDL }), [
        {
          Init: {
            minting_account: {
              owner: minterIdentity.getPrincipal(),
              subaccount: [],
            },
            initial_balances: [],
            transfer_fee: 10_000n,
            token_name: 'Test Token',
            token_symbol: 'TTK',
            metadata: [],
            // Provide the mandatory archive_options
            archive_options: {
              num_blocks_to_archive: 1000n,
              trigger_threshold: 2000n,
              controller_id: minterIdentity.getPrincipal(),
              // Optional fields can be empty arrays
              max_message_size_bytes: [],
              cycles_for_archive_creation: [],
              node_max_memory_size_bytes: [],
              more_controller_ids: [],
              max_transactions_per_response: [],
            },
            // Other optional fields
            decimals: [],
            fee_collector_account: [],
            max_memo_length: [],
            index_principal: [],
            feature_flags: [],
          },
        },
      ]),
    });
    ledgerActor = ledgerFixture.actor;
    ledgerCanisterId = ledgerFixture.canisterId;

    // 3. Mint tokens to the user so they have funds
    ledgerActor.setIdentity(minterIdentity);
    await ledgerActor.icrc1_transfer({
      to: { owner: userIdentity.getPrincipal(), subaccount: [] },
      amount: userStartingBalance, // 1 full token
      fee: [],
      memo: [],
      from_subaccount: [],
      created_at_time: [],
    });

    // 2. Deploy the MCP Server Canister
    const serverFixture = await pic.setupCanister<McpServerService>({
      idlFactory: mcpServerIdlFactory,
      wasm: MCP_SERVER_WASM_PATH,
      sender: serverOwnerIdentity.getPrincipal(),
      arg: IDL.encode(mcpServerInit({ IDL }), [
        [
          {
            paymentLedger: ledgerFixture.canisterId,
          },
        ],
      ]),
    });
    serverCanisterId = serverFixture.canisterId;
    serverActor = pic.createDeferredActor(
      mcpServerIdlFactory,
      serverCanisterId,
    );
  });

  afterAll(async () => {
    await pic.tearDown();
  });

  const performAuthenticatedRequest = async (rpcPayload: object) => {
    // --- Define URLs for clarity ---
    const MOCK_JWKS_URL = `${MOCK_ISSUER_URL}/.well-known/jwks.json`;
    const MOCK_DISCOVERY_URL = `${MOCK_ISSUER_URL}/.well-known/oauth-authorization-server`;

    // 1. Create the JWT.
    const resourceServerUrl = new URL(mcpUrl, 'http://127.0.0.1:4943');
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

  it('should FAIL to call a paid tool due to insufficient allowance', async () => {
    serverActor.setIdentity(userIdentity);

    const rpcPayload = {
      jsonrpc: '2.0',
      method: 'tools/call',
      params: { name: 'generate_image', arguments: { prompt: 'a cool robot' } },
      id: 1,
    };

    const httpResponse = await performAuthenticatedRequest(rpcPayload);

    expect(httpResponse.status_code).toBe(200);
    const responseBody = JSON.parse(
      new TextDecoder().decode(httpResponse.body as Uint8Array),
    );

    expect(responseBody).toHaveProperty('result');
    const result = responseBody.result;

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('Insufficient allowance');
    expect(result.structuredContent).toBeDefined();
    // This URL comes from the McpServer.mo config, not the mock server.
    expect(result.content[0].text).toContain(
      'https://canister_id.icp0.io/allowances',
    );
  });

  it('should allow the user to set an allowance for the server', async () => {
    ledgerActor.setIdentity(userIdentity);
    const approvalAmount = toolCost * 5n;
    const approveResult = await ledgerActor.icrc2_approve({
      spender: { owner: serverCanisterId, subaccount: [] },
      amount: approvalAmount,
      fee: [],
      memo: [],
      from_subaccount: [],
      created_at_time: [],
      expected_allowance: [],
      expires_at: [],
    });

    expect('Ok' in approveResult).toBe(true);
  });

  it('should SUCCEED in calling the paid tool after setting an allowance', async () => {
    // CORRECTED: Use the helper to make an authenticated request.
    const rpcPayload = {
      jsonrpc: '2.0',
      method: 'tools/call',
      params: { name: 'generate_image', arguments: { prompt: 'a happy dog' } },
      id: 2,
    };

    const httpResponse = await performAuthenticatedRequest(rpcPayload);

    const responseBody = JSON.parse(
      new TextDecoder().decode(httpResponse.body as Uint8Array),
    );
    expect(responseBody).toHaveProperty('result');
    const result = responseBody.result;

    expect(result.isError).toBe(false);
    expect(result.structuredContent.imageUrl).toContain('happy-dog');
  });

  it('should have transferred the funds correctly', async () => {
    const userBalance = await ledgerActor.icrc1_balance_of({
      owner: userIdentity.getPrincipal(),
      subaccount: [],
    });

    const expectedUserBalance =
      userStartingBalance - toolCost - transferFee - approvalFee;

    expect(userBalance).toBe(expectedUserBalance);

    const serverBalance = await ledgerActor.icrc1_balance_of({
      owner: serverCanisterId,
      subaccount: [],
    });
    expect(serverBalance).toBe(toolCost);
  });

  describe('Treasury Management', () => {
    // We need a new identity for the withdrawal destination
    const destinationIdentity: Identity = createIdentity('destination');
    const newOwnerIdentity: Identity = createIdentity('new-owner');

    // This test runs in a clean environment thanks to beforeEach
    it('should correctly report the initial owner and balance', async () => {
      // Check owner
      const getOwner = await serverActor.get_owner();
      const owner = await getOwner();
      expect(owner.toString()).toBe(
        serverOwnerIdentity.getPrincipal().toString(),
      );

      // Check initial balance (should be tool cost from previous tests)
      const getTreasuryBalance =
        await serverActor.get_treasury_balance(ledgerCanisterId);
      const balance = await getTreasuryBalance();
      expect(balance).toBe(toolCost);
    });

    it('should reflect the correct balance after a payment is received', async () => {
      // ARRANGE: Perform a successful tool call to get funds into the canister
      serverActor.setIdentity(userIdentity);
      ledgerActor.setIdentity(userIdentity);
      await ledgerActor.icrc2_approve({
        spender: { owner: serverCanisterId, subaccount: [] },
        amount: toolCost,
        fee: [],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        expected_allowance: [],
        expires_at: [],
      });
      const rpcPayload = {
        jsonrpc: '2.0',
        method: 'tools/call',
        params: { name: 'generate_image', arguments: { prompt: 'test' } },
        id: 1,
      };
      await performAuthenticatedRequest(rpcPayload);

      // ACT & ASSERT: Check the treasury balance
      const getTreasuryBalance =
        await serverActor.get_treasury_balance(ledgerCanisterId);

      const balance = await getTreasuryBalance();
      expect(balance).toBe(toolCost);
    });

    it('should PREVENT a non-owner from withdrawing funds', async () => {
      // ARRANGE: Get funds into the canister
      // (Same setup as the test above)
      serverActor.setIdentity(userIdentity);
      ledgerActor.setIdentity(userIdentity);
      await ledgerActor.icrc2_approve({
        spender: { owner: serverCanisterId, subaccount: [] },
        amount: toolCost,
        fee: [],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        expected_allowance: [],
        expires_at: [],
      });
      const rpcPayload = {
        jsonrpc: '2.0',
        method: 'tools/call',
        params: { name: 'generate_image', arguments: { prompt: 'test' } },
        id: 1,
      };
      await performAuthenticatedRequest(rpcPayload);

      // ACT: Attempt to withdraw as the `userIdentity` (a non-owner)
      serverActor.setIdentity(userIdentity);
      const withdraw = await serverActor.withdraw(ledgerCanisterId, toolCost, {
        owner: destinationIdentity.getPrincipal(),
        subaccount: [],
      });
      const withdrawResult = await withdraw();

      // ASSERT: The call must fail with a `NotOwner` error
      expect(withdrawResult).toHaveProperty('err');
      // @ts-ignore: Property 'NotOwner' does not exist on type 'unknown'. --- IGNORE ---
      expect(withdrawResult.err).toHaveProperty('NotOwner');

      // ASSERT: The canister's balance should be unchanged
      const getTreasuryBalance =
        await serverActor.get_treasury_balance(ledgerCanisterId);
      const balance = await getTreasuryBalance();
      expect(balance).toBe(toolCost);
    });

    it('should ALLOW the owner to withdraw funds', async () => {
      // ARRANGE: Get funds into the canister
      serverActor.setIdentity(userIdentity);
      ledgerActor.setIdentity(userIdentity);
      await ledgerActor.icrc2_approve({
        spender: { owner: serverCanisterId, subaccount: [] },
        amount: toolCost,
        fee: [],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        expected_allowance: [],
        expires_at: [],
      });
      const rpcPayload = {
        jsonrpc: '2.0',
        method: 'tools/call',
        params: { name: 'generate_image', arguments: { prompt: 'test' } },
        id: 1,
      };
      await performAuthenticatedRequest(rpcPayload);

      // The amount to withdraw must be less than the balance to account for the transfer fee
      const amountToWithdraw = toolCost - transferFee;

      // ACT: Withdraw as the `serverOwnerIdentity`
      serverActor.setIdentity(serverOwnerIdentity);
      const withdraw = await serverActor.withdraw(
        ledgerCanisterId,
        amountToWithdraw,
        { owner: destinationIdentity.getPrincipal(), subaccount: [] },
      );
      const withdrawResult = await withdraw();

      // ASSERT SUCCESS
      expect(withdrawResult).toHaveProperty('ok');

      // ASSERT BALANCES
      // The canister's balance should now be zero (it paid the fee from the remainder)
      const getTreasuryBalance =
        await serverActor.get_treasury_balance(ledgerCanisterId);
      const finalCanisterBalance = await getTreasuryBalance();
      expect(finalCanisterBalance).toBe(0n);

      // The destination should have received the withdrawn amount
      const destinationBalance = await ledgerActor.icrc1_balance_of({
        owner: destinationIdentity.getPrincipal(),
        subaccount: [],
      });
      expect(destinationBalance).toBe(amountToWithdraw);
    });

    it('should PREVENT a non-owner from changing the owner', async () => {
      // ACT: Attempt to set owner as the `userIdentity`
      serverActor.setIdentity(userIdentity);
      const setOwner = await serverActor.set_owner(
        newOwnerIdentity.getPrincipal(),
      );

      const setResult = await setOwner();
      // ASSERT: The call must fail
      expect(setResult).toHaveProperty('err');
      // @ts-ignore: Property 'NotOwner' does not exist on type 'unknown'. --- IGNORE ---
      expect(setResult.err).toHaveProperty('NotOwner');

      // ASSERT: The owner should remain unchanged
      const getOwner = await serverActor.get_owner();
      const owner = await getOwner();

      expect(owner.toText()).toBe(serverOwnerIdentity.getPrincipal().toText());
    });

    it('should ALLOW the current owner to change the owner', async () => {
      // ACT: As the current owner, transfer ownership
      serverActor.setIdentity(serverOwnerIdentity);
      const setOwner = await serverActor.set_owner(
        newOwnerIdentity.getPrincipal(),
      );
      const setResult = await setOwner();
      expect(setResult).toHaveProperty('ok');

      // ASSERT: The owner should now be the new principal
      const getOwner = await serverActor.get_owner();
      const newOwner = await getOwner();
      expect(newOwner.toText()).toBe(newOwnerIdentity.getPrincipal().toText());

      // FURTHER ASSERTION: The OLD owner should no longer have owner privileges
      serverActor.setIdentity(serverOwnerIdentity); // Set identity to the old owner
      const setOwnerAgain = await serverActor.set_owner(
        userIdentity.getPrincipal(),
      );
      const secondSetResult = await setOwnerAgain();
      expect(secondSetResult).toHaveProperty('err'); // This should now fail
      // @ts-ignore: Property 'NotOwner' does not exist on type 'unknown'. --- IGNORE ---
      expect(secondSetResult.err).toHaveProperty('NotOwner');
    });
  });
});
