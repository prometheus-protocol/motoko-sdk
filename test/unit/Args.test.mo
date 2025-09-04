import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import { obj; str; int; nullable; arr } "mo:json";
import { test; suite; expect } "mo:test/async";

// The modules we are testing and their dependencies
import Args "../../src/server/Args";
import Decode "../../src/server/Decode";

// =================================================================================================
// HELPER FUNCTIONS FOR TESTING
// =================================================================================================

func showText(t : Text) : Text { t };
func equalText(a : Text, b : Text) : Bool { a == b };

// Helper for the two-argument test case
type PrincipalNatTuple = (Principal, Nat);
func showPrincipalNatTuple(t : PrincipalNatTuple) : Text {
  "(\"" # Principal.toText(t.0) # "\", " # Nat.toText(t.1) # ")";
};
func equalPrincipalNatTuple(a : PrincipalNatTuple, b : PrincipalNatTuple) : Bool {
  a.0 == b.0 and a.1 == b.1
};

// =================================================================================================
// TEST SUITE FOR ARGS DECODERS
// =================================================================================================

await suite(
  "Args",
  func() : async () {

    await test(
      "by_name_0 should succeed for empty or null params",
      func() : async () {
        let decoder = Args.by_name_0();
        expect.option<()>(decoder(nullable()), func(u) { "" }, func(a, b) { true }).isSome();
        expect.option<()>(decoder(obj([])), func(u) { "" }, func(a, b) { true }).isSome();
      },
    );

    await test(
      "by_name_1 should decode a single named argument",
      func() : async () {
        let decoder = Args.by_name_1<Text>(("name", Decode.text));
        let params = obj([("name", str("alice"))]);
        let result = decoder(params);

        expect.option<Text>(result, showText, equalText).equal(?("alice"));
      },
    );

    await test(
      "by_name_2 should decode two named arguments of different types",
      func() : async () {
        let decoder = Args.by_name_2<Principal, Nat>(
          ("to", Decode.principal),
          ("amount", Decode.nat),
        );
        let params = obj([
          ("to", str("aaaaa-aa")),
          ("amount", int(100_000_000)),
        ]);
        let result = decoder(params);
        let expected = (Principal.fromText("aaaaa-aa"), 100_000_000);

        expect.option<PrincipalNatTuple>(result, showPrincipalNatTuple, equalPrincipalNatTuple).equal(?expected);
      },
    );

    await test(
      "by_name_1 should return null if the field is missing",
      func() : async () {
        let decoder = Args.by_name_1<Text>(("name", Decode.text));
        let params = obj([("wrong_name", str("bob"))]);
        let result = decoder(params);

        expect.option<Text>(result, showText, equalText).isNull();
      },
    );

    await test(
      "by_name_2 should return null if any field is missing",
      func() : async () {
        let decoder = Args.by_name_2<Principal, Nat>(
          ("to", Decode.principal),
          ("amount", Decode.nat),
        );
        let params = obj([("to", str("aaaaa-aa"))]);
        let result = decoder(params);

        expect.option<PrincipalNatTuple>(result, showPrincipalNatTuple, equalPrincipalNatTuple).isNull();
      },
    );

    await test(
      "by_name_1 should return null if param is not a JSON object",
      func() : async () {
        let decoder = Args.by_name_1<Text>(("name", Decode.text));
        let params = arr([]);
        let result = decoder(params);

        expect.option<Text>(result, showText, equalText).isNull();
      },
    );
  },
);
