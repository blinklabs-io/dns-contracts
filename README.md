# Handshake-Cardano Interoperability Demonstration

This project demonstrates the possibility of verifying signatures generated on the Handshake blockchain on the Cardano blockchain using a Aiken smart contract. This showcases a potential path for interoperability between the two networks, enabling Handshake domain owners to manage their TLDs and subdomains on Cardano.

## Project Structure

```
hns-sig/              # Node.js signature generation (bcrypto)
onchain/              # Aiken smart contracts
  validators/         # Validator source files
    tld_registration/ # TLD registrar and reference validators
  lib/                # Shared types and utilities
scripts/              # Cardano CLI automation
preprod/              # Testnet artifacts (tx, validators, wallets)
docs/                 # Architecture and research documentation
```

## Architecture

The system uses a **registrar NFT bearer authority plus one-time owner signature** approach with a three-layer validator architecture:

### Validators

**tld_registrar** ([`onchain/validators/tld_registration/tld_registrar.ak`](onchain/validators/tld_registration/tld_registrar.ak))
- Trust anchor for bridging Handshake domains to Cardano
- Uses a registrar NFT as bearer authority and verifies the owner signature during initial activation
- Owner signature only required once during initial activation

**tld_reference** ([`onchain/validators/tld_registration/tld_reference.ak`](onchain/validators/tld_registration/tld_reference.ak))
- Token-based authorization layer for ongoing operations
- Issues reference tokens (domain state) and user tokens (ownership proof)
- Manages subdomains via linked-list structure for scalability

**sld_reference** ([`onchain/validators/tld_registration/sld_reference.ak`](onchain/validators/tld_registration/sld_reference.ak))
- Manages individual subdomain token pairs
- Stores DNS records for each subdomain
- Coordinates minting/burning with TLD layer atomically

**verify_hns_sig** ([`onchain/validators/verify_hns_sig.ak`](onchain/validators/verify_hns_sig.ak))
- Standalone secp256k1 ECDSA signature verification demo

### Validation Flow

1. **Registration**: Registrar validates domain and creates on-chain registration with owner's Handshake public key
2. **Activation**: Owner provides one-time Handshake signature to mint reference and user tokens
3. **Operations**: Subsequent actions (subdomain management, DNS records) only require user token possession
4. **Deregistration**: Burn all reference tokens, then registrar can remove the registration

### Token System

| Token | Name Derivation | Purpose |
|-------|---------------------|---------|
|TLD Reference | `blake2b_256("r" ++ tld)` | Stores domain state and subdomain lists |
|TLD User | `blake2b_256("u" ++ tld)` | Proof of TLD ownership |
|SLD Reference | `blake2b_256("r" ++ sld)` | Stores subdomain DNS records |
|SLD User | `blake2b_256("u" ++ sld)` | Proof of subdomain ownership |

### Documentation
**Ownership Validation**: See [`docs/architecture/validation-method.md`](docs/architecture/validation-method.md) for details on how Handshake domain ownership is cryptographically proven on Cardano.

**Technical Architecture**: See [`docs/architecture/smart-contract-architecture.md`](docs/architecture/smart-contract-architecture.md) for the complete architecture reference, with diagrams covering:
- Parametric identity ("inheritance") chain and the data model
- Token system, object ownership, and custody
- End-to-end data flow and per-operation transaction anatomies
- Multi-validator coordination and the `minted` reference-counter state machine
- Linked-list scaling (split/merge), invariants, and design rationale

## Prerequisites

To run this demonstration, you will need:

* Node.js
* Aiken toolchain
* Cardano node and `cardano-cli` (configured for a testnet like Preprod)

Please ensure these are installed and configured correctly on your system.

## Installation

1. **Clone the repository:**

```bash
    git clone https://github.com/blinklabs-io/decentralized-dns-contracts
    cd decentralized-dns-contracts
```

2. **Install Node.js dependencies:**

    Navigate to the `hns-sig` directory and install the required packages.

```bash
    cd hns-sig
    npm install
    cd ..
```

3. **Install Aiken:**

    Follow the official Aiken installation guide: [Getting started With Aiken](https://aiken-lang.org/fundamentals/getting-started)

4. **Set up Cardano Node and `cardano-cli`:**

    Ensure you have a running Cardano node and `cardano-cli` configured to connect to a testnet (e.g., Preprod). Refer to the official Cardano documentation for setup instructions.

## Running `sign.js`

The [`sign.js`](hns-sig/sign.js) script is used to generate signatures. To run it:

1. Navigate to the `hns-sig` directory.
2. Execute the script using Node.js.

    ```bash
    cd hns-sig
    node sign.js
    cd ..
    ```

    *(Note: You may need to modify [`sign.js`](hns-sig/sign.js) to perform the specific signing operation required for your demonstration.)*

## Running the On-Chain Validator

The validator is written in Aiken and compiled to Plutus Core. The source code is located in [`onchain/validators/verify_hns_sig.ak`](onchain/validators/verify_hns_sig.ak).

To build the validator (compile Aiken to Plutus):

1. Navigate to the `onchain` directory.
2. Run the Aiken build command.

    ```bash
    cd onchain
    aiken build
    cd ..
    ```

    This will generate the Plutus file, typically in `onchain/build/`.

The validator is used in on-chain transactions to verify signatures. Its functionality is primarily demonstrated through the Aiken tests and the provided shell scripts.

## Running Scripts

The scripts in the `scripts` directory facilitate interaction with the Cardano testnet for demonstration purposes.

* [`env.sh`](scripts/env.sh): Sets up environment variables and helper functions for `cardano-cli` operations. You should source this file in your terminal session.

    ```bash
    source scripts/env.sh
    ```

* [`create-user.sh`](scripts/create-user.sh): Creates Cardano payment and stake keys and addresses for a user.
  
    ```bash
    scripts/create-user.sh <username>
    ```

    Replace `<username>` with a desired name for the wallet (e.g., `user1`).

* [`balance-wallet.sh`](scripts/balance-wallet.sh): Checks the balance of a user's wallet.

    ```bash
    scripts/balance-wallet.sh <username>
    ```

    Replace `<username>` with the wallet name.

* [`hello-handshake.sh`](scripts/hello-handshake.sh): This is the main demonstration script. It builds, signs, and submits a transaction that interacts with the on-chain validator, likely minting a token based on a verified Handshake signature.
  
    ```bash
    scripts/hello-handshake.sh <username>
    ```

    Replace `<username>` with the wallet name created using `create-user.sh`.

To run the full demonstration using the scripts:

1. Source the environment file: `source scripts/env.sh`
2. Create a user wallet: `scripts/create-user.sh user1`
3. Fund the `user1` wallet with testnet ADA.
4. Run the main demonstration script: `scripts/hello-handshake.sh user1`

## Running Validator Tests

The Aiken project includes tests for the validators in [`onchain/validators/tld_registration/tests/`](onchain/validators/tld_registration/tests/). To run these tests:

1. Navigate to the `onchain` directory.
2. Run the Aiken test command.

    ```bash
    cd onchain
    aiken check              # Run all tests
    aiken check -m <pattern> # Run tests matching pattern
    cd ..
    ```

    This will execute the tests defined in the test files and report the results.
