import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Json "mo:json";
import HttpTypes "mo:http-types";

// The only SDK import the user needs!
import Mcp "../../../src/mcp/Mcp";
import McpTypes "../../../src/mcp/Types";
import AuthTypes "../../../src/auth/Types";
import HttpHandler "../../../src/mcp/HttpHandler";
import SrvTypes "../../../src/server/Types";
import Cleanup "../../../src/mcp/Cleanup";
import State "../../../src/mcp/State";

shared persistent actor class McpServer() = self {
  // --- STATE (Lives in the main actor) ---
  var resourceContents = [
    ("file:///main.py", "print('Hello from main.py!')"),
    ("file:///README.md", "# MCP Motoko Server"),
  ];

  var appContext : McpTypes.AppContext = State.init(resourceContents);

  // --- Cleanup Timer For Deleting Old Streams ---
  Cleanup.startCleanupTimer<system>(appContext);

  // --- 1. DEFINE YOUR RESOURCES & TOOLS ---
  var resources : [McpTypes.Resource] = [
    {
      uri = "file:///main.py";
      name = "main.py";
      title = ?"Main Python Script";
      description = ?"Contains the main logic of the application.";
      mimeType = ?"text/x-python";
      payment = null;
    },
    {
      uri = "file:///README.md";
      name = "README.md";
      title = ?"Project Documentation";
      description = null;
      mimeType = ?"text/markdown";
      payment = null;
    },
  ];

  var tools : [McpTypes.Tool] = [{
    name = "get_weather";
    title = ?"Weather Provider";
    description = ?"Get current weather information for a location";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("location", Json.obj([("type", Json.str("string")), ("description", Json.str("City name or zip code"))]))])),
      ("required", Json.arr([Json.str("location")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("report", Json.obj([("type", Json.str("string")), ("description", Json.str("The textual weather report."))]))])),
      ("required", Json.arr([Json.str("report")])),
    ]);
  }];

  // --- 2. DEFINE YOUR TOOL LOGIC ---
  func getWeatherTool(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    let location = switch (Result.toOption(Json.getAsText(args, "location"))) {
      case (?loc) { loc };
      case (null) {
        return cb(#ok({ content = [#text({ text = "Missing 'location' arg." })]; isError = true; structuredContent = null }));
      };
    };

    // The human-readable report.
    let report = "The weather in " # location # " is sunny.";

    // Build the structured JSON payload that matches our outputSchema.
    let structuredPayload = Json.obj([("report", Json.str(report))]);
    let stringified = Json.stringify(structuredPayload, null);

    // Return the full, compliant result.
    cb(#ok({ content = [#text({ text = stringified })]; isError = false; structuredContent = ?structuredPayload }));
  };

  // --- 3. CONFIGURE THE SDK ---
  transient let mcpConfig : McpTypes.McpConfig = {
    self = Principal.fromActor(self);
    allowanceUrl = null; // No payment handling in this public example
    serverInfo = {
      name = "MCP-Motoko-Server";
      title = "MCP Motoko Reference Server";
      version = "0.1.0";
    };
    resources = resources;
    resourceReader = func(uri) {
      Map.get(appContext.resourceContents, thash, uri);
    };
    tools = tools;
    toolImplementations = [
      ("get_weather", getWeatherTool),
    ];
  };

  // --- 4. CREATE THE SERVER LOGIC ---
  transient let mcpServer = Mcp.createServer(mcpConfig);

  // --- PUBLIC ENTRY POINTS ---

  // Helper to avoid repeating context creation.
  private func _create_http_context() : HttpHandler.Context {
    return {
      self = Principal.fromActor(self);
      active_streams = appContext.activeStreams;
      mcp_server = mcpServer;
      streaming_callback = http_request_streaming_callback;
      auth = null;
      http_asset_cache = null;
      mcp_path = ?"/mcp";
    };
  };

  public query func http_request(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    // Ask the SDK to handle the request
    switch (HttpHandler.http_request(ctx, req)) {
      case (?mcpResponse) {
        // The SDK handled it, so we return its response.
        return mcpResponse;
      };
      case (null) {
        // The SDK ignored it. Now we can handle our own custom routes.
        if (req.url == "/") {
          // e.g., Serve a frontend asset
          return {
            status_code = 200;
            headers = [("Content-Type", "text/html")];
            body = Text.encodeUtf8("<h1>My Canister Frontend</h1>");
            upgrade = null;
            streaming_strategy = null;
          };
        } else {
          // Return a 404 for any other unhandled routes.
          return {
            status_code = 404;
            headers = [];
            body = Blob.fromArray([]);
            upgrade = null;
            streaming_strategy = null;
          };
        };
      };
    };
  };

  public shared func http_request_update(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();

    // Ask the SDK to handle the request
    let mcpResponse = await HttpHandler.http_request_update(ctx, req);

    switch (mcpResponse) {
      case (?res) {
        // The SDK handled it.
        return res;
      };
      case (null) {
        // The SDK ignored it. Handle custom update calls here.
        return {
          status_code = 404;
          headers = [];
          body = Blob.fromArray([]);
          upgrade = null;
          streaming_strategy = null;
        };
      };
    };
  };

  public query func http_request_streaming_callback(token : HttpTypes.StreamingToken) : async ?HttpTypes.StreamingCallbackResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    return HttpHandler.http_request_streaming_callback(ctx, token);
  };
};
