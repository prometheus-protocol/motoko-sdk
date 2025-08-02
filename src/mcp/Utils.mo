import Json "mo:json";
import HttpTypes "mo:http-types";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
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
   * A helper function to get the URL for this canister.
   * This version is robust enough to handle both production and local test environments.
   * @param context The canister's context, containing its own Principal (self).
   * @param req The incoming HTTP request, used to determine the host.
   * @returns The canister URL (e.g., "https://<auth_canister_id>.icp0.io").
   */
  public func getThisUrl(self : Principal, req : HttpTypes.Request) : Text {
    let hostFromHeader = getHostFromReq(req);
    let selfCanisterIdText = Principal.toText(self);
    var finalHost : Text = "";

    switch (getEnvironment(hostFromHeader)) {
      case (#production) {
        // In production, the host header is already correct.
        finalHost := hostFromHeader;
        return "https://" # finalHost;
      };
      case (#local) {
        // In local dev, we might need to fix the host for E2E tests.
        let canisterIdIsMissing = not Text.contains(hostFromHeader, #text(selfCanisterIdText));
        if (canisterIdIsMissing) {
          // Prepend the canister ID if it's not in the host string.
          finalHost := selfCanisterIdText # "." # hostFromHeader;
        } else {
          finalHost := hostFromHeader;
        };
        return "http://" # finalHost;
      };
    };
  };

  // Get json body for resource metadata.
  public func getResourceMetadataBlob(
    self : Principal,
    authCtx : AuthTypes.AuthContext,
    req : HttpTypes.Request,
  ) : Blob {

    let jsonScopes = Encode.array(authCtx.requiredScopes, Json.str);

    // Auth is enabled, so serve the metadata document.
    let bodyJson = Json.obj([
      ("authorization_servers", Json.arr([Json.str(authCtx.issuerUrl)])),
      ("resource", Json.str(getThisUrl(self, req))),
      ("scopes_supported", jsonScopes),
    ]);

    let stingified = Json.stringify(bodyJson, null);

    return Text.encodeUtf8(stingified);
  };
};
