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
import Beacon "../../../src/mcp/Beacon";

import IC "mo:ic"; // Import the IC module for HTTP requests

// Auth
import AuthState "../../../src/auth/State";
import HttpAssets "../../../src/mcp/HttpAssets";

shared ({ caller = deployer }) persistent actor class McpServer(
  args : ?{
    beaconCanisterId : Principal;
    beaconIntervalSec : Nat;
  }
) = self {

  let beaconCanisterId : Principal = switch (args) {
    case (?a) { a.beaconCanisterId };
    case (null) { Principal.fromText("aaaaa-aa") }; // Default to the public beacon canister
  };
  let beaconIntervalSec : ?Nat = switch (args) {
    case (?a) { ?a.beaconIntervalSec };
    case (null) { null };
  };

  // State for certified HTTP assets (like /.well-known/...)
  var stable_http_assets : HttpAssets.StableEntries = [];
  transient let http_assets = HttpAssets.init(stable_http_assets);

  // The application context that holds our state.
  var appContext : McpTypes.AppContext = State.init([]);

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
    deployer, // Set the owner to the deployer for this example
    issuerUrl,
    requiredScopes,
    transformJwksResponse,
  );

  // Initialize the beacon context
  let beaconContext : Beacon.BeaconContext = Beacon.init(
    beaconCanisterId, // Public beacon canister ID
    beaconIntervalSec, // Send a beacon every 10 seconds
  );

  // --- Timers ---
  Cleanup.startCleanupTimer<system>(appContext);
  AuthCleanup.startCleanupTimer<system>(authContext);
  Beacon.startTimer<system>(beaconContext);

  // --- 3. DEFINE YOUR TOOLS ---
  var tools : [McpTypes.Tool] = [
    {
      name = "get_balance";
      title = null;
      description = null;
      payment = null;
      inputSchema = Json.obj([]);
      outputSchema = null;
    },
    {
      name = "get_transactions";
      title = null;
      description = null;
      payment = null;
      inputSchema = Json.obj([]);
      outputSchema = null;
    },
  ];

  // --- 4. DEFINE YOUR TOOL LOGIC ---
  func getBalanceTool(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async {
    cb(#ok({ content = [#text({ text = "{\"balance\": 100}" })]; isError = false; structuredContent = null }));
  };

  func getTransactionsTool(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async {
    cb(#ok({ content = [#text({ text = "{\"transactions\": []}" })]; isError = false; structuredContent = null }));
  };

  // --- 5. CONFIGURE THE SDK ---
  transient let mcpConfig : McpTypes.McpConfig = {
    self = Principal.fromActor(self);
    allowanceUrl = null;
    serverInfo = {
      name = "Beacon-Test-Server";
      title = "MCP Beacon Test Server";
      version = "0.1.0";
    };
    resources = [];
    resourceReader = func(_) { null };
    tools = tools;
    toolImplementations = [
      ("get_balance", getBalanceTool),
      ("get_transactions", getTransactionsTool),
    ];
    beacon = ?beaconContext; // Enable beacon tracking
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
      deployer,
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
