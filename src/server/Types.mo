// src/lib/Types.mo
import Json "mo:json";
import HttpTypes "mo:http-types";

module {

  public type JsonValue = Json.Json;

  // Standard IC http types
  public type HeaderField = HttpTypes.Header;
  public type HttpRequest = HttpTypes.Request;
  public type HttpResponse = HttpTypes.Response;

  // JSON-RPC 2.0 types
  public type JsonRpcRequest = {
    jsonrpc : Text; // "2.0"
    method : Text;
    params : JsonValue;
    id : JsonValue;
  };

  // A structure for notifications (no id)
  public type JsonRpcNotification = {
    jsonrpc : Text;
    method : Text;
    params : JsonValue;
  };

  // A variant to hold either type
  public type RpcMessage = {
    #request : JsonRpcRequest;
    #notification : JsonRpcNotification;
  };

  public type JsonRpcResponse = {
    jsonrpc : Text; // "2.0"
    result : ?JsonValue;
    error : ?JsonRpcError;
    id : JsonValue;
  };

  public type JsonRpcError = {
    code : Int;
    message : Text;
    data : ?JsonValue;
  };

};
