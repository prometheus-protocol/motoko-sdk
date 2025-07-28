import Text "mo:base/Text";
import Char "mo:base/Char";
import Int "mo:base/Int";
import Int32 "mo:base/Int32";
import Float "mo:base/Float";
import Bool "mo:base/Bool";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat32 "mo:base/Nat32";

module {
  public type Path = Text;
  public type PathPart = {
    #key : Text;
    #index : Nat;
    #wildcard;
  };
  public type Schema = {
    #object_ : {
      properties : [(Text, Schema)];
      required : ?[Text];
    };
    #array : {
      items : Schema;
    };
    #string;
    #number;
    #boolean;
    #null_;
  };

  public type ValidationError = {
    #typeError : {
      expected : Text;
      got : Text;
      path : Text;
    };
    #requiredField : Text;
  };
  public type Token = {
    #beginArray;
    #beginObject;
    #endArray;
    #endObject;
    #nameSeperator;
    #valueSeperator;
    #whitespace;
    #false_;
    #null_;
    #true_;
    #number : {
      #int : Int;
      #float : Float;
    };
    #string : Text;
  };
  public type Json = {
    #object_ : [(Text, Json)];
    #array : [Json];
    #string : Text;
    #number : {
      #int : Int;
      #float : Float;
    };
    #bool : Bool;
    #null_;
  };

  public type Error = {
    #invalidString : Text;
    #invalidNumber : Text;
    #invalidKeyword : Text;
    #invalidChar : Text;
    #invalidValue : Text;
    #unexpectedEOF;
    #unexpectedToken : Text;
  };

  public func transform(json : Json, replacer : (Text, Json) -> ?Json, key : Text) : Json {
    let replaced = switch (replacer(key, json)) {
      case (?newValue) { newValue };
      case (null) { json };
    };

    switch (replaced) {
      case (#object_(entries)) {
        #object_(
          Array.map<(Text, Json), (Text, Json)>(
            entries,
            func((k, v) : (Text, Json)) : (Text, Json) = (k, transform(v, replacer, k)),
          )
        );
      };
      case (#array(items)) {
        #array(
          Array.map<Json, Json>(
            items,
            func(item : Json) : Json = transform(item, replacer, key),
          )
        );
      };
      case _ { replaced };
    };
  };
  public func filterByKeys(json : Json, keys : [Text]) : Json {
    switch (json) {
      case (#object_(entries)) {
        #object_(
          Array.filter<(Text, Json)>(
            entries,
            func((k, _) : (Text, Json)) : Bool {
              for (allowedKey in keys.vals()) {
                if (k == allowedKey) return true;
              };
              false;
            },
          )
        );
      };
      case (#array(items)) {
        #array(
          Array.map<Json, Json>(
            items,
            func(item : Json) : Json = filterByKeys(item, keys),
          )
        );
      };
      case _ { json };
    };
  };

  public func charAt(i : Nat, t : Text) : Char {
    let arr = Text.toArray(t);
    arr[i];
  };
  func to4DigitHex(n : Nat32) : Text {
    let hex_chars = "0123456789abcdef";
    var s = "";
    var i = n;
    var counter : Nat = 0;

    while (counter < 4) {
      // Get the last 4 bits to find the hex character index.
      let index = Nat32.toNat(i & 0xF);
      // Prepend the character to build the string in the correct order.
      s := Text.fromChar(Text.toArray(hex_chars)[index]) # s;
      // Shift bits for the next character.
      i >>= 4;
      // Increment the counter.
      counter += 1;
    };
    return s;
  };
  // A helper function to correctly escape a string for JSON.
  public func escape(s : Text) : Text {
    let buf = Buffer.Buffer<Text>(s.size()); // Pre-allocate buffer for performance.
    for (c in s.chars()) {
      switch (c) {
        case ('\"') { buf.add("\\\"") };
        case ('\\') { buf.add("\\\\") };
        case ('\n') { buf.add("\\n") };
        case ('\r') { buf.add("\\r") };
        case ('\t') { buf.add("\\t") };
        // Note: Motoko Char doesn't have literals for \b and \f,
        // so we handle them in the default case via their code points.
        case _ {
          let code = Char.toNat32(c);
          if (code == 0x8) {
            // Backspace
            buf.add("\\b");
          } else if (code == 0xC) {
            // Form feed
            buf.add("\\f");
          } else if (code < 32) {
            // Other control characters (U+0000 to U+001F)
            buf.add("\\u" # to4DigitHex(code));
          } else {
            // A regular, non-special character.
            buf.add(Text.fromChar(c));
          };
        };
      };
    };
    return Buffer.foldLeft<Text, Text>(buf, "", func(acc, part) { acc # part });
  };
  public func toText(json : Json) : Text {
    switch (json) {
      case (#object_(entries)) {
        let fields = entries.vals();
        var result = "{";
        var first = true;
        for ((key, value) in fields) {
          if (not first) { result #= "," };
          result #= "\"" # key # "\":" # toText(value);
          first := false;
        };
        result # "}";
      };
      case (#array(items)) {
        let values = items.vals();
        var result = "[";
        var first = true;
        for (item in values) {
          if (not first) { result #= "," };
          result #= toText(item);
          first := false;
        };
        result # "]";
      };
      case (#string(text)) { "\"" # escape(text) # "\"" };
      case (#number(#int(n))) { Int.toText(n) };
      case (#number(#float(n))) { Float.format(#exact, n) };
      case (#bool(b)) { Bool.toText(b) };
      case (#null_) { "null" };
    };
  };
  func charToInt(c : Char) : Int {
    Int32.toInt(Int32.fromNat32(Char.toNat32(c) - 48));
  };

  public func textToFloat(text : Text) : ?Float {
    var integer : Int = 0;
    var fraction : Float = 0;
    var isNegative = false;
    var position : Nat = 0;
    let chars = text.chars();

    if (Text.size(text) == 0) {
      return null;
    };
    let firstchar = Text.toArray(text)[0];

    if (firstchar == '-' and text.size() == 1) {
      return null;
    };
    if (firstchar == 'e' or firstchar == 'E') {
      return null;
    };

    switch (chars.next()) {
      case (?'-') {
        isNegative := true;
        position += 1;
      };
      case (?'+') {
        position += 1;
      };
      case (?'.') {
        position += 1;
        switch (chars.next()) {
          case (?d) if (Char.isDigit(d)) {
            fraction := 0.1 * Float.fromInt(charToInt(d));
            position += 1;
          };
          case (_) { return null };
        };
      };
      case (?d) if (Char.isDigit(d)) {
        integer := charToInt(d);
        position += 1;
      };
      case (_) { return null };
    };

    var hasDigits = position > 0;
    label integer loop {
      switch (chars.next()) {
        case (?d) {
          if (Char.isDigit(d)) {
            integer := integer * 10 + charToInt(d);
            position += 1;
            hasDigits := true;
          } else if (d == '.') {
            position += 1;
            break integer;
          } else if (d == 'e' or d == 'E') {
            position += 1;
            if (not hasDigits) {
              return null;
            };

            var expResult = parseExponent(chars);
            switch (expResult) {
              case (null) {
                return null;
              };
              case (?(expValue, _)) {
                // Calculate final value with exponent
                let base = Float.fromInt(if (isNegative) -integer else integer) +
                (if (isNegative) -fraction else fraction);
                let multiplier = Float.pow(10, Float.fromInt(expValue));
                return ?(base * multiplier);
              };
            };
          } else {
            return null;
          };
        };
        case (null) {
          if (not hasDigits) {
            return null;
          };
          return ?(Float.fromInt(if (isNegative) -integer else integer));
        };
      };
    };

    var fractionMultiplier : Float = 0.1;
    var hasFractionDigits = false;

    label fraction loop {
      switch (chars.next()) {
        case (?d) {
          if (Char.isDigit(d)) {
            fraction += fractionMultiplier * Float.fromInt(charToInt(d));
            fractionMultiplier *= 0.1;
            position += 1;
            hasFractionDigits := true;
          } else if (d == 'e' or d == 'E') {
            position += 1;

            if (not (hasDigits or hasFractionDigits)) {
              return null;
            };

            // Handle exponent part
            var expResult = parseExponent(chars);
            switch (expResult) {
              case (null) {
                return null; // Invalid exponent format
              };
              case (?(expValue, _)) {
                // Calculate final value with exponent
                let base = Float.fromInt(if (isNegative) -integer else integer) +
                (if (isNegative) -fraction else fraction);
                let multiplier = Float.pow(10, Float.fromInt(expValue));
                return ?(base * multiplier);
              };
            };
          } else {
            return null;
          };
        };
        case (null) {
          // End of input - return complete number
          let result = Float.fromInt(if (isNegative) -integer else integer) +
          (if (isNegative) -fraction else fraction);
          return ?result;
        };
      };
    };

    return null;
  };

  func parseExponent(chars : Iter.Iter<Char>) : ?(Int, Nat) {
    var exponent : Int = 0;
    var expIsNegative = false;
    var position = 0;
    var hasDigits = false;

    // Parse optional sign or first digit
    switch (chars.next()) {
      case (?d) {
        if (d == '-') {
          expIsNegative := true;
          position += 1;
        } else if (d == '+') {
          position += 1;
        } else if (Char.isDigit(d)) {
          exponent := charToInt(d);
          position += 1;
          hasDigits := true;
        } else {
          return null;
        };
      };
      case (null) { return null };
    };

    label exponent loop {
      switch (chars.next()) {
        case (?d) {
          if (Char.isDigit(d)) {
            exponent := exponent * 10 + charToInt(d);
            position += 1;
            hasDigits := true;
          } else {
            return null;
          };
        };
        case (null) {
          if (not hasDigits) {
            return null;
          };
          return ?(if (expIsNegative) -exponent else exponent, position);
        };
      };
    };

    return null;
  };

  public func texttofloat(t : Text) : async ?Float {
    textToFloat(t);
  };
  public func parseInt(text : Text) : ?Int {
    var int : Int = 0;
    var isNegative = false;
    let chars = text.chars();

    switch (chars.next()) {
      case (?'-') {
        isNegative := true;
      };
      case (?d) if (Char.isDigit(d)) {
        int := Int32.toInt(Int32.fromNat32(Char.toNat32(d) - 48));
      };
      case (_) { return null };
    };

    label parsing loop {
      switch (chars.next()) {
        case (?d) {
          if (Char.isDigit(d)) {
            int := int * 10 + Int32.toInt(Int32.fromNat32(Char.toNat32(d) - 48));
          } else {
            return null;
          };
        };
        case (null) {
          return ?(if (isNegative) -int else int);
        };
      };
    };
    return null;
  };
  public func getTypeString(json : Json) : Text {
    switch (json) {
      case (#object_(_)) "object";
      case (#array(_)) "array";
      case (#string(_)) "string";
      case (#number(_)) "number";
      case (#bool(_)) "boolean";
      case (#null_) "null";
    };
  };
};
