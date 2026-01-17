use aiken/collection/list.{concat, map, sort}
use aiken/primitive/bytearray.{compare}
use cardano/assets.{from_asset_list}
use cardano/transaction.{Input, Transaction, placeholder}
use constants.{sld, sld_reference_cs, stake_cred, tld, tld_reference_cs}
use test_utils.{
  create_sld_reference_output, create_sld_user_token_output,
  create_tld_reference_output, mock_utxo_ref,
}
use tld_registration/sld_reference
use types.{MintSld, SLDReferenceDatum}
use utils.{create_reference_token_tn, create_user_token_tn}

// helper: mint sld reference
fn sld_mint(red: MintSld, tx: Transaction) -> Bool {
  sld_reference.sld_reference.mint(
    tld_reference_cs,
    stake_cred,
    red,
    sld_reference_cs,
    tx,
  )
}

// helper: create basic mint succeed context
fn sld_mint_succeed_tx(m: List<ByteArray>, b: List<ByteArray>) -> Transaction {
  let to_mint = map(m, fn(m1) { Pair(create_reference_token_tn(m1), 1) })
  let to_burn = map(b, fn(b1) { Pair(create_reference_token_tn(b1), -1) })
  let to_mint_u = map(m, fn(m1) { Pair(create_user_token_tn(m1), 1) })
  let to_burn_u = map(b, fn(b1) { Pair(create_user_token_tn(b1), -1) })
  let tn_ams = concat(concat(concat(to_mint, to_burn), to_mint_u), to_burn_u)
  Transaction {
    ..placeholder,
    inputs: [
      Input(mock_utxo_ref("1", 1), create_tld_reference_output([], [], "")),
    ],
    outputs: map(m, fn(m1) { create_sld_reference_output(m1) }),
    mint: from_asset_list(
      [
        Pair(
          sld_reference_cs,
          sort(tn_ams, fn(Pair(n1, _m), Pair(n2, _m)) { compare(n1, n2) }),
        ),
      ],
    ),
  }
}

// sld minting
test success_sld_mint() {
  let m_slds = ["a", "b", "c"]
  let b_slds = ["d", "e", "f"]
  let red = MintSld(tld, m_slds, b_slds)
  sld_mint(red, sld_mint_succeed_tx(m_slds, b_slds))
}

test fail_sld_mint_missing_tld_input() fail {
  let m_slds = ["a", "b", "c"]
  let b_slds = ["d", "e", "f"]
  let red = MintSld(tld, m_slds, b_slds)
  sld_mint(
    red,
    Transaction { ..sld_mint_succeed_tx(m_slds, b_slds), inputs: [] },
  )
}

// helper: spend sld reference
fn sld_spend(dat: SLDReferenceDatum, tx: Transaction) -> Bool {
  let red: Data = ""
  sld_reference.sld_reference.spend(
    tld_reference_cs,
    stake_cred,
    Some(dat),
    red,
    mock_utxo_ref("0", 0),
    tx,
  )
}

// helper: create basic update sld context
fn sld_spend_update_tx(sld: ByteArray) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [
      Input(mock_utxo_ref("0", 0), create_sld_reference_output(sld)),
      Input(mock_utxo_ref("3", 3), create_sld_user_token_output),
    ],
    outputs: [create_sld_reference_output(sld)],
  }
}

test success_sld_spend_update() {
  let sld_reference_datum = SLDReferenceDatum(tld, sld, [])
  sld_spend(sld_reference_datum, sld_spend_update_tx(sld))
}

test fail_sld_spend_update_sld_missmatch() fail {
  let sld_reference_datum = SLDReferenceDatum(tld, sld, [])
  sld_spend(sld_reference_datum, sld_spend_update_tx("wrong_sld"))
}

// helper: create simple spend burn context
fn sld_burn_mint_spend_tx(m: List<ByteArray>, b: List<ByteArray>) -> Transaction {
  let to_mint = map(m, fn(m1) { Pair(create_reference_token_tn(m1), 1) })
  let to_burn = map(b, fn(b1) { Pair(create_reference_token_tn(b1), -1) })
  let to_mint_u = map(m, fn(m1) { Pair(create_user_token_tn(m1), 1) })
  let to_burn_u = map(b, fn(b1) { Pair(create_user_token_tn(b1), -1) })
  let tn_ams = concat(concat(concat(to_mint, to_burn), to_mint_u), to_burn_u)
  Transaction {
    ..placeholder,
    inputs: [
      Input(mock_utxo_ref("3", 3), create_sld_user_token_output),
      Input(mock_utxo_ref("0", 0), create_sld_reference_output(sld)),
      Input(mock_utxo_ref("1", 1), create_tld_reference_output([], [], "")),
    ],
    outputs: map(m, fn(m1) { create_sld_reference_output(m1) }),
    mint: from_asset_list(
      [
        Pair(
          sld_reference_cs,
          sort(tn_ams, fn(Pair(n1, _m), Pair(n2, _m)) { compare(n1, n2) }),
        ),
      ],
    ),
  }
}

test success_sld_burn_mint_spend() {
  let sld_reference_datum = SLDReferenceDatum(tld, sld, [])
  let m_slds = ["a", "b", "c"]
  let b_slds = ["d", "e", "f", sld]
  let red = MintSld(tld, m_slds, b_slds)
  let tx = sld_burn_mint_spend_tx(m_slds, b_slds)
  sld_spend(sld_reference_datum, tx) && sld_mint(red, tx)
}

test fail_sld_burn_mint_spend() fail {
  let sld_reference_datum = SLDReferenceDatum(tld, sld, [])
  let m_slds = ["a", "b", "c"]
  let b_slds = ["d", "e", "f", sld]
  let red = MintSld(tld, m_slds, b_slds)
  let tx = sld_burn_mint_spend_tx(m_slds, m_slds)
  sld_spend(sld_reference_datum, tx) && sld_mint(red, tx)
}
