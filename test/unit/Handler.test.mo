import { test; suite; expect } "mo:test/async";
import { str; int; obj; stringify } "mo:json";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Result "mo:base/Result";

// Modules and dependencies
import Handler "../../src/server/Handler";
import Args "../../src/server/Args";
import Decode "../../src/server/Decode";
import Encode "../../src/server/Encode";
import AuthTypes "../../src/auth/Types";

// =================================================================================================
// TEST SUITE FOR HANDLER FACTORIES
// =================================================================================================

await suite(
  "Handler",
  func() : async () {

    await test(
      "query1 should create a #read handler that decodes/encodes correctly",
      func() : async () {
        // 1. Define a function with the NEW signature.
        let greet = func(
          name : Text,
          auth : ?AuthTypes.AuthInfo,
          cb : (Result.Result<Text, Handler.HandlerError>) -> (),
        ) {
          // MODIFIED: Callback now wraps the success value in #ok.
          cb(#ok("Hello, " # name # "!"));
        };
        let handler = Handler.query1<Text, Text>(
          greet,
          Args.by_name_1(("name", Decode.text)),
          Encode.text,
        );

        // 2. Unwrap the handler variant.
        switch (handler) {
          case (#mutation(_)) { assert false };
          case (#read(rep)) {
            // 3. Call the synchronous `call` function.
            let params = obj([("name", str("alice"))]);
            let result = rep.call(params, null);

            // 4. Check the Result from the call.
            switch (result) {
              case (#err(_)) { assert false };
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
        // 1. Define an async function with the NEW signature.
        var counter : Nat = 0;
        let inc_count = func(
          auth : ?AuthTypes.AuthInfo,
          cb : (Result.Result<Nat, Handler.HandlerError>) -> (),
        ) : async () {
          counter += 1;
          // MODIFIED: Callback now wraps the success value in #ok.
          cb(#ok(counter));
        };
        let handler = Handler.update0<Nat>(inc_count, Encode.nat);

        // 2. Unwrap the handler variant.
        switch (handler) {
          case (#read(_)) { assert false };
          case (#mutation(rep)) {
            // 3. Call the asynchronous `call` function.
            let result = await rep.call(obj([]), null);

            // 4. Check the Result from the call.
            switch (result) {
              case (#err(_)) { assert false };
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
        // 1. Define a dummy function with the NEW signature.
        let greet = func(
          _ : Text,
          _ : ?AuthTypes.AuthInfo,
          cb : (Result.Result<Text, Handler.HandlerError>) -> (),
        ) { cb(#ok("...")) };
        let handler = Handler.query1<Text, Text>(
          greet,
          Args.by_name_1(("name", Decode.text)),
          Encode.text,
        );

        // 2. Unwrap the handler variant.
        switch (handler) {
          case (#mutation(_)) { assert false };
          case (#read(rep)) {
            // 3. Call with invalid params.
            let invalid_params = obj([("username", str("alice"))]);
            let result = rep.call(invalid_params, null);

            // 4. Assert that the result is an #err.
            switch (result) {
              case (#ok(_)) { assert false };
              case (#err(error_res)) {
                expect.int(error_res.code).equal(-32602); // Invalid params
                expect.text(error_res.message).equal("Invalid params");
              };
            };
          };
        };
      },
    );

    // NEW TEST CASE
    await test(
      "query1 handler should propagate a business-logic #err from the callback",
      func() : async () {
        // 1. Define a function that always returns a business-logic error.
        let fail_greet = func(
          _ : Text,
          _ : ?AuthTypes.AuthInfo,
          cb : (Result.Result<Text, Handler.HandlerError>) -> (),
        ) {
          cb(#err({ code = -32000; message = "User not found"; data = null }));
        };
        let handler = Handler.query1<Text, Text>(
          fail_greet,
          Args.by_name_1(("name", Decode.text)),
          Encode.text,
        );

        // 2. Unwrap the handler variant.
        switch (handler) {
          case (#mutation(_)) { assert false };
          case (#read(rep)) {
            // 3. Call with valid params, expecting the handler to fail internally.
            let params = obj([("name", str("alice"))]);
            let result = rep.call(params, null);

            // 4. Assert that the result is the specific #err we returned.
            switch (result) {
              case (#ok(_)) { assert false };
              case (#err(error_res)) {
                expect.int(error_res.code).equal(-32000);
                expect.text(error_res.message).equal("User not found");
              };
            };
          };
        };
      },
    );
  },
);
