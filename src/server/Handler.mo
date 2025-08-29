import Types "Types";
import Args "Args";
import Encode "Encode";
import Result "mo:base/Result";
import AuthTypes "../auth/Types";
import Json "mo:json";

module {
  // The HandlerError type now includes the optional `data` field
  // to be fully compliant with the JSON-RPC spec and our usage.
  public type HandlerError = {
    code : Int;
    message : Text;
    data : ?Json.Json;
  };

  // Reps are correct, they already accept authInfo.
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

  public func update0<R>(
    // MODIFIED: Handler now receives authInfo and the callback accepts a Result.
    handle : ((?AuthTypes.AuthInfo, (Result.Result<R, HandlerError>) -> ()) -> async ()),
    return_encoder : Encode.Encoder<R>,
  ) : Handler {
    let rep : MutationRep = {
      call = func(_ : Types.JsonValue, authInfo : ?AuthTypes.AuthInfo) : async Result.Result<Types.JsonValue, HandlerError> {
        var result_opt : ?Result.Result<R, HandlerError> = null;
        let callback = func(result : Result.Result<R, HandlerError>) {
          result_opt := ?result;
        };
        // MODIFIED: Pass authInfo to the handler.
        await handle(authInfo, callback);
        switch (result_opt) {
          case (?#ok(res)) { return #ok(return_encoder(res)) };
          case (?#err(err)) { return #err(err) };
          case (null) {
            return #err({
              code = -32603;
              message = "Handler did not call callback";
              data = null;
            });
          };
        };
      };
    };
    return #mutation(rep);
  };

  public func query0<R>(
    // MODIFIED: Handler now receives authInfo and the callback accepts a Result.
    handle : ((?AuthTypes.AuthInfo, (Result.Result<R, HandlerError>) -> ()) -> ()),
    return_encoder : Encode.Encoder<R>,
  ) : Handler {
    let rep : ReadRep = {
      call = func(_ : Types.JsonValue, authInfo : ?AuthTypes.AuthInfo) : Result.Result<Types.JsonValue, HandlerError> {
        var result_opt : ?Result.Result<R, HandlerError> = null;
        let callback = func(result : Result.Result<R, HandlerError>) {
          result_opt := ?result;
        };
        // MODIFIED: Pass authInfo to the handler.
        handle(authInfo, callback);
        switch (result_opt) {
          case (?#ok(res)) { return #ok(return_encoder(res)) };
          case (?#err(err)) { return #err(err) };
          case (null) {
            return #err({
              code = -32603;
              message = "Handler did not call callback";
              data = null;
            });
          };
        };
      };
    };
    return #read(rep);
  };

  // --- 1-Argument Handlers ---

  public func query1<A, R>(
    // MODIFIED: Handler now receives authInfo and the callback accepts a Result.
    handle : ((A, ?AuthTypes.AuthInfo, (Result.Result<R, HandlerError>) -> ()) -> ()),
    arg_decoder : Args.ArgDecoder<A>,
    return_encoder : Encode.Encoder<R>,
  ) : Handler {
    let rep : ReadRep = {
      call = func(params : Types.JsonValue, authInfo : ?AuthTypes.AuthInfo) : Result.Result<Types.JsonValue, HandlerError> {
        switch (arg_decoder(params)) {
          case (?arg1) {
            var result_opt : ?Result.Result<R, HandlerError> = null;
            let callback = func(result : Result.Result<R, HandlerError>) {
              result_opt := ?result;
            };
            // MODIFIED: Pass authInfo to the handler.
            handle(arg1, authInfo, callback);
            switch (result_opt) {
              case (?#ok(res)) { return #ok(return_encoder(res)) };
              case (?#err(err)) { return #err(err) };
              case (null) {
                return #err({
                  code = -32603;
                  message = "Handler did not call callback";
                  data = null;
                });
              };
            };
          };
          case (null) {
            return #err({
              code = -32602;
              message = "Invalid params";
              data = null;
            });
          };
        };
      };
    };
    return #read(rep);
  };

  public func update1<A, R>(
    // This function was already correct from our previous fix.
    handle : ((A, ?AuthTypes.AuthInfo, (Result.Result<R, HandlerError>) -> ()) -> async ()),
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
            await handle(arg1, authInfo, callback);
            switch (result_opt) {
              case (?#ok(res)) { return #ok(return_encoder(res)) };
              case (?#err(handler_err)) { return #err(handler_err) };
              case (null) {
                return #err({
                  code = -32603;
                  message = "Handler did not call callback";
                  data = null;
                });
              };
            };
          };
          case (null) {
            return #err({
              code = -32602;
              message = "Invalid params";
              data = null;
            });
          };
        };
      };
    };
    return #mutation(rep);
  };
};
