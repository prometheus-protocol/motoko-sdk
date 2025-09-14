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

  public type JwksTransformFunc = shared query ({
    context : Blob;
    response : IC.HttpRequestResult;
  }) -> async IC.HttpRequestResult;

  // The information associated with a single API key.
  public type ApiKeyInfo = {
    principal : Principal; // The principal this key acts on behalf of.
    scopes : [Text]; // The permissions granted by this key.
    name : Text; // A human-readable name for the key (e.g., "Analytics Service").
    created : Time.Time; // When the key was created.
  };

  // A type alias for the SHA-256 hash of an API key.
  public type HashedApiKey = Text;

  // The main storage for API keys. Maps the hash to its info.
  public type ApiKeyStore = Map.Map<HashedApiKey, ApiKeyInfo>;

  // The data returned to an admin when listing keys (never includes the raw key).
  public type ApiKeyMetadata = {
    hashed_key : HashedApiKey;
    info : ApiKeyInfo;
  };

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

  // --- NEW: OIDC-specific state ---
  public type OidcState = {
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
  };

  // --- NEW: API Key-specific state ---
  public type ApiKeyState = {
    // The principal authorized to manage API keys.
    owner : Principal;
    // The mutable store for API keys.
    apiKeys : ApiKeyStore;
  };

  // A dedicated context for authentication ---
  // This object holds all the state and configuration needed ONLY for auth.
  public type AuthContext = {
    // An optional record for OIDC configuration and state.
    oidc : ?OidcState;
    // An optional record for API Key configuration and state.
    apiKey : ?ApiKeyState;
    // The timer ID for the cleanup task (can be shared or managed separately).
    var cleanupTimerId : ?Timer.TimerId;
  };
};
