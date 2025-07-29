import { test; suite; expect } "mo:test/async";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Result "mo:base/Result";
import BaseX "mo:base-x-encoder";
import Json "../src/json";
import Debug "mo:base/Debug";

// Module to test
import Jwk "../src/auth/Jwk";

// =================================================================================================
// HELPER FUNCTIONS FOR TESTING
// =================================================================================================

// Helper to compare two Result<Blob, Text> values.
func equalResult(a : Result.Result<Blob, Text>, b : Result.Result<Blob, Text>) : Bool {
  switch (a, b) {
    case (#ok(blobA), #ok(blobB)) { return Blob.equal(blobA, blobB) };
    case (#err(textA), #err(textB)) { return textA == textB };
    case _ { return false };
  };
};

// Helper to display a Result<Blob, Text> value for test output.
func showResult(r : Result.Result<Blob, Text>) : Text {
  return debug_show (r);
};

// =================================================================================================
// TEST SUITE FOR JWK MODULE
// =================================================================================================

await suite(
  "Jwk",
  func() : async () {

    await suite(
      "jwkToPublicKeyBlob",
      func() : async () {

        await test(
          "should correctly convert a valid P-256 JWK",
          func() : async () {
            // This is a standard test vector from RFC 7515
            let jwk = Json.obj([
              ("kty", Json.str("EC")),
              ("crv", Json.str("P-256")),
              ("x", Json.str("f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU")),
              ("y", Json.str("x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0")),
            ]);

            let result = Jwk.jwkToPublicKeyBlob(jwk);

            // The expected output is the uncompressed key: 0x04 | x | y
            let expectedHex = "047fcdce2770f6c45d4183cbee6fdb4b7b580733357be9ef13bacf6e3c7bd15445c7f144cd1bbd9b7e872cdfedb9eeb9f4b3695d6ea90b24ad8a4623288588e5ad";
            let decoded = switch (BaseX.fromHex(expectedHex, { prefix = #none })) {
              case (#ok(b)) { b };
              case (#err(e)) {
                Debug.trap("Failed to decode expected hex: " # e);
              };
            };
            let expectedBlob = Blob.fromArray(decoded);

            switch (result) {
              case (#ok(blob)) {
                expect.blob(blob).equal(expectedBlob);
              };
              case (#err(e)) {
                Debug.trap("Test failed unexpectedly with error: " # e);
              };
            };
          },
        );

        await test(
          "should return an error for an unsupported key type (kty)",
          func() : async () {
            let jwk = Json.obj([
              ("kty", Json.str("RSA")), // Unsupported type
              ("crv", Json.str("P-256")),
              ("x", Json.str("...")),
            ]);
            let result = Jwk.jwkToPublicKeyBlob(jwk);
            expect.result<Blob, Text>(result, showResult, equalResult).isErr();
          },
        );

        await test(
          "should return an error for an unsupported curve (crv)",
          func() : async () {
            let jwk = Json.obj([
              ("kty", Json.str("EC")),
              ("crv", Json.str("P-384")), // Unsupported curve
              ("x", Json.str("...")),
            ]);
            let result = Jwk.jwkToPublicKeyBlob(jwk);
            expect.result<Blob, Text>(result, showResult, equalResult).isErr();
          },
        );

        await test(
          "should return an error if 'x' coordinate is missing",
          func() : async () {
            let jwk = Json.obj([
              ("kty", Json.str("EC")),
              ("crv", Json.str("P-256")),
              // Missing "x"
              ("y", Json.str("x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0")),
            ]);
            let result = Jwk.jwkToPublicKeyBlob(jwk);
            expect.result<Blob, Text>(result, showResult, equalResult).isErr();
          },
        );

        await test(
          "should return an error for invalid Base64 encoding",
          func() : async () {
            let jwk = Json.obj([
              ("kty", Json.str("EC")),
              ("crv", Json.str("P-256")),
              ("x", Json.str("this-is-not-valid-base64!!")), // Invalid characters
              ("y", Json.str("x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0")),
            ]);
            let result = Jwk.jwkToPublicKeyBlob(jwk);
            expect.result<Blob, Text>(result, showResult, equalResult).isErr();
          },
        );
      },
    );
  },
);
