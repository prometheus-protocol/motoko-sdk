import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Json "mo:json";
import Types "Types";

module {
  // A Decoder now takes the top-level JSON and a path to the desired value.
  public type Decoder<T> = (json : Types.JsonValue, path : Json.Path) -> ?T;

  // Decodes a JSON string at a given path to a Motoko Text.
  public let text : Decoder<Text> = func(json, path) {
    switch (Json.getAsText(json, path)) {
      case (#ok(t)) { return ?t };
      case (#err(_)) { return null };
    };
  };

  // Decodes a JSON number at a given path to a Motoko Int.
  public let int : Decoder<Int> = func(json, path) {
    switch (Json.getAsInt(json, path)) {
      case (#ok(i)) { return ?i };
      case (#err(_)) { return null };
    };
  };

  // Decodes a JSON number at a given path to a Motoko Nat.
  public let nat : Decoder<Nat> = func(json, path) {
    switch (Json.getAsNat(json, path)) {
      case (#ok(n)) { return ?n };
      case (#err(_)) { return null };
    };
  };

  // Decodes a JSON string at a given path to a Motoko Principal.
  public let principal : Decoder<Principal> = func(json, path) {
    switch (Json.getAsText(json, path)) {
      case (#ok(s)) {
        // TODO: Check for invalid principal format
        ?Principal.fromText(s);
      };
      case (#err(_)) { return null };
    };
  };

  // Decodes a JSON boolean at a given path to a Motoko Bool.
  public let bool : Decoder<Bool> = func(json, path) {
    switch (Json.getAsBool(json, path)) {
      case (#ok(b)) { return ?b };
      case (#err(_)) { return null };
    };
  };
};
