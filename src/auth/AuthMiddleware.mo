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
import Option "mo:base/Option";
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

  // --- NEW: OIDC-specific 401 Unauthorized response ---
  private func _unauthorizedOidc(resourceUrl : Text) : HttpTypes.Response {
    // This header is CRITICAL for OIDC clients to discover how to authenticate.
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

  // --- NEW: Generic 401 Unauthorized response for API Keys ---
  private func _unauthorizedApiKey() : HttpTypes.Response {
    // Note the ABSENCE of the WWW-Authenticate header. This is crucial.
    return {
      status_code = 401;
      headers = [("Content-Type", "application/json")];
      body = Text.encodeUtf8("{\"error\":\"Unauthorized\",\"message\":\"A valid API key is required.\"}");
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
    oidcState : Types.OidcState,
    tokenString : Text,
    metadataUrl : Text,
    thisUrl : Text,
  ) : async Result.Result<Types.CachedSession, HttpTypes.Response> {
    // 2. Parse the token structure.
    let parsedToken = switch (Jwt.parse(tokenString)) {
      case (#ok(t)) { t };
      case (#err(_)) {
        Debug.print("Failed to parse JWT.");
        return #err(_unauthorizedOidc(metadataUrl));
      };
    };

    // 3. Get the Key ID (kid) from the token header.
    let kid = switch (Jwt.getHeaderValue(parsedToken, "kid")) {
      case (?#string(k)) { k };
      case _ {
        Debug.print("JWT is missing 'kid' header.");
        return #err(_unauthorizedOidc(metadataUrl));
      };
    };

    // 4. Fetch the public key data.
    let pkData = switch (await JwksClient.getPublicKey(oidcState, kid)) {
      case (?data) { data };
      case (null) {
        Debug.print("Failed to fetch public key.");
        return #err(_unauthorizedOidc(metadataUrl));
      };
    };
    let curve = ECDSA.Curve(pkData.curveKind);
    let publicKeyObject = ECDSA.PublicKey(pkData.x, pkData.y, curve);
    let verificationKey = #ecdsa(publicKeyObject);

    // 5. Define validation options and validate the token.
    Debug.print("Validating JWT...");
    Debug.print("audience: " # thisUrl);
    let validationOptions : Jwt.ValidationOptions = {
      expiration = true;
      notBefore = true;
      issuer = #one(Utils.normalizeUri(oidcState.issuerUrl));
      audience = #one(Utils.normalizeUri(thisUrl));
      signature = #key(verificationKey);
    };

    switch (Jwt.validate(parsedToken, validationOptions)) {
      case (#err(e)) {
        Debug.print("JWT validation error: " # e);
        return #err(_unauthorizedOidc(metadataUrl));
      };
      case (#ok()) {};
    };

    // 6. Validate scopes.
    let token_scope_text = switch (Jwt.getPayloadValue(parsedToken, "scope")) {
      case (?#string(t)) { t };
      case _ { "" };
    };
    let token_scopes = Buffer.fromIter<Text>(Text.split(token_scope_text, #char ' '));
    for (required_scope in oidcState.requiredScopes.vals()) {
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
    mcpUrl : Text,
  ) : async Result.Result<Types.AuthInfo, HttpTypes.Response> {
    // --- 1. EXTRACT CREDENTIALS FROM REQUEST ---
    // We support two authentication methods:
    // 1. API Key via "X-API-Key" header
    // 2. Bearer Token (JWT) via "Authorization" header
    let apiKeyText = _get_api_key(req);
    let authTokenText = _get_auth_token(req);

    // --- 2. UNIFIED AUTHENTICATION LOGIC ---

    // --- A. Check for an API Key first (FAST PATH) ---
    // --- A. API Key takes precedence if provided ---
    switch (apiKeyText) {
      case (null) { /* No API key provided, skip to JWT check */ };
      case (?keyText) {
        switch (ctx.apiKey) {
          case (?apiKeyState) {
            // API Key module is enabled. Proceed with validation.
            let raw_key_blob = switch (Base16.decode(keyText)) {
              case (?blob) { blob };
              case (null) { Blob.fromArray([]) };
            };
            let hashed_key_blob = Sha256.fromBlob(#sha256, raw_key_blob);
            let hashed_key_text : Types.HashedApiKey = Base16.encode(hashed_key_blob);

            switch (Map.get(apiKeyState.apiKeys, thash, hashed_key_text)) {
              case (?key_info) {
                return #ok({
                  principal = key_info.principal;
                  scopes = key_info.scopes;
                });
              };
              case (null) {
                return #err(_unauthorizedApiKey());
              };
            };
          };
          case (null) {
            // An API key was provided, but the module is not configured. This is an error.
            return #err(_forbidden("API Key authentication is not enabled for this resource."));
          };
        };
      };
    };

    // --- B. If no API Key, check for a JWT ---
    switch (authTokenText) {
      case (null) { /* No token provided, skip to final error */ };
      case (?tokenString) {

        switch (ctx.oidc) {
          case (?oidcState) {
            // OIDC module is enabled. Proceed with validation.
            let tokenHashBlob = Sha256.fromBlob(#sha256, Text.encodeUtf8(tokenString));
            let cacheKey = Base16.encode(tokenHashBlob);

            // Check the session cache within the OIDC state.
            switch (Map.get(oidcState.sessionCache, thash, cacheKey)) {
              case (?cachedSession) {
                if (Time.now() > cachedSession.expiresAt) {
                  Map.delete(oidcState.sessionCache, thash, cacheKey);
                } else {
                  return #ok(cachedSession.authInfo);
                };
              };
              case (null) {};
            };

            // CACHE MISS: Perform full validation using the OIDC state.
            let path = "/.well-known/oauth-protected-resource";
            let thisUrl = Utils.getThisUrl(oidcState.self, req, ?mcpUrl);
            let metadataUrl = Utils.getThisUrl(oidcState.self, req, ?path);

            let validationResult = await _performFullValidation(oidcState, tokenString, metadataUrl, thisUrl);
            switch (validationResult) {
              case (#ok(newSession)) {
                Map.set(oidcState.sessionCache, thash, cacheKey, newSession);
                return #ok(newSession.authInfo);
              };
              case (#err(response)) {
                return #err(response);
              };
            };
          };
          case (null) {
            // A JWT was provided, but the OIDC module is not configured. This is an error.
            return #err(_forbidden("Bearer Token (OIDC) authentication is not enabled for this resource."));
          };
        };
      };
    };

    // We must decide which error to show. If OIDC is enabled, it's the most likely
    // intended method for interactive clients. If not, the API key error is better.
    switch (ctx.oidc) {
      case (?oidcState) {
        let path = "/.well-known/oauth-protected-resource";
        let thisUrl = Utils.getThisUrl(oidcState.self, req, null);
        let metadataUrl = Utils.getThisUrl(oidcState.self, req, ?path);

        return #err(_unauthorizedOidc(metadataUrl));
      };
      case (null) {
        return #err(_unauthorizedApiKey());
      };
    };
  };
};
