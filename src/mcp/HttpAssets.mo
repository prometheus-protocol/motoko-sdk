import CertifiedCache "mo:certified-cache";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Hash "mo:base/Hash";
import Nat "mo:base/Nat";

module {
  // A type to hold the cache state.
  public type State = {
    cache : CertifiedCache.CertifiedCache<Text, Blob>;
  };

  // The type for the stable variable that will live in the main actor.
  public type StableEntries = [(Text, (Blob, Nat))];

  /**
   * Initializes the certified asset cache from stable entries.
   * Call this once in your main actor.
   */
  public func init(stable_entries : StableEntries) : State {
    let cache = CertifiedCache.fromEntries<Text, Blob>(
      stable_entries,
      Text.equal,
      Text.hash,
      Text.encodeUtf8,
      func(b : Blob) : Blob { b },
      2 * 24 * 60 * 60 * 1_000_000_000 // Default TTL: 2 days
    );
    return { cache = cache };
  };

  /**
   * Prepares the cache entries for stable storage.
   * Call this from your `preupgrade` system hook.
   */
  public func preupgrade(state : State) : StableEntries {
    return state.cache.entries();
  };

  /**
   * Prunes expired entries from the cache.
   * Call this from your `postupgrade` system hook.
   */
  public func postupgrade(state : State) {
    ignore state.cache.pruneAll();
  };
};
