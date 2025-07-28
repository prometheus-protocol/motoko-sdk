// import { test; suite; expect } "mo:test/async";
// import ExperimentalCycles "mo:base/ExperimentalCycles";
// import { str; int; obj } "json";
// import Json "json";
// import Nat "mo:base/Nat";
// import Text "mo:base/Text";
// import Blob "mo:base/Blob";
// import Main "../examples/mcp_server/main"; // Import the canister actor to be deployed
// import Types "../src";

// // This entire file is an actor that will deploy our main canister and run tests against it.
// actor {
//   // --- SETUP PHASE ---
//   // This code runs when the test actor itself is deployed.

//   // 1. Add cycles to this test actor so it can pay to deploy our main canister.
//   // ExperimentalCycles.add(1_000_000_000_000);

//   // 2. Deploy a fresh instance of our main canister for testing.
//   let canister = await Main.Main();

//   // --- HELPER FUNCTION ---
//   // Helper to create a valid JSON-RPC request.
//   func create_request(method : Text, params : Types.JsonValue, id : Nat) : Types.HttpRequest {
//     let rpc_body = obj([
//       ("jsonrpc", str("2.0")),
//       ("method", str(method)),
//       ("params", params),
//       ("id", int(id)),
//     ]);

//     return {
//       method = "POST";
//       url = "/";
//       headers = [("Authorization", "Bearer FAKE_TOKEN")];
//       body = Text.encodeUtf8(Json.stringify(rpc_body));
//     };
//   };

//   // --- TEST RUNNER ---
//   // This public function is the entry point that `mops test --replica` will execute.
//   public func runTests() : async () {

//     await suite(
//       "Server Replica Tests",
//       func() : async () {

//         await test(
//           "should handle a read-only call via http_request",
//           func() : async () {
//             let req = create_request("get_count", obj([]), 1);
//             let res = await canister.http_request(req);

//             expect.nat16(res.status_code).equal(200);
//             expect.option<Bool>(res.upgrade, func(b) { ?b.toText() }, func(a, b) { a == b }).isNull();

//             let ?body_text = Text.decodeUtf8(res.body) else assert false;
//             let #ok(json_res) = Json.parse(body_text) else assert false;
//             let #ok(id_val) = Json.getAsInt(json_res, "id") else assert false;
//             let #ok(result_val) = Json.getAsInt(json_res, "result") else assert false;

//             expect.int(id_val).equal(1);
//             expect.int(result_val).equal(0); // Counter should be 0 initially.
//           },
//         );

//         await test(
//           "should request an upgrade for a mutation via http_request",
//           func() : async () {
//             let req = create_request("inc_count", obj([]), 2);
//             // We call the QUERY endpoint to test the upgrade flow.
//             let res = await canister.http_request(req);

//             expect.nat16(res.status_code).equal(200);
//             expect.option<Bool>(res.upgrade, func(b) { ?b.toText() }, func(a, b) { a == b }).equal(?true);
//             expect.nat(res.body.size()).equal(0);
//           },
//         );

//         await test(
//           "should execute a mutation via http_request_update",
//           func() : async () {
//             let req = create_request("inc_count", obj([]), 3);
//             // We call the UPDATE endpoint to actually change state.
//             let res = await canister.http_request_update(req);

//             expect.nat16(res.status_code).equal(200);
//             expect.option<Bool>(res.upgrade, func(b) { ?b.toText() }, func(a, b) { a == b }).isNull();

//             let ?body_text = Text.decodeUtf8(res.body) else assert false;
//             let #ok(json_res) = Json.parse(body_text) else assert false;
//             let #ok(result_val) = Json.getAsInt(json_res, "result") else assert false;

//             // The counter was 0, this is the first successful increment.
//             expect.int(result_val).equal(1);
//           },
//         );

//         await test(
//           "should return 401 for missing auth header",
//           func() : async () {
//             var req = create_request("get_count", obj([]), 4);
//             req.headers := []; // Remove auth header
//             let res = await canister.http_request(req);

//             expect.nat16(res.status_code).equal(401);
//           },
//         );

//         await test(
//           "should return JSON-RPC error for method not found",
//           func() : async () {
//             let req = create_request("non_existent_method", obj([]), 5);
//             let res = await canister.http_request(req);

//             expect.nat16(res.status_code).equal(200);
//             let ?body_text = Text.decodeUtf8(res.body) else assert false;
//             let #ok(json_res) = Json.parse(body_text) else assert false;
//             let #ok(err_obj) = Json.getAsObject(json_res, "error") else assert false;
//             let #ok(code) = Json.getAsInt(err_obj, "code") else assert false;

//             expect.int(code).equal(-32601);
//           },
//         );

//         await test(
//           "should return JSON-RPC error for malformed body",
//           func() : async () {
//             var req = create_request("get_count", obj([]), 6);
//             req.body := Text.encodeUtf8("{not json}"); // Malformed body
//             let res = await canister.http_request(req);

//             expect.nat16(res.status_code).equal(200);
//             let ?body_text = Text.decodeUtf8(res.body) else assert false;
//             let #ok(json_res) = Json.parse(body_text) else assert false;
//             let #ok(err_obj) = Json.getAsObject(json_res, "error") else assert false;
//             let #ok(code) = Json.getAsInt(err_obj, "code") else assert false;
//             let id_val = Json.get(json_res, "id")!;

//             expect.int(code).equal(-32700);
//             expect.bool(Json.isNull(id_val)).isTrue(); // ID should be null on parse error
//           },
//         );
//       },
//     );
//   };
// };
