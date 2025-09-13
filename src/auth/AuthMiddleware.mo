// src/mcp/AuthMiddleware.mo

import Types "Types";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Principal "mo:base/Principal";
import JwksClient "JwksClient";
import HttpTypes "mo:http-types";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Float "mo:base/Float";
import Blob "mo:base/Blob";
import Jwt "mo:jwt";
import ECDSA "mo:ecdsa";
import Sha256 "mo:sha2/Sha256";
import Utils "../mcp/Utils";
import Map "mo:map/Map";
import { thash } "mo:map/Map";
import BaseX "mo:base-x-encoder";
import Base16 "mo:base16/Base16";

module {
  // --- Private Helper Functions ---
  private func _get_api_key(req : HttpTypes.Request) : ?Text {
    for ((name, value) in req.headers.vals()) {
      if (Text.toLowercase(name) == "x-api-key") {
        return ?value;
      };
    };
    return null;
  };

  private func _get_auth_token(req : HttpTypes.Request) : ?Text {
    for ((name, value) in req.headers.vals()) {
      if (Text.toLowercase(name) == "authorization") {
        if (Text.startsWith(value, #text "Bearer ")) {
          return ?Text.replace(value, #text "Bearer ", "");
        };
      };
    };
    return null;
  };

  private func _unauthorized(resourceUrl : Text) : HttpTypes.Response {
    let wwwAuthHeader : (Text, Text) = (
      "WWW-Authenticate",
      "Bearer resource_metadata=\"" # resourceUrl # "\"",
    );
    return {
      status_code = 401;
      headers = [wwwAuthHeader, ("Content-Type", "application/json")];
      body = Text.encodeUtf8("{\"error\":\"Unauthorized\",\"message\":\"A valid Bearer token is required.\"}");
      upgrade = null;
      streaming_strategy = null;
    };
  };

  private func _forbidden(reason : Text) : HttpTypes.Response {
    return {
      status_code = 403;
      headers = [("Content-Type", "application/json")];
      body = Text.encodeUtf8("{\"error\":\"Forbidden\",\"message\":\"" # reason # "\"}");
      upgrade = null;
      streaming_strategy = null;
    };
  };

  // This is the "SLOW PATH" that we only take on a cache miss.
  private func _performFullValidation(
    ctx : Types.AuthContext,
    tokenString : Text,
    metadataUrl : Text,
    thisUrl : Text,
  ) : async Result.Result<Types.CachedSession, HttpTypes.Response> {
    // 2. Parse the token structure.
    let parsedToken = switch (Jwt.parse(tokenString)) {
      case (#ok(t)) { t };
      case (#err(_)) {
        Debug.print("Failed to parse JWT.");
        return #err(_unauthorized(metadataUrl));
      };
    };

    // 3. Get the Key ID (kid) from the token header.
    let kid = switch (Jwt.getHeaderValue(parsedToken, "kid")) {
      case (?#string(k)) { k };
      case _ {
        Debug.print("JWT is missing 'kid' header.");
        return #err(_unauthorized(metadataUrl));
      };
    };

    // 4. Fetch the public key data.
    let pkData = switch (await JwksClient.getPublicKey(ctx, kid)) {
      case (?data) { data };
      case (null) {
        Debug.print("Failed to fetch public key.");
        return #err(_unauthorized(metadataUrl));
      };
    };
    let curve = ECDSA.Curve(pkData.curveKind);
    let publicKeyObject = ECDSA.PublicKey(pkData.x, pkData.y, curve);
    let verificationKey = #ecdsa(publicKeyObject);

    // 5. Define validation options and validate the token.
    let validationOptions : Jwt.ValidationOptions = {
      expiration = true;
      notBefore = true;
      issuer = #one(Utils.normalizeUri(ctx.issuerUrl));
      audience = #one(Utils.normalizeUri(thisUrl));
      signature = #key(verificationKey);
    };

    switch (Jwt.validate(parsedToken, validationOptions)) {
      case (#err(e)) {
        Debug.print("JWT validation error: " # e);
        return #err(_unauthorized(metadataUrl));
      };
      case (#ok()) {};
    };

    // 6. Validate scopes.
    let token_scope_text = switch (Jwt.getPayloadValue(parsedToken, "scope")) {
      case (?#string(t)) { t };
      case _ { "" };
    };
    let token_scopes = Buffer.fromIter<Text>(Text.split(token_scope_text, #char ' '));
    for (required_scope in ctx.requiredScopes.vals()) {
      if (not Buffer.contains(token_scopes, required_scope, Text.equal)) {
        let reason = "Token is missing required scope: " # required_scope;
        return #err(_forbidden(reason));
      };
    };

    // 7. Extract claims to build the session object.
    let sub = switch (Jwt.getPayloadValue(parsedToken, "sub")) {
      case (?#string(t)) { t };
      case _ { return #err(_forbidden("Token is missing 'sub' claim.")) };
    };
    let exp_s = switch (Jwt.getPayloadValue(parsedToken, "exp")) {
      case (?#number(t)) {
        switch (t) {
          case (#float(v)) { Float.toInt(v) };
          case (#int(v)) { v };
        };
      };
      case _ { return #err(_forbidden("Token is missing 'exp' claim.")) };
    };

    // 8. Construct and return the FULL CachedSession object.
    let authInfo : Types.AuthInfo = {
      principal = Principal.fromText(sub);
      scopes = Buffer.toArray(token_scopes);
    };
    let session : Types.CachedSession = {
      authInfo = authInfo;
      expiresAt = exp_s * 1_000_000_000;
    };

    return #ok(session);
  };

  // --- Public Middleware Function ---

  /// Checks the request for a valid API Key or JWT and ensures it contains all required scopes.
  public func check(
    ctx : Types.AuthContext,
    req : HttpTypes.Request,
  ) : async Result.Result<Types.AuthInfo, HttpTypes.Response> {
    let path = "/.well-known/oauth-protected-resource";
    let thisUrl = Utils.getThisUrl(ctx.self, req, null);
    let metadataUrl = Utils.getThisUrl(ctx.self, req, ?path);

    // --- 2. UNIFIED AUTHENTICATION LOGIC ---

    // --- A. Check for an API Key first (FAST PATH) ---
    switch (_get_api_key(req)) {
      case (?api_key_text) {
        // 1. DECODE the hex string from the header back into its original raw bytes.
        let raw_key_blob = switch (Base16.decode(api_key_text)) {
          case (?blob) { blob };
          case (null) {
            // The provided key is not valid hex. It cannot possibly match.
            // We can return an error or hash a known-bad value to ensure the lookup fails.
            Blob.fromArray([]);
          };
        };

        // 2. Hash the DECODED blob. This now matches the data hashed during creation.
        let hashed_key_blob = Sha256.fromBlob(#sha256, raw_key_blob);
        let hashed_key_text : Types.HashedApiKey = Base16.encode(hashed_key_blob);

        switch (Map.get(ctx.apiKeys, thash, hashed_key_text)) {
          case (?key_info) {
            // Key is valid! Return its associated AuthInfo.
            return #ok({
              principal = key_info.principal;
              scopes = key_info.scopes;
            });
          };
          case (null) {
            // An invalid API key was provided. Deny access.
            return #err(_unauthorized(metadataUrl));
          };
        };
      };
      case (null) {
        // --- B. No API key found, proceed to JWT validation (EXISTING LOGIC) ---
        // 1. Extract the token string.
        let tokenString = switch (_get_auth_token(req)) {
          case (?t) { t };
          case (null) { return #err(_unauthorized(metadataUrl)) };
        };

        // 2. Hash the token to create a cache key.
        let tokenHash = Sha256.fromBlob(#sha256, Text.encodeUtf8(tokenString));
        let cacheKey = BaseX.toBase64(tokenHash.vals(), #standard({ includePadding = true }));

        // 3. Check the session cache.
        switch (Map.get(ctx.sessionCache, thash, cacheKey)) {
          case (?cachedSession) {
            // CACHE HIT
            if (Time.now() > cachedSession.expiresAt) {
              Map.delete(ctx.sessionCache, thash, cacheKey);
            } else {
              return #ok(cachedSession.authInfo);
            };
          };
          case (null) {};
        };

        // CACHE MISS
        let validationResult = await _performFullValidation(ctx, tokenString, metadataUrl, thisUrl);

        switch (validationResult) {
          case (#ok(newSession)) {
            Map.set(ctx.sessionCache, thash, cacheKey, newSession);
            return #ok(newSession.authInfo);
          };
          case (#err(response)) {
            return #err(response);
          };
        };
      };
    };
  };
};
