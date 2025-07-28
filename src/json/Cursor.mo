import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Array "mo:base/Array";

module {
  public class Cursor(t : Text) {
    public let string = Text.toArray(t);
    private var pos : Nat = 0;

    public func getPos() : Nat {
      pos;
    };

    public func current() : Char {
      if (pos < string.size()) {
        string[pos];
      } else {
        Debug.trap("Attempted to access character out of bounds at position " # Nat.toText(pos));
      };
    };

    public func hasNext() : Bool {
      pos < string.size();
    };

    public func inc() {
      if (pos < string.size()) {
        pos += 1;
      };
    };

    public func advance(n : Nat) {
      if (pos + n <= string.size()) {
        pos += n;
      } else {
        pos := string.size();
      };
    };

    public func substring(text : Text, start : Nat, end : Nat) : Text {
      let chars = Text.toArray(text);
      assert (start <= end);
      assert (end <= chars.size());
      if (start == end) return "";
      Text.fromIter(Array.slice<Char>(chars, start, end));
    };
  };
};
