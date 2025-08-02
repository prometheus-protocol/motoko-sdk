import { test; suite; expect } "mo:test/async";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Result "mo:base/Result";
import BaseX "mo:base-x-encoder";
import Json "../src/json";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";

// Module to test
import Jwk "../src/auth/Jwk";
import Types "../src/auth/Types"; // NEW: Import the types module

// =================================================================================================
// HELPER FUNCTIONS FOR TESTING
// =================================================================================================

// CORRECTED: Helper to compare two Result<PublicKeyData, Text> values.
func equalResult(a : Result.Result<Types.PublicKeyData, Text>, b : Result.Result<Types.PublicKeyData, Text>) : Bool {
  switch (a, b) {
    case (#ok(dtoA), #ok(dtoB)) {
      // Compare each field of the DTO
      return dtoA.curveKind == dtoB.curveKind and dtoA.x == dtoB.x and dtoA.y == dtoB.y;
    };
    case (#err(textA), #err(textB)) { return textA == textB };
    case _ { return false };
  };
};

// CORRECTED: Helper to display a Result<PublicKeyData, Text> value for test output.
func showResult(r : Result.Result<Types.PublicKeyData, Text>) : Text {
  return debug_show (r);
};

// This is needed because Motoko's base library doesn't have a direct equivalent.
func natFromBytesBE(bytes : [Nat8]) : Nat {
  var result : Nat = 0;
  for (byte in bytes.vals()) {
    // Left shift the current result by 8 bits to make room for the new byte.
    result := Nat.bitshiftLeft(result, 8);
    // Add the value of the new byte.
    result := result + Nat8.toNat(byte);
  };
  return result;
};

// Helper to decode Base64URL and convert to a Nat
func natFromBase64Url(s : Text) : Nat {
  let bytes = switch (BaseX.fromBase64(s)) {
    case (#ok(b)) { b };
    case (#err(e)) { Debug.trap("Test setup failed: invalid base64url: " # e) };
  };
  return natFromBytesBE(bytes);
};

// =================================================================================================
// TEST SUITE FOR JWK MODULE
// =================================================================================================

await suite(
  "Jwk",
  func() : async () {

    await suite(
      "jwkToPublicKeyData", // CORRECTED: Suite name reflects new function
      func() : async () {

        await test(
          "should correctly convert a valid P-256 JWK to a PublicKeyData DTO",
          func() : async () {
            // ARRANGE: A standard test vector from RFC 7515
            let x_b64 = "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU";
            let y_b64 = "x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0";

            let jwk = Json.obj([
              ("kty", Json.str("EC")),
              ("crv", Json.str("P-256")),
              ("x", Json.str(x_b64)),
              ("y", Json.str(y_b64)),
            ]);

            // ACT
            let result = Jwk.jwkToPublicKeyData(jwk);

            // ASSERT
            // CORRECTED: The expected output is now a structured DTO, not a blob.
            let expectedData : Types.PublicKeyData = {
              curveKind = #prime256v1;
              x = natFromBase64Url(x_b64);
              y = natFromBase64Url(y_b64);
            };

            expect.result<Types.PublicKeyData, Text>(result, showResult, equalResult).equal(#ok(expectedData));
          },
        );

        await test(
          "should return an error for an unsupported key type (kty)",
          func() : async () {
            let jwk = Json.obj([("kty", Json.str("RSA")), ("crv", Json.str("P-256")), ("x", Json.str("..."))]);
            // CORRECTED: Call the right function and use the right types
            let result = Jwk.jwkToPublicKeyData(jwk);
            expect.result<Types.PublicKeyData, Text>(result, showResult, equalResult).isErr();
          },
        );

        await test(
          "should return an error for an unsupported curve (crv)",
          func() : async () {
            let jwk = Json.obj([("kty", Json.str("EC")), ("crv", Json.str("P-384")), ("x", Json.str("..."))]);
            // CORRECTED: Call the right function and use the right types
            let result = Jwk.jwkToPublicKeyData(jwk);
            expect.result<Types.PublicKeyData, Text>(result, showResult, equalResult).isErr();
          },
        );

        await test(
          "should return an error if 'x' coordinate is missing",
          func() : async () {
            let jwk = Json.obj([("kty", Json.str("EC")), ("crv", Json.str("P-256")), ("y", Json.str("..."))]);
            // CORRECTED: Call the right function and use the right types
            let result = Jwk.jwkToPublicKeyData(jwk);
            expect.result<Types.PublicKeyData, Text>(result, showResult, equalResult).isErr();
          },
        );

        await test(
          "should return an error for invalid Base64 encoding",
          func() : async () {
            let jwk = Json.obj([("kty", Json.str("EC")), ("crv", Json.str("P-256")), ("x", Json.str("!!invalid!!")), ("y", Json.str("..."))]);
            // CORRECTED: Call the right function and use the right types
            let result = Jwk.jwkToPublicKeyData(jwk);
            expect.result<Types.PublicKeyData, Text>(result, showResult, equalResult).isErr();
          },
        );
      },
    );
  },
);
