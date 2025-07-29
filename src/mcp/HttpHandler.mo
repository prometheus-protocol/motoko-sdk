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
    active_streams : Map.Map<Text, Time.Time>;
    // The configured MCP server instance.
    mcp_server : Server.Server;
    // A reference to the public streaming callback function in main.mo.
    streaming_callback : shared query (HttpTypes.StreamingToken) -> async ?HttpTypes.StreamingCallbackResponse;
  };

  // The public entry point for query calls.
  public func http_request(ctx : Context, req : SrvTypes.HttpRequest) : SrvTypes.HttpResponse {
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
    return await ctx.mcp_server.handle_request(req, null);
  };
};
