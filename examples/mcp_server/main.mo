import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Json "../../src/json";
import HttpTypes "mo:http-types";
import BaseX "mo:base-x-encoder";

// The only SDK import the user needs!
import Mcp "../../src/mcp/Mcp";
import HttpHandler "../../src/mcp/HttpHandler";
import SrvTypes "../../src/server/Types";

shared persistent actor class McpServer() {
  // --- STATE (Lives in the main actor) ---
  var active_streams = Map.new<Text, ()>();

  // --- 1. DEFINE YOUR RESOURCES & TOOLS ---
  var resources : [Mcp.Resource] = [
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

  var resourceContents : Map.Map<Text, Text> = Map.fromIter(
    [
      ("file:///main.py", "print('Hello from main.py!')"),
      ("file:///README.md", "# MCP Motoko Server"),
    ].vals(),
    thash,
  );

  var tools : [Mcp.Tool] = [{
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

  // --- 2. DEFINE YOUR LOGIC ---
  func get_weather_tool(args : Mcp.JsonValue, cb : (Result.Result<Mcp.CallToolResult, Mcp.HandlerError>) -> ()) {
    let location = switch (Result.toOption(Json.getAsText(args, "location"))) {
      case (?loc) { loc };
      case (null) {
        return cb(#ok({ content = [#text({ text = "Missing 'location' arg." })]; isError = true; structuredContent = null }));
      };
    };

    // The human-readable report.
    let report = "The weather in " # location # " is sunny.";

    // CORRECTED: Build the structured JSON payload that matches our outputSchema.
    let structured_payload = Json.obj([("report", Json.str(report))]);
    let stringified = Json.stringify(structured_payload, null);

    Debug.print("stringified structured payload : " # stringified);

    // Return the full, compliant result.
    cb(#ok({ content = [#text({ text = Json.stringify(structured_payload, null) })]; isError = false; structuredContent = ?structured_payload }));
  };

  // --- 3. CONFIGURE THE SDK ---
  transient let mcp_config : Mcp.McpConfig = {
    serverInfo = {
      name = "MCP-Motoko-Server";
      title = "MCP Motoko Reference Server";
      version = "0.1.0";
    };
    resources = resources;
    resourceReader = func(uri) { Map.get(resourceContents, thash, uri) };
    tools = tools;
    toolImplementations = [
      ("get_weather", get_weather_tool),
    ];
    customRoutes = null; // No extra routes for now.
  };

  // --- 4. CREATE THE SERVER LOGIC ---
  transient let mcp_server = Mcp.createServer(mcp_config);

  // --- PUBLIC ENTRY POINTS ---

  // The streaming callback MUST be a public function of the main actor.
  public query func http_request_streaming_callback(token : HttpTypes.StreamingToken) : async ?HttpTypes.StreamingCallbackResponse {
    let token_key = BaseX.toBase64(token.vals(), #standard({ includePadding = true }));
    // It has access to the actor's state.
    if (Option.isNull(Map.get(active_streams, thash, token_key))) {
      return ?{ body = Blob.fromArray([]); token = null };
    };
    let chunk = Text.encodeUtf8("data: {\"type\":\"keep-alive\"}\n\n");
    return ?{ body = chunk; token = ?token };
  };

  public query func http_request(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    // Construct the context object on the fly.
    let ctx : HttpHandler.Context = {
      active_streams = active_streams;
      mcp_server = mcp_server;
      streaming_callback = http_request_streaming_callback;
    };
    // Delegate the complex logic to the handler module.
    return HttpHandler.http_request(ctx, req);
  };

  public func http_request_update(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = {
      active_streams = active_streams;
      mcp_server = mcp_server;
      streaming_callback = http_request_streaming_callback;
    };
    return await HttpHandler.http_request_update(ctx, req);
  };
};
