// src/mcp/ApiKey.mo

import Types "Types";
import Base16 "mo:base16/Base16";
import Sha256 "mo:sha2/Sha256";
import Random "mo:base/Random";
import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Map "mo:map/Map";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";

module {

  // --- Private Helper: Safely get the ApiKeyState ---
  // This helper is unchanged and remains good practice.
  private func _getApiState(ctx : Types.AuthContext) : Types.ApiKeyState {
    switch (ctx.apiKey) {
      case (?state) { return state };
      case (null) { Debug.trap("Error: API Key module is not enabled.") };
    };
  };

  // =================================================================================================
  // NEW: SELF-SERVICE FUNCTIONS (For any authenticated user)
  // =================================================================================================

  // --- CREATE MY API KEY (Update Method) ---
  // Allows any caller to create an API key for their own Principal.
  public func create_my_api_key(
    ctx : Types.AuthContext,
    caller : Principal,
    name : Text,
    scopes : [Text],
  ) : async Text {
    let apiState = _getApiState(ctx);

    // No owner check is needed. Any user can create a key for themselves.

    let raw_key_blob : Blob = await Random.blob();
    let raw_key_text = Base16.encode(raw_key_blob);

    let hashed_key_blob = Sha256.fromBlob(#sha256, raw_key_blob);
    let hashed_key_text : Types.HashedApiKey = Base16.encode(hashed_key_blob);

    let key_info : Types.ApiKeyInfo = {
      // CRITICAL: The principal is always the caller, preventing impersonation.
      principal = caller;
      scopes = scopes;
      name = name;
      created = Time.now();
    };

    Map.set(apiState.apiKeys, Map.thash, hashed_key_text, key_info);

    return raw_key_text;
  };

  // --- LIST MY API KEYS (Query Method) ---
  // Allows any caller to list the metadata for keys they own.
  public func list_my_api_keys(ctx : Types.AuthContext, caller : Principal) : [Types.ApiKeyMetadata] {
    let apiState = _getApiState(ctx);

    var metadata : [Types.ApiKeyMetadata] = [];
    for ((hash, info) in Map.entries(apiState.apiKeys)) {
      // CRITICAL: Only return keys where the principal matches the caller.
      if (info.principal == caller) {
        metadata := Array.append(metadata, [{ hashed_key = hash; info = info }]);
      };
    };
    return metadata;
  };

  // --- REVOKE MY API KEY (Update Method) ---
  // Allows any caller to revoke an API key that they own.
  public func revoke_my_api_key(ctx : Types.AuthContext, caller : Principal, hashed_key : Types.HashedApiKey) {
    let apiState = _getApiState(ctx);

    // 1. First, get the key's info to check for ownership.
    switch (Map.get(apiState.apiKeys, Map.thash, hashed_key)) {
      case (?key_info) {
        // 2. CRITICAL: Verify the caller owns this specific key before revoking.
        if (key_info.principal != caller) {
          Debug.trap("Unauthorized: You can only revoke your own API keys.");
        };

        // 3. If ownership is confirmed, remove the key.
        ignore Map.remove(apiState.apiKeys, Map.thash, hashed_key);
      };
      case (null) {
        // Key doesn't exist, do nothing.
        Debug.print("Warning: Attempted to revoke a non-existent API key: " # hashed_key);
      };
    };
  };
};
