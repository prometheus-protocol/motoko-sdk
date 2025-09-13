import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Result "mo:base/Result";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Json "mo:json";
import HttpTypes "mo:http-types";

// The only SDK import the user needs!
import Mcp "../../../src/mcp/Mcp";
import McpTypes "../../../src/mcp/Types";
import AuthTypes "../../../src/auth/Types";
import AuthCleanup "../../../src/auth/Cleanup";
import HttpHandler "../../../src/mcp/HttpHandler";
import SrvTypes "../../../src/server/Types";
import Cleanup "../../../src/mcp/Cleanup";
import State "../../../src/mcp/State";
import Payments "../../../src/mcp/Payments";

import IC "mo:ic"; // Import the IC module for HTTP requests

// Auth
import AuthState "../../../src/auth/State";
import HttpAssets "../../../src/mcp/HttpAssets";

shared ({ caller = deployer }) persistent actor class McpServer(
  args : ?{
    paymentLedger : Principal;
  }
) = self {

  var owner : Principal = deployer;

  let paymentLedger : Principal = switch (args) {
    case (?a) { a.paymentLedger };
    case (null) { Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai") }; // Default to ICP ledger
  };

  // Ownership
  /// Returns the principal of the current owner of this canister.
  public query func get_owner() : async Principal {
    return owner;
  };

  /// Transfers ownership of the canister to a new principal.
  /// Only the current owner can call this function.
  public shared ({ caller }) func set_owner(new_owner : Principal) : async Result.Result<(), Payments.TreasuryError> {
    if (caller != owner) {
      return #err(#NotOwner);
    };
    owner := new_owner;
    return #ok(());
  };

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

  let issuerUrl = "https://mock-auth-server.com";
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
    owner, // Set the owner to the canister itself for this example
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
    name = "generate_image";
    title = ?"Image Generator";
    description = ?"Generate an image from a text prompt";
    payment = ?{
      amount = 1_000_000; // Corrected amount to match test
      ledger = paymentLedger;
    };
    // MODIFIED: The input schema now expects a 'prompt'.
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("prompt", Json.obj([("type", Json.str("string")), ("description", Json.str("A text description of the image to generate."))]))])),
      ("required", Json.arr([Json.str("prompt")])),
    ]);
    // MODIFIED: The output schema now returns an 'imageUrl'.
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("imageUrl", Json.obj([("type", Json.str("string")), ("description", Json.str("The URL of the generated image."))]))])),
      ("required", Json.arr([Json.str("imageUrl")])),
    ]);
  }];

  // --- 2. DEFINE YOUR TOOL LOGIC ---
  // This is the function that executes when the tool is called.

  func generateImageTool(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    // MODIFIED: Get the 'prompt' argument instead of 'location'.
    let prompt = switch (Result.toOption(Json.getAsText(args, "prompt"))) {
      case (?p) { p };
      case (null) {
        // Return a tool-level error if the required argument is missing.
        return cb(#ok({ content = [#text({ text = "Missing required 'prompt' argument." })]; isError = true; structuredContent = null }));
      };
    };

    // MODIFIED: Simulate generating an image URL based on the prompt.
    // In a real application, this would call an image generation service.
    let sanitizedPrompt = Text.replace(prompt, #text " ", "-");
    let imageUrl = "https://images.example.com/" # sanitizedPrompt # ".png";

    // MODIFIED: Build the structured JSON payload that matches our new outputSchema.
    let structuredPayload = Json.obj([("imageUrl", Json.str(imageUrl))]);

    // Return the full, compliant result.
    cb(#ok({ content = [#text({ text = "Image generated successfully: " # imageUrl })]; isError = false; structuredContent = ?structuredPayload }));
  };

  // --- 3. CONFIGURE THE SDK ---
  transient let mcpConfig : McpTypes.McpConfig = {
    self = Principal.fromActor(self);
    allowanceUrl = ?"https://canister_id.icp0.io/allowances"; // Example allowance URL for payment handling
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
      ("generate_image", generateImageTool),
    ];
    beacon = null;
  };

  // --- 4. CREATE THE SERVER LOGIC ---
  transient let mcpServer = Mcp.createServer(mcpConfig);

  // --- PUBLIC ENTRY POINTS ---

  // Treasury
  public shared func get_treasury_balance(ledger_id : Principal) : async Nat {
    return await Payments.get_treasury_balance(Principal.fromActor(self), ledger_id);
  };

  public shared ({ caller }) func withdraw(
    ledger_id : Principal,
    amount : Nat,
    destination : Payments.Destination,
  ) : async Result.Result<Nat, Payments.TreasuryError> {
    return await Payments.withdraw(
      caller,
      owner,
      ledger_id,
      amount,
      destination,
    );
  };

  // Helper to avoid repeating context creation.
  private func _create_http_context() : HttpHandler.Context {
    return {
      self = Principal.fromActor(self);
      active_streams = appContext.activeStreams;
      mcp_server = mcpServer;
      streaming_callback = http_request_streaming_callback;
      auth = ?authContext;
      http_asset_cache = ?http_assets.cache;
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

  system func preupgrade() {
    stable_http_assets := HttpAssets.preupgrade(http_assets);
  };

  system func postupgrade() {
    HttpAssets.postupgrade(http_assets);
  };
};
