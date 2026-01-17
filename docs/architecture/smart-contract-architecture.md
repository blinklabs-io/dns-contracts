# Cardano Domain Management Architecture

## Purpose of This Document

This document provides detailed technical information about the Cardano-based domain management system implementation. It complements the [validation method](validation-method.md) documentation by explaining the complete operational architecture, validator interactions, and design decisions.

## System Overview

The domain management system consists of three interconnected Aiken validators that enable Handshake TLD owners to manage their domains, subdomains, and DNS records on Cardano after ownership has been validated.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: TLD Registrar (tld_registrar.ak)                  │
│ • Tracks reference token count via minted field            │
│ • Controls domain lifecycle (register → deregister)        │
│ • Validates registrar authorization                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: TLD Reference (tld_reference.ak)                  │
│ • Manages TLD token pairs (reference + user tokens)        │
│ • Stores subdomain lists in linked list structure          │
│ • Coordinates with SLD validator for subdomain operations  │
│ • Enables scaling via UTxO splitting/merging               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: SLD Reference (sld_reference.ak)                  │
│ • Manages individual subdomain token pairs                 │
│ • Stores DNS records for each subdomain                    │
│ • Validates parent TLD reference is present                │
│ • Coordinates minting/burning with TLD layer               │
└─────────────────────────────────────────────────────────────┘
```

### Validator Responsibilities

#### TLD Registrar ([tld_registrar.ak](../../onchain/validators/tld_registration/tld_registrar.ak))

**Primary Role**: Lifecycle management and reference token accounting.

**Redeemers**:
- `RegisterTLD`: Initial domain registration (mint validator path)
- `OwnerAction`: Mint/burn TLD reference tokens (spend validator path)
- `RegistrarAction`: Final deregistration when all references are burned (both paths)

**Datum**: `TLDRegisterDatum`
```aiken
TLDRegisterDatum {
  tld: ByteArray,           // The TLD name (e.g., "example")
  owner_hns_key: ByteArray, // Handshake public key
  minted: Int               // Count of TLD reference tokens in circulation
}
```

**Critical Invariant**: 
- The `minted` field must always equal the actual number of TLD reference tokens in 
  circulation.
- Incrementing `minted` when `OwnerAction` mints tokens
- Decrementing `minted` when `OwnerAction` burns tokens
- Only allowing `RegistrarAction` deregistration when `minted == 0`

**Why this matters**: Prevents premature deregistration while the domain is actively being used. The registrar cannot remove the registration until all references have been properly cleaned up.

#### TLD Reference ([tld_reference.ak](../../onchain/validators/tld_registration/tld_reference.ak))

**Primary Role**: Domain state management and scalability.

**Redeemers**:
- `InitRemoveReference`: Mint/burn the initial TLD token pair
- `SpendReference`: Modify subdomain lists and DNS records
- `MintAdditionalReference`: Split into multiple UTxOs for more datum space
- `BurnReference`: Merge multiple UTxOs back into one

**Datum**: `TLDReferenceDatum`
```aiken
TLDReferenceDatum {
  tld: ByteArray,                    // The TLD name
  slds: List<ByteArray>,             // Subdomain names (sorted)
  next: ByteArray,                   // Linked list pointer (or "" if last)
  sld_reference_policy_id: PolicyId, // For coordinating SLD operations
  records: [DNSRecord]               // TLD-level DNS records
}
```

**Critical Invariants**:
- `slds` list must always be lexicographically sorted and contain unique values
- `next` field must maintain linked list integrity across all operations
- User token must be present in transaction inputs for all spend operations

**Why linked lists**: Cardano UTxO datums have size limits. When a TLD has many subdomains, the list won't fit in a single datum. The linked list structure allows distributing subdomains across multiple UTxOs while maintaining order.

#### SLD Reference ([sld_reference.ak](../../onchain/validators/tld_registration/sld_reference.ak))

**Primary Role**: Subdomain-level management and DNS record storage.

**Redeemers**:
- `MintSld`: Create/destroy subdomain token pairs
- (Spend uses generic `Data` redeemer)

**Datum**: `SLDReferenceDatum`
```aiken
SLDReferenceDatum {
  tld: ByteArray,    // Parent TLD name
  sld: ByteArray,    // This subdomain name
  records: [DNSRecord]      // DNS records for this subdomain
}
```

**Critical Invariant**: Every SLD operation must occur while the parent TLD reference token exists in transaction inputs. This ensures subdomains cannot be orphaned.

**Coordination Requirement**: When minting/burning SLD tokens, the `MintSld` redeemer must be present in the transaction, and it must be called by the TLD reference validator's validation logic.

## Token System Design

### Token Naming Convention

All tokens use `blake2b_256` hashing with specific prefixes:

**Reference Tokens**: `blake2b_256("r" + cleartext_name)`
- Purpose: Store data in UTxO datums
- Quantity: Can have multiple copies per domain/subdomain
- Usage: Must be present when performing operations on that domain/subdomain

**User Tokens**: `blake2b_256("u" + cleartext_name)`  
- Purpose: Prove ownership and authorization
- Quantity: Exactly one per domain/subdomain
- Usage: Must be present in transaction inputs to authorize operations

### Examples

For TLD "example":
- Reference token: `blake2b_256("r" + "example")` = `7a3f8b2c...`
- User token: `blake2b_256("u" + "example")` = `9e4d1a5f...`

For SLD "test" under "example":
- Reference token: `blake2b_256("r" + "test")` = `2c8e9f1b...`
- User token: `blake2b_256("u" + "test")` = `5a7c3d9e...`

### Why Token Pairs?

**Separation of Concerns**:
- Reference tokens handle data storage and can be duplicated for scaling
- User tokens handle authorization and must remain unique to prevent ownership conflicts

**Operational Flexibility**:
- Reference tokens can be split across multiple UTxOs without affecting ownership
- User tokens can be transferred independently to change ownership
- This separation enables clean ownership transfers without reorganizing data

**Security**:
- User token uniqueness prevents multiple parties from claiming ownership
- Reference token presence requirement ensures operations act on valid data
- Both must be satisfied for operations to succeed

## Linked List Architecture

### Problem: UTxO Datum Size Limits

Cardano imposes a practical limit per UTxO datum. For a TLD with thousands of subdomains, the `slds` list in `TLDReferenceDatum` would exceed this limit.

### Solution: Distributed Storage via Linked Lists

The system uses a linked list structure where:
- Each TLD reference UTxO contains a subset of subdomains
- The `next` field points to the first subdomain in the next UTxO
- Subdomains are maintained in lexicographical order across all UTxOs

### Visual Example

```
Single UTxO (before growth):
┌─────────────────────────────────┐
│ TLD Reference UTxO              │
│ slds: [api, blog, mail, what]   │
│ next: ""                        │
└─────────────────────────────────┘

After splitting (too many subdomains):
┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│ TLD Reference UTxO #1           │     │ TLD Reference UTxO #2           │
│ slds: [api, blog, mail]        │────>│ slds: [shop, what, ...more]     │
│ next: "shop"                    │     │ next: ""                        │
└─────────────────────────────────┘     └─────────────────────────────────┘
         Points to first SLD in next UTxO
```

### Linked List Invariants

**Ordering**: All subdomains across all UTxOs must be in strict lexicographical order.

**Pointer Integrity**: The `next` field must point to the first subdomain in the subsequent UTxO, or be empty (`""`) if it's the last UTxO in the chain.

**No Cycles**: The chain must be acyclic and terminate with an empty `next` field.

**Complete Coverage**: The union of all `slds` lists across linked UTxOs must represent all registered subdomains.

### Operations on Linked Lists

#### Split Operation (MintAdditionalReference)

**Trigger**: When a TLD reference datum is approaching size limits.

**Process**:
1. Input: One UTxO with many subdomains
2. Mint: One new reference token
3. Output: Two UTxOs, each with a subset of subdomains
4. Constraint: Linked list pointers must be set correctly

**Example**:
```
Input:
  slds: [a, b, c, d, e, f], next: "g"

Output 1:
  slds: [a, b, c], next: "d"  ← Points to first element of Output 2

Output 2:
  slds: [d, e, f], next: "g"  ← Inherits original next pointer
```

**Why this matters**: If the pointers are set incorrectly, the linked list chain breaks and subdomains become inaccessible. The validator enforces correct pointer management.

#### Merge Operation (BurnReference)

**Trigger**: When consolidating after removing many subdomains.

**Process**:
1. Input: Two UTxOs with subdomains
2. Burn: One reference token
3. Output: One UTxO with combined subdomains
4. Constraint: Preserve linked list connections to any remaining UTxOs

**Example**:
```
Input 1:
  slds: [a, b], next: "c"

Input 2:
  slds: [c, d], next: "e"  ← Points to next UTxO in chain

Output:
  slds: [a, b, c, d], next: "e"  ← Inherits pointer to continue chain
```

**Why this matters**: The merge operation must preserve the linked list chain for any UTxOs that come after the merged pair. Incorrect pointer handling would orphan the rest of the chain.

## Multi-Validator Coordination

### The Coordination Problem

When a subdomain is added to a TLD, two things must happen atomically:
1. The TLD reference datum must add the SLD name to its `slds` list
2. The SLD reference validator must mint the SLD token pair

If only one happens, the system becomes inconsistent:
- SLD in list but no tokens = "ghost entry" (can't manage subdomain)
- SLD tokens but not in list = "orphaned subdomain" (parent doesn't know it exists)

### Solution: Redeemer-Based Coordination

The system uses a redeemer coordination pattern where validators check for each other's redeemers in the transaction.

#### When Adding/Removing Subdomains

**In TLD Reference Validator** (`validate_sld_minting` function):
```aiken
fn validate_sld_minting(
  mint: Value,
  old_slds: List<ByteArray>,
  new_slds: List<ByteArray>,
  tld: ByteArray,
  redeemers: Pairs<ScriptPurpose, Redeemer>,
  sld_reference_policy_id: PolicyId,
) -> Bool {
  let sld_mints = difference(new_slds, old_slds)  // SLDs being added
  let sld_burns = difference(old_slds, new_slds)  // SLDs being removed
  
  if sld_burns == [] && sld_mints == [] {
    // No SLD changes, so no minting should happen
    is_empty(tokens(mint, sld_reference_policy_id))?
  } else {
    // SLD changes detected, verify MintSld redeemer is present
    let mint_red: Redeemer = MintSld(tld, sld_mints, sld_burns)
    let mint_purpose = Pair(Mint(sld_reference_policy_id), mint_red)
    any(redeemers, fn(r) { r == mint_purpose })
  }
}
```

**What this does**: 
- Compares old and new SLD lists
- If they differ, checks that a `MintSld` redeemer is present in the transaction
- The redeemer must specify exactly which SLDs are being added/removed

**In SLD Reference Validator** (mint path):
```aiken
mint(redeemer: MintSld, policy_id: PolicyId, tx: Transaction) {
  let MintSld { tld, mint_slds, burn_slds } = redeemer
  
  // Verify TLD reference token is present
  let tld_reference_present =
    token_in_inputs(
      inputs,
      tld_reference_policy_id,
      create_reference_token_tn(tld),
    )
  
  // Verify correct tokens are being minted/burned
  let slds_minted = all(mint_slds, fn(sld) { 
    check_minting(mint_tn_ams, sld, 1)? && 
    check_output_exist(outputs, policy_id, sld, tld, own_address)?
  })
  
  tld_reference_present? && slds_minted? && ...
}
```

**What this does**:
- Requires parent TLD reference token in inputs
- Verifies the token pairs are being minted correctly
- Ensures output UTxOs exist with proper datums

### Coordination Flow Example

Adding subdomain "what" to TLD "example":

```
Transaction contains:

Inputs:
  - TLD reference UTxO (slds: [api, blog])
  - User token for "example"

Outputs:
  - TLD reference UTxO (slds: [api, blog, what])  ← "what" added
  - SLD reference UTxO for "what" (new)

Mint:
  - +1 blake2b_256("r" + "what")
  - +1 blake2b_256("u" + "what")

Redeemers:
  - Spend(TLD reference): SpendReference
  - Mint(SLD reference): MintSld("example", ["what"], [])  ← Declares what is being added

Validation:
  1. TLD spend validator sees slds changed from [api,blog] to [api,blog,what]
  2. Calls validate_sld_minting which checks redeemers list
  3. Finds MintSld("example", ["what"], []) redeemer ✓
  4. SLD mint validator checks TLD reference token is in inputs ✓
  5. SLD mint validator verifies "what" tokens are being minted ✓
  6. Both validators pass → transaction succeeds
```

**Why both checks are needed**:
- TLD validator ensures: "If SLDs change, minting must happen"
- SLD validator ensures: "If minting happens, parent exists and output is correct"
- Together they guarantee atomic, consistent operations

## Operational Workflows

### Workflow 1: Adding a Subdomain

**Scenario**: Owner wants to add "what" to their "example" TLD.

**Steps**:

1. **Prepare Transaction**:
   - Input: TLD reference UTxO
   - Input: User token for "example"
   - Output: Updated TLD reference UTxO with "what" in slds list
   - Output: New SLD reference UTxO for "what"
   - Mint: SLD token pair for "what"

2. **TLD Layer Validation** (tld_reference.ak spend):
   - Verify user token is present
   - Detect SLD list changed (added "what")
   - Call `validate_sld_minting` to verify `MintSld` redeemer exists
   - Verify output datum maintains invariants (sorted, unique list)

3. **SLD Layer Validation** (sld_reference.ak mint):
   - Verify TLD reference token is in inputs
   - Verify "what" token pair is being minted
   - Verify output UTxO exists with correct SLDReferenceDatum
   - Verify datum has tld="example", sld="what"

4. **Transaction Succeeds**: Both validators pass, subdomain is added atomically.

### Workflow 2: Splitting a TLD Reference

**Scenario**: TLD has 800 subdomains, approaching datum size limit. Owner wants to split into two UTxOs.

**Steps**:

1. **Prepare Transaction**:
   - Input: TLD reference UTxO with 800 subdomains
   - Input: User token for TLD
   - Output: TLD reference UTxO #1 with first 400 subdomains
   - Output: TLD reference UTxO #2 with remaining 400 subdomains
   - Mint: +1 TLD reference token

2. **Validation** (tld_reference.ak mint with MintAdditionalReference):
   - Verify exactly 1 reference token being minted
   - Verify input has existing subdomains
   - Verify two outputs exist, both with reference tokens
   - Verify combined SLD lists equal original list
   - Verify linked list pointers are correctly set
   - Verify each output has sorted, unique SLD list

3. **Linked List Setup**:
   ```
   Input: [a, b, c, ..., subdomain_400, subdomain_401, ..., z]
   
   Output 1: [a, b, c, ..., subdomain_400]
            next: "subdomain_401"  ← Points to first of Output 2
   
   Output 2: [subdomain_401, ..., z]
            next: ""  ← End of chain
   ```

4. **Transaction Succeeds**: TLD is now distributed across two UTxOs, enabling more subdomains to be added.

### Workflow 3: Updating DNS Records

**Scenario**: Owner wants to update DNS records for subdomain "what".

**Steps**:

1. **Prepare Transaction**:
   - Input: SLD reference UTxO for "what"
   - Input: User token for "what"
   - Output: SLD reference UTxO with updated records field

2. **Validation** (sld_reference.ak spend):
   - Verify SLD reference token is in input
   - Verify user token for "what" is present
   - Verify output exists with same tld and sld fields
   - Records field can change freely

3. **Transaction Succeeds**: DNS records updated without affecting structure.

### Workflow 4: Complete Deregistration

**Scenario**: Owner wants to completely remove TLD from Cardano.

**Required Steps** (in order):

1. **Burn All SLD Tokens**:
   - For each subdomain: spend SLD reference UTxO with burn
   - Transaction must include SLD user token
   - Mint -1 reference token, -1 user token
   - No output for that SLD

2. **Merge TLD References** (if multiple exist):
   - Repeatedly use BurnReference to consolidate UTxOs
   - Each merge burns one reference token
   - Continue until only one TLD reference UTxO remains

3. **Burn Final TLD Reference**:
   - Use InitRemoveReference with negative mint
   - Burns both reference and user tokens
   - Updates registrar datum: minted becomes 0

4. **Registrar Deregistration**:
   - Registrar executes RegistrarAction
   - Validates minted == 0
   - Burns registration NFT
   - Domain is fully removed

**Why this order**:
- Bottom-up dependency: SLDs depend on TLD, so must be removed first
- Reference counting: minted tracks all outstanding references
- Safety: Cannot remove infrastructure while data is attached
- Clean state: No orphaned tokens or datums remain

## Design Rationale

### Why Three Separate Validators?

**Modularity**: Each validator has a focused responsibility:
- Registrar: Trust anchor and lifecycle
- TLD Reference: State management and scaling
- SLD Reference: Granular subdomain control

**Fee Efficiency**: Only relevant validators execute for each operation type. Adding a subdomain doesn't need to execute registrar logic.

**Security Isolation**: Bugs in one layer don't necessarily compromise others.

### Why Linked Lists Instead of Other Data Structures?

**UTxO Model Fit**: Linked lists map naturally to UTxO structure - each UTxO is a node.

**Dynamic Growth**: Can grow unbounded without pre-allocation.

**Efficient Split/Merge**: One UTxO splits into two, or two merge into one - natural operations in UTxO model.

**Ordered Traversal**: Off-chain systems can traverse in order for efficient lookups.

**Alternative Considered - Merkle Trees**: 
- Pros: Efficient proofs of inclusion
- Cons: Complex rebalancing in UTxO model, harder to implement split/merge
- Decision: Simplicity and UTxO-native operations favored

### Why Require User Token Presence?

**Authorization Proof**: Possession of user token proves right to operate on domain/subdomain.

**Transfer Mechanism**: Token transfer = ownership transfer, no smart contract interaction needed.

**Delegation**: Owner can temporarily delegate by transferring token, then reclaim it.

**Compatibility**: Works with existing Cardano wallet infrastructure and DEXs.

### Why Coordinated Redeemers?

**Atomic Operations**: Ensures multi-validator operations complete successfully or fail completely.

**Data Consistency**: Prevents partial updates that would corrupt system state.

**Transaction Validation**: Both validators must approve, providing defense in depth.

**Alternative Considered - State Tokens**: 
- Pros: Simpler validation logic
- Cons: Requires additional tokens, more complex state management
- Decision: Redeemer coordination is more elegant and gas-efficient

## Conclusion

The three-layer Cardano architecture provides a complete, scalable domain management system:

**Layer 1 (Registrar)**: Establishes trust and manages lifecycle
**Layer 2 (TLD Reference)**: Provides state management and unlimited scaling
**Layer 3 (SLD Reference)**: Enables granular subdomain control

**Key Capabilities**:
- Unlimited subdomain support via linked lists
- Flexible DNS record management
- Token-based ownership and authorization
- Clean deregistration and cleanup