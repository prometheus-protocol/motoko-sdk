// src/lib/Args.mo
import Types "Types";
import Decode "Decode";

module {
  // The public signature remains the same: it takes a params object and returns typed values.
  public type ArgDecoder<T> = (params : Types.JsonValue) -> ?T;

  public func by_name_0() : ArgDecoder<()> {
    return func(_) {
      return ?();
    };
  };

  public func by_name_1<A>(
    f1 : (Text, Decode.Decoder<A>)
  ) : ArgDecoder<A> {
    let (name1, decoder1) = f1;
    // The ArgDecoder just calls the primitive Decoder with the params and the name (path).
    return func(params) {
      return decoder1(params, name1);
    };
  };

  public func by_name_2<A, B>(
    f1 : (Text, Decode.Decoder<A>),
    f2 : (Text, Decode.Decoder<B>),
  ) : ArgDecoder<(A, B)> {
    let (name1, decoder1) = f1;
    let (name2, decoder2) = f2;
    return func(params) {
      // Call the decoders for each argument.
      let val1_opt = decoder1(params, name1);
      let val2_opt = decoder2(params, name2);

      // Only succeed if ALL decoders succeed.
      switch ((val1_opt, val2_opt)) {
        case (?(val1), ?(val2)) {
          return ?(val1, val2);
        };
        case _ { return null };
      };
    };
  };
};
