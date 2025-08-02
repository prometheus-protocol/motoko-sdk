import Map "mo:map/Map";
import ECDSA "mo:ecdsa";
import CertTree "mo:ic-certification/CertTree";

module {
  public type AuthInfo = {
    principal : Principal;
    scopes : [Text];
  };

  // A sharable DTO to hold the raw components of an ECDSA public key.
  public type PublicKeyData = {
    x : Nat;
    y : Nat;
    curveKind : ECDSA.CurveKind; // The curve's enum is a sharable variant.
  };

  // The cache will now store this sharable DTO.
  public type JwksKeyCache = Map.Map<Text, Map.Map<Text, PublicKeyData>>;
  public type JwksKeyCacheEntry = Map.Map<Text, PublicKeyData>;

  // A dedicated context for authentication ---
  // This object holds all the state and configuration needed ONLY for auth.
  public type AuthContext = {
    // The configuration for the authentication server.
    issuerUrl : Text;
    // The scopes that are required for any valid token.
    requiredScopes : [Text];
    // The mutable cache for JSON Web Keys.
    jwksCache : JwksKeyCache;
    // The certification tree for managing certified resources.
    certTree : CertTree.Ops;
  };
};
