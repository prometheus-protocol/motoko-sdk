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

> **For a complete, runnable example, please see the `examples/public_mcp_server` directory in this repository.**

### 1. Define Resources

Resources are the static content your server provides, like documentation or data files. You define them as an array of `Mcp.Resource` records.

```motoko
let resources : [Mcp.Resource] = [
  {
    uri = "file:///README.md";
    name = "README.md";
    title = ?"Project Documentation";
    description = null;
    mimeType = ?"text/markdown";
  },
];
```

### 2. Define Tools

Tools are the functions that a model can execute. You define their schema as an array of `Mcp.Tool` records.

```motoko
let tools : [Mcp.Tool] = [{
  name = "get_weather";
  title = ?"Weather Provider";
  description = ?"Get current weather for a location";
  inputSchema = Json.obj([...]);  // Standard JSON Schema
  outputSchema = ?Json.obj([...]); // Standard JSON Schema
}];
```

### 3. Implement Tool Logic

For each tool you define, you must provide a corresponding Motoko function that implements its logic. The function receives the tool's arguments and a callback to return the result.

```motoko
func getWeatherTool(args: Mcp.JsonValue, cb: (Result.Result<Mcp.CallToolResult, Mcp.HandlerError>) -> ()) {
  // 1. Parse arguments from `args`
  let location = ...;

  // 2. Perform your logic
  let report = "The weather in " # location # " is sunny.";
  let structured = Json.obj([("report", Json.str(report))]);

  // 3. Return the result via the callback
  cb(#ok({
    content = [#text({ text = Json.stringify(structured) })],
    isError = false,
    structuredContent = ?structured
  }));
};
```

### 4. Configure and Create the Server

Finally, you bundle everything into a single `McpConfig` record and pass it to the SDK's `createServer` function. This is where you link your tool schemas to their implementations.

```motoko
let mcp_config : Mcp.McpConfig = {
  serverInfo = { name = "My MCP Server", ... };
  resources = resources;
  resourceReader = func(uri) { ... }; // Your function to read resource content
  tools = tools;
  toolImplementations = [
    ("get_weather", getWeatherTool) // Link "get_weather" to its function
  ];
  customRoutes = null;
};

let mcp_server = Mcp.createServer(mcp_config);
```

The SDK takes this config and generates a fully compliant MCP server.

## Connection Management & Upgrades

The SDK uses a low-cost `Timer` to automatically clean up stale client connections, preventing memory leaks and keeping hosting costs low.

Because timers are not automatically restored after a canister upgrade.

```motoko
// In your main.mo, after setting up your state...
Cleanup.startCleanupTimer(appCtx);
```

## Running the Example

To run the full example server included in this repository:

1.  Navigate to the example directory:
    ```bash
    cd examples/public_mcp_server
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
*   **feat**: A new feature
*   **fix**: A bug fix
*   **docs**: Documentation only changes
*   **style**: Changes that do not affect the meaning of the code (white-space, formatting, etc)
*   **refactor**: A code change that neither fixes a bug nor adds a feature
*   **perf**: A code change that improves performance
*   **test**: Adding missing tests or correcting existing tests
*   **chore**: Changes to the build process or auxiliary tools and libraries such as documentation generation

#### Example

```
feat(server): add support for OAuth 2.0 authentication
```

Committing with this format allows us to automatically generate changelogs and determine the next version number for releases.

## License

This SDK is licensed under the [MIT License](LICENSE).