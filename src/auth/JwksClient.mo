// src/mcp/JwksClient.mo
// A stateless logic module that operates on a mutable AuthContext object
// to fetch and cache JSON Web Key Sets (JWKS).

import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Json "mo:json";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import IC "ic:aaaaa-aa";

import Types "Types";
import Jwk "Jwk";

module {
  // A reasonable amount of cycles for a single HTTPS GET request.
  let HTTPS_OUTCALL_CYCLES : Nat = 30_000_000_000; // 30B cycles
  // This module is completely stateless.

  // Helper to perform a GET request using the native IC interface.
  private func _http_get(url : Text) : async Result.Result<Text, Text> {
    let http_request : IC.http_request_args = {
      url = url;
      max_response_bytes = null;
      headers = [{ name = "User-Agent"; value = "mcp-motoko-sdk/1.0" }];
      body = null;
      method = #get;
      transform = null; // No transform function needed for simple GET.
    };

    let http_response = await (with cycles = HTTPS_OUTCALL_CYCLES) IC.http_request(http_request);

    if (http_response.status < 200 or http_response.status >= 300) {
      return #err("HTTP request failed with status " # Nat.toText(http_response.status));
    };

    switch (Text.decodeUtf8(http_response.body)) {
      case (null) { return #err("Failed to decode response body.") };
      case (?text) {
        Debug.print("HTTP GET response: " # text);
        return #ok(text);
      };
    };
  };

  private func _fetchAndCacheKeys(ctx : Types.AuthContext) : async ?[(Text, Types.PublicKeyData)] {
    let metadataUrl = ctx.issuerUrl # "/.well-known/oauth-authorization-server";

    let newKeysArray = do ? {
      let metadataText = Result.toOption(await _http_get(metadataUrl))!;
      let metadataJson = Result.toOption(Json.parse(metadataText))!;
      let jwksUri = Result.toOption(Json.getAsText(metadataJson, "jwks_uri"))!;

      let jwksText = Result.toOption(await _http_get(jwksUri))!;
      let jwksJson = Result.toOption(Json.parse(jwksText))!;
      let keysArray = Result.toOption(Json.getAsArray(jwksJson, "keys"))!;

      var parsedKeysMap = Map.new<Text, Types.PublicKeyData>();
      for (keyJson in keysArray.vals()) {
        ignore do ? {
          let kid = Result.toOption(Json.getAsText(keyJson, "kid"))!;
          let keyBlob = Result.toOption(Jwk.jwkToPublicKeyData(keyJson))!;
          Map.set(parsedKeysMap, thash, kid, keyBlob);
        };
      };

      // Mutate the context with the new map of keys.
      Map.set(ctx.jwksCache, thash, ctx.issuerUrl, parsedKeysMap);

      // Convert the map to a sharable array before returning.
      Iter.toArray(Map.entries(parsedKeysMap));
    };

    return newKeysArray;
  };

  /// The public function to get a specific public key.
  public func getPublicKey(ctx : Types.AuthContext, kid : Text) : async ?Types.PublicKeyData {
    switch (Map.get(ctx.jwksCache, thash, ctx.issuerUrl)) {
      case (?keys) {
        // Cache hit.
        Debug.print("Cache hit for JWKS key: " # kid);
        let cachedPkData = Map.get(keys, thash, kid);
        Debug.print("Found key: " # debug_show cachedPkData);
        let reconstructedPkData = switch (cachedPkData) {
          case (?data) {
            ?{
              x = data.x;
              y = data.y;
              curveKind = data.curveKind;
            };
          };
          case (null) { null };
        };

        // Return the newly constructed object, wrapped in an async block.
        return reconstructedPkData;
      };
      case (null) {
        // Cache miss, fetch the keys.
        switch (await _fetchAndCacheKeys(ctx)) {
          case (?newlyFetchedKeysArray) {
            // We received an array, so we must iterate to find the key.
            for ((keyId, keyData) in newlyFetchedKeysArray.vals()) {
              if (keyId == kid) {
                return ?keyData;
              };
            };
            // Key with the specified kid was not in the fetched set.
            return null;
          };
          case (null) {
            // The entire fetch operation failed.
            return null;
          };
        };
      };
    };
  };
};
