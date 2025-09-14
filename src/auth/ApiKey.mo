// src/mcp/ApiKey.mo

import Types "Types"; // Ensure this path is correct
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
  // This helper reduces boilerplate and ensures consistent error handling.
  private func _getApiState(ctx : Types.AuthContext) : Types.ApiKeyState {
    switch (ctx.apiKey) {
      case (?state) {
        // The module is enabled, return its state.
        return state;
      };
      case (null) {
        // The module is not configured. This is a fatal error for any API key operation.
        Debug.trap("Error: API Key module is not enabled for this canister.");
      };
    };
  };

  // --- CREATE API KEY (Update Method) ---
  // Generates a new key, stores its hash, and returns the raw key ONCE.
  public func create_api_key(
    ctx : Types.AuthContext,
    caller : Principal,
    name : Text,
    principal : Principal,
    scopes : [Text],
  ) : async Text {
    // 1. Get the specific state for the API key module. This will trap if not enabled.
    let apiState = _getApiState(ctx);

    // 2. Perform the owner check using the state from the module.
    if (caller != apiState.owner) {
      Debug.trap("Unauthorized: Only the owner can create API keys.");
    };

    // 3. Generate a secure, random 32-byte key.
    let raw_key_blob : Blob = await Random.blob();
    let raw_key_text = Base16.encode(raw_key_blob);

    // 4. Hash the raw key for storage.
    let hashed_key_blob = Sha256.fromBlob(#sha256, raw_key_blob);
    let hashed_key_text : Types.HashedApiKey = Base16.encode(hashed_key_blob);

    // 5. Create the info record.
    let key_info : Types.ApiKeyInfo = {
      principal = principal;
      scopes = scopes;
      name = name;
      created = Time.now();
    };

    // 6. Store the HASH in the module's state.
    Map.set(apiState.apiKeys, Map.thash, hashed_key_text, key_info);

    // 7. Return the PLAINTEXT key to the admin.
    return raw_key_text;
  };

  // --- LIST API KEYS (Query Method) ---
  // Securely lists metadata about existing keys.
  public func list_api_keys(ctx : Types.AuthContext, caller : Principal) : [Types.ApiKeyMetadata] {
    // 1. Get the specific state for the API key module.
    let apiState = _getApiState(ctx);

    // 2. Perform the owner check.
    if (caller != apiState.owner) {
      Debug.trap("Unauthorized: Only the owner can list API keys.");
    };

    // 3. Iterate over the map in the module's state.
    var metadata : [Types.ApiKeyMetadata] = [];
    for ((hash, info) in Map.entries(apiState.apiKeys)) {
      metadata := Array.append(metadata, [{ hashed_key = hash; info = info }]);
    };
    return metadata;
  };

  // --- REVOKE API KEY (Update Method) ---
  public func revoke_api_key(ctx : Types.AuthContext, caller : Principal, hashed_key : Types.HashedApiKey) {
    // 1. Get the specific state for the API key module.
    let apiState = _getApiState(ctx);

    // 2. Perform the owner check.
    if (caller != apiState.owner) {
      Debug.trap("Unauthorized: Only the owner can revoke API keys.");
    };

    // 3. Remove the key from the map in the module's state.
    let removed = Map.remove(apiState.apiKeys, Map.thash, hashed_key);
    if (removed == null) {
      Debug.print("Warning: Attempted to revoke a non-existent API key: " # hashed_key);
    };
  };
};
