import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Json "../../../src/json";
import HttpTypes "mo:http-types";
import BaseX "mo:base-x-encoder";

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

  // The streaming callback MUST be a public function of the main actor.
  public query func http_request_streaming_callback(token : HttpTypes.StreamingToken) : async ?HttpTypes.StreamingCallbackResponse {
    let token_key = BaseX.toBase64(token.vals(), #standard({ includePadding = true }));
    // It has access to the actor's state.
    if (Option.isNull(Map.get(appContext.activeStreams, thash, token_key))) {
      return ?{ body = Blob.fromArray([]); token = null };
    };

    // Update the timestamp to prove the stream is still active.
    Map.set(appContext.activeStreams, thash, token_key, Time.now());

    let chunk = Text.encodeUtf8("data: {\"type\":\"keep-alive\"}\n\n");
    return ?{ body = chunk; token = ?token };
  };

  public query func http_request(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    // Construct the context object on the fly.
    let ctx : HttpHandler.Context = {
      self = Principal.fromActor(self); // Pass the server principal
      active_streams = appContext.activeStreams;
      mcp_server = mcpServer;
      streaming_callback = http_request_streaming_callback;
      auth = null; // No authentication in this example.
      http_asset_cache = null; // No HTTP asset cache in this example.
    };
    // Delegate the complex logic to the handler module.
    return HttpHandler.http_request(ctx, req);
  };

  public func http_request_update(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = {
      self = Principal.fromActor(self); // Pass the server principal
      active_streams = appContext.activeStreams;
      mcp_server = mcpServer;
      streaming_callback = http_request_streaming_callback;
      auth = null; // No authentication in this example.
      http_asset_cache = null; // No HTTP asset cache in this example.
    };
    return await HttpHandler.http_request_update(ctx, req);
  };
};
