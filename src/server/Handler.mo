import Types "Types";
import Args "Args";
import Encode "Encode";
import Result "mo:base/Result";
import AuthTypes "../auth/Types";

module {
  // A structured error type for handlers to return.
  public type HandlerError = {
    code : Int;
    message : Text;
  };

  // Both Reps now use HandlerError.
  public type ReadRep = {
    call : (params : Types.JsonValue, auth : ?AuthTypes.AuthInfo) -> Result.Result<Types.JsonValue, HandlerError>;
  };
  public type MutationRep = {
    call : (params : Types.JsonValue, auth : ?AuthTypes.AuthInfo) -> async Result.Result<Types.JsonValue, HandlerError>;
  };

  public type Handler = {
    #mutation : MutationRep;
    #read : ReadRep;
  };

  // --- 0-Argument Handlers ---

  // UPDATED: update0 now returns a HandlerError on failure.
  public func update0<R>(
    handle : ((R) -> ()) -> async (),
    return_encoder : Encode.Encoder<R>,
  ) : Handler {
    let rep : MutationRep = {
      call = func(_ : Types.JsonValue, authInfo : ?AuthTypes.AuthInfo) : async Result.Result<Types.JsonValue, HandlerError> {
        var result_opt : ?R = null;
        let callback = func(result : R) { result_opt := ?result };
        await handle(callback);
        switch (result_opt) {
          case (?res) { return #ok(return_encoder(res)) };
          case (null) {
            return #err({
              code = -32603;
              message = "Handler did not call callback";
            });
          };
        };
      };
    };
    return #mutation(rep);
  };

  // UPDATED: query0 now returns a HandlerError on failure.
  public func query0<R>(
    handle : ((R) -> ()) -> (),
    return_encoder : Encode.Encoder<R>,
  ) : Handler {
    let rep : ReadRep = {
      call = func(params : Types.JsonValue, authInfo : ?AuthTypes.AuthInfo) : Result.Result<Types.JsonValue, HandlerError> {
        var result_opt : ?R = null;
        let callback = func(result : R) { result_opt := ?result };
        handle(callback);
        switch (result_opt) {
          case (?res) { return #ok(return_encoder(res)) };
          case (null) {
            return #err({
              code = -32603;
              message = "Handler did not call callback";
            });
          };
        };
      };
    };
    return #read(rep);
  };

  // --- 1-Argument Handlers ---

  // UPDATED: query1 now returns a HandlerError on failure.
  public func query1<A, R>(
    handle : ((A, (R) -> ()) -> ()),
    arg_decoder : Args.ArgDecoder<A>,
    return_encoder : Encode.Encoder<R>,
  ) : Handler {
    let rep : ReadRep = {
      call = func(params : Types.JsonValue, authInfo : ?AuthTypes.AuthInfo) : Result.Result<Types.JsonValue, HandlerError> {
        switch (arg_decoder(params)) {
          case (?arg1) {
            var result_opt : ?R = null;
            let callback = func(result : R) { result_opt := ?result };
            handle(arg1, callback);
            switch (result_opt) {
              case (?res) { return #ok(return_encoder(res)) };
              case (null) {
                return #err({
                  code = -32603;
                  message = "Handler did not call callback";
                });
              };
            };
          };
          case (null) {
            return #err({ code = -32602; message = "Invalid params" });
          };
        };
      };
    };
    return #read(rep);
  };

  // This function is already correct.
  public func update1<A, R>(
    handle : ((A, (Result.Result<R, HandlerError>) -> ()) -> async ()),
    arg_decoder : Args.ArgDecoder<A>,
    return_encoder : Encode.Encoder<R>,
  ) : Handler {
    let rep : MutationRep = {
      call = func(params : Types.JsonValue, authInfo : ?AuthTypes.AuthInfo) : async Result.Result<Types.JsonValue, HandlerError> {
        switch (arg_decoder(params)) {
          case (?arg1) {
            var result_opt : ?Result.Result<R, HandlerError> = null;
            let callback = func(result : Result.Result<R, HandlerError>) {
              result_opt := ?result;
            };
            await handle(arg1, callback);
            switch (result_opt) {
              case (?#ok(res)) { return #ok(return_encoder(res)) };
              case (?#err(handler_err)) { return #err(handler_err) };
              case (null) {
                return #err({
                  code = -32603;
                  message = "Handler did not call callback";
                });
              };
            };
          };
          case (null) {
            return #err({ code = -32602; message = "Invalid params" });
          };
        };
      };
    };
    return #mutation(rep);
  };
};
