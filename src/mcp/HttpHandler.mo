// src/mcp/HttpHandler.mo

import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Option "mo:base/Option";
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
    // The base path for all MCP requests, e.g., "/mcp".
    // The SDK will ignore any requests that do not start with this path.
    mcp_path : ?Text;
  };

  // Helper function to determine if a request is for a streaming response.
  // According to the MCP spec, this is signaled by the 'Accept' header.
  private func is_streaming_request(req : SrvTypes.HttpRequest) : Bool {
    for (header in req.headers.vals()) {
      // Headers are case-insensitive, so we should normalize the key.
      if (Text.toLowercase(header.0) == "accept") {
        // The value can be a list, e.g., "application/json, text/event-stream"
        if (Text.contains(header.1, #text "text/event-stream")) {
          return true;
        };
      };
    };
    return false;
  };

  public func http_request_streaming_callback(ctx : Context, token : HttpTypes.StreamingToken) : ?HttpTypes.StreamingCallbackResponse {
    let tokenKey = BaseX.toBase64(token.vals(), #standard({ includePadding = true }));
    // It has access to the actor's state.
    if (Option.isNull(Map.get(ctx.active_streams, thash, tokenKey))) {
      return ?{ body = Blob.fromArray([]); token = null };
    };

    // Update the timestamp to prove the stream is still active.
    Map.set(ctx.active_streams, thash, tokenKey, Time.now());

    let chunk = Text.encodeUtf8("data: {\"type\":\"keep-alive\"}\n\n");
    return ?{ body = chunk; token = ?token };
  };

  // The public entry point for query calls.
  public func http_request(ctx : Context, req : SrvTypes.HttpRequest) : ?SrvTypes.HttpResponse {
    if (req.method == "GET" and Text.contains(req.url, #text "/.well-known/oauth-protected-resource")) {
      switch (ctx.http_asset_cache) {
        case (?cache) {
          // --- START: WORKAROUND FOR CERTIFICATION BUG ---
          // The certification library can fail if the URL contains query parameters.
          // We split the URL by '?' and take the first part to get a clean path.
          let clean_path : Text = do {
            // Text.split returns an iterator.
            let iter = Text.split(req.url, #char '?');
            // We take the first element from the iterator.
            switch (iter.next()) {
              case (null) {
                // This case only occurs if the original URL was empty.
                "";
              };
              case (?path) {
                // We successfully got the first part of the split.
                // The `_` ignores the rest of the iterator.
                path;
              };
            };
          };
          // --- END: WORKAROUND ---

          // 1. Check the cache.
          switch (cache.get(clean_path)) {
            case (?bodyBlob) {
              // CACHE HIT: The library handles everything.
              return ?{
                status_code = 200;
                headers = [
                  ("Content-Type", "application/json"),
                  cache.certificationHeader(clean_path) // The library builds the header!
                ];
                body = bodyBlob;
                upgrade = null;
                streaming_strategy = null;
              };
            };
            case (null) {
              // CACHE MISS: Instruct the client to upgrade.
              return ?{
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

    // --- 2. Check if the request is for the configured MCP path ---
    let mcpUrl = Option.get(ctx.mcp_path, "/mcp");
    if (not Text.startsWith(req.url, #text mcpUrl)) {
      // This is not an MCP request. Signal the caller to handle it.
      return null;
    };

    if (req.method == "GET" and is_streaming_request(req)) {
      // Handle the streaming handshake for clients like the MCP Inspector.
      let token_blob = Blob.fromArray(Utils.nat64ToBytes(Nat64.fromIntWrap(Time.now())));
      let token_key = BaseX.toBase64(token_blob.vals(), #standard({ includePadding = true }));
      Map.set(ctx.active_streams, thash, token_key, Time.now());

      let streaming_strategy : HttpTypes.StreamingStrategy = #Callback({
        callback = ctx.streaming_callback;
        token = token_blob;
      });

      return ?{
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
      return ?{
        status_code = 204; // 204 No Content is a standard way to signal an upgrade.
        headers = [];
        body = Blob.fromArray([]);
        upgrade = ?true;
        streaming_strategy = null;
      };
    };
  };

  // The public entry point for update calls.
  public func http_request_update(ctx : Context, req : SrvTypes.HttpRequest) : async ?SrvTypes.HttpResponse {
    // All MCP logic is now routed through here, ensuring responses are certified.

    // --- Intercept metadata requests to perform certification ---
    if (req.method == "GET" and Text.contains(req.url, #text "/.well-known/oauth-protected-resource")) {
      switch (ctx.auth, ctx.http_asset_cache) {
        case (?authCtx, ?cache) {

          switch (authCtx.oidc) {
            case (null) {
              // OIDC is not configured, so we cannot serve the metadata document.
              return ?{
                status_code = 404;
                headers = [];
                body = Blob.fromArray([]);
                upgrade = null;
                streaming_strategy = null;
              };
            };
            case (?oidcState) {
              // OIDC is configured, so we can proceed.

              // 1. Generate the content.
              let mcpPath = Option.get(ctx.mcp_path, "/mcp");
              let bodyBlob = Utils.getResourceMetadataBlob(ctx.self, mcpPath, oidcState, req);

              // 2. Put it in the cache. The library handles hashing and set_certified_data().
              cache.put(req.url, bodyBlob, null);

              // 3. Return a simple, uncertified 200 OK.
              return ?{
                status_code = 200;
                headers = [("Content-Type", "application/json")];
                body = bodyBlob;
                upgrade = null;
                streaming_strategy = null;
              };
            };
          };
        };
        case (_, _) { /* Handle error */ };
      };
    };

    // --- 2. Check if the request is for the configured MCP path ---
    let mcpUrl = Option.get(ctx.mcp_path, "/mcp");
    if (not Text.startsWith(req.url, #text mcpUrl)) {
      // This is not an MCP request. Signal the caller to handle it.
      return null;
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
            return ?httpResponse;
          };
          case (#ok(authInfo)) {
            // Auth succeeded, handle the request with the trusted auth info.
            return ?(await ctx.mcp_server.handle_request(req, ?authInfo));
          };
        };
      };
      case (_) {
        // --- AUTH IS OFF ---
        // No auth config, so proceed without authentication.
        return ?(await ctx.mcp_server.handle_request(req, null));
      };
    };
  };
};
