// src/auth/State.mo

import Map "mo:map/Map";
import Types "Types";
module {
  // The init function creates a fresh instance of our application's auth state.
  public func init(self : Principal, owner : Principal, issuerUrl : Text, requiredScopes : [Text], transformJwksResponse : Types.JwksTransformFunc) : Types.AuthContext {

    {
      self = self; // Store the canister's principal for audience validation
      owner = owner; // Store the owner principal
      issuerUrl = issuerUrl;
      requiredScopes = requiredScopes;
      jwksCache = Map.new<Text, Map.Map<Text, Types.PublicKeyData>>();
      transformJwksResponse = transformJwksResponse; // Function to transform JWKS responses
      sessionCache = Map.new<Text, Types.CachedSession>(); // Cache for validated sessions
      var cleanupTimerId = null; // No cleanup timer initially
      apiKeys = Map.new<Types.HashedApiKey, Types.ApiKeyInfo>(); // Initialize empty API key store
    };
  };
};
