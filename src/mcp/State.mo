// src/mcp/State.mo

import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Time "mo:base/Time";
import Types "Types"; // Import our new types module

module {
  // The init function creates a fresh instance of our application's state.
  public func init(initialResources : [(Text, Text)]) : Types.AppContext {
    {
      activeStreams = Map.new<Text, Time.Time>();
      messageQueues = Map.new<Text, [Text]>();
      var cleanupTimerId = null;
      // The resource contents are initialized with data provided at creation time.
      resourceContents = Map.fromIter<Text, Text>(initialResources.vals(), thash);
    };
  };
};
