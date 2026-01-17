use aiken/builtin.{head_list, tail_list, un_b_data, un_i_data, unconstr_fields}
use aiken/collection/dict.{get, is_empty, size}
use aiken/collection/list.{any, concat, difference, foldl, push, sort, unique}
use aiken/option.{is_none}
use aiken/primitive/bytearray.{compare}
use cardano/address.{Address, Script, StakeCredential}
use cardano/assets.{PolicyId, Value, quantity_of, tokens}
use cardano/transaction.{
  Input, Mint, Output, OutputReference, Redeemer, ScriptPurpose, Transaction,
}
use types.{
  BurnReference, InitRemoveReference, MintAdditionalReference, MintSld,
  SpendReference, TLDReferenceAction, TLDReferenceDatum,
}
use utils.{
  create_reference_token_tn, create_user_token_tn, filter_input_with_token,
  filter_single_token_in_outputs, find_input_output, get_asset_name,
  get_inline_datum_output, get_script_hash_from_address, single_value,
  token_in_inputs, two_token_value,
}

// A handshake tld is registered on cardano. Slds and records can be added/removed/managed.
// A tld reference tokens name is derived by the blake2b_256 hash of "r" + clear string tld. 
// Ownership is proved by the same policy with the token name derived by the blake2_256 hash
// "u" + clear string tld.
// - 1. InitRemoveReference: Initialise tld reference. Mint tld reference pair ("u" + "r" token)
// - 2. SpendReference: UpdateTLDReferenceDatum, add/remove slds or records
// - 3. MintAdditionalReference: Add additional tld "r" token to add additional datum space.
//        Linked through sld names in lexicographical order.
// - 4. BurnReference: Remove "r" token.
// - 5. InitRemoveReference: Remove last tld reference, needed to get handshake tld back.

// Every sld added/removed is combined with a sld reference token minting.

// Linked List Structure:
// - Each TLD reference UTxO contains a subset of SLDs in lexicographical order
// - 'next' field points to the first SLD in the next UTxO (or "" if last)
// - Example: UTxO1 [a,b,c] next="d" → UTxO2 [d,e,f] next=""
//
// INVARIANT: slds must be sorted lexicographically and unique within each UTxO
// INVARIANT: next field must maintain linked list integrity across split/merge operations

validator tld_reference(
  tld_registrar_policy_id: PolicyId,
  stake_cred: StakeCredential,
) {
  spend(
    datum_opt: Option<TLDReferenceDatum>,
    redeemer: TLDReferenceAction,
    output_reference: OutputReference,
    tx: Transaction,
  ) {
    when redeemer is {
      SpendReference -> {
        let Transaction { inputs, outputs, mint, redeemers, .. } = tx
        expect Some(TLDReferenceDatum {
          tld,
          slds,
          next,
          sld_reference_policy_id,
          ..
        }) = datum_opt
        let output = find_input_output(inputs, output_reference)
        let own_address = output.address
        let own_policy_id = get_script_hash_from_address(own_address)
        let tld_r_tn = create_reference_token_tn(tld)
        let own_input_token =
          get_asset_name(output.value, own_policy_id) == tld_r_tn
        // ownership prove by having "u" token
        let user_token_is_present =
          token_in_inputs(inputs, own_policy_id, create_user_token_tn(tld))
        let is_minting = !(quantity_of(mint, own_policy_id, tld_r_tn) == 0)?
        // skip validation if minting purpose present otherwise valdiate adding/removing slds and output
        let output_valid =
          if is_minting {
            True
          } else {
            // one output expected
            expect [own_output] =
              filter_single_token_in_outputs(outputs, own_policy_id, tld_r_tn)
            expect TLDReferenceDatum {
              tld: tld_new,
              slds: slds_new,
              next: next_new,
              sld_reference_policy_id: sld_reference_policy_id_new,
              ..
            } = get_inline_datum_output(own_output)
            let output_datum_correct =
              (next_new == next)? && (tld_new == tld)? && slds_sort_unique(
                slds_new,
              )? && sld_reference_policy_id == sld_reference_policy_id_new
            let slds_minted =
              validate_sld_minting(
                mint,
                slds,
                slds_new,
                tld,
                redeemers,
                sld_reference_policy_id,
              )
            let output_is_correct =
              two_token_value(own_output.value)? && is_none(
                own_output.reference_script,
              )? && (own_output.address == own_address)? && output_datum_correct?
            output_is_correct? && slds_minted?
          }

        own_input_token? && user_token_is_present? && output_valid?
      }

      _ -> fail
    }
  }

  mint(redeemer: TLDReferenceAction, policy_id: PolicyId, tx: Transaction) {
    when redeemer is {
      InitRemoveReference -> {
        let Transaction { inputs, outputs, mint, .. } = tx
        // get tld registration utxo -> tld amount validation
        let (tld, minted) =
          get_tld_reference_datum(inputs, tld_registrar_policy_id, policy_id)
        let tld_r_tn = create_reference_token_tn(tld)
        // either minting or burning tld reference token pair
        if minted == 0 {
          expect [own_output] =
            filter_single_token_in_outputs(outputs, policy_id, tld_r_tn)
          expect TLDReferenceDatum { tld: tld_ref, slds, next, .. } =
            get_inline_datum_output(own_output)
          // valdiate init datum
          let output_datum_correct =
            (next == "")? && (tld_ref == tld)? && (slds == [])?
          let own_address = Address(Script(policy_id), Some(stake_cred))
          let output_is_correct =
            two_token_value(own_output.value)? && is_none(
              own_output.reference_script,
            )? && (own_output.address == own_address)? && output_datum_correct?
          let correct_mint =
            check_init_minting(mint, policy_id, tld, tld_r_tn, 1)?
          output_is_correct? && correct_mint?
        } else {
          check_init_minting(mint, policy_id, tld, tld_r_tn, -1)?
        }
      }
      MintAdditionalReference -> {
        let Transaction { inputs, outputs, mint, redeemers, .. } = tx
        // Split operation: one input UTxO becomes two output UTxOs
        // Distributes SLDs across outputs while maintaining sorted order and linked list integrity
        // get tld registration utxo -> tld amount validation
        let (tld, minted) =
          get_tld_reference_datum(inputs, tld_registrar_policy_id, policy_id)
        let tld_r_tn = create_reference_token_tn(tld)
        // not more than one tld reference token can be added at a time
        let correct_mint = single_value(mint, policy_id, tld_r_tn, 1)
        // first mint -> InitRemoveReference
        let not_first = !(minted == 0)?
        // not more than input
        expect [Input { output: own_input, .. }] =
          filter_input_with_token(inputs, policy_id, tld_r_tn)
        // Records are not validated here - they're stored in the datum but don't affect token logic
        expect TLDReferenceDatum {
          tld: tld_own,
          slds,
          sld_reference_policy_id,
          ..
        } = get_inline_datum_output(own_input)
        let own_address = Address(Script(policy_id), Some(stake_cred))
        // validate outputs and return datum -> exactly two
        expect [own_output_dat1,
          own_output_dat2] =
          foldl(
            outputs,
            [],
            fn(output, all) {
              if get_asset_name(output.value, policy_id) == tld_r_tn {
                if two_token_value(output.value)? && is_none(
                  output.reference_script,
                )? && (output.address == own_address)? {
                  expect dat: TLDReferenceDatum =
                    get_inline_datum_output(output)
                  push(all, dat)
                } else {
                  fail
                }
              } else {
                all
              }
            },
          )
        let tld_is_same = tld_own == tld
        let all_new_slds = concat(own_output_dat1.slds, own_output_dat2.slds)
        let slds_minted =
          validate_sld_minting(
            mint,
            slds,
            all_new_slds,
            tld,
            redeemers,
            sld_reference_policy_id,
          )
        let all_slds_still_exist =
          slds_sort_unique(own_output_dat1.slds)? && slds_sort_unique(
            own_output_dat2.slds,
          )
        // first and last next are same as before to keep linked list in tact
        let next_is_set =
          // One output must be "first" (next points to other output's first SLD)
          // Other output must be "last" (inherits the original next pointer)
          if own_output_dat1.next == "" {
            head_list(own_output_dat1.slds) == own_output_dat2.next
          } else {
            own_output_dat2.next == "" && head_list(own_output_dat2.slds) == own_output_dat1.next
          }

        correct_mint? && not_first? && tld_is_same? && all_slds_still_exist? && next_is_set? && slds_minted?
      }

      BurnReference -> {
        let Transaction { inputs, outputs, mint, redeemers, .. } = tx
        // Merge operation: two input UTxOs become one output UTxO
        // Combines SLDs from both inputs while preserving linked list connections
        // get tld registration utxo -> tld amount validation
        let (tld, minted) =
          get_tld_reference_datum(inputs, tld_registrar_policy_id, policy_id)
        let tld_r_tn = create_reference_token_tn(tld)
        // exactly two tld reference token inputs
        expect [
          Input { output: own_input1, .. },
          Input { output: own_input2, .. },
        ] = filter_input_with_token(inputs, policy_id, tld_r_tn)
        expect own_input_dat1: TLDReferenceDatum =
          get_inline_datum_output(own_input1)
        expect own_input_dat2: TLDReferenceDatum =
          get_inline_datum_output(own_input2)
        let own_address = Address(Script(policy_id), Some(stake_cred))
        // exactly 1 tld reference token output
        expect [own_output] =
          filter_single_token_in_outputs(outputs, policy_id, tld_r_tn)
        let own_output_valid =
          two_token_value(own_output.value)? && is_none(
            own_output.reference_script,
          )? && (own_output.address == own_address)?
        // we do not care about records
        expect TLDReferenceDatum {
          tld: tld_new,
          slds,
          next,
          sld_reference_policy_id,
          ..
        } = get_inline_datum_output(own_output)
        let correct_mint = single_value(mint, policy_id, tld_r_tn, -1)
        // last burn -> InitRemoveReference
        let not_last = (minted == 1)?
        // first and last next are same as before to keep linked list in tact
        let tld_same = tld == tld_new
        let next_is_valid =
          if own_input_dat1.next == head_list(own_input_dat2.slds) {
            next == own_input_dat2.next
          } else {
            own_input_dat2.next == head_list(own_input_dat1.slds) && next == own_input_dat1.next
          }
        let all_old_slds = concat(own_input_dat1.slds, own_input_dat2.slds)
        let sld_refs_same =
          own_input_dat1.sld_reference_policy_id == sld_reference_policy_id
        let slds_minted =
          validate_sld_minting(
            mint,
            all_old_slds,
            slds,
            tld,
            redeemers,
            sld_reference_policy_id,
          )
        let all_slds_present = slds_sort_unique(slds)
        correct_mint? && not_last? && own_output_valid? && tld_same? && next_is_valid? && all_slds_present? && slds_minted? && sld_refs_same
      }

      _ -> fail
    }
  }

  else(_) {
    fail
  }
}

// when difference in input and output slds then check minting redeemer present
fn validate_sld_minting(
  mint: Value,
  old_slds: List<ByteArray>,
  new_slds: List<ByteArray>,
  tld_i: ByteArray,
  redeemers: Pairs<ScriptPurpose, Redeemer>,
  sld_reference_policy_id: PolicyId,
) -> Bool {
  let sld_mints = difference(new_slds, old_slds)
  let sld_burns = difference(old_slds, new_slds)
  // no difference -> no minting
  if sld_burns == [] && sld_mints == [] {
    is_empty(tokens(mint, sld_reference_policy_id))?
  } else {
    let mint_red: Redeemer = MintSld(tld_i, sld_mints, sld_burns)
    let mint_purpose = Pair(Mint(sld_reference_policy_id), mint_red)
    any(redeemers, fn(r) { r == mint_purpose })
  }
}

fn check_init_minting(
  mint: Value,
  policy_id: PolicyId,
  tld: ByteArray,
  tld_r_tn: ByteArray,
  am: Int,
) -> Bool {
  let mint_tn_ams = tokens(mint, policy_id)
  (size(mint_tn_ams) == 2)? && (get(mint_tn_ams, tld_r_tn) == Some(am))? && (get(
    mint_tn_ams,
    create_user_token_tn(tld),
  ) == Some(am))?
}

fn get_tld_reference_datum(
  inputs: List<Input>,
  tld_registrar_policy_id: PolicyId,
  policy_id: PolicyId,
) -> (ByteArray, Int) {
  expect [Input { output, .. }] =
    filter_input_with_token(inputs, tld_registrar_policy_id, policy_id)
  let register_fields = unconstr_fields(get_inline_datum_output(output))
  (
    un_b_data(head_list(register_fields)),
    un_i_data(head_list(tail_list(tail_list(register_fields)))),
  )
}

fn slds_sort_unique(self: List<ByteArray>) -> Bool {
  (self == unique(sort(self, compare)))?
}
