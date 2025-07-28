// src/mcp/HttpHandler.mo

import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import BaseX "mo:base-x-encoder";
import HttpTypes "mo:http-types";

import SrvTypes "../../src/server/Types";
import Utils "../../src/server/Utils";
import Server "../../src/server/Server";

module {
  // The context object that main.mo will construct and pass to us.
  public type Context = {
    // The stateful map of active streams.
    active_streams : Map.Map<Text, ()>;
    // The configured MCP server instance.
    mcp_server : Server.Server;
    // A reference to the public streaming callback function in main.mo.
    streaming_callback : shared query (HttpTypes.StreamingToken) -> async ?HttpTypes.StreamingCallbackResponse;
  };

  // The public entry point for query calls.
  public func http_request(ctx : Context, req : SrvTypes.HttpRequest) : SrvTypes.HttpResponse {
    if (Text.contains(req.url, #text "transportType=streamable-http")) {
      // All the streaming handshake logic is now hidden in here.
      let token_blob = Blob.fromArray(Utils.nat64ToBytes(Nat64.fromIntWrap(Time.now())));
      let token_key = BaseX.toBase64(token_blob.vals(), #standard({ includePadding = true }));
      // It modifies the state object passed in via the context.
      Map.set(ctx.active_streams, thash, token_key, ());

      let streaming_strategy : HttpTypes.StreamingStrategy = #Callback({
        // It uses the callback function passed in via the context.
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
      // It automatically routes non-streaming requests to the MCP server.
      return ctx.mcp_server.handle_query(req);
    };
  };

  // The public entry point for update calls.
  public func http_request_update(ctx : Context, req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    // It automatically routes update calls to the MCP server.
    return await ctx.mcp_server.handle_update(req);
  };
};
