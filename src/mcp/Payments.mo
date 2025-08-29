import Debug "mo:base/Debug";
import Result "mo:base/Result";
import ICRC2 "mo:icrc2-types";
import Error "mo:base/Error";
import Principal "mo:base/Principal";
import Json "mo:json";

import AuthTypes "../auth/Types";
import Handler "../server/Handler";

import Types "Types";
import ErrorUtils "ErrorUtils";

module {

  public type Destination = ICRC2.Account;

  /// Gets this canister's balance of a given ICRC-1 token.
  /// This function is public and can be called by anyone.
  public func get_treasury_balance(self : Principal, ledger_id : Principal) : async Nat {
    let ledger : ICRC2.Service = actor (Principal.toText(ledger_id));

    try {
      return await ledger.icrc1_balance_of({
        owner = self;
        subaccount = null;
      });
    } catch (e) {
      // If the ledger traps or doesn't exist, return a balance of 0.
      Debug.print("Failed to get treasury balance: " # Error.message(e));
      return 0;
    };
  };

  public type TreasuryError = {
    #NotOwner;
    #TransferFailed : ICRC2.TransferError;
    #LedgerTrap : Text; // For when the ledger canister itself fails
  };

  /// Withdraws a specified amount of an ICRC-2 token to a destination account.
  /// Only the current owner can call this function.
  public func withdraw(
    caller : Principal,
    owner : Principal,
    ledger_id : Principal,
    amount : Nat,
    destination : ICRC2.Account,
  ) : async Result.Result<Nat, TreasuryError> {
    // SECURITY: This is the most important check.
    if (caller != owner) {
      return #err(#NotOwner);
    };

    let ledger : ICRC2.Service = actor (Principal.toText(ledger_id));

    try {
      let transferResult = await ledger.icrc1_transfer({
        from_subaccount = null; // Withdraw from the canister's default account
        to = destination;
        amount = amount;
        fee = null;
        memo = null;
        created_at_time = null;
      });

      switch (transferResult) {
        case (#Ok(blockIndex)) {
          return #ok(blockIndex);
        };
        case (#Err(err)) {
          // The transfer was rejected by the ledger (e.g., insufficient funds)
          return #err(#TransferFailed(err));
        };
      };
    } catch (e) {
      // The ledger canister itself trapped (e.g., out of cycles, uninstalled)
      let err_msg = Error.message(e);
      Debug.print("FATAL: Withdrawal failed, ledger trapped: " # err_msg);
      return #err(#LedgerTrap(err_msg));
    };
  };

  // The centralized payment handler.
  // It now returns a Result with a HandlerError on failure, which the caller can decide how to handle.
  public func handlePayment(
    paymentInfo : Types.PaymentInfo,
    payoutPrincipal : Principal,
    auth : ?AuthTypes.AuthInfo,
    allowanceUrl : ?Text,
  ) : async Result.Result<Nat, Handler.HandlerError> {
    switch (auth) {
      case (null) {
        return #err({
          code = -32001;
          message = "Authentication is required for this operation.";
          data = null;
        });
      };
      case (?authInfo) {
        let caller = authInfo.principal;
        let ledger : ICRC2.Service = actor (Principal.toText(paymentInfo.ledger));
        // --- START: Add try...catch block around the inter-canister call ---
        try {
          let transferResult = await ledger.icrc2_transfer_from({
            spender_subaccount = null;
            from = { owner = caller; subaccount = null };
            to = { owner = payoutPrincipal; subaccount = null };
            amount = paymentInfo.amount;
            fee = null;
            created_at_time = null;
            memo = null;
          });

          // This logic only runs if the `await` call itself succeeds.
          switch (transferResult) {
            case (#Ok(blockIndex)) {
              return #ok(blockIndex);
            };
            case (#Err(err)) {
              // This handles predictable ICRC-2 business logic errors.
              let friendlyMessage = ErrorUtils.parseIcrc2TransferFromError(err, allowanceUrl);
              let (code, data) = switch (err) {
                case (#InsufficientAllowance(_)) {
                  (-32003, switch (allowanceUrl) { case (?url) { ?Json.obj([("allowanceUrl", Json.str(url))]) }; case (null) { null } });
                };
                case (_) { (-32002, null) };
              };
              return #err({
                code = code;
                message = friendlyMessage;
                data = data;
              });
            };
          };
        } catch (e) {
          // --- CATCH BLOCK ---
          // This block executes if the `await ledger.icrc2_transfer_from` call TRAPS.
          // This is a "canister fault" error (e.g., ledger is out of cycles, doesn't exist, etc.).
          // We catch the raw error, log it for our own debugging, and return a clean error to the user.
          Debug.print("FATAL: Inter-canister call to ledger trapped: " # Error.message(e));

          return #err({
            code = -32004; // Custom code for "Dependency Failure"
            message = "The payment operation failed due to an issue with the ledger. Please try again later.";
            data = null;
          });
        };
      };
    };
  };

};
