import Map "mo:map/Map";
import IC "ic:aaaaa-aa";

module {

  // The configuration for mandatory, server-wide authentication.
  public type AuthConfig = {
    // The unique URL of the trusted Authorization Server (e.g., https://<principal>.icp0.io)
    issuerUrl : Text;
    // The set of scopes that MUST be present in any valid token for this server.
    requiredScopes : [Text];
  };

  public type AuthInfo = {
    principal : Principal;
    scopes : [Text];
  };

  // The type for the required transform function for HTTPS outcalls.
  public type JwksTransformFunc = shared query ({
    context : Blob;
    response : IC.http_request_result;
  }) -> async IC.http_request_result;

  // The type for the JWKS key cache.
  public type JwksKeyCache = Map.Map<Text, Map.Map<Text, Blob>>;

  // A dedicated context for authentication ---
  // This object holds all the state and configuration needed ONLY for auth.
  public type AuthContext = {
    // The mutable cache for JSON Web Keys.
    jwksCache : JwksKeyCache;
    // A reference to the transform function in the main actor.
    jwksTransform : JwksTransformFunc;
  };
};
