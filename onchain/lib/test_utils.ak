use aiken/builtin.{blake2b_224, blake2b_256}
use cardano/address.{Address, VerificationKey}
use cardano/assets.{add, from_asset, from_lovelace}
use cardano/transaction.{InlineDatum, NoDatum, Output, OutputReference}
use constants.{
  sld, sld_reference_addr, sld_reference_cs, tld, tld_reference_addr,
  tld_reference_cs, tld_registrar_addr, tld_registrar_cs,
}
use types.{DNSRecord, SLDReferenceDatum, TLDReferenceDatum, TLDRegisterDatum}
use utils.{create_reference_token_tn, create_user_token_tn}

// ### OutputReference
/// Creates an output reference where id is hashed and ix is the index.
pub fn mock_utxo_ref(id: ByteArray, ix: Int) -> OutputReference {
  OutputReference { transaction_id: blake2b_256(id), output_index: ix }
}

// ### Address
/// Mock public key address, where payment part is hashed bytearray, no staking 
pub fn mock_pub_key_address(bytearray: ByteArray) -> Address {
  Address(VerificationKey(blake2b_224(bytearray)), None)
}

pub fn create_tld_registrar_output(owner: ByteArray, int: Int) -> Output {
  Output(
    tld_registrar_addr,
    add(from_lovelace(2_000_000), tld_registrar_cs, tld_reference_cs, 1),
    InlineDatum(TLDRegisterDatum(tld, owner, int)),
    None,
  )
}

pub fn create_tld_reference_output(
  records: List<DNSRecord>,
  slds: List<ByteArray>,
  next: ByteArray,
) -> Output {
  Output(
    tld_reference_addr,
    add(
      from_lovelace(2_000_000),
      tld_reference_cs,
      create_reference_token_tn(tld),
      1,
    ),
    InlineDatum(TLDReferenceDatum(tld, slds, sld_reference_cs, next, records)),
    None,
  )
}

pub const create_tld_user_token_output =
  Output(
    mock_pub_key_address("u"),
    from_asset(tld_reference_cs, create_user_token_tn(tld), 1),
    NoDatum,
    None,
  )

pub fn create_sld_reference_output(sld: ByteArray) -> Output {
  Output(
    sld_reference_addr,
    add(
      from_lovelace(2_000_000),
      sld_reference_cs,
      create_reference_token_tn(sld),
      1,
    ),
    InlineDatum(SLDReferenceDatum(tld, sld, [])),
    None,
  )
}

pub const create_sld_user_token_output =
  Output(
    mock_pub_key_address("u"),
    from_asset(sld_reference_cs, create_user_token_tn(sld), 1),
    NoDatum,
    None,
  )
