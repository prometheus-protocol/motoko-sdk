import { test; suite; expect } "mo:test/async";
import { str; int; obj; stringify } "../src/json";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

// Modules and dependencies
import Handler "../src/server/Handler";
import Args "../src/server/Args";
import Decode "../src/server/Decode";
import Encode "../src/server/Encode";

// =================================================================================================
// TEST SUITE FOR HANDLER FACTORIES
// =================================================================================================

await suite(
  "Handler",
  func() : async () {

    await test(
      "query1 should create a #read handler that decodes/encodes correctly",
      func() : async () {
        // 1. Define a synchronous CPS-style function.
        let greet = func(name : Text, cb : (Text) -> ()) {
          cb("Hello, " # name # "!");
        };
        let handler = Handler.query1<Text, Text>(
          greet,
          Args.by_name_1(("name", Decode.text)),
          Encode.text,
        );

        // 2. Unwrap the handler variant.
        switch (handler) {
          case (#mutation(_)) {
            assert false;
          };
          case (#read(rep)) {
            // 3. Call the synchronous `call` function.
            let params = obj([("name", str("alice"))]);
            let result = rep.call(params);

            // 4. Check the Result from the call.
            switch (result) {
              case (#err(_)) {
                assert false;
              };
              case (#ok(result_json)) {
                let actual_text = stringify(result_json, null);
                let expected_text = stringify(str("Hello, alice!"), null);
                expect.text(actual_text).equal(expected_text);
              };
            };
          };
        };
      },
    );

    await test(
      "update0 should create a #mutation handler",
      func() : async () {
        // 1. Define an async CPS-style function.
        var counter : Nat = 0;
        let inc_count = func(cb : (Nat) -> ()) : async () {
          counter += 1;
          cb(counter);
        };
        let handler = Handler.update0<Nat>(inc_count, Encode.nat);

        // 2. Unwrap the handler variant.
        switch (handler) {
          case (#read(_)) {
            assert false;
          };
          case (#mutation(rep)) {
            // 3. Call the asynchronous `call` function.
            let result = await rep.call(obj([]));

            // 4. Check the Result from the call.
            switch (result) {
              case (#err(_)) {
                assert false;
              };
              case (#ok(result_json)) {
                let actual_text = stringify(result_json, null);
                let expected_text = stringify(int(1), null);
                expect.text(actual_text).equal(expected_text);
              };
            };
          };
        };
      },
    );

    await test(
      "query1 handler should return #err on bad params",
      func() : async () {
        // 1. Define a dummy function.
        let greet = func(_ : Text, cb : (Text) -> ()) { cb("...") };
        let handler = Handler.query1<Text, Text>(
          greet,
          Args.by_name_1(("name", Decode.text)),
          Encode.text,
        );

        // 2. Unwrap the handler variant.
        switch (handler) {
          case (#mutation(_)) {
            assert false;
          };
          case (#read(rep)) {
            // 3. Call with invalid params.
            let invalid_params = obj([("username", str("alice"))]);
            let result = rep.call(invalid_params);

            // 4. Assert that the result is an #err.
            switch (result) {
              case (#ok(_)) {
                assert false;
              };
              case (#err(error_res)) {
                // This is the success case for this test.
                expect.int(error_res.code).equal(-32602); // Invalid params
                expect.text(error_res.message).equal("Invalid params");
              };
            };
          };
        };
      },
    );
  },
);
