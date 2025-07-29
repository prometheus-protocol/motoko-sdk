// src/mcp/Jwk.mo
// A utility to convert a JSON Web Key (JWK) object into a public key Blob
// using the `mo:ecdsa` library.

import Json "mo:json";
import Result "mo:base/Result";
import Blob "mo:base/Blob";
import BaseX "mo:base-x-encoder";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";

// Import the new, powerful ECDSA library.
import ECDSA "mo:ecdsa";

module {
  // Helper function to convert big-endian bytes to a Nat.
  private func _bytesToNat(bytes : [Nat8]) : Nat {
    var n : Nat = 0;
    for (byte in bytes.vals()) {
      n := Nat.bitshiftLeft(n, 8) + Nat8.toNat(byte);
    };
    return n;
  };
  /// Converts a JWK JSON object into a PEM-formatted Blob for the mo:jwt library.
  public func jwkToPublicKeyBlob(jwk : Json.Json) : Result.Result<Blob, Text> {
    // 1. Extract required fields from the JSON object.
    let kty = switch (Json.getAsText(jwk, "kty")) {
      case (#ok(k)) { k };
      case (#err(_)) { return #err("JWK is missing 'kty' field.") };
    };

    if (kty != "EC") {
      return #err("Unsupported key type. Only EC (Elliptic Curve) is supported.");
    };

    let crv = switch (Json.getAsText(jwk, "crv")) {
      case (#ok(c)) { c };
      case (#err(_)) { return #err("JWK is missing 'crv' field.") };
    };

    let x_b64 = switch (Json.getAsText(jwk, "x")) {
      case (#ok(x)) { x };
      case (#err(_)) { return #err("JWK is missing 'x' coordinate.") };
    };

    let y_b64 = switch (Json.getAsText(jwk, "y")) {
      case (#ok(y)) { y };
      case (#err(_)) { return #err("JWK is missing 'y' coordinate.") };
    };

    // 2. Select the correct curve based on the "crv" field.
    let curve = switch (crv) {
      case ("P-256") { ECDSA.prime256v1Curve() };
      case ("secp256k1") { ECDSA.secp256k1Curve() };
      case _ { return #err("Unsupported curve: " # crv) };
    };

    // 3. Decode the Base64Url coordinates and convert them to Nats.
    let x_bytes = switch (BaseX.fromBase64(x_b64)) {
      case (#ok(b)) { b };
      case (#err(_)) {
        return #err("Invalid Base64Url encoding for 'x' coordinate.");
      };
    };
    let y_bytes = switch (BaseX.fromBase64(y_b64)) {
      case (#ok(b)) { b };
      case (#err(_)) {
        return #err("Invalid Base64Url encoding for 'y' coordinate.");
      };
    };
    let x_nat = _bytesToNat(x_bytes);
    let y_nat = _bytesToNat(y_bytes);

    // 4. Use the ecdsa library to construct a structured PublicKey object.
    let publicKey = ECDSA.PublicKey(x_nat, y_nat, curve);

    // 5. Export the key into the standard uncompressed byte format required by mo:jwt.
    let keyBytes = publicKey.toBytes(#uncompressed);

    // 6. Return the final key as a Blob.
    return #ok(Blob.fromArray(keyBytes));
  };
};
