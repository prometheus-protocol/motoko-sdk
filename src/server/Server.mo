import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Text "mo:base/Text";
import Result "mo:base/Result";
import Json "../json";
import AuthTypes "../auth/Types";
import Handler "Handler";
import Types "Types";
import Rpc "Rpc";

module {

  // An intermediate result type for our synchronous routing logic.
  type RouteResult = Result.Result<(Handler.Handler, Types.RpcMessage), Types.HttpResponse>;

  public class Server(routes : [(Text, Handler.Handler)]) {
    // The dispatch table mapping method names to their handlers.
    private let dispatch_table : Map.Map<Text, Handler.Handler> = Map.fromIter(routes.vals(), thash);

    // --- Private Helper Functions ---

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
      // 1. Parse Body to Text
      let body_text = switch (Text.decodeUtf8(req.body)) {
        case (?text) { text };
        case (null) {
          let err_res = Rpc.createErrorResponse(-32700, "Parse error", null);
          return #err(_create_json_response(err_res));
        };
      };

      // 2. Parse Text to JSON
      let rpc_req_json = switch (Json.parse(body_text)) {
        case (#ok(json)) { json };
        case (#err(_)) {
          let err_res = Rpc.createErrorResponse(-32700, "Parse error", null);
          return #err(_create_json_response(err_res));
        };
      };

      // 3. Parse JSON to structured RPC Request
      let rpc_message = switch (Rpc.jsonToMessage(rpc_req_json)) {
        case (?msg) { msg };
        case (null) {
          let err_res = Rpc.createErrorResponse(-32602, "Invalid params", null);
          return #err(_create_json_response(err_res));
        };
      };

      // 4. Route to the correct handler
      //  Map.get signature is (map, key, hash)
      let method = switch (rpc_message) {
        case (#request(req)) { req.method };
        case (#notification(notif)) { notif.method };
      };
      let handler = switch (Map.get(dispatch_table, thash, method)) {
        case (?h) { h };
        case (null) {
          let id = switch (rpc_message) {
            case (#request(req)) { ?req.id };
            case (#notification(_)) { null };
          };
          let err_res = Rpc.createErrorResponse(-32601, "Method not found", id);
          return #err(_create_json_response(err_res));
        };
      };

      // 5. Success! Return the handler and the parsed request.
      return #ok((handler, rpc_message));
    };

    // --- PUBLIC ENTRY POINT FOR THE SDK ---

    public func handle_request(req : Types.HttpRequest, auth : ?AuthTypes.AuthInfo) : async Types.HttpResponse {
      switch (_route_request(req)) {
        case (#err(http_response)) {
          // If routing failed (e.g., parse error, method not found), return the pre-built error response.
          return http_response;
        };
        case (#ok((handler, rpc_message))) {
          // Extract params and id from the parsed RPC message.
          let (params, id) = switch (rpc_message) {
            case (#request(r)) { (r.params, r.id) };
            case (#notification(n)) { (n.params, Json.nullable()) };
          };

          // NEW LOGIC: Handle both handler types within this single async function.
          switch (handler) {
            case (#read(rep)) {
              // This is a read method. Execute it synchronously.
              // This is valid because we are inside an async function.
              switch (rep.call(params, auth)) {
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
            case (#mutation(rep)) {
              // This is a mutation. Execute it asynchronously.
              switch (await rep.call(params, auth)) {
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
