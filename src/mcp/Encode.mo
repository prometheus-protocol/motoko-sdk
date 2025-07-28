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
    var top_level_fields : [(Text, Types.JsonValue)] = [];

    // Handle the 'resources' capability
    switch (caps.resources) {
      case (?res_caps) {
        // The capability exists, now build its inner JSON object.
        var inner_fields : [(Text, Types.JsonValue)] = [];

        // Only add "subscribe" if it's explicitly true.
        if (res_caps.subscribe == ?true) {
          inner_fields := Array.append(inner_fields, [("subscribe", Json.bool(true))]);
        };

        // Only add "listChanged" if it's explicitly true.
        if (res_caps.listChanged == ?true) {
          inner_fields := Array.append(inner_fields, [("listChanged", Json.bool(true))]);
        };

        let resources_obj = Json.obj(inner_fields);
        top_level_fields := Array.append(top_level_fields, [("resources", resources_obj)]);
      };
      case (null) { /* Do nothing if the capability is not supported */ };
    };

    // Handle the 'tools' capability
    switch (caps.tools) {
      case (?tool_caps) {
        var inner_fields : [(Text, Types.JsonValue)] = [];
        if (tool_caps.listChanged == ?true) {
          inner_fields := Array.append(inner_fields, [("listChanged", Json.bool(true))]);
        };
        let tools_obj = Json.obj(inner_fields);
        top_level_fields := Array.append(top_level_fields, [("tools", tools_obj)]);
      };
      case (null) {};
    };

    // We can add similar logic for `logging` and `prompts` here if needed.

    return Json.obj(top_level_fields);
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

        Debug.print("Tool result content (text): " # debug_show (content));
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
      case (?json_val) {
        fields := Array.append(fields, [("structuredContent", json_val)]);
      };
      case (null) {};
    };

    let result_obj = Json.obj(fields);
    Debug.print("Call tool result: " # Json.stringify(result_obj, null));
    return result_obj;
  };

};
