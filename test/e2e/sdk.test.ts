import { describe, test, expect, beforeAll, afterAll } from 'vitest';
import * as dotenv from 'dotenv';
import * as path from 'path';

// Import the official MCP Client and its HTTP Transport
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

// --- Test Setup ---
dotenv.config({ path: path.resolve(__dirname, '.test.env') });

const canisterId = process.env.E2E_CANISTER_ID_PUBLIC!;
const replicaUrl = process.env.E2E_REPLICA_URL!;
const mcpPath = '/mcp';

describe('MCP Server Compliance via SDK', () => {
  let client: Client;

  beforeAll(async () => {
    if (!canisterId || !replicaUrl) {
      throw new Error('E2E environment variables not set.');
    }

    const url = new URL(mcpPath, replicaUrl);
    url.searchParams.set('canisterId', canisterId);
    const transport = new StreamableHTTPClientTransport(url);

    // transport.onerror = (error) => {
    //   console.error('Transport error:', error);
    // };
    // transport.onmessage = (message) => {
    //   console.log('Received message:', message);
    // };

    // Create a new client instance.
    client = new Client({
      name: 'mcp-sdk-e2e-tests',
      version: '1.0.0',
    });
    try {
      await client.connect(transport);
    } catch (error) {
      console.error('Failed to connect to the MCP server:', error);
      throw error;
    }
  });

  afterAll(async () => {
    // Disconnect the client after tests are done.
    await client.close();
  });

  test('should connect to the server successfully', async () => {
    const capabilities = client.getServerCapabilities();
    expect(capabilities).toStrictEqual({ resources: {}, tools: {} });

    const instructions = client.getInstructions();
    expect(instructions).toBeDefined();
    expect(instructions).toBe('Welcome to the Motoko MCP Server!')
  });

  test('should respond to a ping request', async () => {
    // Arrange: The ping method takes no parameters.

    // Act: Use the low-level `request` method to send the ping.
    const result = await client.ping();

    // Assert: The result MUST be an empty object, as per the spec.
    expect(result).toBeDefined();
    expect(result).toEqual({});
  });

  describe('MCP Resources', () => {
    test('should list available resources using the SDK client', async () => {
      // Act: Use the high-level SDK method to fetch resource metadata.
      const result = await client.listResources();

      // Assert: Check that the server returns the correct list of resources.
      expect(Array.isArray(result.resources)).toBe(true);
      expect(result.resources.length).toBe(2); // Based on our main.mo setup

      const readmeResource = result.resources[1] as any; // Type assertion for simplicity
      expect(readmeResource.uri).toBe('file:///README.md');
      expect(readmeResource.name).toBe('README.md');
      expect(readmeResource.mimeType).toBe('text/markdown');
    });

    test('should read a specific resource using the SDK client', async () => {
      // Arrange: The URI of the resource we know exists.
      const resourceUri = 'file:///README.md';

      // Act: Use the high-level SDK method to fetch the resource's content.
      const result = await client.readResource({ uri: resourceUri });

      // Assert: Check that the server returns the correct content.
      expect(result).toBeDefined();
      expect(Array.isArray(result.contents)).toBe(true);
      expect(result.contents.length).toBe(1);

      const contentBlock = result.contents[0];
      expect(contentBlock.uri).toBe(resourceUri);
      expect(contentBlock.text).toBe('# MCP Motoko Server'); // The actual content from State.init()
    });
  });

   describe('MCP Resources', () => {
    test('should list tools using the SDK client', async () => {
      // Act: Use the high-level SDK method.
      const result = await client.listTools();

      // Assert: The SDK conveniently unwraps the result for us.
      expect(Array.isArray(result.tools)).toBe(true);
      expect(result.tools.length).toBe(1);

      const weatherTool = result.tools[0];
      expect(weatherTool.name).toBe('get_weather');
    });

    test('should call the get_weather tool and receive a valid result', async () => {
      // Arrange: Define the parameters for the tool call.
      const toolParams = {
        name: 'get_weather',
        arguments: {
          location: 'denver',
        },
      };

      // Act: Call the tool using the SDK client.
      const result = await client.callTool(toolParams) as {
        isError: boolean;
        structuredContent: { report: string };
        content: Array<{ type: string; text: string }>;
      };

      // Assert: Check the structure of the result.
      expect(result).toBeDefined();
      expect(result.isError).toBe(false);

      // Assert that the structuredContent is correct.
      expect(result.structuredContent).toEqual({
        report: 'The weather in denver is sunny.',
      });

      // Assert that the `content` array has the structure our server is currently producing.
      // This is where we can test our theories about what the client expects.
      expect(Array.isArray(result.content)).toBe(true);

      const contentBlock = result.content[0];
      expect(contentBlock.type).toBe('text');

      // This is the crucial assertion. We expect the 'text' property to be a
      // string that is itself a valid JSON object.
      expect(contentBlock.text).toBe('{"report":"The weather in denver is sunny."}');
    });
  });
});