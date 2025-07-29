// src/mcp/JwksClient.mo
// A stateless logic module that operates on a mutable AuthContext object
// to fetch and cache JSON Web Key Sets (JWKS).

import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Json "mo:json";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import IC "ic:aaaaa-aa";

import Types "Types";
import Jwk "Jwk";

module {
  // A reasonable amount of cycles for a single HTTPS GET request.
  let HTTPS_OUTCALL_CYCLES : Nat = 2_000_000_000; // 2B cycles
  // This module is completely stateless.

  // Helper to perform a GET request using the native IC interface.
  private func _http_get(url : Text, transformFunc : Types.JwksTransformFunc) : async Result.Result<Text, Text> {
    let http_request : IC.http_request_args = {
      url = url;
      max_response_bytes = null;
      headers = [{ name = "User-Agent"; value = "mcp-motoko-sdk/1.0" }];
      body = null;
      method = #get;
      transform = ?{
        function = transformFunc;
        context = Blob.fromArray([]);
      };
    };

    let http_response = await (with cycles = HTTPS_OUTCALL_CYCLES) IC.http_request(http_request);

    if (http_response.status < 200 or http_response.status >= 300) {
      return #err("HTTP request failed with status " # Nat.toText(http_response.status));
    };

    switch (Text.decodeUtf8(http_response.body)) {
      case (null) { return #err("Failed to decode response body.") };
      case (?text) { return #ok(text) };
    };
  };

  private func _fetchAndCacheKeys(ctx : Types.AuthContext, issuerUrl : Text) : async ?[(Text, Blob)] {
    let metadataUrl = issuerUrl # "/.well-known/oauth-authorization-server";

    let newKeysArray = do ? {
      let metadataText = Result.toOption(await _http_get(metadataUrl, ctx.jwksTransform))!;
      let metadataJson = Result.toOption(Json.parse(metadataText))!;
      let jwksUri = Result.toOption(Json.getAsText(metadataJson, "jwks_uri"))!;

      let jwksText = Result.toOption(await _http_get(jwksUri, ctx.jwksTransform))!;
      let jwksJson = Result.toOption(Json.parse(jwksText))!;
      let keysArray = Result.toOption(Json.getAsArray(jwksJson, "keys"))!;

      var parsedKeysMap = Map.new<Text, Blob>();
      for (keyJson in keysArray.vals()) {
        ignore do ? {
          let kid = Result.toOption(Json.getAsText(keyJson, "kid"))!;
          let keyBlob = Result.toOption(Jwk.jwkToPublicKeyBlob(keyJson))!;
          Map.set(parsedKeysMap, thash, kid, keyBlob);
        };
      };

      // Mutate the context with the new map of keys.
      Map.set(ctx.jwksCache, thash, issuerUrl, parsedKeysMap);

      // Convert the map to a sharable array before returning.
      Iter.toArray(Map.entries(parsedKeysMap));
    };

    return newKeysArray;
  };

  /// The public function to get a specific public key.
  public func getPublicKey(ctx : Types.AuthContext, issuerUrl : Text, kid : Text) : async ?Blob {
    switch (Map.get(ctx.jwksCache, thash, issuerUrl)) {
      case (?keys) {
        // Cache hit.
        return Map.get(keys, thash, kid);
      };
      case (null) {
        // Cache miss, fetch the keys.
        switch (await _fetchAndCacheKeys(ctx, issuerUrl)) {
          case (?newlyFetchedKeysArray) {
            // We received an array, so we must iterate to find the key.
            for ((keyId, keyBlob) in newlyFetchedKeysArray.vals()) {
              if (keyId == kid) {
                return ?keyBlob;
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
