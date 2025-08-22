import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Result "mo:base/Result";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Json "mo:json";
import HttpTypes "mo:http-types";

// The only SDK import the user needs!
import Mcp "../../../src/mcp/Mcp";
import McpTypes "../../../src/mcp/Types";
import AuthCleanup "../../../src/auth/Cleanup";
import AuthTypes "../../../src/auth/Types";
import HttpHandler "../../../src/mcp/HttpHandler";
import SrvTypes "../../../src/server/Types";
import Cleanup "../../../src/mcp/Cleanup";
import State "../../../src/mcp/State";

import IC "mo:ic";

// Auth
import AuthState "../../../src/auth/State";
import HttpAssets "../../../src/mcp/HttpAssets";

shared persistent actor class McpServer() = self {

  // State for certified HTTP assets (like /.well-known/...)
  var stable_http_assets : HttpAssets.StableEntries = [];
  transient let http_assets = HttpAssets.init(stable_http_assets);

  // --- STATE (Lives in the main actor) ---
  var resourceContents = [
    ("file:///main.py", "print('Hello from main.py!')"),
    ("file:///README.md", "# MCP Motoko Server"),
  ];

  // The application context that holds our state.
  var appContext : McpTypes.AppContext = State.init(resourceContents);

  let issuerUrl = "https://bfggx-7yaaa-aaaai-q32gq-cai.icp0.io";
  let requiredScopes = ["openid"];

  //function to transform the response for jwks client
  public query func transformJwksResponse({
    context : Blob;
    response : IC.HttpRequestResult;
  }) : async IC.HttpRequestResult {
    {
      response with headers = []; // not intersted in the headers
    };
  };

  // Initialize the auth context with the issuer URL and required scopes.
  let authContext : AuthTypes.AuthContext = AuthState.init(
    Principal.fromActor(self),
    issuerUrl,
    requiredScopes,
    transformJwksResponse,
  );

  // --- Cleanup Timers ---
  Cleanup.startCleanupTimer<system>(appContext);
  AuthCleanup.startCleanupTimer<system>(authContext);

  // --- 1. DEFINE YOUR RESOURCES & TOOLS ---
  var resources : [McpTypes.Resource] = [
    {
      uri = "file:///main.py";
      name = "main.py";
      title = ?"Main Python Script";
      description = ?"Contains the main logic of the application.";
      mimeType = ?"text/x-python";
    },
    {
      uri = "file:///README.md";
      name = "README.md";
      title = ?"Project Documentation";
      description = null;
      mimeType = ?"text/markdown";
    },
  ];

  var tools : [McpTypes.Tool] = [{
    name = "get_weather";
    title = ?"Weather Provider";
    description = ?"Get current weather information for a location";
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
    serverInfo = {
      name = "full-onchain-mcp-server";
      title = "Full On-chain MCP Server";
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
      auth = ?authContext;
      http_asset_cache = ?http_assets.cache;
    };
  };

  public query func http_request(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    return HttpHandler.http_request(ctx, req);
  };

  public func http_request_update(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    return await HttpHandler.http_request_update(ctx, req);
  };

  public query func http_request_streaming_callback(token : HttpTypes.StreamingToken) : async ?HttpTypes.StreamingCallbackResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    return HttpHandler.http_request_streaming_callback(ctx, token);
  };

  system func preupgrade() {
    stable_http_assets := HttpAssets.preupgrade(http_assets);
  };

  system func postupgrade() {
    HttpAssets.postupgrade(http_assets);
  };
};
