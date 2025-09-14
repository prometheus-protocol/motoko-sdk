// src/auth/State.mo

import Map "mo:map/Map";
import Types "Types";

module {

  // --- NEW: Initialize with ONLY OIDC enabled ---
  public func initOidc(
    self : Principal,
    issuerUrl : Text,
    requiredScopes : [Text],
    transformJwksResponse : Types.JwksTransformFunc,
  ) : Types.AuthContext {
    return {
      oidc = ?{
        issuerUrl = issuerUrl;
        requiredScopes = requiredScopes;
        jwksCache = Map.new<Text, Map.Map<Text, Types.PublicKeyData>>();
        sessionCache = Map.new<Text, Types.CachedSession>();
        transformJwksResponse = transformJwksResponse;
        self = self;
      };
      apiKey = null;
      var cleanupTimerId = null;
    };
  };

  // --- NEW: Initialize with ONLY API Keys enabled ---
  public func initApiKey(owner : Principal) : Types.AuthContext {
    return {
      oidc = null;
      apiKey = ?{
        owner = owner;
        apiKeys = Map.new<Types.HashedApiKey, Types.ApiKeyInfo>();
      };
      var cleanupTimerId = null;
    };
  };

  // --- NEW: Initialize with BOTH enabled ---
  public func init(
    self : Principal,
    owner : Principal,
    issuerUrl : Text,
    requiredScopes : [Text],
    transformJwksResponse : Types.JwksTransformFunc,
  ) : Types.AuthContext {
    return {
      oidc = ?{
        issuerUrl = issuerUrl;
        requiredScopes = requiredScopes;
        jwksCache = Map.new<Text, Map.Map<Text, Types.PublicKeyData>>();
        sessionCache = Map.new<Text, Types.CachedSession>();
        transformJwksResponse = transformJwksResponse;
        self = self;
      };
      apiKey = ?{
        owner = owner;
        apiKeys = Map.new<Types.HashedApiKey, Types.ApiKeyInfo>();
      };
      var cleanupTimerId = null;
    };
  };
};
