import Json "mo:json";
import HttpTypes "mo:http-types";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Types "Types";
import Encode "../server/Encode";
import AuthTypes "../auth/Types";

module {
  // Creates a generic HTTP response with a JSON body.
  public func jsonResponse(status : Nat16, body : Json.Json, headers : [HttpTypes.Header]) : HttpTypes.Response {
    return {
      status_code = status;
      headers = Array.append([("Content-Type", "application/json")], headers);
      body = Text.encodeUtf8(Json.stringify(body, null));
      upgrade = null;
      streaming_strategy = null;
    };
  };

  // Helper function to convert a Nat64 into an array of 8 bytes.
  // This is the "hack" needed due to the lack of a direct Nat64.toNat8 function.
  public func nat64ToBytes(n : Nat64) : [Nat8] {
    return Array.tabulate<Nat8>(
      8,
      func(i) {
        // 1. Isolate the byte we want as a Nat64.
        let byte_as_nat64 = (n >> (Nat64.fromNat(i) * 8)) & 0xFF;
        // 2. Convert the Nat64 to a general-purpose Nat. This is a safe operation
        //    because we know the value is between 0 and 255.
        let byte_as_nat = Nat64.toNat(byte_as_nat64);
        // 3. Convert the Nat to a Nat8. This is also safe.
        return Nat8.fromNat(byte_as_nat);
      },
    );
  };

  // Safely extracts the host from the request headers, with a fallback for local dev.
  private func getHostFromReq(req : HttpTypes.Request) : Text {
    let headers = Map.fromIter<Text, Text>(req.headers.vals(), thash);
    return Option.get(Map.get(headers, thash, "host"), "127.0.0.1:4943");
  };

  // Determines the environment based on the host header. This is the core decision-maker.
  private func getEnvironment(host : Text) : Types.Environment {
    if (Text.contains(host, #text("127.0.0.1")) or Text.contains(host, #text("localhost"))) {
      return #local;
    } else {
      return #production;
    };
  };

  /**
   * A helper function to get a URL for this canister, optionally with a path.
   * This version correctly handles trailing slashes and path construction for
   * both production and local environments.
   * @param self The canister's own Principal.
   * @param req The incoming HTTP request, used to determine the host.
   * @param path An optional path to append to the canister's base URL (e.g., ?".well-known/oauth-protected-resource").
   * @returns The full URL.
   */
  public func getThisUrl(self : Principal, req : HttpTypes.Request, path : ?Text) : Text {
    let hostFromHeader = getHostFromReq(req);
    let selfCanisterIdText = Principal.toText(self);

    var pathSegment : Text = "";
    switch (path) {
      case (?p) {
        // If a path is provided, ensure it starts with a slash.
        if (Text.startsWith(p, #char '/')) {
          pathSegment := p;
        } else {
          pathSegment := "/" # p;
        };
      };
      case (null) {
        // If no path is provided, the "path" is just a single trailing slash.
        // This is the key fix for the validation error.
        pathSegment := "/";
      };
    };

    switch (getEnvironment(hostFromHeader)) {
      case (#production) {
        // e.g., "https://<canister_id>.icp0.io" + "/"
        // or "https://<canister_id>.icp0.io" + "/.well-known/..."
        return "https://" # hostFromHeader # pathSegment;
      };
      case (#local) {
        let baseUrl = "http://" # hostFromHeader;
        let canisterIdIsMissing = not Text.contains(hostFromHeader, #text(selfCanisterIdText));

        if (canisterIdIsMissing) {
          // Correct order: base_url + path + query_string
          // e.g., "http://127.0.0.1:4943" + "/" + "?canisterId=..."
          return baseUrl # pathSegment # "?canisterId=" # selfCanisterIdText;
        } else {
          return baseUrl # pathSegment;
        };
      };
    };
  };

  // Get json body for resource metadata.
  public func getResourceMetadataBlob(
    self : Principal,
    mcpPath : Text,
    oidcState : AuthTypes.OidcState,
    req : HttpTypes.Request,
  ) : Blob {

    let jsonScopes = Encode.array(oidcState.requiredScopes, Json.str);

    // Auth is enabled, so serve the metadata document.
    let bodyJson = Json.obj([
      ("authorization_servers", Json.arr([Json.str(oidcState.issuerUrl)])),
      ("resource", Json.str(getThisUrl(self, req, ?mcpPath))),
      ("scopes_supported", jsonScopes),
    ]);

    let stringified = Json.stringify(bodyJson, null);

    return Text.encodeUtf8(stringified);
  };

  // A helper function to ensure URIs are stored and looked up consistently.
  public func normalizeUri(uri : Text) : Text {
    return Text.trimEnd(uri, #char '/');
  };
};
