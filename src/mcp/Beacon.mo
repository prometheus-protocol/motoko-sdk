// src/beacon/Beacon.mo

import Map "mo:map/Map";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Error "mo:base/Error";

/**
 * This module contains the core implementation logic for the Prometheus Usage Beacon.
 * It is imported and used by the main Mcp.mo module.
 */
module {

  // --- Beacon Payload Types ---
  // These types define the data structure sent to the UsageTracker canister.

  public type CallerActivity = {
    caller : Principal;
    tool_id : Text;
    call_count : Nat;
  };

  public type UsageStats = {
    start_timestamp_ns : Time.Time;
    end_timestamp_ns : Time.Time;
    activity : [CallerActivity];
  };

  // --- Beacon State & Configuration ---

  /**
   * A dedicated context for the usage beacon.
   * This object holds all the state needed for the beacon to operate.
   * An instance of this should be created as a stable variable in the developer's actor.
   */
  public type BeaconContext = {
    // The core data structure for accumulating usage data between beacon sends.
    var usage_data : Map.Map<Principal, Map.Map<Text, Nat>>;
    // The active timer ID.
    var timer_id : ?Timer.TimerId;
    // The timestamp of the last successful beacon transmission.
    var last_send_timestamp_ns : Time.Time;
    // The Principal of the central UsageTracker canister.
    tracker_canister_id : Principal;
    // The interval in seconds for sending usage reports.
    reporting_interval_seconds : Nat;
  };

  /**
   * The init function creates a fresh, empty instance of the beacon's context.
   * This should be used to initialize the stable variable in your main actor.
   */
  public func init(trackerCanisterId : Principal, reportingIntervalSeconds : ?Nat) : BeaconContext {
    {
      var usage_data = Map.new<Principal, Map.Map<Text, Nat>>();
      var timer_id = null;
      var last_send_timestamp_ns = 0;
      tracker_canister_id = trackerCanisterId;
      reporting_interval_seconds = Option.get(reportingIntervalSeconds, 1 * 60 * 60); // Default to 1 hours if not provided
    };
  };

  // ==================================================================================================
  // PRIVATE HELPERS & TYPES
  // ==================================================================================================

  // Actor type for the UsageTracker to enable typed inter-canister calls.
  private type UsageTrackerActor = actor {
    log_call : (stats : UsageStats) -> async Result.Result<(), Text>;
  };

  // The function executed by the timer to send the beacon signal.
  private func send_beacon(tracker_id : Principal, context : BeaconContext) : async () {
    let data_to_send = context.usage_data;
    Debug.print("Sending usage beacon with " # debug_show (Map.size(data_to_send)) # " active users...");
    context.usage_data := Map.new<Principal, Map.Map<Text, Nat>>();

    let start_time = context.last_send_timestamp_ns;
    let end_time = Time.now();
    context.last_send_timestamp_ns := end_time;

    if (Map.empty(data_to_send)) { return };

    var activity_array : [CallerActivity] = [];
    for ((user, tool_map) in Map.entries(data_to_send)) {
      for ((tool, count) in Map.entries(tool_map)) {
        activity_array := Array.append(activity_array, [{ caller = user; tool_id = tool; call_count = count }]);
      };
    };

    let stats : UsageStats = {
      start_timestamp_ns = start_time;
      end_timestamp_ns = end_time;
      activity = activity_array;
    };

    try {
      let tracker : UsageTrackerActor = actor (Principal.toText(tracker_id));
      ignore await tracker.log_call(stats);
    } catch (e) {
      Debug.print("MCP Beacon Error: Failed to send usage stats. Error: " # Error.message(e));
    };
  };

  // ==================================================================================================
  // PUBLIC API
  // ==================================================================================================

  /**
   * Initializes the beacon timer based on the provided configuration.
   * This function is called once by `Mcp.createServer`.
   */
  public func startTimer<system>(ctx : BeaconContext) {
    // Cancel any pre-existing timer from a previous upgrade.
    switch (ctx.timer_id) {
      case (?id) { Timer.cancelTimer(id) };
      case (null) {};
    };
    ctx.last_send_timestamp_ns := Time.now();
    let tracker_id = ctx.tracker_canister_id;
    // The timer closure captures the necessary config and state.
    ctx.timer_id := ?Timer.recurringTimer<system>(
      #seconds(ctx.reporting_interval_seconds),
      func() : async () { ignore send_beacon(tracker_id, ctx) },
    );
    Debug.print("Beacon submission timer started.");
  };

  /**
   * Tracks a single tool invocation by mutating the provided context.
   * This function is called from the `tools/call` handler.
   */
  public func track_call(context : BeaconContext, caller : Principal, tool_id : Text) {
    Debug.print("Beacon: Tracking call by " # Principal.toText(caller) # " to tool " # tool_id);
    let user_activity = Option.get(
      Map.get(context.usage_data, Map.phash, caller),
      Map.new<Text, Nat>(),
    );
    let current_count = Option.get(Map.get(user_activity, Map.thash, tool_id), 0);
    Map.set(user_activity, Map.thash, tool_id, current_count + 1);
    Map.set(context.usage_data, Map.phash, caller, user_activity);
  };
};
