import Json "../json";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Types "Types"; // Our MCP Types
import ServerEncode "../server/Encode"

module {
  public func jsonValue(v : Json.Json) : Types.JsonValue {
    return v;
  };

  // Encodes the `serverInfo` object.
  func serverInfo(info : Types.ServerInfo) : Types.JsonValue {
    return Json.obj([
      ("name", Json.str(info.name)),
      ("title", Json.str(info.title)),
      ("version", Json.str(info.version)),
    ]);
  };

  public func serverCapabilities(caps : Types.ServerCapabilities) : Types.JsonValue {
    var topLevelFields : [(Text, Types.JsonValue)] = [];

    // Handle the 'resources' capability
    switch (caps.resources) {
      case (?resCaps) {
        // The capability exists, now build its inner JSON object.
        var innerFields : [(Text, Types.JsonValue)] = [];

        // Only add "subscribe" if it's explicitly true.
        if (resCaps.subscribe == ?true) {
          innerFields := Array.append(innerFields, [("subscribe", Json.bool(true))]);
        };

        // Only add "listChanged" if it's explicitly true.
        if (resCaps.listChanged == ?true) {
          innerFields := Array.append(innerFields, [("listChanged", Json.bool(true))]);
        };

        let resourcesObj = Json.obj(innerFields);
        topLevelFields := Array.append(topLevelFields, [("resources", resourcesObj)]);
      };
      case (null) { /* Do nothing if the capability is not supported */ };
    };

    // Handle the 'tools' capability
    switch (caps.tools) {
      case (?toolCaps) {
        var innerFields : [(Text, Types.JsonValue)] = [];
        if (toolCaps.listChanged == ?true) {
          innerFields := Array.append(innerFields, [("listChanged", Json.bool(true))]);
        };
        let toolsObj = Json.obj(innerFields);
        topLevelFields := Array.append(topLevelFields, [("tools", toolsObj)]);
      };
      case (null) {};
    };

    // We can add similar logic for `logging` and `prompts` here if needed.

    return Json.obj(topLevelFields);
  };

  // The main encoder for the entire `initialize` result object.
  public func initializeResult(res : Types.InitializeResult) : Types.JsonValue {
    var fields : [(Text, Types.JsonValue)] = [
      ("protocolVersion", Json.str(res.protocolVersion)),
      ("capabilities", serverCapabilities(res.capabilities)),
      ("serverInfo", serverInfo(res.serverInfo)),
    ];
    // Handle optional instructions field
    switch (res.instructions) {
      case (?text) {
        fields := Array.append(fields, [("instructions", Json.str(text))]);
      };
      case (null) {};
    };
    return Json.obj(fields);
  };

  public func resource(res : Types.Resource) : Types.JsonValue {
    var fields = [
      ("uri", Json.str(res.uri)),
      ("name", Json.str(res.name)),
    ];

    switch (res.title) {
      case (?value) {
        fields := Array.append(fields, [("title", Json.str(value))]);
      };
      case (null) {};
    };
    switch (res.description) {
      case (?value) {
        fields := Array.append(fields, [("description", Json.str(value))]);
      };
      case (null) {};
    };
    switch (res.mimeType) {
      case (?value) {
        fields := Array.append(fields, [("mimeType", Json.str(value))]);
      };
      case (null) {};
    };

    return Json.obj(fields);
  };

  // Encodes an array of Resource records into a JSON array.
  public func resourceList(list : [Types.Resource]) : Types.JsonValue {
    return ServerEncode.array<Types.Resource>(list, resource);
  };

  // The main encoder for the `tools/list` result object.
  public func listResourcesResult(res : Types.ListResourcesResult) : Types.JsonValue {
    var fields = [
      ("resources", resourceList(res.resources)),
    ];
    // Handle optional nextCursor
    switch (res.nextCursor) {
      case (?cursor) {
        fields := Array.append(fields, [("nextCursor", Json.str(cursor))]);
      };
      case (null) {};
    };
    return Json.obj(fields);
  };

  // Encodes a single ResourceContent block.
  public func resourceContent(content : Types.ResourceContent) : Types.JsonValue {
    var fields = [
      ("uri", Json.str(content.uri)),
      ("name", Json.str(content.name)),
    ];

    switch (content.title) {
      case (?value) {
        fields := Array.append(fields, [("title", Json.str(value))]);
      };
      case (null) {};
    };
    switch (content.mimeType) {
      case (?value) {
        fields := Array.append(fields, [("mimeType", Json.str(value))]);
      };
      case (null) {};
    };
    switch (content.text) {
      case (?value) {
        fields := Array.append(fields, [("text", Json.str(value))]);
      };
      case (null) {};
    };
    // We'll skip blob for now.

    return Json.obj(fields);
  };

  // Encodes the full result for `resources/read`.
  public func readResourceResult(res : Types.ReadResourceResult) : Types.JsonValue {
    return Json.obj([("contents", ServerEncode.array<Types.ResourceContent>(res.contents, resourceContent))]);
  };

  // Encodes a single Tool record into a JSON object.
  public func tool(t : Types.Tool) : Types.JsonValue {
    var fields = [
      ("name", Json.str(t.name)),
      // The inputSchema is already a JsonValue, so we add it directly.
      ("inputSchema", t.inputSchema),
    ];
    switch (t.title) {
      case (?value) {
        fields := Array.append(fields, [("title", Json.str(value))]);
      };
      case (null) {};
    };
    switch (t.description) {
      case (?value) {
        fields := Array.append(fields, [("description", Json.str(value))]);
      };
      case (null) {};
    };
    switch (t.outputSchema) {
      case (?schema) {
        fields := Array.append(fields, [("outputSchema", schema)]);
      };
      case (null) {};
    };

    return Json.obj(fields);
  };

  // Encodes an array of Tool records into a JSON array.
  public func toolList(list : [Types.Tool]) : Types.JsonValue {
    return ServerEncode.array<Types.Tool>(list, tool);
  };

  // The main encoder for the `tools/list` result object.
  public func listToolsResult(res : Types.ListToolsResult) : Types.JsonValue {
    var fields = [
      ("tools", toolList(res.tools)),
    ];
    // Handle optional nextCursor
    switch (res.nextCursor) {
      case (?cursor) {
        fields := Array.append(fields, [("nextCursor", Json.str(cursor))]);
      };
      case (null) {};
    };
    return Json.obj(fields);
  };

  // Encodes a single ToolResultContent block.
  public func toolResultContent(content : Types.ToolResultContent) : Types.JsonValue {
    switch (content) {
      case (#text(data)) {
        let content = Json.obj([
          ("type", Json.str("text")),
          ("text", Json.str(data.text)),
        ]);

        return content;
      };
      // We can add other cases like #image here later.
    };
  };

  // Encodes the full result for `tools/call`.
  public func callToolResult(res : Types.CallToolResult) : Types.JsonValue {
    var fields = [
      ("content", ServerEncode.array<Types.ToolResultContent>(res.content, toolResultContent)),
      ("isError", Json.bool(res.isError)),
    ];

    switch (res.structuredContent) {
      case (?jsonVal) {
        fields := Array.append(fields, [("structuredContent", jsonVal)]);
      };
      case (null) {};
    };

    let result_obj = Json.obj(fields);
    return result_obj;
  };

};
