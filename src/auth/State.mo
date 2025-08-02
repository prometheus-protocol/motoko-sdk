// src/auth/State.mo

import Map "mo:map/Map";
import CertTree "mo:ic-certification/CertTree";
import Types "Types"; // Import our new types module

module {
  // The init function creates a fresh instance of our application's auth state.
  public func init(issuerUrl : Text, requiredScopes : [Text]) : Types.AuthContext {
    var cert_store : CertTree.Store = CertTree.newStore();
    let ct = CertTree.Ops(cert_store);

    {
      issuerUrl = issuerUrl;
      requiredScopes = requiredScopes;
      jwksCache = Map.new<Text, Map.Map<Text, Types.PublicKeyData>>();
      certTree = ct;
    };
  };
};
