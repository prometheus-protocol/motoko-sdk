// src/auth/State.mo

import Map "mo:map/Map";
import CertTree "mo:ic-certification/CertTree";
import Types "Types"; // Import our new types module

module {
  // The init function creates a fresh instance of our application's auth state.
  public func init(self : Principal, issuerUrl : Text, requiredScopes : [Text], jwksCache : Map.Map<Text, Map.Map<Text, Types.PublicKeyData>>, transformJwksResponse : Types.JwksTransformFunc) : Types.AuthContext {
    var cert_store : CertTree.Store = CertTree.newStore();
    let ct = CertTree.Ops(cert_store);

    {
      self = self; // Store the canister's principal for audience validation
      issuerUrl = issuerUrl;
      requiredScopes = requiredScopes;
      jwksCache = jwksCache;
      certTree = ct;
      transformJwksResponse = transformJwksResponse; // Function to transform JWKS responses
    };
  };
};
