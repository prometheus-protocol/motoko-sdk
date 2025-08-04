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
import Jwt "mo:jwt";
import ECDSA "mo:ecdsa";
import Sha256 "mo:sha2/Sha256";
import Utils "../mcp/Utils";
import Map "mo:map/Map";
import { thash } "mo:map/Map";
import BaseX "mo:base-x-encoder";

module {
  // --- Private Helper Functions ---

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
      case (#err(_)) { return #err(_unauthorized(metadataUrl)) };
    };

    // 3. Get the Key ID (kid) from the token header.
    let kid = switch (Jwt.getHeaderValue(parsedToken, "kid")) {
      case (?#string(k)) { k };
      case _ { return #err(_unauthorized(metadataUrl)) };
    };

    // 4. Fetch the public key data.
    let pkData = switch (await JwksClient.getPublicKey(ctx, kid)) {
      case (?data) { data };
      case (null) { return #err(_unauthorized(metadataUrl)) };
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
      case (#err(e)) { return #err(_unauthorized(metadataUrl)) };
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

  /// Checks the request for a valid JWT and ensures it contains all required scopes.
  // --- PUBLIC MIDDLEWARE: Now with caching logic ---
  public func check(
    ctx : Types.AuthContext,
    req : HttpTypes.Request,
  ) : async Result.Result<Types.AuthInfo, HttpTypes.Response> {
    let path = "/.well-known/oauth-protected-resource";
    let thisUrl = Utils.getThisUrl(ctx.self, req, null);
    let metadataUrl = Utils.getThisUrl(ctx.self, req, ?path);

    // 1. Extract the token string.
    let tokenString = switch (_get_auth_token(req)) {
      case (?t) { t };
      case (null) { return #err(_unauthorized(metadataUrl)) };
    };

    // --- CACHING LOGIC STARTS HERE ---

    // 2. Hash the token to create a deterministic, fixed-size cache key. (FAST)
    let tokenHash = Sha256.fromBlob(#sha256, Text.encodeUtf8(tokenString));

    let cacheKey = BaseX.toBase64(tokenHash.vals(), #standard({ includePadding = true }));

    // 3. Check the cache for the token hash. (FAST)
    switch (Map.get(ctx.sessionCache, thash, cacheKey)) {
      case (?cachedSession) {
        // --- CACHE HIT: THE FAST PATH ---
        // 4. Check if the cached session is expired. (FAST)
        if (Time.now() > cachedSession.expiresAt) {
          // Expired. Remove it from the cache and proceed to full validation.
          Map.delete(ctx.sessionCache, thash, cacheKey);
        } else {
          // Still valid! We are done. Return the cached info.
          // This avoids all parsing, crypto, and claim validation.
          return #ok(cachedSession.authInfo);
        };
      };
      case (null) {
        // No action needed, we just proceed to full validation.
      };
    };

    // --- CACHE MISS: THE SLOW PATH ---
    // 5. Perform the full, expensive validation.
    let validationResult = await _performFullValidation(ctx, tokenString, metadataUrl, thisUrl);

    switch (validationResult) {
      case (#ok(newSession)) {
        // 6. Validation succeeded. STORE the result in the cache for next time.
        Map.set(ctx.sessionCache, thash, cacheKey, newSession);
        // And return the auth info for the current request.
        return #ok(newSession.authInfo);
      };
      case (#err(response)) {
        // Validation failed. Return the generated error response.
        return #err(response);
      };
    };
  };
};
