// src/mcp/Cleanup.mo

import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Timer "mo:base/Timer";
import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Types "Types";

module {
  // This is the public function the developer will call.
  public func startCleanupTimer<system>(ctx : Types.AppContext) : () {
    // If a timer is already running, cancel it before starting a new one.
    switch (ctx.cleanupTimerId) {
      case (?id) { Timer.cancelTimer(id) };
      case (null) {};
    };

    // Set a recurring timer for every 24 hours.
    let interval = #nanoseconds(24 * 60 * 60 * 1_000_000_000);

    // Define the cleanup function that will run on each timer tick.
    // It will remove any streams that have been inactive for more than 24 hours.
    func runCleanup() : async () {
      Debug.print("Running scheduled stream cleanup via Timer...");
      let STALE_STREAM_TIMEOUT : Int = 24 * 60 * 60 * 1_000_000_000; // 24 hours
      let now = Time.now();
      var keysToRemove : [Text] = [];

      for ((tokenKey, lastSeen) in Map.entries(ctx.activeStreams)) {
        if (now > lastSeen + STALE_STREAM_TIMEOUT) {
          keysToRemove := Array.append(keysToRemove, [tokenKey]);
        };
      };

      for (key in keysToRemove.vals()) {
        Map.delete(ctx.activeStreams, thash, key);
        Map.delete(ctx.messageQueues, thash, key);
      };
      Debug.print("Cleaned up " # Nat.toText(keysToRemove.size()) # " stale streams.");
    };

    // The timer will call our cleanup function, passing the context.
    ctx.cleanupTimerId := ?Timer.recurringTimer<system>(interval, runCleanup);
    Debug.print("Stream cleanup timer started.");
  };
};
