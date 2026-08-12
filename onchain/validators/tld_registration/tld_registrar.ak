use aiken/builtin.{append_bytearray, serialise_data}
use aiken/collection/list.{any}
use cardano/address.{Address, Script, StakeCredential}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}
use types.{
  OwnerAction, RegisterTLD, RegistrarAction, RegistrarRedeemer, TLDRegisterDatum,
}
use utils.{
  all_burned, any_native_value, check_output_exist, create_reference_token_tn,
  create_user_token_tn, find_input_output, get_asset_name,
  get_script_hash_from_address, policy_id_present_in_output,
  policy_id_present_in_outputs, single_value, verify_tld_signature,
}

// A registrar registers a handshake tld on cardano.
// - 1. RegisterTLD: He puts a `TLDRegisterDatum on chain which consists of the tld, handshake owner public key and a number.
//        The number is the minted amount of tld references tokens which starts with 0.
// - 2. OwnerAction: The tld owner mints tld reference tokens where slds and records are attached.
// - 3. RegistrarAction: A registrar can burn a tld only if all tld reference tokens are burned.

// Token naming scheme:
// - Registration token: policy_id = this script hash, asset_name = tld_reference_policy_id
// - Proves a TLD has been registered and tracks reference token count via datum
//
// INVARIANT: minted field must equal number of TLD reference tokens in circulation
// INVARIANT: TLD can only be deregistered when minted == 0 (all references burned)

validator tld_registrar(
  registrar_nft_policy_id: PolicyId,
  stake_cred: StakeCredential,
) {
  spend(
    datum_opt: Option<TLDRegisterDatum>,
    redeemer: RegistrarRedeemer,
    output_reference: OutputReference,
    tx: Transaction,
  ) {
    when redeemer is {
      RegistrarAction -> {
        expect Some(TLDRegisterDatum { minted, .. }) = datum_opt
        let Transaction { inputs, outputs, .. } = tx
        let own_input = find_input_output(inputs, output_reference)
        let own_policy_id = get_script_hash_from_address(own_input.address)
        let onw_input_token = policy_id_present_in_output(
          own_input,
          own_policy_id,
        )
        // only registrar can remove tld references -> and unlock hns tld
        let has_registrar_nft = policy_id_present_in_outputs(
          outputs,
          registrar_nft_policy_id,
        )

        // no tld registration tokens in outputs -> are burned
        let no_own_token_output = !policy_id_present_in_outputs(
          outputs,
          own_policy_id,
        )
        // all tld tokens must be removed before reference can be removed
        let tld_reference_burned = minted == 0
        onw_input_token? && tld_reference_burned? && has_registrar_nft? && no_own_token_output?
      }

      OwnerAction { owner_signature, receiver_address } -> {
        expect Some(TLDRegisterDatum { tld, owner_hns_key, minted }) = datum_opt
        let Transaction { inputs, outputs, mint, .. } = tx
        // Owner can mint/burn TLD reference tokens without registrar approval
        // First mint requires Handshake signature, subsequent mints only need user token
        let own_input = find_input_output(inputs, output_reference)
        let own_address = own_input.address
        let own_policy_id = get_script_hash_from_address(own_address)
        let tld_reference_policy_id = get_asset_name(
          own_input.value,
          own_policy_id,
        )
        let tld_r_tn = create_reference_token_tn(tld)
        // tld reference tokens minted or burned
        let tld_reference_mint_am = quantity_of(
          mint,
          tld_reference_policy_id,
          tld_r_tn,
        )
        // handshake tld owner has to sign to mint first tld token
        let has_owner_signed = if minted == 0 {
          verify_tld_signature(
            owner_hns_key,
            append_bytearray(
              append_bytearray(tld, serialise_data(receiver_address)),
              serialise_data(output_reference),
            ),
            owner_signature,
          ) && // pin the newly minted "u" token to the signed destination          
          any(
            outputs,
            fn(o) {
              any_native_value(
                o.value,
                tld_reference_policy_id,
                create_user_token_tn(tld),
              )? && (o.address == receiver_address)?
            },
          )
        } else {
          True
        }

        // Must mint or burn - zero changes are prohibited to prevent no-op transactions
        expect !(tld_reference_mint_am == 0)
        let registration_datum = InlineDatum(
          TLDRegisterDatum(tld, owner_hns_key, minted + tld_reference_mint_am),
        )
        let output_exists = check_output_exist(
          outputs,
          own_policy_id,
          tld_reference_policy_id,
          own_address,
          registration_datum,
        )
        has_owner_signed? && output_exists?
      }

      _ -> fail
    }
  }

  mint(redeemer: RegistrarRedeemer, policy_id: PolicyId, tx: Transaction) {
    when redeemer is {
      RegisterTLD { tld, owner, tld_reference_policy_id } -> {
        let Transaction { outputs, mint, .. } = tx
        let is_single_mint = single_value(
          mint,
          policy_id,
          tld_reference_policy_id,
          1,
        )
        let has_registrar_nft = policy_id_present_in_outputs(
          outputs,
          registrar_nft_policy_id,
        )

        // output to this validator where stake cred provided through parameters
        let own_address = Address(Script(policy_id), Some(stake_cred))
        // tld register start by 0 tld tokens
        let registration_datum = InlineDatum(TLDRegisterDatum(tld, owner, 0))
        let output_exists = check_output_exist(
          outputs,
          policy_id,
          tld_reference_policy_id,
          own_address,
          registration_datum,
        )
        has_registrar_nft? && is_single_mint? && output_exists?
      }
      RegistrarAction { .. } -> {
        let Transaction { mint, .. } = tx
        // no outputs just burning -> registrar auth in spending
        let is_burning = all_burned(mint, policy_id)
        is_burning?
      }
      _ -> fail
    }
  }

  else(_) {
    fail
  }
}
