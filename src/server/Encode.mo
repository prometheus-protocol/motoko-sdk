// src/lib/Decode.mo
import Types "Types";
import Json "mo:json";
import Nat "mo:base/Nat";
import Array "mo:base/Array";

module {

  public type Encoder<T> = (T) -> Types.JsonValue;

  public let text : Encoder<Text> = Json.str;
  public let nat : Encoder<Nat> = func(n) { Json.int(n) };
  public let nullable : Encoder<()> = func(_) { Json.nullable() };

  // --- Generic Container Encoders ---

  // A generic function to encode an array of any type `T`.
  // It takes the array and a specific encoder for type `T`.
  public func array<T>(items : [T], item_encoder : Encoder<T>) : Types.JsonValue {
    // 1. Use Array.map to apply the item_encoder to each element,
    //    producing a new array of JsonValue.
    let json_items = Array.map<T, Types.JsonValue>(items, item_encoder);
    // 2. Use Json.arr to convert the Motoko array of JsonValue
    //    into a single JsonValue of the array variant.
    return Json.arr(json_items);
  };

  // A generic function to encode a record into a JSON object.
  // It takes a list of (key, value) pairs.
  public func obj(fields : [(Text, Types.JsonValue)]) : Types.JsonValue {
    return Json.obj(fields);
  };
};
