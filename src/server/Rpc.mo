// src/lib/Rpc.mo

import Json "../json";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Types "Types";

module {

  // A smart parser that checks for an `id`
  public func jsonToMessage(json : Types.JsonValue) : ?Types.RpcMessage {
    let method = switch (Json.getAsText(json, "method")) {
      case (#ok(m)) { m };
      case (#err(_)) { return null }; // If 'method' is missing or not a string, return null.
    };
    let params = Option.get(Json.get(json, "params"), Json.nullable());

    switch (jsonToRequest(json)) {
      case (?req) {
        // If an 'id' exists, it's a request.
        return ?#request(req);
      };
      case null {
        // If no 'id', it's a notification.
        return ?#notification({
          jsonrpc = "2.0";
          method = method;
          params = params;
        });
      };
    };
  };

  public func jsonToRequest(json : Types.JsonValue) : ?Types.JsonRpcRequest {
    // 1. The 'method' field MUST exist and MUST be a string.
    //    We use a switch to handle the Result from getAsText.
    switch (Json.getAsText(json, "method")) {
      case (#ok(method_text)) {
        // Method is valid. Now, get the 'id' field.

        // 2. The 'id' field MUST exist. It can be any JSON type, so we
        //    just need to check for its presence. Json.get returning an Option is perfect.
        switch (Json.get(json, "id")) {
          case (?id_json) {
            // ID is valid. Now, handle the optional 'params' field.

            // 3. The 'params' field is OPTIONAL. Default to JSON null if absent.
            let params_json = switch (Json.get(json, "params")) {
              case (?p) { p }; // If it exists, use it.
              case (null) { Json.nullable() }; // Otherwise, use JSON null.
            };

            // 4. Success! All parts are valid. Construct and return the record.
            return ?{
              jsonrpc = "2.0";
              method = method_text;
              params = params_json;
              id = id_json;
            };
          };
          case (null) {
            // The 'id' field was missing.
            return null;
          };
        };
      };
      case (#err(_)) {
        // The 'method' field was missing or was not a string.
        return null;
      };
    };
  };

  // --- SERIALIZATION (Motoko Record -> JSON) ---

  // Converts our structured JsonRpcError record into a JsonValue.
  private func jsonRpcErrorToJson(err : Types.JsonRpcError) : Types.JsonValue {
    var fields = [
      ("code", Json.int(err.code)),
      ("message", Json.str(err.message)),
    ];
    // The 'data' field is optional.
    switch (err.data) {
      case (?d) { fields := Array.append(fields, [("data", d)]) };
      case _ {};
    };
    return Json.obj(fields);
  };

  // Converts our structured JsonRpcResponse record into a JsonValue.
  public func responseToJson(res : Types.JsonRpcResponse) : Types.JsonValue {
    var fields = [
      ("jsonrpc", Json.str("2.0")),
      ("id", res.id),
    ];

    // The 'result' and 'error' fields are mutually exclusive.
    switch (res.error) {
      case (?err) {
        fields := Array.append(fields, [("error", jsonRpcErrorToJson(err))]);
      };
      case (null) {
        // Only add the result field if there is no error.
        switch (res.result) {
          case (?r) { fields := Array.append(fields, [("result", r)]) };
          case _ {};
        };
      };
    };
    return Json.obj(fields);
  };

  // --- Helper for creating structured error responses ---
  public func createErrorResponse(code : Int, message : Text, id : ?Json.Json) : Types.JsonRpcResponse {
    return {
      jsonrpc = "2.0";
      result = null;
      error = ?{
        code = code;
        message = message;
        data = null;
      };
      // Ensure the ID is JSON null if not provided, as per the spec.
      id = Option.get(id, Json.nullable());
    };
  };
};
