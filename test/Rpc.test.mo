import { test; suite; expect } "mo:test/async";
import { obj; str; int; nullable } "mo:json";
import Text "mo:base/Text";

// Modules to test
import Rpc "../src/server/Rpc";
import Types "../src/server/Types";

// =================================================================================================
// HELPER FUNCTIONS FOR TESTING
// =================================================================================================

// Helper to compare our custom JsonRpcRequest records.
func equalRequest(a : Types.JsonRpcRequest, b : Types.JsonRpcRequest) : Bool {
  a.jsonrpc == b.jsonrpc and a.method == b.method and
  // Compare nested JSON by stringifying it.
  debug_show (a.params) == debug_show (b.params) and debug_show (a.id) == debug_show (b.id)
};

// Helper to display a JsonRpcRequest for test output.
func showRequest(r : Types.JsonRpcRequest) : Text {
  "{\n" #
  "  jsonrpc: \"" # r.jsonrpc # "\",\n" #
  "  method: \"" # r.method # "\",\n" #
  "  params: " # debug_show (r.params) # ",\n" #
  "  id: " # debug_show (r.id) # "\n" #
  "}";
};

// =================================================================================================
// TEST SUITE FOR RPC MODULE
// =================================================================================================

await suite(
  "Rpc",
  func() : async () {

    await suite(
      "jsonToRequest",
      func() : async () {

        await test(
          "should parse a valid request with params",
          func() : async () {
            let json = obj([
              ("jsonrpc", str("2.0")),
              ("method", str("my_method")),
              ("params", obj([("foo", str("bar"))])),
              ("id", int(1)),
            ]);
            let result = Rpc.jsonToRequest(json);
            let expected = {
              jsonrpc = "2.0";
              method = "my_method";
              params = obj([("foo", str("bar"))]);
              id = int(1);
            };
            expect.option<Types.JsonRpcRequest>(result, showRequest, equalRequest).equal(?expected);
          },
        );

        await test(
          "should parse a valid request without params",
          func() : async () {
            let json = obj([
              ("jsonrpc", str("2.0")),
              ("method", str("my_method")),
              ("id", int(1)),
            ]);
            let result = Rpc.jsonToRequest(json);
            let expected = {
              jsonrpc = "2.0";
              method = "my_method";
              params = nullable(); // Should default to JSON null
              id = int(1);
            };
            expect.option<Types.JsonRpcRequest>(result, showRequest, equalRequest).equal(?expected);
          },
        );

        await test(
          "should return null if method is missing",
          func() : async () {
            let json = obj([("id", int(1))]);
            expect.option<Types.JsonRpcRequest>(Rpc.jsonToRequest(json), showRequest, equalRequest).isNull();
          },
        );

        await test(
          "should return null if id is missing",
          func() : async () {
            let json = obj([("method", str("foo"))]);
            expect.option<Types.JsonRpcRequest>(Rpc.jsonToRequest(json), showRequest, equalRequest).isNull();
          },
        );

        await test(
          "should return null if method is not a string",
          func() : async () {
            let json = obj([("method", int(123)), ("id", int(1))]);
            expect.option<Types.JsonRpcRequest>(Rpc.jsonToRequest(json), showRequest, equalRequest).isNull();
          },
        );
      },
    );

    await suite(
      "responseToJson",
      func() : async () {

        await test(
          "should serialize a success response",
          func() : async () {
            let response_rec : Types.JsonRpcResponse = {
              jsonrpc = "2.0";
              result = ?str("success!");
              error = null;
              id = str("req-123");
            };
            let result_json = Rpc.responseToJson(response_rec);
            let expected_json = obj([
              ("jsonrpc", str("2.0")),
              ("id", str("req-123")),
              ("result", str("success!")),
            ]);

            expect.text(debug_show (result_json)).equal(debug_show (expected_json));
          },
        );

        await test(
          "should serialize an error response",
          func() : async () {
            let response_rec : Types.JsonRpcResponse = {
              jsonrpc = "2.0";
              result = null;
              error = ?{
                code = -32601;
                message = "Method not found";
                data = null;
              };
              id = int(1);
            };
            let result_json = Rpc.responseToJson(response_rec);
            let expected_json = obj([
              ("jsonrpc", str("2.0")),
              ("id", int(1)),
              ("error", obj([("code", int(-32601)), ("message", str("Method not found"))])),
            ]);

            expect.text(debug_show (result_json)).equal(debug_show (expected_json));
          },
        );

        await test(
          "should serialize an error response with data",
          func() : async () {
            let response_rec : Types.JsonRpcResponse = {
              jsonrpc = "2.0";
              result = null;
              error = ?{
                code = -32602;
                message = "Invalid params";
                data = ?str("Missing 'to' field");
              };
              id = int(2);
            };
            let result_json = Rpc.responseToJson(response_rec);
            let expected_json = obj([
              ("jsonrpc", str("2.0")),
              ("id", int(2)),
              ("error", obj([("code", int(-32602)), ("message", str("Invalid params")), ("data", str("Missing 'to' field"))])),
            ]);

            expect.text(debug_show (result_json)).equal(debug_show (expected_json));
          },
        );
      },
    );
  },
);
