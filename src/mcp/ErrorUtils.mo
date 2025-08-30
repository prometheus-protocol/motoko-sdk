// src/lib/ErrorUtils.mo

import Text "mo:base/Text";
import Nat "mo:base/Nat";
import ICRC2 "mo:icrc2-types";

module {
  /**
   * A helper function to parse the structured error from an ICRC-2 ledger.
   * @param error The error variant returned by the ledger canister.
   * @param allowanceUrl The URL for the user to manage their funds/allowance.
   * @returns A human-readable error string.
   */
  public func parseIcrc2TransferFromError(error : ICRC2.TransferFromError, allowanceUrl : ?Text) : Text {
    // Create the user action prompt only if a URL is provided.
    let userActionPrompt = switch (allowanceUrl) {
      case (?url) {
        "\n\nPlease visit the dashboard to top up your balance or manage your allowance: " # url;
      };
      case (null) { "" };
    };

    switch (error) {
      case (#InsufficientAllowance(info)) {
        return "Insufficient allowance: The user has not approved a large enough spending limit for this server. Current allowance: " # Nat.toText(info.allowance) # " tokens (in the smallest unit)." # userActionPrompt;
      };
      case (#InsufficientFunds(info)) {
        return "Insufficient funds: The user's wallet balance is too low. Current balance: " # Nat.toText(info.balance) # " tokens (in the smallest unit)." # userActionPrompt;
      };
      case (#BadFee(info)) {
        return "Bad fee: The transaction fee was incorrect. Expected: " # Nat.toText(info.expected_fee) # " tokens (in the smallest unit).";
      };
      case (#Duplicate(info)) {
        return "Duplicate transaction: This transaction has already been processed. Duplicate of block: " # Nat.toText(info.duplicate_of) # ".";
      };
      case (#TemporarilyUnavailable) {
        return "The ledger is temporarily unavailable. Please try again later.";
      };
      case (#TooOld) {
        return "The transaction is too old to be processed.";
      };
      case (#CreatedInFuture(_)) {
        return "The transaction was created in the future according to the ledger's clock.";
      };
      case (#BadBurn(info)) {
        return "Invalid burn transaction. Minimum burn amount: " # Nat.toText(info.min_burn_amount) # ".";
      };
      case (#GenericError(info)) {
        return "A generic ledger error occurred: " # info.message # " (Code: " # Nat.toText(info.error_code) # ")";
      };
    };
  };
};
