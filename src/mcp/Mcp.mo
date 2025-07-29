import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Json "../json";

// Internal SDK imports
import Server "../server/Server";
import Handler "../server/Handler";
import Encode "../server/Encode";

// Public-facing MCP types
import Types "Types";
import Decode "Decode";
import MCPEncode "Encode";

module {

  // Re-export types the developer will need.
  public type Tool = Types.Tool;
  public type Resource = Types.Resource;
  public type ServerInfo = Types.ServerInfo;
  public type CallToolResult = Types.CallToolResult;
  public type HandlerError = Handler.HandlerError;
  public type JsonValue = Types.JsonValue;

  // A type alias for the developer's tool implementation functions.
  public type ToolFn = (JsonValue, (Result.Result<CallToolResult, HandlerError>) -> ()) -> ();

  // The configuration record the developer will provide.
  public type McpConfig = {
    serverInfo : ServerInfo;
    resources : [Resource];
    resourceReader : (uri : Text) -> ?Text;
    tools : [Tool];
    toolImplementations : [(Text, ToolFn)];
    customRoutes : ?[(Text, Handler.Handler)];
  };

  // The main builder function for the SDK.
  public func createServer(config : McpConfig) : Server.Server {
    // --- Auto-generated MCP Handlers ---

    // 1. `initialize` handler
    let initializeHandler = (
      "initialize",
      Handler.query1<Types.InitializeParams, Types.InitializeResult>(
        func(params, cb) {
          // Define the capabilities our server actually supports.
          let capabilities : Types.ServerCapabilities = {
            logging = null; // We don't support this.
            prompts = null; // We don't support this.
            // We support the 'resources' capability, but not its optional features.
            // This will be encoded as: "resources": {}
            resources = ?{
              subscribe = null;
              listChanged = null;
            };
            // We support the 'tools' capability, but not its optional features.
            // This will be encoded as: "tools": {}
            tools = ?{
              listChanged = null;
            };
          };

          // Construct the full, correct response.
          cb({
            protocolVersion = params.protocolVersion;
            capabilities = capabilities;
            serverInfo = config.serverInfo;
            instructions = ?"Welcome to the Motoko MCP Server!";
          });
        },
        Decode.initializeParams,
        MCPEncode.initializeResult,
      ),
    );

    // 2. `resources/list` handler
    let resourcesListHandler = (
      "resources/list",
      Handler.query0<Types.ListResourcesResult>(
        func(cb) { cb({ resources = config.resources; nextCursor = null }) },
        MCPEncode.listResourcesResult,
      ),
    );

    // 3. `resources/read` handler
    let resourcesReadHandler = (
      "resources/read",
      Handler.query1<Types.ReadResourceParams, Types.ReadResourceResult>(
        func(params, cb) {
          // Find the resource metadata and content.
          let resource_meta = Array.find<Resource>(config.resources, func(r) { r.uri == params.uri });
          let content_text = config.resourceReader(params.uri);

          switch (resource_meta, content_text) {
            case (?meta, ?text) {
              // Found both! Construct the response.
              let content_block : Types.ResourceContent = {
                uri = meta.uri;
                name = meta.name;
                title = meta.title;
                mimeType = meta.mimeType;
                text = ?text;
                blob = null;
              };
              cb({ contents = [content_block] });
            };
            case (_, _) {
              // Not found. Return an empty list of contents.
              // A proper implementation would return a JSON-RPC error. We'll add that later.
              cb({ contents = [] });
            };
          };
        },
        Decode.readResourceParams,
        MCPEncode.readResourceResult,
      ),
    );

    // 4. `tools/list` handler
    let toolsListHandler = (
      "tools/list",
      Handler.query0<Types.ListToolsResult>(
        func(cb) { cb({ tools = config.tools; nextCursor = null }) },
        MCPEncode.listToolsResult,
      ),
    );

    // 5. `tools/call` handler (with its dispatcher)
    let toolDispatcher = Map.fromIter<Text, ToolFn>(config.toolImplementations.vals(), thash);
    let toolCallHandler = (
      "tools/call",
      Handler.update1<Types.CallToolParams, CallToolResult>(
        func(params : Types.CallToolParams, cb : (Result.Result<CallToolResult, HandlerError>) -> ()) : async () {
          switch (Map.get(toolDispatcher, thash, params.name)) {
            case (?fn) { fn(params.arguments, cb) };
            case (null) {
              cb(#err({ code = -32602; message = "Unknown tool: " # params.name }));
            };
          };
        },
        Decode.callToolParams,
        MCPEncode.callToolResult,
      ),
    );

    // A handler for the `ping` method.
    // We use `Handler.query0` because `ping` takes no parameters.
    let pingHandler = (
      "ping",
      Handler.query0<JsonValue>(
        // The callback `cb` expects the raw success value, not a Result.
        // The `query0` helper wraps it in #ok for us.
        func(cb) {
          cb(Json.obj([]));
        },
        // Use a generic encoder for the raw JSON response.
        MCPEncode.jsonValue,
      ),
    );

    let notificationsInitializedHandler = (
      "notifications/initialized",
      Handler.query0<()>(
        func(cb) { cb(()) }, // No-op, just acknowledges the notification.
        Encode.nullable, // No return value for notifications.
      ),
    );

    // --- Assemble All Routes ---
    var allRoutes = [
      initializeHandler,
      notificationsInitializedHandler,
      resourcesListHandler,
      resourcesReadHandler,
      toolsListHandler,
      toolCallHandler,
      pingHandler,
    ];

    switch (config.customRoutes) {
      case (?routes) {
        allRoutes := Array.append(allRoutes, routes);
      };
      case (null) {};
    };

    // --- Create and return the low-level server ---
    let FAKE_JWT_KEY : Blob = Blob.fromArray([]);
    return Server.Server(allRoutes, FAKE_JWT_KEY);
  };

};
