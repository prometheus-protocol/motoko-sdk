# MCP Motoko SDK

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![mops](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/mops/mcp-motoko-sdk)](https://mops.one/mcp-motoko-sdk)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)](#)

A comprehensive, robust, and developer-friendly SDK for building [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) compliant servers on the Internet Computer using Motoko.

This SDK handles the low-level details of the MCP specification—including routing, authentication, and connection management—allowing you to focus on defining your application's resources, tools, and logic.

https://prometheusprotocol.org

## Live Examples

Check out the live example servers running on the Internet Computer:

- [Public MCP Example Server](https://remote-mcp-servers.com/servers/03e3732f-a617-4631-a1b1-5b489f26dd95).
- [Private MCP Example Server](https://remote-mcp-servers.com/servers/6bc72920-c72b-4a80-b2f3-6b46c78de654).

Connect to it using any MCP client including the [MCP Inspector](https://github.com/modelcontextprotocol/inspector).

## Core Concepts

This SDK is designed to be declarative. You define your server's capabilities by creating records and functions, and then pass them to the SDK to handle the rest.

> **For complete, runnable examples, please see the `canisters` directory in this repository.**

### 1. Define Resources

Resources are the static content your server provides. You define them in an array and provide a `resourceReader` function to serve their content.

```motoko
// Define the resources your server offers.
var resources : [McpTypes.Resource] = [
  {
    uri = "file:///main.py";
    name = "main.py";
    title = ?"Main Python Script";
    mimeType = ?"text/x-python";
    // ...
  },
];

// Implement a function that reads the content for a given resource URI.
func resourceReader(uri : Text) : ?Text {
  // In a real app, you'd read from a more robust data store.
  return Map.get(appContext.resourceContents, thash, uri);
};
```

### 2. Define Tools

Tools are the interactive functions of your server. You define their schema and link them to their implementation.

```motoko
// Define the tool's interface, including its name and JSON schemas.
var tools : [McpTypes.Tool] = [{
  name = "get_weather";
  title = ?"Weather Provider";
  description = ?"Get current weather information for a location";
  payment = null;
  inputSchema = Json.obj([("location", ... )]);
  outputSchema = ?Json.obj([("report", ... )]);
}];

// Implement the tool's logic.
func getWeatherTool(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : ...) {
  let location = ...; // Parse location from args
  let report = "The weather in " # location # " is sunny.";
  let structuredPayload = Json.obj([("report", Json.str(report))]);
  cb(#ok({ content = [#text({ text = Json.stringify(structuredPayload) })], ... }));
};
```

### 3. Configure and Create the Server

Finally, you bundle everything into a single `McpConfig` record and create the server.

```motoko
let mcpConfig : McpTypes.McpConfig = {
  self = Principal.fromActor(self);
  serverInfo = { name = "My MCP Server", ... };
  resources = resources;
  resourceReader = resourceReader;
  tools = tools;
  toolImplementations = [
    ("get_weather", getWeatherTool) // Link tool name to its function
  ];
  // ... other config
};

let mcpServer = Mcp.createServer(mcpConfig);
```

## Authentication

The SDK features a modular authentication layer that can be configured to secure your server. You can enable API Key authentication, OIDC (OAuth2), or both.

### API Key Authentication (Recommended for M2M)

This is the simplest way to secure your server for machine-to-machine communication.

#### Step 1: Initialize the Auth Context

In your main actor, initialize the `AuthContext` in API Key mode, specifying the canister `owner` who will be authorized to manage keys.

```motoko
import AuthState "../../../src/auth/State";
import AuthTypes "../../../src/auth/Types";

// ... inside your actor class ...
let authContext : AuthTypes.AuthContext = AuthState.initApiKey(owner);
```

#### Step 2: Configure the HTTP Handler

Pass the configured `authContext` to the `HttpHandler` when processing requests. The middleware will automatically reject requests that don't include a valid API key.

```motoko
private func _create_http_context() : HttpHandler.Context {
  return {
    // ... other context fields
    auth = ?authContext; // Enable authentication
  };
};
```

#### Step 3: Manage API Keys

Expose a secure method on your canister for the owner to create and manage API keys. The SDK provides helpers for this.

```motoko
import ApiKey "../../../src/auth/ApiKey";

// ... inside your actor class ...
public shared (msg) func create_api_key(name : Text, scopes : [Text]) : async Text {
  // The SDK handles key generation and secure storage of the key's hash.
  // The key will be associated with the caller's principal.
  return await ApiKey.create_api_key(authContext, msg.caller, name, msg.caller, scopes);
};
```

#### Step 4: Connecting to Your Server

The recommended way to test and interact with your secure server is using the **MCP Inspector**. It fully supports the protocol's streaming handshake and custom authentication headers.

1.  **Generate a Key**: Call your canister's `create_api_key` function to get a new key.
    ```bash
    dfx canister call mcp_server create_api_key '("My Test Key", vec {})'
    ```
2.  **Open the [MCP Inspector](https://github.com/modelcontextprotocol/inspector)**.
3.  Enter your canister ID in the connection panel.
4.  Navigate to the **Headers** tab and add a new header:
    - **Name**: `x-api-key`
    - **Value**: (Paste the API key you generated in step 1)
5.  Click **Connect**. The Inspector will handle the handshake and list your available tools.

### OIDC / OAuth2 Authentication (Recommended for User-Facing Apps)

For applications where a human user needs to log in via a web frontend, the SDK supports OIDC, a modern identity layer built on top of OAuth2.

#### Step 1: Initialize the Auth Context

Initialize the `AuthContext` in OIDC mode, providing your identity provider's `issuerUrl` and any required scopes.

```motoko
import AuthState "../../../src/auth/State";
import AuthTypes "../../../src/auth/Types";

// ... inside your actor class ...
let issuerUrl = "https://identity.ic0.app"; // Example: Internet Identity
let requiredScopes = ["openid"];

// A standard transform function required by the IC's HTTP outcalls.
public query func transform(raw : IC.TransformArgs) : async IC.HttpResponse {
  { ...raw.response with headers = [] };
};

let authContext : AuthTypes.AuthContext = AuthState.initOidc(
  Principal.fromActor(self),
  issuerUrl,
  requiredScopes,
  transform
);
```

#### Step 2: The Client-Side Flow

The SDK automatically exposes a `/.well-known/oauth-protected-resource` metadata endpoint. A compliant client-side OIDC library will:

1.  Fetch this endpoint to discover the `issuerUrl`.
2.  Redirect the user to the issuer to log in (e.g., the Internet Identity login page).
3.  Receive a JWT (Bearer Token) after a successful login.
4.  Include this token in the `Authorization: Bearer <token>` header for all subsequent MCP requests.

### Using Both Methods

You can enable both API Key and OIDC authentication simultaneously. The middleware will prioritize an API key if the `x-api-key` header is present; otherwise, it will look for an `Authorization` header.

```motoko
// Initialize with parameters for both modules
let authContext : AuthTypes.AuthContext = AuthState.init(
  Principal.fromActor(self),
  owner,
  issuerUrl,
  requiredScopes,
  transform
);
```

## Monetization and Treasury Management

For tools that require payment, the SDK provides out-of-the-box Treasury functions to securely manage the funds your canister collects.

- **`get_owner()`**: View the canister's owner.
- **`set_owner(new_owner)`**: Transfer ownership (owner only).
- **`get_treasury_balance(ledger_id)`**: Check the canister's balance of any ICRC-1 token.
- **`withdraw(ledger_id, amount, destination)`**: Withdraw funds to any account (owner only).

To enable payments, define the `payment` field on a tool and provide an `allowanceUrl` in your `McpConfig`. See the `canisters/paid_mcp_server` for a full implementation.

## Proof-of-Use and Usage Mining (Beacon SDK)

The SDK includes a built-in "beacon" system to participate in the Prometheus Protocol's "Proof-of-Use" usage mining program. This allows your server to automatically and securely report tool usage statistics, making it eligible for rewards.

To enable, initialize the `Beacon.Context` as a stable variable and pass it to your `McpConfig`. The SDK automatically tracks every successful, **authenticated** tool call.

```motoko
import Beacon "mo:mcp_sdk/beacon";

persistent actor class MyMcpServer {
    // 1. Declare the beacon's state as a stable variable.
    var beaconContext = Beacon.init();
    Beacon.startTimer<system>(beaconContext);

    // 2. Configure the beacon in your McpConfig.
    let mcpConfig : McpTypes.McpConfig = {
        // ... other config
        beacon = ?beaconContext;
    };
    // ...
}
```

## Connection Management

The SDK uses low-cost timers to automatically clean up stale state, preventing memory leaks and keeping hosting costs low. You should start these timers when your canister initializes.

```motoko
// In your main.mo, after setting up your state...
import Cleanup "../../../src/mcp/Cleanup";
import AuthCleanup "../../../src/auth/Cleanup";

// Cleans up stale streaming connections
Cleanup.startCleanupTimer<system>(appContext);

// Cleans up expired JWT sessions from the cache
AuthCleanup.startCleanupTimer<system>(authContext);
```

## Running the Example

To run the full API key example server included in this repository:

1.  Navigate to the example directory:
    ```bash
    cd canisters/api_key_mcp_server
    ```
2.  Install dependencies and deploy:
    ```bash
    mops install
    dfx deploy
    ```
3.  Create an API key and connect to the server using the **MCP Inspector** as described in the authentication section above.

## Contributing

We welcome contributions! To ensure a smooth and automated release process, we adhere to the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification. Please see the contribution guidelines at the end of this document.

## License

This SDK is licensed under the [MIT License](LICENSE).
