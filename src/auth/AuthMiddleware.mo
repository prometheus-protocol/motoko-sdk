// src/mcp/AuthMiddleware.mo

import Types "Types";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Principal "mo:base/Principal";
import JwksClient "JwksClient";
import HttpTypes "mo:http-types";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Jwt "mo:jwt";
import ECDSA "mo:ecdsa";

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

  private func _unauthorized() : HttpTypes.Response {
    let wwwAuthHeader : (Text, Text) = (
      "WWW-Authenticate",
      "Bearer resource_metadata=\"/.well-known/oauth-protected-resource\"",
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

  // --- Public Middleware Function ---

  /// Checks the request for a valid JWT and ensures it contains all required scopes.
  public func check(
    ctx : Types.AuthContext,
    req : HttpTypes.Request,
  ) : async Result.Result<Types.AuthInfo, HttpTypes.Response> {

    // 1. Extract the token string.
    let tokenString = switch (_get_auth_token(req)) {
      case (?t) { t };
      case (null) { return #err(_unauthorized()) };
    };

    // 2. Parse the token structure.
    let parsedToken = switch (Jwt.parse(tokenString)) {
      case (#ok(t)) { t };
      case (#err(_)) { return #err(_unauthorized()) };
    };

    // 3. Get the Key ID (kid) from the token header.
    let kid = switch (Jwt.getHeaderValue(parsedToken, "kid")) {
      case (?#string(k)) { k };
      case _ { return #err(_unauthorized()) };
    };

    // 4. Fetch the public key *data* (the DTO).
    let pkData = switch (await JwksClient.getPublicKey(ctx, kid)) {
      case (?data) { data };
      case (null) { return #err(_unauthorized()) };
    };

    // --- NEW: Reconstruct the PublicKey object from the DTO ---
    let curve = ECDSA.Curve(pkData.curveKind);
    let publicKeyObject = ECDSA.PublicKey(pkData.x, pkData.y, curve);
    // --- END NEW ---

    // 5. Define validation options using the reconstructed object.
    let verificationKey = #ecdsa(publicKeyObject);

    // 5. Define validation options and validate the token.
    let validationOptions : Jwt.ValidationOptions = {
      expiration = true;
      notBefore = true;
      issuer = #one(ctx.issuerUrl);
      // TODO: Derive audience from canister id and ic host
      audience = #skip;
      signature = #key(verificationKey);
    };

    switch (Jwt.validate(parsedToken, validationOptions)) {
      case (#err(e)) {
        return #err(_unauthorized());
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

    // 7. Construct and return AuthInfo.
    let sub = switch (Jwt.getPayloadValue(parsedToken, "sub")) {
      case (?#string(t)) { t };
      case _ {
        return #err(_forbidden("Token is missing or has invalid 'sub' claim."));
      };
    };

    let authInfo : Types.AuthInfo = {
      principal = Principal.fromText(sub);
      scopes = Buffer.toArray(token_scopes);
    };

    return #ok(authInfo);
  };
};
