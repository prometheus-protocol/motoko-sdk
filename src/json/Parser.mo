import Types "./Types";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Text "mo:base/Text";
import Nat "mo:base/Nat";

module {
  type Json = Types.Json;
  public class Parser(tokens : [Types.Token]) {
    var position = 0;

    private func current() : ?Types.Token {
      if (position < tokens.size()) ?tokens[position] else null;
    };

    private func advance() {
      position += 1;
    };

    public func parse() : Result.Result<Types.Json, Types.Error> {
      switch (parseValue()) {
        case (#ok(json)) {
          switch (current()) {
            case (null) { #ok(json) };
            case (?_) { #err(#unexpectedToken("Expected end of input")) };
          };
        };
        case (#err(e)) { #err(e) };
      };
    };

    private func parseValue() : Result.Result<Types.Json, Types.Error> {
      switch (current()) {
        case (null) { #err(#unexpectedEOF) };
        case (?token) {
          switch (token) {
            case (#beginObject) { parseObject() };
            case (#beginArray) { parseArray() };
            case (#string(s)) { advance(); #ok(#string(s)) };
            case (#number(n)) { advance(); #ok(#number(n)) };
            case (#true_) { advance(); #ok(#bool(true)) };
            case (#false_) { advance(); #ok(#bool(false)) };
            case (#null_) { advance(); #ok(#null_) };
            case (_) { #err(#unexpectedToken("Expected value")) };
          };
        };
      };
    };

    private func parseObject() : Result.Result<Types.Json, Types.Error> {
      advance();
      var fields : [(Text, Types.Json)] = [];

      switch (current()) {
        case (?#endObject) {
          advance();
          #ok(#object_(fields));
        };
        case (?#string(_)) {
          switch (parseMember()) {
            case (#err(e)) { #err(e) };
            case (#ok(field)) {
              fields := [(field.0, field.1)];
              loop {
                switch (current()) {
                  case (?#valueSeperator) {
                    advance();
                    switch (parseMember()) {
                      case (#ok(next)) {
                        fields := Array.append(fields, [(next.0, next.1)]);
                      };
                      case (#err(e)) { return #err(e) };
                    };
                  };
                  case (?#endObject) {
                    advance();
                    return #ok(#object_(fields));
                  };
                  case (null) { return #err(#unexpectedEOF) };
                  case (_) {
                    return #err(#unexpectedToken("Expected ',' or '}'"));
                  };
                };
              };
            };
          };
        };
        case (null) { #err(#unexpectedEOF) };
        case (_) { #err(#unexpectedToken("Expected string or '}'")) };
      };
    };

    private func parseMember() : Result.Result<(Text, Types.Json), Types.Error> {
      switch (current()) {
        case (?#string(key)) {
          advance();
          switch (current()) {
            case (?#nameSeperator) {
              advance();
              switch (parseValue()) {
                case (#ok(value)) { #ok((key, value)) };
                case (#err(e)) { #err(e) };
              };
            };
            case (null) { #err(#unexpectedEOF) };
            case (_) { #err(#unexpectedToken("Expected ':'")) };
          };
        };
        case (null) { #err(#unexpectedEOF) };
        case (_) { #err(#unexpectedToken("Expected string")) };
      };
    };

    private func parseArray() : Result.Result<Types.Json, Types.Error> {
      advance();
      var elements : [Types.Json] = [];

      switch (current()) {
        case (?#endArray) {
          advance();
          #ok(#array(elements));
        };
        case (null) {
          #err(#unexpectedEOF);
        };
        case (_) {
          switch (parseValue()) {
            case (#err(e)) { #err(e) };
            case (#ok(value)) {
              elements := [value];
              loop {
                switch (current()) {
                  case (?#valueSeperator) {
                    advance();
                    switch (parseValue()) {
                      case (#ok(next)) {
                        elements := Array.append(elements, [next]);
                      };
                      case (#err(e)) { return #err(e) };
                    };
                  };
                  case (?#endArray) {
                    advance();
                    return #ok(#array(elements));
                  };
                  case (null) { return #err(#unexpectedEOF) };
                  case (_) {
                    return #err(#unexpectedToken("Expected ',' or ']'"));
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  public func parsePath(path : Text) : [Types.PathPart] {
    let chars = path.chars();
    let parts = Buffer.Buffer<Types.PathPart>(8);
    var current = Buffer.Buffer<Char>(16);
    var inBracket = false;

    for (c in chars) {
      switch (c) {
        case '[' {
          if (current.size() > 0) {
            parts.add(#key(Text.fromIter(current.vals())));
            current.clear();
          };
          inBracket := true;
        };
        case ']' {
          if (current.size() > 0) {
            let indexText = Text.fromIter(current.vals());
            if (indexText == "*") {
              parts.add(#wildcard);
            } else {
              switch (Nat.fromText(indexText)) {
                case (?idx) { parts.add(#index(idx)) };
                case null {};
              };
            };
            current.clear();
          };
          inBracket := false;
        };
        case '.' {
          if (current.size() > 0) {
            let key = Text.fromIter(current.vals());
            if (key == "*") {
              parts.add(#wildcard);
            } else {
              parts.add(#key(key));
            };
            current.clear();
          };
        };
        case c { current.add(c) };
      };
    };
    if (current.size() > 0) {
      let final = Text.fromIter(current.vals());
      if (final == "*") {
        parts.add(#wildcard);
      } else {
        parts.add(#key(final));
      };
    };

    Buffer.toArray(parts);
  };

  public func getWithParts(json : Json, parts : [Types.PathPart]) : ?Json {
    if (parts.size() == 0) { return ?json };

    switch (parts[0], json) {
      case (#key(key), #object_(entries)) {
        for ((k, v) in entries.vals()) {
          if (k == key) {
            return getWithParts(
              v,
              Array.tabulate<Types.PathPart>(
                parts.size() - 1,
                func(i) = parts[i + 1],
              ),
            );
          };
        };
        null;
      };
      case (#index(i), #array(items)) {
        if (i < items.size()) {
          getWithParts(
            items[i],
            Array.tabulate<Types.PathPart>(
              parts.size() - 1,
              func(i) = parts[i + 1],
            ),
          );
        } else {
          null;
        };
      };
      case (#wildcard, #object_(entries)) {
        ?#array(
          Array.mapFilter<(Text, Json), Json>(
            entries,
            func((_, v)) = getWithParts(
              v,
              Array.tabulate<Types.PathPart>(
                parts.size() - 1,
                func(i) = parts[i + 1],
              ),
            ),
          )
        );
      };
      case (#wildcard, #array(items)) {
        ?#array(
          Array.mapFilter<Json, Json>(
            items,
            func(item) = getWithParts(
              item,
              Array.tabulate<Types.PathPart>(
                parts.size() - 1,
                func(i) = parts[i + 1],
              ),
            ),
          )
        );
      };
      case _ { null };
    };
  };

  public func setWithParts(json : Json, parts : [Types.PathPart], newValue : Json) : Json {
    if (parts.size() == 0) {
      return newValue;
    };

    switch (parts[0], json) {
      case (#key(key), #object_(entries)) {
        let remaining = Array.tabulate<Types.PathPart>(
          parts.size() - 1,
          func(i) = parts[i + 1],
        );

        var found = false;
        let newEntries = Array.map<(Text, Json), (Text, Json)>(
          entries,
          func((k, v) : (Text, Json)) : (Text, Json) {
            if (k == key) {
              found := true;
              (k, setWithParts(v, remaining, newValue));
            } else { (k, v) };
          },
        );

        if (not found) {
          #object_(Array.append(newEntries, [(key, setWithParts(#null_, remaining, newValue))]));
        } else {
          #object_(newEntries);
        };
      };

      case (#index(i), #array(items)) {
        let remaining = Array.tabulate<Types.PathPart>(
          parts.size() - 1,
          func(i) = parts[i + 1],
        );

        if (i < items.size()) {
          #array(
            Array.tabulate<Json>(
              items.size(),
              func(idx : Nat) : Json {
                if (idx == i) {
                  setWithParts(items[idx], remaining, newValue);
                } else {
                  items[idx];
                };
              },
            )
          );
        } else {
          let nulls = Array.tabulate<Json>(
            i - items.size(),
            func(_) = #null_,
          );
          #array(
            Array.append(
              Array.append(items, nulls),
              [setWithParts(#null_, remaining, newValue)],
            )
          );
        };
      };

      case (#key(key), _) {
        let remaining = Array.tabulate<Types.PathPart>(
          parts.size() - 1,
          func(i) = parts[i + 1],
        );
        #object_([(key, setWithParts(#null_, remaining, newValue))]);
      };

      case (#index(i), _) {
        let remaining = Array.tabulate<Types.PathPart>(
          parts.size() - 1,
          func(i) = parts[i + 1],
        );
        let items = Array.tabulate<Json>(
          i + 1,
          func(idx : Nat) : Json {
            if (idx == i) {
              setWithParts(#null_, remaining, newValue);
            } else {
              #null_;
            };
          },
        );
        #array(items);
      };

      case _ { json };
    };
  };

  public func removeWithParts(json : Json, parts : [Types.PathPart]) : Json {
    if (parts.size() == 0) {
      return #null_;
    };

    switch (parts[0], json) {
      case (#key(key), #object_(entries)) {
        if (parts.size() == 1) {
          #object_(
            Array.filter<(Text, Json)>(
              entries,
              func((k, _) : (Text, Json)) : Bool { k != key },
            )
          );
        } else {
          let remaining = Array.tabulate<Types.PathPart>(
            parts.size() - 1,
            func(i) = parts[i + 1],
          );

          #object_(
            Array.map<(Text, Json), (Text, Json)>(
              entries,
              func((k, v) : (Text, Json)) : (Text, Json) {
                if (k == key) { (k, removeWithParts(v, remaining)) } else {
                  (k, v);
                };
              },
            )
          );
        };
      };

      case (#index(i), #array(items)) {
        if (i >= items.size()) {
          return json;
        };

        if (parts.size() == 1) {
          #array(
            Array.tabulate<Json>(
              items.size() - 1,
              func(idx : Nat) : Json {
                if (idx < i) {
                  items[idx];
                } else {
                  items[idx + 1];
                };
              },
            )
          );
        } else {
          let remaining = Array.tabulate<Types.PathPart>(
            parts.size() - 1,
            func(i) = parts[i + 1],
          );

          #array(
            Array.tabulate<Json>(
              items.size(),
              func(idx : Nat) : Json {
                if (idx == i) {
                  removeWithParts(items[idx], remaining);
                } else {
                  items[idx];
                };
              },
            )
          );
        };
      };
      case _ { json };
    };
  };

  public func validate(instance : Json, schema : Types.Schema) : Result.Result<(), Types.ValidationError> {
    switch (schema) {
      case (#object_ { properties; required }) {
        switch (instance) {
          case (#object_(entries)) {
            switch (required) {
              case (?requiredFields) {
                for (requiredKey in requiredFields.vals()) {
                  var found = false;
                  label checking for ((key, _) in entries.vals()) {
                    if (key == requiredKey) {
                      found := true;
                      break checking;
                    };
                  };
                  if (not found) {
                    return #err(#requiredField(requiredKey));
                  };
                };
              };
              case null {};
            };
            for ((schemaKey, schemaType) in properties.vals()) {
              for ((key, value) in entries.vals()) {
                if (key == schemaKey) {
                  switch (validate(value, schemaType)) {
                    case (#err(e)) return #err(e);
                    case (#ok()) {};
                  };
                };
              };
            };
            #ok();
          };
          case (_) {
            #err(
              #typeError {
                expected = "object";
                got = Types.getTypeString(instance);
                path = "";
              }
            );
          };
        };
      };
      case (#array { items }) {
        switch (instance) {
          case (#array(values)) {
            for (value in values.vals()) {
              switch (validate(value, items)) {
                case (#err(e)) return #err(e);
                case (#ok()) {};
              };
            };
            #ok();
          };
          case (_) {
            #err(
              #typeError {
                expected = "array";
                got = Types.getTypeString(instance);
                path = "";
              }
            );
          };
        };
      };
      case (#string) {
        switch (instance) {
          case (#string(_)) #ok();
          case (_) {
            #err(
              #typeError {
                expected = "string";
                got = Types.getTypeString(instance);
                path = "";
              }
            );
          };
        };
      };
      case (#number) {
        switch (instance) {
          case (#number(_)) #ok();
          case (_) {
            #err(
              #typeError {
                expected = "number";
                got = Types.getTypeString(instance);
                path = "";
              }
            );
          };
        };
      };
      case (#boolean) {
        switch (instance) {
          case (#bool(_)) #ok();
          case (_) {
            #err(
              #typeError {
                expected = "boolean";
                got = Types.getTypeString(instance);
                path = "";
              }
            );
          };
        };
      };
      case (#null_) {
        switch (instance) {
          case (#null_) #ok();
          case (_) {
            #err(
              #typeError {
                expected = "null";
                got = Types.getTypeString(instance);
                path = "";
              }
            );
          };
        };
      };
    };
  };
};
