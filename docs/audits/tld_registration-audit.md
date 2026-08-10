# TLD Registration Audit

Scope: `onchain/validators/tld_registration/` and the paired `registrar_nft` policy.

Method: static review of the Aiken sources, helper functions, and validator tests, followed by `aiken check` in `onchain/` on 2026-08-10.

Test status: `25/25` tests passed.

## Summary

The registrar NFT bearer model is intentional and should be treated as the authority boundary, not as a vulnerability. The remaining protocol issues are in the cross-validator coupling around `OwnerAction` and the split/merge counter flow.

Findings:

1. High - `OwnerAction` depends on the companion `tld_reference` validator for the actual bearer check, so the registrar UTxO itself is not self-authenticating after activation.
2. Medium - the `BurnReference` guard is inverted relative to the intended split/merge lifecycle, which makes the documented merge path unreachable under a consistent counter flow.

## Findings

### 1. High - `OwnerAction` depends on cross-validator coupling for authority

Evidence:

- [tld_registrar.ak](/home/adrian/blinklabs/cdnsd/decentralized-dns-contracts/onchain/validators/tld_registration/tld_registrar.ak#L66) switches `has_owner_signed` to `True` whenever `minted != 0`.
- The same branch recomputes `new_minted` from the transaction mint and only checks that the registration output is recreated with the new datum in [tld_registrar.ak](/home/adrian/blinklabs/cdnsd/decentralized-dns-contracts/onchain/validators/tld_registration/tld_registrar.ak#L91).
- The local `OwnerAction` path does not itself check the TLD user token; that bearer check lives in the companion `tld_reference` validator.

Impact:

This is safe only because the protocol requires the paired `tld_reference` spend/mint to run in the same transaction. The registrar UTxO is therefore not self-authenticating after activation; the authority boundary is split across two validators. That is acceptable if the off-chain builder always emits the paired flow, but it is a coupling point that should be treated as a protocol invariant and tested as such.

Exploit path:

1. Build an `OwnerAction` transaction that tries to mutate the registration counter without the paired reference-token path.
2. `tld_registrar` alone will not reject the post-activation branch on signer identity.
3. The transaction only becomes safe because `tld_reference` rejects it unless the bearer token and reference-token semantics also line up.

Fix:

- Document the bearer-token dependency as a hard protocol invariant.
- Add tests that exercise the full `OwnerAction` + `tld_reference` pair, not the registrar validator in isolation.
- If you want the registrar UTxO to be self-authenticating, add a local bearer or signature check on the `OwnerAction` path.

### 2. Medium - the merge guard does not match the intended lifecycle

Evidence:

- [tld_reference.ak](/home/adrian/blinklabs/cdnsd/decentralized-dns-contracts/onchain/validators/tld_registration/tld_reference.ak#L276) names the variable `not_last`, but the actual guard is `minted == 1`.
- The architecture docs describe `BurnReference` as the 2-to-1 merge path and `InitRemoveReference` as the final burn path.
- The code path in [tld_reference.ak](/home/adrian/blinklabs/cdnsd/decentralized-dns-contracts/onchain/validators/tld_registration/tld_reference.ak#L235) requires two reference-token inputs and one output, which is the merge shape, but the registration counter check only accepts the state value used for the final burn path.

Impact:

With a consistent counter flow, a real split will raise `minted` above `1`, so the merge path fails when the contract should accept it. The result is a dead end in the linked-list scaling model: split operations can work, but the documented merge operation cannot be completed from the counter state that the rest of the protocol is supposed to maintain.

Fix:

- Change the guard to match the intended merge state, and add an end-to-end test that performs a split through `OwnerAction`, updates the counter, and then merges back.
- Keep the merge and final-burn branches disjoint and covered by tests so the state machine cannot drift again.

## Test Coverage Notes

The current unit suite is useful for happy-path validation, but it does not cover the actual adversarial cases behind the findings above.

- No test drives `OwnerAction` and the paired `tld_reference` logic together as a single authorization boundary.
- No test attempts the split/merge flow with a real counter progression through `OwnerAction`.
- No test asserts the intended registrar bearer model as a protocol invariant.

## Recommendation

Treat the registrar NFT holder as the registrar authority by design, then tighten the cross-validator tests around `OwnerAction` and fix the `BurnReference` counter check. The current code passes its tests, but the split/merge state machine still disagrees with the documented lifecycle.
