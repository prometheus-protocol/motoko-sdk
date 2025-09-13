import Types "Types";
import Base16 "mo:base16/Base16";
import Sha256 "mo:sha2/Sha256";
import Random "mo:base/Random";
import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Map "mo:map/Map";
import Array "mo:base/Array";

module {

  // --- CREATE API KEY (Update Method) ---
  // Generates a new key, stores its hash, and returns the raw key ONCE.
  type CreateApiKeyArgs = {
    ctx : Types.AuthContext; // The auth context (for owner check).
    caller : Principal; // The principal making the request (for auth).
    name : Text; // A human-readable name for the key (e.g., "Analytics Service").
    principal : Principal; // The principal this key acts on behalf of.
    scopes : [Text]; // The permissions granted by this key.
  };

  public func create_api_key(args : CreateApiKeyArgs) : async Text {
    if (args.caller != args.ctx.owner) {
      Debug.trap("Unauthorized: Only the owner can create API keys.");
    };

    // 1. Generate a secure, random 32-byte key.
    let raw_key_blob : Blob = await Random.blob();
    let raw_key_text = Base16.encode(raw_key_blob);

    // 2. Hash the raw key for storage.
    // let tokenHash = Sha256.fromBlob(#sha256, Text.encodeUtf8(tokenString));

    let hashed_key_blob = Sha256.fromBlob(#sha256, raw_key_blob);
    let hashed_key_text : Types.HashedApiKey = Base16.encode(hashed_key_blob);

    // 3. Create the info record.
    let key_info : Types.ApiKeyInfo = {
      principal = args.principal;
      scopes = args.scopes;
      name = args.name;
      created = Time.now();
    };

    // 4. Store the HASH, not the raw key.
    Map.set(args.ctx.apiKeys, Map.thash, hashed_key_text, key_info);

    // 5. Return the PLAINTEXT key to the admin. This is their only chance to see it.
    return raw_key_text;
  };

  // --- LIST API KEYS (Query Method) ---
  // Securely lists metadata about existing keys.
  public func list_api_keys(ctx : Types.AuthContext, caller : Principal) : async [Types.ApiKeyMetadata] {
    if (caller != ctx.owner) {
      Debug.trap("Unauthorized: Only the owner can list API keys.");
    };

    var metadata : [Types.ApiKeyMetadata] = [];
    for ((hash, info) in Map.entries(ctx.apiKeys)) {
      metadata := Array.append(metadata, [{ hashed_key = hash; info = info }]);
    };
    return metadata;
  };

  // --- REVOKE API KEY (Update Method) ---
  public func revoke_api_key(ctx : Types.AuthContext, caller : Principal, hashed_key : Types.HashedApiKey) : async () {
    if (caller != ctx.owner) {
      Debug.trap("Unauthorized: Only the owner can revoke API keys.");
    };

    let removed = Map.remove(ctx.apiKeys, Map.thash, hashed_key);
    // Optional: Check if `removed` was null to confirm a key was actually deleted.
    if (removed == null) {
      Debug.print("Warning: Attempted to revoke a non-existent API key: " # hashed_key);
    };
  };
};
