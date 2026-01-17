use aiken/builtin.{
  blake2b_256, fst_pair, head_list, unconstr_fields,
  verify_ecdsa_secp256k1_signature,
}
use aiken/collection/dict.{empty, insert, size, to_pairs}
use aiken/collection/list.{all, any, filter}
use aiken/option.{is_none}
use aiken/primitive/bytearray.{concat}
use cardano/address.{Address, Script}
use cardano/assets.{
  AssetName, PolicyId, Value, policies, to_dict, tokens, without_lovelace,
}
use cardano/transaction.{Datum, Input, Output, OutputReference, find_input}

pub fn create_reference_token_tn(self: ByteArray) -> ByteArray {
  blake2b_256(concat("r", self))
}

pub fn create_user_token_tn(self: ByteArray) -> ByteArray {
  blake2b_256(concat("u", self))
}

pub fn verify_tld_signature(
  verification_key: ByteArray,
  tld: ByteArray,
  signature: ByteArray,
) -> Bool {
  verify_ecdsa_secp256k1_signature(
    verification_key,
    blake2b_256(tld),
    signature,
  )
}

pub fn check_output_exist(
  outputs: List<Output>,
  policy_id: PolicyId,
  tn: AssetName,
  address: Address,
  datum: Datum,
) -> Bool {
  any(
    outputs,
    fn(output) {
      single_value(output.value, policy_id, tn, 1)? && (output.address == address)? && (output.datum == datum)? && is_none(
        output.reference_script,
      )?
    },
  )
}

/// Check if only one token name with a specific policy id is an value with given amount.
/// Useful to check minting values.
pub fn single_value(value: Value, cs: PolicyId, tn: AssetName, am: Int) -> Bool {
  insert(empty, tn, am) == tokens(value, cs)
}

/// Check if only one non ada token with a specific policy id is an value with given amount.
pub fn single_native_value(value: Value, cs: PolicyId, tn: AssetName) -> Bool {
  when
    value
      |> without_lovelace
      |> tokens(cs)
      |> to_pairs
  is {
    [Pair(tnn, _am)] -> tn == tnn
    _ -> False
  }
}

/// Check if only one non ada token with a specific policy id is an value with given amount.
pub fn any_native_value(value: Value, cs: PolicyId, tn: AssetName) -> Bool {
  let tn_am =
    value
      |> tokens(cs)
      |> to_pairs
  any(tn_am, fn(Pair(tnn, _am)) { tnn == tn })
}

pub fn all_burned(mint: Value, policy_id: PolicyId) -> Bool {
  all(to_pairs(tokens(mint, policy_id)), fn(Pair(_, am)) { am < 0 })
}

/// Check there are exactly 2 tokens in a value.
/// Useful to check there is only ada and one native token in a value.
pub fn two_token_value(value: Value) -> Bool {
  when
    value
      |> without_lovelace
      |> to_dict
      |> to_pairs
  is {
    [Pair(_cs, tn_ams)] -> size(tn_ams) == 1
    _ -> False
  }
}

/// Get a token name from a value by policy id
/// use with caution if policy id could have multiple token names
pub fn get_asset_name(value: Value, policy_id: PolicyId) -> AssetName {
  tokens(value, policy_id)
    |> to_pairs
    |> head_list
    |> fst_pair
}

/// Get the script hash of an address. Address must have a script payment part. 
/// Useful if a script is for spending and minting.
/// ```aiken
/// let address = Address(Script("7c9f5b4a2d3e89f04c7a12d3be68a1e7f9bde64321a7fcd8e5a9031b"), None)
/// get_script_hash_from_address(addres) == "7c9f5b4a2d3e89f04c7a12d3be68a1e7f9bde64321a7fcd8e5a9031b"
///```
pub fn get_script_hash_from_address(address: Address) -> ByteArray {
  expect Script(script_hash) = address.payment_credential
  script_hash
}

/// Check if a policy id is present in an output
pub fn policy_id_present_in_output(output: Output, policy_id: PolicyId) -> Bool {
  output.value
    |> policies
    |> any(fn(n) { n == policy_id })
}

/// Check if a policy id is present in a list of outputs
pub fn policy_id_present_in_outputs(
  outputs: List<Output>,
  policy_id: PolicyId,
) -> Bool {
  any(outputs, fn(output) { policy_id_present_in_output(output, policy_id) })
}

/// Check if a policy id is present in a list of outputs
pub fn filter_single_token_in_outputs(
  outputs: List<Output>,
  policy_id: PolicyId,
  tn: AssetName,
) -> List<Output> {
  filter(
    outputs,
    fn(Output { value, .. }) { any_native_value(value, policy_id, tn) },
  )
}

/// Filter for input with native asset
pub fn filter_input_with_token(
  inputs: List<Input>,
  policy_id: PolicyId,
  tn: AssetName,
) -> List<Input> {
  filter(
    inputs,
    fn(input) { any_native_value(input.output.value, policy_id, tn) },
  )
}

// Any input with token?
pub fn token_in_inputs(
  inputs: List<Input>,
  policy_id: PolicyId,
  tn: AssetName,
) -> Bool {
  any(inputs, fn(input) { any_native_value(input.output.value, policy_id, tn) })
}

pub fn get_inline_datum_output(output: Output) -> Data {
  head_list(unconstr_fields(output.datum))
}

pub fn find_input_output(
  inputs: List<Input>,
  output_reference: OutputReference,
) -> Output {
  expect Some(Input { output, .. }) = find_input(inputs, output_reference)
  output
}
