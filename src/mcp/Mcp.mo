import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Json "mo:json";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import ICRC2 "mo:icrc2-types";
import Error "mo:base/Error";
import Option "mo:base/Option";

// Internal SDK imports
import Server "../server/Server";
import Handler "../server/Handler";
import Encode "../server/Encode";

// Public-facing MCP types
import Types "Types";
import Decode "Decode";
import MCPEncode "Encode";
import Payments "Payments";
import Beacon "Beacon";

// SDK dependencies for monetization
import AuthTypes "../auth/Types";
import ErrorUtils "ErrorUtils";

module {
  public func createServer(config : Types.McpConfig) : Server.Server {
    // --- Auto-generated MCP Handlers ---

    // 1. `initialize` handler
    let initializeHandler = (
      "initialize",
      // MODIFIED: Signature updated to match new Handler.mo
      Handler.query1<Types.InitializeParams, Types.InitializeResult>(
        func(params, auth, cb) {
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
          // MODIFIED: Callback now wraps result in #ok
          cb(#ok({ protocolVersion = params.protocolVersion; capabilities = capabilities; serverInfo = config.serverInfo; instructions = ?"Welcome to the Motoko MCP Server!" }));
        },
        Decode.initializeParams,
        MCPEncode.initializeResult,
      ),
    );

    // 2. `resources/list` handler
    let resourcesListHandler = (
      "resources/list",
      // MODIFIED: Signature updated
      Handler.query0<Types.ListResourcesResult>(
        func(auth, cb) {
          cb(#ok({ resources = config.resources; nextCursor = null }));
        },
        MCPEncode.listResourcesResult,
      ),
    );

    // 3. `resources/read` handler (as an inefficient update call)
    let resourcesReadHandler = (
      "resources/read",
      Handler.update1<Types.ReadResourceParams, Types.ReadResourceResult>(
        func(params : Types.ReadResourceParams, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<Types.ReadResourceResult, Handler.HandlerError>) -> ()) : async () {
          let resource_meta = Array.find<Types.Resource>(config.resources, func(r) { r.uri == params.uri });

          switch (resource_meta) {
            case (null) {
              cb(#err({ code = -32000; message = "Resource not found: " # params.uri; data = null }));
            };
            case (?meta) {

              // Payment is no longer required, so we proceed directly to serving the resource.
              let content_text = config.resourceReader(params.uri);
              switch (content_text) {
                case (?text) {
                  let content_block : Types.ResourceContent = {
                    uri = meta.uri;
                    name = meta.name;
                    title = meta.title;
                    mimeType = meta.mimeType;
                    text = ?text;
                    blob = null;
                  };
                  cb(#ok({ contents = [content_block] }));
                };
                case (null) {
                  cb(#err({ code = -32000; message = "Resource content not found for URI: " # params.uri; data = null }));
                };
              };
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
      // MODIFIED: Signature updated
      Handler.query0<Types.ListToolsResult>(
        func(auth, cb) { cb(#ok({ tools = config.tools; nextCursor = null })) },
        MCPEncode.listToolsResult,
      ),
    );

    // 5. `tools/call` handler (with its dispatcher)
    let toolDispatcher = Map.fromIter<Text, Types.ToolFn>(config.toolImplementations.vals(), thash);
    let toolCallHandler = (
      "tools/call",
      Handler.update1<Types.CallToolParams, Types.CallToolResult>(
        func(params : Types.CallToolParams, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<Types.CallToolResult, Handler.HandlerError>) -> ()) : async () {
          let tool_def = Array.find<Types.Tool>(config.tools, func(t) { t.name == params.name });
          switch (tool_def) {
            case (null) {
              cb(#err({ code = -32602; message = "Unknown tool: " # params.name; data = null }));
            };
            case (?tool) {
              let tool_fn = Map.get(toolDispatcher, thash, tool.name);
              switch (tool_fn) {
                case (null) {
                  cb(#err({ code = -32601; message = "Tool implementation not found: " # tool.name; data = null }));
                };
                case (?fn) {
                  // Create a helper function to encapsulate the call logic.
                  let handle_call = func() : async () {
                    // --- BEACON INTEGRATION POINT ---
                    switch (config.beacon) {
                      case (?beaconCtx) {
                        let principal = Option.get(do ? { auth!.principal }, Principal.fromText("aaaaa-aa"));
                        Beacon.track_call(beaconCtx, principal, tool.name);
                      };
                      case (_) {};
                    };
                    // --- END BEACON INTEGRATION ---

                    // Now, call the actual tool function.
                    await fn(params.arguments, auth, cb);
                  };

                  // Use the new handle_call helper.
                  switch (tool.payment) {
                    case (null) { await handle_call() }; // For free tools
                    case (?paymentInfo) {
                      let paymentResult = await Payments.handlePayment(paymentInfo, config.self, auth, config.allowanceUrl);
                      switch (paymentResult) {
                        case (#ok(_)) {
                          await handle_call(); // For paid tools after successful payment
                        };
                        case (#err(handlerError)) {
                          // Payment failed. Translate the protocol error into a tool error for the agent.
                          let structured = Json.obj([("error", Json.str(handlerError.message))]);
                          let toolErrorResult : Types.CallToolResult = {
                            content = [#text({ text = Json.stringify(structured, null) })];
                            isError = true;
                            structuredContent = ?structured;
                          };
                          cb(#ok(toolErrorResult));
                        };
                      };
                    };
                  };
                };
              };
            };
          };
        },
        Decode.callToolParams,
        MCPEncode.callToolResult,
      ),
    );

    // 6. `ping` handler
    let pingHandler = (
      "ping",
      // MODIFIED: Signature updated
      Handler.query0<Types.JsonValue>(
        func(auth, cb) { cb(#ok(Json.obj([]))) },
        MCPEncode.jsonValue,
      ),
    );

    // 7. `notifications/initialized` handler
    let notificationsInitializedHandler = (
      "notifications/initialized",
      // MODIFIED: Signature updated
      Handler.query0<()>(
        func(auth, cb) { cb(#ok(())) },
        Encode.nullable,
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

    return Server.Server(allRoutes);
  };
};
