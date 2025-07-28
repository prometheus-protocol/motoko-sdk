import Json "../json";
import Map "mo:map/Map";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
// This file defines the core data structures for the MCP Lifecycle.
// Based on spec revision: 2025-06-18

module {
  public type JsonValue = Json.Json;

  // --- Client Information ---
  public type ClientInfo = {
    name : Text;
    title : ?Text;
    version : Text;
  };

  // A simple type for capability objects, which are currently empty.
  public type Empty = {};

  public type ClientCapabilities = {
    roots : ?Empty;
    sampling : ?Empty;
    elicitation : ?Empty;
  };

  // The `params` object for an `initialize` request.
  public type InitializeParams = {
    protocolVersion : Text;
    capabilities : ClientCapabilities;
    clientInfo : ClientInfo;
  };

  // --- Server Information ---
  public type ServerInfo = {
    name : Text;
    title : Text;
    version : Text;
  };

  public type ServerCapabilities = {
    logging : ?Empty;
    prompts : ?{ listChanged : ?Bool };
    resources : ?{ subscribe : ?Bool; listChanged : ?Bool };
    tools : ?{ listChanged : ?Bool };
  };

  // The `result` object for a successful `initialize` response.
  public type InitializeResult = {
    protocolVersion : Text;
    capabilities : ServerCapabilities;
    serverInfo : ServerInfo;
    instructions : ?Text;
  };

  // Represents a single resource exposed by the server.
  public type Resource = {
    uri : Text;
    name : Text;
    title : ?Text;
    description : ?Text;
    mimeType : ?Text;
    // We'll omit size and annotations for now for simplicity, but can add them later.
  };

  // The content block returned by resources/read.
  public type ResourceContent = {
    uri : Text;
    name : Text;
    title : ?Text;
    mimeType : ?Text;
    text : ?Text; // For text content
    blob : ?Blob; // For binary content
  };

  // The `params` object for a `resources/read` request.
  public type ReadResourceParams = {
    uri : Text;
  };

  // The `result` object for a successful `resources/read` response.
  public type ReadResourceResult = {
    contents : [ResourceContent];
  };

  // Represents a single tool the server can execute.
  public type Tool = {
    name : Text;
    title : ?Text;
    description : ?Text;
    inputSchema : JsonValue; // The schema is a JSON object itself.
    outputSchema : ?JsonValue;
    // We'll omit  annotations for now for simplicity.
  };

  // The `result` object for a successful `tools/list` response.
  public type ListToolsResult = {
    tools : [Tool];
    nextCursor : ?Text; // For pagination, which we'll ignore for now.
  };

  // The `params` object for a `tools/call` request.
  public type CallToolParams = {
    name : Text;
    arguments : JsonValue; // The arguments are an arbitrary JSON object.
  };

  // A content block for the tool's result. For now, we only support text.
  public type ToolResultContent = {
    #text : { text : Text };
    // We can add #image, #audio, etc. later.
  };

  // The `result` object for a successful `tools/call` response.
  public type CallToolResult = {
    content : [ToolResultContent];
    isError : Bool;
    structuredContent : ?JsonValue;
  };

  public type AppContext = {
    activeStreams : Map.Map<Text, Time.Time>;
    messageQueues : Map.Map<Text, [Text]>;
    var cleanupTimerId : ?Timer.TimerId;
    resourceContents : Map.Map<Text, Text>;
  };
};
