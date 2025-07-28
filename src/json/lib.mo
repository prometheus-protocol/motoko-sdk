import Lexer "Lexer";
import Parser "Parser";
import Types "Types";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Int "mo:base/Int";
import Float "mo:base/Float";
module Json {
  public type Json = Types.Json;
  public type Replacer = {
    #function : (Text, Json) -> ?Json;
    #keys : [Text];
  };
  public type GetAsError = {
    #pathNotFound;
    #typeMismatch;
  };
  public type Path = Types.Path;
  public type Error = Types.Error;
  public func errToText(e : Error) : Text {
  switch (e) {
    case (#invalidString(err)) { err };
    case (#invalidNumber(err)) { err };
    case (#invalidKeyword(err)) { err };
    case (#invalidChar(err)) { err };
    case (#invalidValue(err)) { err };
    case (#unexpectedEOF()) { "Unexpected EOF" };
    case (#unexpectedToken(err)) { err };
    };
  };
  public type Schema = Types.Schema;
  public type ValidationError = Types.ValidationError;
  //Json Type constructors
  public func str(text : Text) : Json = #string(text);
  public func int(n : Int) : Json = #number(#int(n));
  public func float(n : Float) : Json = #number(#float(n));
  public func bool(b : Bool) : Json = #bool(b);
  public func nullable() : Json = #null_;
  public func obj(entries : [(Text, Json)]) : Json = #object_(entries);
  public func arr(items : [Json]) : Json = #array(items);
  //Schema Type constructors
  public func string() : Types.Schema = #string;
  public func number() : Types.Schema = #number;
  public func boolean() : Types.Schema = #boolean;
  public func nullSchema() : Types.Schema = #null_;
  public func array(itemSchema : Types.Schema) : Types.Schema = #array({
    items = itemSchema;
  });
  public func schemaObject(
    properties : [(Text, Types.Schema)],
    required : ?[Text],
  ) : Types.Schema = #object_({
    properties;
    required;
  });

  public func parse(input : Text) : Result.Result<Types.Json, Types.Error> {
    let lexer = Lexer.Lexer(input);
    let tokens = switch (lexer.tokenize()) {
      case (#ok(tokens)) { tokens };
      case (#err(e)) { return #err(e) };
    };
    let parser = Parser.Parser(tokens);
    parser.parse();
  };

  public func stringify(json : Json, replacer : ?Replacer) : Text {
    switch (replacer) {
      case (null) {
        Types.toText(json);
      };
      case (?#function(fn)) {
        Types.toText(Types.transform(json, fn, ""));
      };
      case (?#keys(allowedKeys)) {
        Types.toText(Types.filterByKeys(json, allowedKeys));
      };
    };
  };
  public func get(json : Json, path : Types.Path) : ?Json {
    let parts = Parser.parsePath(path);
    Parser.getWithParts(json, parts);
  };

  public func getAsNat(json : Json, path : Types.Path) : Result.Result<Nat, GetAsError> {
    let ?value = get(json, path) else return #err(#pathNotFound);
    let #number(#int(intValue)) = value else return #err(#typeMismatch);
    if (intValue < 0) {
      // Must be a positive integer
      return #err(#typeMismatch);
    };
    #ok(Int.abs(intValue));
  };

  public func getAsInt(json : Json, path : Types.Path) : Result.Result<Int, GetAsError> {
    let ?value = get(json, path) else return #err(#pathNotFound);
    let #number(#int(intValue)) = value else return #err(#typeMismatch);
    #ok(intValue);
  };

  public func getAsFloat(json : Json, path : Types.Path) : Result.Result<Float, GetAsError> {
    let ?value = get(json, path) else return #err(#pathNotFound);
    let #number(numberValue) = value else return #err(#typeMismatch);
    let floatValue = switch (numberValue) {
      case (#int(intValue)) { Float.fromInt(intValue) };
      case (#float(floatValue)) { floatValue };
    };
    #ok(floatValue);
  };

  public func getAsBool(json : Json, path : Types.Path) : Result.Result<Bool, GetAsError> {
    let ?value = get(json, path) else return #err(#pathNotFound);
    let #bool(boolValue) = value else return #err(#typeMismatch);
    #ok(boolValue);
  };

  public func getAsText(json : Json, path : Types.Path) : Result.Result<Text, GetAsError> {
    let ?value = get(json, path) else return #err(#pathNotFound);
    let #string(text) = value else return #err(#typeMismatch);
    #ok(text);
  };

  public func getAsArray(json : Json, path : Types.Path) : Result.Result<[Json], GetAsError> {
    let ?value = get(json, path) else return #err(#pathNotFound);
    let #array(items) = value else return #err(#typeMismatch);
    #ok(items);
  };

  public func getAsObject(json : Json, path : Types.Path) : Result.Result<[(Text, Json)], GetAsError> {
    let ?value = get(json, path) else return #err(#pathNotFound);
    let #object_(entries) = value else return #err(#typeMismatch);
    #ok(entries);
  };

  public func set(json : Json, path : Types.Path, newValue : Json) : Json {
    let parts = Parser.parsePath(path);
    Parser.setWithParts(json, parts, newValue);
  };
  public func remove(json : Json, path : Types.Path) : Json {
    let parts = Parser.parsePath(path);
    Parser.removeWithParts(json, parts);
  };
  public func validate(json : Json, schema : Types.Schema) : Result.Result<(), Types.ValidationError> {
    Parser.validate(json, schema);
  };
};
