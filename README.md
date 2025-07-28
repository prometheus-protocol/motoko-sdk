# MCP Motoko SDK

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](#)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)](#)

A comprehensive, robust, and developer-friendly SDK for building [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) compliant servers on the Internet Computer using Motoko.

This SDK handles the low-level details of the MCP specification—including routing, protocol compliance, and connection management—allowing you to focus on defining your application's resources, tools, and logic.

## Core Concepts

This SDK is designed to be declarative. You define your server's capabilities by creating records and functions, and then pass them to the SDK to handle the rest.

> **For a complete, runnable example, please see the `examples/mcp_server` directory in this repository.**

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

Because timers are not automatically restored after a canister upgrade, **it is essential to add the `post_upgrade` system function to your `main.mo` file.** The SDK provides a simple `Cleanup` module for this.

```motoko
// In your main.mo, after setting up your state...
Cleanup.startCleanupTimer(appCtx);
```

## Running the Example

To run the full example server included in this repository:

1.  Navigate to the example directory:
    ```bash
    cd examples/mcp_server
    ```
2.  Install dependencies and deploy:
    ```bash
    mops install
    dfx deploy
    ```
3.  Connect to the server using [MCP Inspector](https://github.com/modelcontextprotocol/inspector) or any MCP client.
    

## Contributing

Contributions are welcome! Please open an issue to discuss your ideas before submitting a pull request.

## License

This SDK is licensed under the [MIT License](LICENSE).