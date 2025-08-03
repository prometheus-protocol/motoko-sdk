// src/mcp/HttpHandler.mo

import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import BaseX "mo:base-x-encoder";
import HttpTypes "mo:http-types";
import Utils "Utils";
import CertifiedCache "mo:certified-cache";

import SrvTypes "../../src/server/Types";
import Server "../../src/server/Server";

import AuthTypes "../../src/auth/Types";
import AuthMiddleware "../../src/auth/AuthMiddleware";

module {
  // The context object that main.mo will construct and pass to us.
  public type Context = {
    // The principal of the server actor.
    self : Principal;
    // The stateful map of active streams.
    active_streams : Map.Map<Text, Time.Time>;
    // The configured MCP server instance.
    mcp_server : Server.Server;
    // A reference to the public streaming callback function in main.mo.
    streaming_callback : shared query (HttpTypes.StreamingToken) -> async ?HttpTypes.StreamingCallbackResponse;
    // The authentication context, if configured.
    auth : ?AuthTypes.AuthContext;
    // The HTTP asset cache, if configured.
    http_asset_cache : ?CertifiedCache.CertifiedCache<Text, Blob>;
  };

  // The public entry point for query calls.
  public func http_request(ctx : Context, req : SrvTypes.HttpRequest) : SrvTypes.HttpResponse {
    if (req.method == "GET" and Text.contains(req.url, #text "/.well-known/oauth-protected-resource")) {
      switch (ctx.http_asset_cache) {
        case (?cache) {
          // 1. Check the cache.
          switch (cache.get(req.url)) {
            case (?bodyBlob) {
              // CACHE HIT: The library handles everything.
              return {
                status_code = 200;
                headers = [
                  ("Content-Type", "application/json"),
                  cache.certificationHeader(req.url) // The library builds the header!
                ];
                body = bodyBlob;
                upgrade = null;
                streaming_strategy = null;
              };
            };
            case (null) {
              // CACHE MISS: Instruct the client to upgrade.
              return {
                status_code = 204;
                headers = [];
                body = Blob.fromArray([]);
                upgrade = ?true;
                streaming_strategy = null;
              };
            };
          };
        };
        case (null) { /* Handle error: cache not configured */ };
      };
    };

    if (Text.contains(req.url, #text "transportType=streamable-http")) {
      // Handle the streaming handshake for clients like the MCP Inspector.
      let token_blob = Blob.fromArray(Utils.nat64ToBytes(Nat64.fromIntWrap(Time.now())));
      let token_key = BaseX.toBase64(token_blob.vals(), #standard({ includePadding = true }));
      Map.set(ctx.active_streams, thash, token_key, Time.now());

      let streaming_strategy : HttpTypes.StreamingStrategy = #Callback({
        callback = ctx.streaming_callback;
        token = token_blob;
      });

      return {
        status_code = 200;
        headers = [("Content-Type", "text/event-stream")];
        body = Blob.fromArray([]);
        upgrade = null;
        streaming_strategy = ?streaming_strategy;
      };
    } else {
      // THIS IS THE NEW LOGIC.
      // For any other request, we don't handle it here. We immediately
      // instruct the client to upgrade to an update call. This ensures
      // all responses are certified via consensus.
      return {
        status_code = 204; // 204 No Content is a standard way to signal an upgrade.
        headers = [];
        body = Blob.fromArray([]);
        upgrade = ?true;
        streaming_strategy = null;
      };
    };
  };

  // The public entry point for update calls.
  public func http_request_update(ctx : Context, req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    // All MCP logic is now routed through here, ensuring responses are certified.
    // --- Intercept metadata requests to perform certification ---
    if (req.method == "GET" and Text.contains(req.url, #text "/.well-known/oauth-protected-resource")) {
      switch (ctx.auth, ctx.http_asset_cache) {
        case (?authCtx, ?cache) {
          // 1. Generate the content.
          let bodyBlob = Utils.getResourceMetadataBlob(ctx.self, authCtx, req);

          // 2. Put it in the cache. The library handles hashing and set_certified_data().
          cache.put(req.url, bodyBlob, null);

          // 3. Return a simple, uncertified 200 OK.
          return {
            status_code = 200;
            headers = [("Content-Type", "application/json")];
            body = bodyBlob;
            upgrade = null;
            streaming_strategy = null;
          };
        };
        case (_, _) { /* Handle error */ };
      };
    };

    // Check if authentication is configured on the server.
    switch (ctx.auth) {
      case (?authCtx) {
        // --- AUTH IS ON ---
        // 1. Run the authentication check first.
        let authResult = await AuthMiddleware.check(authCtx, req);

        // 2. Handle the result of the check.
        switch (authResult) {
          case (#err(httpResponse)) {
            // Auth failed, return the error response immediately.
            return httpResponse;
          };
          case (#ok(authInfo)) {
            // Auth succeeded, handle the request with the trusted auth info.
            return await ctx.mcp_server.handle_request(req, ?authInfo);
          };
        };
      };
      case (_) {
        // --- AUTH IS OFF ---
        // No auth config, so proceed without authentication.
        return await ctx.mcp_server.handle_request(req, null);
      };
    };
  };
};
