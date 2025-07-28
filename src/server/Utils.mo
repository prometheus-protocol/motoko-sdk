import Array "mo:base/Array";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";

module {
  // Helper function to convert a Nat64 into an array of 8 bytes.
  // This is the "hack" needed due to the lack of a direct Nat64.toNat8 function.
  public func nat64ToBytes(n : Nat64) : [Nat8] {
    return Array.tabulate<Nat8>(
      8,
      func(i) {
        // 1. Isolate the byte we want as a Nat64.
        let byte_as_nat64 = (n >> (Nat64.fromNat(i) * 8)) & 0xFF;
        // 2. Convert the Nat64 to a general-purpose Nat. This is a safe operation
        //    because we know the value is between 0 and 255.
        let byte_as_nat = Nat64.toNat(byte_as_nat64);
        // 3. Convert the Nat to a Nat8. This is also safe.
        return Nat8.fromNat(byte_as_nat);
      },
    );
  };
};
