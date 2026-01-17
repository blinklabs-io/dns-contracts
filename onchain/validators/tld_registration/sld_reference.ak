use aiken/collection/dict.{Dict, get, size}
use aiken/collection/list.{all, any, length}
use aiken/option.{is_none}
use cardano/address.{Address, Script, StakeCredential}
use cardano/assets.{AssetName, PolicyId, quantity_of, tokens}
use cardano/transaction.{Output, OutputReference, Transaction}
use types.{MintSld, SLDReferenceDatum}
use utils.{
  any_native_value, create_reference_token_tn, create_user_token_tn,
  find_input_output, get_asset_name, get_inline_datum_output,
  get_script_hash_from_address, token_in_inputs,
}

// Adding a sld means mitning a token pair. Records can be added/removed/managed.
// Tld is defined by validator parameter `tld_reference_policy_id`. A sld reference tokens
// name is derived by the blake2b_256 hash of "r" + clear string sld. Ownership is proved by
// the same policy with the token name derived by the blake2_256 hash "u" + clear string sld.
// Note: SLD creation/deletion must be coordinated with parent TLD via validate_sld_minting
// - 1. Mint/Burn: Mint/Burn sld token pair 
// - 2. Update: add/remove records

validator sld_reference(
  tld_reference_policy_id: PolicyId,
  stake_cred: StakeCredential,
) {
  spend(
    datum_opt: Option<SLDReferenceDatum>,
    _redeemer: Data,
    output_reference: OutputReference,
    tx: Transaction,
  ) {
    let Transaction { inputs, outputs, mint, .. } = tx
    expect Some(SLDReferenceDatum { tld, sld, .. }) = datum_opt
    let output = find_input_output(inputs, output_reference)
    let own_address = output.address
    let own_policy_id = get_script_hash_from_address(own_address)
    let sld_r_tn = create_reference_token_tn(sld)
    let own_input_token =
      get_asset_name(output.value, own_policy_id) == sld_r_tn
    let user_token_is_present =
      token_in_inputs(inputs, own_policy_id, create_user_token_tn(sld))
    let burn_or_update =
      quantity_of(mint, own_policy_id, sld_r_tn) < 0 || check_output_exist(
        outputs,
        own_policy_id,
        sld,
        tld,
        own_address,
      )
    own_input_token? && user_token_is_present? && burn_or_update?
  }

  mint(redeemer: MintSld, policy_id: PolicyId, tx: Transaction) {
    let MintSld { tld, mint_slds, burn_slds } = redeemer
    let Transaction { inputs, outputs, mint, .. } = tx
    // This redeemer is called by tld_reference when SLDs are added/removed
    // Validates that minted token pairs match the declared mint_slds/burn_slds lists
    let mint_tn_ams = tokens(mint, policy_id)
    let mint_size_correct =
      // token pair so twice the size
      size(mint_tn_ams) == ( length(mint_slds) + length(burn_slds) ) * 2
    let own_address = Address(Script(policy_id), Some(stake_cred))
    let slds_minted =
      all(
        mint_slds,
        fn(sld) {
          check_minting(mint_tn_ams, sld, 1)? && check_output_exist(
            outputs,
            policy_id,
            sld,
            tld,
            own_address,
          )?
        },
      )
    let tld_reference_present =
      token_in_inputs(
        inputs,
        tld_reference_policy_id,
        create_reference_token_tn(tld),
      )
    let slds_burned =
      all(burn_slds, fn(sld) { check_minting(mint_tn_ams, sld, -1) })
    mint_size_correct? && slds_minted? && slds_burned? && tld_reference_present?
  }

  else(_) {
    fail
  }
}

fn check_minting(self: Dict<AssetName, Int>, sld: ByteArray, am: Int) -> Bool {
  (get(self, create_reference_token_tn(sld)) == Some(am))? && (get(
    self,
    create_user_token_tn(sld),
  ) == Some(am))?
}

pub fn check_output_exist(
  outputs: List<Output>,
  policy_id: PolicyId,
  sld: ByteArray,
  tld: ByteArray,
  address: Address,
) -> Bool {
  any(
    outputs,
    fn(output) {
      if any_native_value(
        output.value,
        policy_id,
        create_reference_token_tn(sld),
      )? {
        expect SLDReferenceDatum { tld: tld_dat, sld: sld_dat, .. } =
          get_inline_datum_output(output)
        is_none(output.reference_script)? && (output.address == address)? && (sld_dat == sld)? && (tld_dat == tld)?
      } else {
        False
      }
    },
  )
}
