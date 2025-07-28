import Json "../json";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Types "Types"; // Our MCP Types

module {
  // Decodes the `clientInfo` object.
  func clientInfo(json : Types.JsonValue) : ?Types.ClientInfo {
    do ? {
      let name = Result.toOption(Json.getAsText(json, "name"))!;
      let title = Result.toOption(Json.getAsText(json, "title"));
      let version = Result.toOption(Json.getAsText(json, "version"))!;

      return ?{ name; title; version };
    };
  };

  // Decodes the `capabilities` object from the client.
  func clientCapabilities(json : Types.JsonValue) : ?Types.ClientCapabilities {
    // For now, we just check for the presence of the keys.
    let roots = if (Json.get(json, "roots") != null) ?{} else null;
    let sampling = if (Json.get(json, "sampling") != null) ?{} else null;
    let elicitation = if (Json.get(json, "elicitation") != null) ?{} else null;
    return ?{ roots; sampling; elicitation };
  };

  // The main decoder for the entire `initialize` params object.
  public func initializeParams(json : Types.JsonValue) : ?Types.InitializeParams {
    Debug.print("--- Decoding initializeParams ---");
    Debug.print(debug_show json);
    let params = do ? {
      let protocolVersion = Result.toOption(Json.getAsText(json, "protocolVersion"))!;
      let capabilities_json = Json.get(json, "capabilities")!;
      let capabilities = clientCapabilities(capabilities_json)!;
      let clientInfo_json = Json.get(json, "clientInfo")!;
      let clientInfoValue = clientInfo(clientInfo_json)!;

      return ?{ protocolVersion; capabilities; clientInfo = clientInfoValue };
    };

    Debug.print("--- Decoded initializeParams successfully ---");
    Debug.print(debug_show params);
    return params;
  };

  // Decoder for the `resources/read` params.
  public func readResourceParams(json : Types.JsonValue) : ?Types.ReadResourceParams {
    switch (Result.toOption(Json.getAsText(json, "uri"))) {
      case (?u) { ?{ uri = u } };
      case (null) { return null }; // If 'uri' is missing or not a string, return null.
    };
  };

  // Decoder for the `tools/call` params.
  public func callToolParams(json : Types.JsonValue) : ?Types.CallToolParams {
    do ? {
      let name = Result.toOption(Json.getAsText(json, "name"))!;
      let arguments_json = Json.get(json, "arguments")!;

      return ?{ name; arguments = arguments_json };
    };
  };
};
