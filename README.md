# MCP Motoko SDK

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![mops](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/mops/mcp-motoko-sdk)](https://mops.one/mcp-motoko-sdk)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)](#)

A comprehensive, robust, and developer-friendly SDK for building [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) compliant servers on the Internet Computer using Motoko.

This SDK handles the low-level details of the MCP specification—including routing, protocol compliance, and connection management—allowing you to focus on defining your application's resources, tools, and logic.

## Live Examples

Check out the live example servers running on the Internet Computer:

- [Public MCP Example Server](https://remote-mcp-servers.com/servers/03e3732f-a617-4631-a1b1-5b489f26dd95).
- [Private MCP Example Server](https://remote-mcp-servers.com/servers/6bc72920-c72b-4a80-b2f3-6b46c78de654).

Connect to it using any MCP client including the [MCP Inspector](https://github.com/modelcontextprotocol/inspector).

## Core Concepts

This SDK is designed to be declarative. You define your server's capabilities by creating records and functions, and then pass them to the SDK to handle the rest.

> **For a complete, runnable example, please see the `test/picjs/paid_mcp_server` directory in this repository.**

### 1. Define Resources and Gated Access

Resources are the static content your server provides. The `Mcp.Resource` type itself does not contain any payment information. Instead, you implement a "gated content" model using your `resourceReader` function.

```motoko
// The resource definition is simple and has no payment info.
let resources : [Mcp.Resource] = [
  {
    uri = "file:///premium_content.md";
    name = "premium_content.md";
    title = ?"Premium Content";
    description = ?"Exclusive content available after purchase.";
    mimeType = ?"text/markdown";
  },
];

// Your resourceReader function acts as the gatekeeper.
// It checks an Access Control List (ACL) before serving content.
func resourceReader(uri : Text, caller : Principal) : ?Text {
  if (hasAccess(caller, uri)) {
    // User has paid, serve the full content.
    return getFullContent(uri);
  } else {
    // User has not paid, serve a placeholder with instructions.
    return ?"# Access Denied\n\nTo view this content, please call the 'unlock_resource' tool with this URI.";
  }
};
```

### 2. Define a Paid "Unlock" Tool

To unlock a gated resource, you create a specific, **paid tool**. This is where the payment details live. This decouples the one-time purchase from repeated, free access.

```motoko
let tools : [Mcp.Tool] = [{
  name = "unlock_resource";
  title = ?"Unlock Resource";
  description = ?"Pay to gain permanent access to a protected resource.";
  inputSchema = Json.obj([("uri", ... )]); // Expects the URI of the resource to unlock
  outputSchema = null;
  // The tool is what carries the payment details.
  payment = ?{
    amount = 50_000_000;
    ledger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
  };
}];
```

### 3. Implement the Tool Logic (The Access Control List)

The implementation for your `unlock_resource` tool is where you grant access. After the SDK successfully processes the payment, your logic updates an Access Control List (ACL) in your canister's state.

```motoko
// State to track who has access to what
var accessRecords : Map.Map<(Principal, Text), Time.Time> = Map.empty();

func unlockResourceTool(args: Mcp.JsonValue, auth: ?Auth.AuthInfo, cb: ...) {
  // By the time this code runs, payment has already been successfully processed by the SDK.
  let caller = auth.caller;
  let uri = ...; // Parse URI from args

  // Grant access by updating the ACL
  accessRecords.put((caller, uri), Time.now());

  cb(#ok({
    content = [#text({ text = "Resource " # uri # " successfully unlocked!" })],
    ...
  }));
};
```

### 4. Configure and Create the Server

Finally, you bundle everything into a single `McpConfig` record. To enable payments for tools, you provide an `allowanceUrl` for user-friendly error messages.

```motoko
let mcp_config : Mcp.McpConfig = {
  serverInfo = { name = "My Paid MCP Server", ... };
  resources = resources;
  resourceReader = resourceReader;
  tools = tools;
  toolImplementations = [
    ("unlock_resource", unlockResourceTool) // Link tool name to its function
  ];
  // Provide a URL for users to manage their token allowances
  allowanceUrl = ?"https://principal_id_issuer_frontend_url/";
};

let mcp_server = Mcp.createServer(mcp_config);
```

## Monetization and Treasury Management

The SDK provides out-of-the-box Treasury functions to securely manage the funds your canister collects. These functions are automatically exposed on your canister actor.

- **`get_owner()`**: View the canister's owner.
- **`set_owner(new_owner)`**: Transfer ownership (owner only).
- **`get_treasury_balance(ledger_id)`**: Check the canister's balance of any ICRC-1 token.
- **`withdraw(ledger_id, amount, destination)`**: Withdraw funds to any account (owner only).

```motoko
// Example: The owner withdrawing 10 tokens (assuming 8 decimals)
import ICRC1 "mo:icrc1/ledgers";

let myCanister : actor {
  withdraw : (Principal, Nat, ICRC1.Account) -> async ...;
  // ...
} = actor "..."; // Your canister's principal

let destinationAccount = {
  owner = Principal.fromText("aaaaa-aa");
  subaccount = null;
};

// This call would be made by the owner from another canister or via dfx
await myCanister.withdraw(
  Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai"), // ledger
  10 * 100_000_000,                                  // amount
  destinationAccount                                // destination
);
```

## Proof-of-Use and Usage Mining (Beacon SDK)

The SDK includes a built-in "beacon" system to participate in the Prometheus Protocol's "Proof-of-Use" usage mining program. This allows your server to automatically and securely report tool usage statistics, making it eligible for `preMCPT` rewards.

The system consists of two parts:

1.  **The `UsageTracker` Canister**: A central, on-chain canister that securely aggregates usage data from all participating MCP servers. Its security model is based on an allowlist of audited Wasm hashes, ensuring that only compliant servers can submit data. The reference implementation can be found in the `canisters/usage_tracker` directory of this repository.
2.  **The Beacon SDK**: The logic integrated into this SDK. It acts as the "beacon" that periodically sends batched usage reports to the `UsageTracker`.

### Enabling the Beacon

Enabling the beacon is done via a single configuration object in your `McpConfig`. You must declare a stable `BeaconContext` variable in your actor and pass it to the configuration.

```motoko
import Beacon "mo:mcp_sdk/beacon";
import McpTypes "mo:mcp_sdk/Types";
import Principal "mo:base/Principal";

persistent actor class MyMcpServer {
    // 1. Declare the beacon's state as a stable variable.
    var beaconContext = Beacon.init();
    Beacon.startTimer<system>(beaconContext);

    // 2. Configure the beacon in your McpConfig.
    let mcpConfig : McpTypes.McpConfig = {
        // ... other config (serverInfo, tools, etc.)
        beacon = ?beaconContext;
    };

    // 3. The SDK handles the rest.
    let mcp_server = Mcp.createServer(mcpConfig);
    // ...
}
```

### How it Works

Once enabled, the SDK will **automatically** track every successful, **authenticated** tool call. This is a deliberate security measure to prevent Sybil attacks (spamming public endpoints) and ensure that rewards are distributed based on legitimate user interactions.

You do not need to add any extra `track_call` functions to your tool implementations; the SDK handles it for you.

## Connection Management

The SDK uses a low-cost `Timer` to automatically clean up stale client connections, preventing memory leaks and keeping hosting costs low. You simply need to start the timer when your canister initializes.

```motoko
// In your main.mo, after setting up your state...
Cleanup.startCleanupTimer(appCtx);
```

## Running the Example

To run the full example server included in this repository:

1.  Navigate to the example directory:
    ```bash
    cd examples/paid_mcp_server
    ```
2.  Install dependencies and deploy:
    ```bash
    mops install
    dfx deploy
    ```
3.  Connect to the server using [MCP Inspector](https://github.com/modelcontextprotocol/inspector) or any MCP client.

## Contributing

We welcome contributions! To ensure a smooth and automated release process, we adhere to the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification.

### Commit Message Format

Each commit message consists of a **header**, a **body**, and a **footer**. The header has a special format that includes a **type**, a **scope**, and a **subject**:

```
<type>(<scope>): <subject>
<BLANK LINE>
<body>
<BLANK LINE>
<footer>
```

#### Type

Must be one of the following:

- **feat**: A new feature
- **fix**: A bug fix
- **docs**: Documentation only changes
- **style**: Changes that do not affect the meaning of the code (white-space, formatting, etc)
- **refactor**: A code change that neither fixes a bug nor adds a feature
- **perf**: A code change that improves performance
- **test**: Adding missing tests or correcting existing tests
- **chore**: Changes to the build process or auxiliary tools and libraries such as documentation generation

#### Example

```
feat(payments): add support for ICRC-2 token payments for tools
```

Committing with this format allows us to automatically generate changelogs and determine the next version number for releases.

## License

This SDK is licensed under the [MIT License](LICENSE).
