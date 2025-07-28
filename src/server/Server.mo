import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Json "../json";

import Handler "Handler";
import Types "Types";
import Rpc "Rpc";

module {

  // An intermediate result type for our synchronous routing logic.
  type RouteResult = Result.Result<(Handler.Handler, Types.RpcMessage), Types.HttpResponse>;

  public class Server(routes : [(Text, Handler.Handler)], jwt_public_key : Blob) {
    // The dispatch table mapping method names to their handlers.
    // CORRECTED: Simplified initialization. No need for map or toRep.
    private let dispatch_table : Map.Map<Text, Handler.Handler> = Map.fromIter(routes.vals(), thash);

    // The key used to validate JWTs.
    private let jwt_key : Blob = jwt_public_key;

    // --- Private Helper Functions ---

    private func _get_auth_token(headers : [Types.HeaderField]) : ?Text {
      for ((name, value) in headers.vals()) {
        if (Text.toLowercase(name) == "authorization") {
          if (Text.startsWith(value, #text "Bearer ")) {
            return ?Text.replace(value, #text "Bearer ", "");
          };
        };
      };
      return null;
    };

    private func _validate_jwt(token : Text) : Bool {
      return token == "FAKE_TOKEN";
    };

    private func _create_json_response(rpc_res : Types.JsonRpcResponse) : Types.HttpResponse {
      let body_text = Json.stringify(Rpc.responseToJson(rpc_res), null);
      return {
        status_code = 200;
        headers = [("Content-Type", "application/json")];
        body = Text.encodeUtf8(body_text);
        upgrade = null;
        streaming_strategy = null; // No streaming for this response
      };
    };

    // --- SYNCHRONOUS ROUTING LOGIC ---
    private func _route_request(req : Types.HttpRequest) : RouteResult {
      // 1. Authentication
      // switch (_get_auth_token(req.headers)) {
      //   case (?token) {
      //     if (not _validate_jwt(token)) {
      //       return #err({
      //         status_code = 401;
      //         headers = [];
      //         body = Blob.fromArray([]);
      //         upgrade = null;
      //         streaming_strategy = null;
      //       });
      //     };
      //   };
      //   case (null) {
      //     return #err({
      //       status_code = 401;
      //       headers = [];
      //       body = Blob.fromArray([]);
      //       upgrade = null;
      //       streaming_strategy = null;
      //     });
      //   };
      // };

      // 2. Parse Body to Text
      let body_text = switch (Text.decodeUtf8(req.body)) {
        case (?text) { text };
        case (null) {
          let err_res = {
            jsonrpc = "2.0";
            result = null;
            error = ?{ code = -32700; message = "Parse error"; data = null };
            id = Json.nullable();
          };
          return #err(_create_json_response(err_res));
        };
      };

      // 3. Parse Text to JSON
      let rpc_req_json = switch (Json.parse(body_text)) {
        case (#ok(json)) { json };
        case (#err(_)) {
          let err_res = {
            jsonrpc = "2.0";
            result = null;
            error = ?{ code = -32700; message = "Parse error"; data = null };
            id = Json.nullable();
          };
          return #err(_create_json_response(err_res));
        };
      };

      // 4. Parse JSON to structured RPC Request
      let rpc_message = switch (Rpc.jsonToMessage(rpc_req_json)) {
        case (?msg) { msg };
        case (null) {
          let err_res = {
            jsonrpc = "2.0";
            result = null;
            error = ?{ code = -32602; message = "Invalid params"; data = null };
            id = Json.nullable();
          };
          return #err(_create_json_response(err_res));
        };
      };

      // 5. Route to the correct handler
      // CORRECTED: Map.get signature is (map, key, hash)
      let method = switch (rpc_message) {
        case (#request(req)) { req.method };
        case (#notification(notif)) { notif.method };
      };
      let handler = switch (Map.get(dispatch_table, thash, method)) {
        case (?h) { h };
        case (null) {
          let id = switch (rpc_message) {
            case (#request(req)) { req.id };
            case (#notification(_)) { Json.nullable() }; // Notifications have no ID to echo back.
          };

          let err_res = {
            jsonrpc = "2.0";
            result = null;
            error = ?{
              code = -32601;
              message = "Method not found";
              data = null;
            };
            id = id;
          };
          return #err(_create_json_response(err_res));
        };
      };

      // 6. Success! Return the handler and the parsed request.
      return #ok((handler, rpc_message));
    };

    // --- PUBLIC ENTRY POINTS FOR THE SDK ---

    /// To be called from the canister's `http_request` query function.
    public func handle_query(req : Types.HttpRequest) : Types.HttpResponse {
      Debug.print("--- handle_query received request ---");
      Debug.print(debug_show req);

      switch (_route_request(req)) {
        case (#err(http_response)) {
          return http_response;
        };
        case (#ok((handler, rpc_message))) {
          // Switch on the handler variant
          let (params, id) = switch (rpc_message) {
            case (#request(r)) { (r.params, r.id) };
            case (#notification(n)) { (n.params, Json.nullable()) };
          };

          switch (handler) {
            case (#mutation(_)) {
              // This is an update method, so we must upgrade.
              return {
                status_code = 200;
                headers = [];
                body = Blob.fromArray([]);
                upgrade = ?true;
                streaming_strategy = null; // No streaming for this response
              };
            };
            case (#read(rep)) {
              // This is a read method, execute it synchronously and handle the Result.
              switch (rep.call(params)) {
                case (#ok(result_json)) {
                  return _create_json_response({
                    jsonrpc = "2.0";
                    result = ?result_json;
                    error = null;
                    id = id;
                  });
                };
                case (#err(handler_err)) {
                  let err_res = {
                    jsonrpc = "2.0";
                    result = null;
                    error = ?{
                      code = handler_err.code;
                      message = handler_err.message;
                      data = null;
                    };
                    id = id;
                  };
                  return _create_json_response(err_res);
                };
              };
            };
          };
        };
      };
    };

    /// To be called from the canister's `http_request_update` update function.
    public func handle_update(req : Types.HttpRequest) : async Types.HttpResponse {
      switch (_route_request(req)) {
        case (#err(http_response)) {
          return http_response;
        };
        case (#ok((handler, rpc_message))) {
          // CORRECTED: Switch on the handler variant
          let (params, id) = switch (rpc_message) {
            case (#request(r)) { (r.params, r.id) };
            case (#notification(n)) { (n.params, Json.nullable()) };
          };

          switch (handler) {
            case (#read(_)) {
              // This is an error: a read method was called via the update entry point.
              let rpc_res = {
                jsonrpc = "2.0";
                result = null;
                error = ?{
                  code = -32603;
                  message = "Internal error: Cannot call read-only method in update context";
                  data = null;
                };
                id = id;
              };
              return _create_json_response(rpc_res);
            };
            case (#mutation(rep)) {
              // This is a mutation, execute it asynchronously and handle the Result.
              switch (await rep.call(params)) {
                case (#ok(result_json)) {
                  return _create_json_response({
                    jsonrpc = "2.0";
                    result = ?result_json;
                    error = null;
                    id = id;
                  });
                };
                case (#err(handler_err)) {
                  let rpc_res = {
                    jsonrpc = "2.0";
                    result = null;
                    error = ?{
                      code = handler_err.code;
                      message = handler_err.message;
                      data = null;
                    };
                    id = id;
                  };
                  return _create_json_response(rpc_res);
                };
              };
            };
          };
        };
      };
    };
  };
};
