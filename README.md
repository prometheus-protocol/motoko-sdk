### **Task 2 (Parallel Work): `prometheus.mo` - The On-Chain Toolkit**

This can be developed in parallel with the JS SDK. It will be a Mops package.

**Week 2: Core Functionality**

*   **[x] Repo & Mops Setup:**
    *   Create a new GitHub repository: `prometheus-motoko-sdk`.
    *   Initialize it as a Mops package.

*   **[ ] JWT Validation:**
    *   Implement the `validateJwt(token: Text)` function.
    *   This function will need to make an `http_outcall` to the Auth Canister's `/.well-known/jwks.json` endpoint.
    *   **Crucially, it must cache the JWKS response in a stable variable with a TTL** to avoid excessive HTTP calls.
    *   It will then use a Motoko JWT library to perform the full signature and claim validation.

*   **[ ] Subscription Checker:**
    *   Implement the `isSubscriptionActive(user: Principal)` function.
    *   This will be a simple, authenticated inter-canister call to our Auth Canister's `get_subscription_status` method.

**Week 3: Polish & Publishing**

*   **[ ] Documentation & Examples:**
    *   Write a clear README with examples of how to protect a canister's functions using this library.
    *   Publish version `0.1.0` to Mops.