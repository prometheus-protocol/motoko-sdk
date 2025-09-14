// src/mcp/AuthCleanup.mo

import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Timer "mo:base/Timer";
import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Types "Types"; // Ensure this path is correct for your project structure

module {
  /// Starts a recurring timer that periodically cleans up expired authentication state.
  public func startCleanupTimer<system>(ctx : Types.AuthContext) : () {
    // If a timer is already running, cancel it before starting a new one.
    // This logic remains the same and is correct.
    switch (ctx.cleanupTimerId) {
      case (?id) { Timer.cancelTimer(id) };
      case (null) {};
    };

    // Set a recurring timer for every 1 hour.
    let interval = #nanoseconds(1 * 60 * 60 * 1_000_000_000);

    // --- REFACTORED: The cleanup function is now module-aware ---
    func runCleanup() : async () {
      Debug.print("Running scheduled auth cleanup...");
      let now = Time.now();

      // --- 1. Clean up the OIDC Session Cache (if enabled) ---
      switch (ctx.oidc) {
        case (?oidcState) {
          // The OIDC module is configured, so we can safely access its sessionCache.
          var keysToRemove : [Text] = [];

          for ((key, session) in Map.entries(oidcState.sessionCache)) {
            if (now > session.expiresAt) {
              keysToRemove := Array.append(keysToRemove, [key]);
            };
          };

          if (keysToRemove.size() > 0) {
            for (key in keysToRemove.vals()) {
              Map.delete(oidcState.sessionCache, thash, key);
            };
            Debug.print("Cleaned up " # Nat.toText(keysToRemove.size()) # " stale OIDC sessions.");
          };
        };
        case (null) {
          // OIDC is not enabled, so there's nothing to clean. We do nothing.
        };
      };

      // --- 2. Clean up the API Key Store (Future-proofing) ---
      // Although API keys don't currently expire in our model, this is where
      // you would add the logic if they did. For now, it's a placeholder.
      switch (ctx.apiKey) {
        case (?apiKeyState) {
          // Example: if (keyInfo.expiresAt < now) { ... }
        };
        case (null) {};
      };
    };

    // The timer will call our new, smarter cleanup function.
    ctx.cleanupTimerId := ?Timer.recurringTimer<system>(interval, runCleanup);
    Debug.print("Auth cleanup timer started.");
  };
};
