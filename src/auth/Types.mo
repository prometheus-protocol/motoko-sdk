import Map "mo:map/Map";
import ECDSA "mo:ecdsa";
import IC "mo:ic";
import Time "mo:base/Time";
import Timer "mo:base/Timer";

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

  public type JwksTransformFunc = shared query ({
    context : Blob;
    response : IC.HttpRequestResult;
  }) -> async IC.HttpRequestResult;

  // This is the lightweight object we store in our cache.
  // It contains the validated result and its original expiration.
  public type CachedSession = {
    authInfo : AuthInfo;
    expiresAt : Time.Time; // Nanoseconds since epoch, from the JWT 'exp' claim
  };

  // The session cache maps a token's hash to its validation result.
  // Key: SHA-256 hash of the raw JWT string.
  // Value: The cached session data.
  public type SessionCache = Map.Map<Text, CachedSession>;

  // A dedicated context for authentication ---
  // This object holds all the state and configuration needed ONLY for auth.
  public type AuthContext = {
    // The configuration for the authentication server.
    issuerUrl : Text;
    // The scopes that are required for any valid token.
    requiredScopes : [Text];
    // The mutable cache for JSON Web Keys.
    jwksCache : JwksKeyCache;
    // Session cache for storing validated tokens.
    sessionCache : SessionCache;
    // The function to transform JWKS responses.
    transformJwksResponse : JwksTransformFunc;
    // This canister's principal, used for audience validation.
    self : Principal;
    // The timer ID for the cleanup task.
    var cleanupTimerId : ?Timer.TimerId;
  };
};
