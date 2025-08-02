import { describe, test, expect, beforeAll } from 'vitest';
import * as jose from 'jose';
import * as dotenv from 'dotenv';
import * as path from 'path';
import * as fs from 'fs/promises';

dotenv.config({ path: path.resolve(__dirname, '.test.env') });

// --- Test Configuration (from environment) ---
const canisterId = process.env.E2E_CANISTER_ID_PRIVATE!;
const replicaUrl = process.env.E2E_REPLICA_URL!;
const mockAuthServerUrl = process.env.E2E_MOCK_AUTH_SERVER_URL!;

// --- Test State ---
let jwtPrivateKey: jose.CryptoKey;

describe('MCP Authentication and Discovery', () => {
  beforeAll(async () => {
    if (!canisterId || !replicaUrl || !mockAuthServerUrl) {
      throw new Error('E2E environment variables not set.');
    }
    const keyPath = path.join(__dirname, '.test-private-key.json');
    const privateKeyJwk = JSON.parse(await fs.readFile(keyPath, 'utf-8'));
    jwtPrivateKey = await jose.importJWK(privateKeyJwk, 'ES256') as jose.CryptoKey;
  }, 30000);

  // --- NEW TEST CASE FOR THE DISCOVERY FLOW ---
  test('should perform the full auth discovery flow on an unauthenticated request', async () => {
    // ARRANGE: A standard protected tool call payload
    const payload = { jsonrpc: '2.0', method: 'tools/call', params: { name: 'get_weather', arguments: { location: 'Tokyo' } }, id: 'discovery-test' };
    const rpcUrl = new URL(replicaUrl);
    rpcUrl.searchParams.set('canisterId', canisterId);

    // STEP 1: Make an unauthenticated call and expect a 401
    const unauthedResponse = await fetch(rpcUrl.toString(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    expect(unauthedResponse.status).toBe(401);

    // STEP 2: Extract the metadata URL from the WWW-Authenticate header
    const wwwAuthHeader = unauthedResponse.headers.get('www-authenticate');
    expect(wwwAuthHeader).toBeDefined();

    // Our canister returns `resource_metadata` as per RFC 9728
    const match = wwwAuthHeader!.match(/resource_metadata="([^"]+)"/);
    expect(match).not.toBeNull();
    const metadataPath = match![1];
    expect(metadataPath).toBe('/.well-known/oauth-protected-resource');

    // STEP 3: Call the metadata URL to discover the auth server
    const metadataUrl = new URL(replicaUrl);
    metadataUrl.searchParams.set('canisterId', canisterId);
    // Add cache busting query param to ensure we get the latest metadata
    metadataUrl.searchParams.set('cache_bust', Date.now().toString());
    metadataUrl.pathname = metadataPath; // Set the path for the GET request

    console.log('Fetching metadata from:', metadataUrl.toString());
    const metadataResponse = await fetch(metadataUrl.toString());
    expect(metadataResponse.status).toBe(200);
    const metadataBody = await metadataResponse.json();

    // STEP 4: Find the authorization server URL
    expect(metadataBody.authorization_servers).toBeInstanceOf(Array);
    const discoveredAuthServerUrl = metadataBody.authorization_servers[0];
    expect(discoveredAuthServerUrl).toBe(mockAuthServerUrl);

    // STEP 5: Get a "fake" token from the discovered Authorization Server
    const token = await new jose.SignJWT({ scope: 'read:weather' })
      .setProtectedHeader({ alg: 'ES256', kid: 'test-key-2025' })
      .setIssuer(discoveredAuthServerUrl) // Use the DISCOVERED URL
      .setSubject('aaaaa-aa')
      .setExpirationTime('2h')
      .sign(jwtPrivateKey);

    // STEP 6: Call the resource server again with the new token
    const finalResponse = await fetch(rpcUrl.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify(payload),
    });
    const finalJson = await finalResponse.json();

    // ASSERT: The final call succeeds
    expect(finalResponse.status).toBe(200);
    expect(finalJson.error).toBeUndefined();
    expect(finalJson.result.content[0].text).toContain('Tokyo');
  });

  test('should succeed when a valid token is provided directly', async () => {
    // Arrange
    const token = await new jose.SignJWT({ scope: 'read:weather' })
      .setProtectedHeader({ alg: 'ES256', kid: 'test-key-2025' })
      .setIssuer(mockAuthServerUrl)
      .setSubject('aaaaa-aa')
      .setExpirationTime('2h')
      .sign(jwtPrivateKey);

    const payload = { jsonrpc: '2.0', method: 'tools/call', params: { name: 'get_weather', arguments: { location: 'Tokyo' } }, id: 1 };
    const url = new URL(replicaUrl);
    url.searchParams.set('canisterId', canisterId);

    // Act
    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify(payload),
    });
    const json = await response.json();

    // Assert
    expect(response.status).toBe(200);
    expect(json.error).toBeUndefined();
    expect(json.result.content[0].text).toContain('Tokyo');
  });
});