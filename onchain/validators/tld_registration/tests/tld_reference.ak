use cardano/assets.{add, from_asset}
use cardano/transaction.{Input, Mint, Redeemer, Transaction, placeholder}
use constants.{
  sld_reference_cs, stake_cred, tld, tld_reference_cs, tld_registrar_cs,
}
use test_utils.{
  create_tld_reference_output, create_tld_registrar_output,
  create_tld_user_token_output, mock_utxo_ref,
}
use tld_registration/tld_reference
use types.{
  BurnReference, InitRemoveReference, MintAdditionalReference, MintSld,
  SpendReference, TLDReferenceAction, TLDReferenceDatum,
}
use utils.{create_reference_token_tn, create_user_token_tn}

// helper: mint tld reference context
fn tld_reference_mint(red: TLDReferenceAction, tx: Transaction) {
  tld_reference.tld_reference.mint(
    tld_registrar_cs,
    stake_cred,
    red,
    tld_reference_cs,
    tx,
  )
}

// helper: spend tld reference context
fn tld_reference_spend(
  dat: TLDReferenceDatum,
  red: TLDReferenceAction,
  tx: Transaction,
) {
  tld_reference.tld_reference.spend(
    tld_registrar_cs,
    stake_cred,
    Some(dat),
    red,
    mock_utxo_ref("0", 0),
    tx,
  )
}

// constant: initialise tld reference transaction
const init_reference_succeed_tx =
  Transaction {
    ..placeholder,
    inputs: [Input(mock_utxo_ref("0", 2), create_tld_registrar_output("", 0))],
    outputs: [create_tld_reference_output([], [], "")],
    mint: add(
      from_asset(tld_reference_cs, create_reference_token_tn(tld), 1),
      tld_reference_cs,
      create_user_token_tn(tld),
      1,
    ),
  }

test success_tld_reference_mint() {
  tld_reference_mint(InitRemoveReference, init_reference_succeed_tx)
}

// constant: spend tld reference success transaction
const tld_reference_spend_simple_succeed = {
    let mint_red: Redeemer = MintSld(tld, ["a", "b", "c"], [])
    Transaction {
      ..placeholder,
      inputs: [
        Input(mock_utxo_ref("0", 0), create_tld_reference_output([], [], "")),
        Input(mock_utxo_ref("12", 12), create_tld_user_token_output),
      ],
      outputs: [create_tld_reference_output([], ["a", "b", "c"], "")],
      redeemers: [Pair(Mint(sld_reference_cs), mint_red)],
      mint: from_asset(sld_reference_cs, "a", 1),
    }
  }

test success_tld_reference_spend_update() {
  tld_reference_spend(
    TLDReferenceDatum(tld, [], sld_reference_cs, "", []),
    SpendReference,
    tld_reference_spend_simple_succeed,
  )
}

// helper: create mint additional tld reference succed transaction
fn tld_reference_mint_additional_succeed_tx() {
  Transaction {
    ..placeholder,
    inputs: [
      Input(
        mock_utxo_ref("0", 0),
        create_tld_reference_output([], ["a", "b", "c"], ""),
      ),
      Input(mock_utxo_ref("12", 12), create_tld_user_token_output),
      Input(mock_utxo_ref("0", 2), create_tld_registrar_output("", 1)),
    ],
    outputs: [
      create_tld_reference_output([], ["a", "b"], "c"),
      create_tld_reference_output([], ["c"], ""),
    ],
    mint: from_asset(tld_reference_cs, create_reference_token_tn(tld), 1),
  }
}

test success_tld_reference_spend_mint_update() {
  tld_reference_spend(
    TLDReferenceDatum(tld, [], sld_reference_cs, "", []),
    SpendReference,
    tld_reference_mint_additional_succeed_tx(),
  )? && tld_reference_mint(
    MintAdditionalReference,
    tld_reference_mint_additional_succeed_tx(),
  )?
}

fn tld_reference_remove_additional_succeed_tx() {
  Transaction {
    ..placeholder,
    inputs: [
      Input(
        mock_utxo_ref("0", 0),
        create_tld_reference_output([], ["a", "b"], "c"),
      ),
      Input(mock_utxo_ref("0", 1), create_tld_reference_output([], ["c"], "")),
      Input(mock_utxo_ref("12", 12), create_tld_user_token_output),
      Input(mock_utxo_ref("0", 2), create_tld_registrar_output("", 1)),
    ],
    outputs: [create_tld_reference_output([], ["a", "b", "c"], "")],
    mint: from_asset(tld_reference_cs, create_reference_token_tn(tld), -1),
  }
}

test success_tld_reference_spend_remove_update() {
  tld_reference_spend(
    TLDReferenceDatum(tld, [], sld_reference_cs, "", []),
    SpendReference,
    tld_reference_remove_additional_succeed_tx(),
  ) && tld_reference_mint(
    BurnReference,
    tld_reference_remove_additional_succeed_tx(),
  )
}

const burn_remove_succeed_tx =
  Transaction {
    ..placeholder,
    inputs: [
      Input(
        mock_utxo_ref("0", 0),
        create_tld_reference_output([], ["a", "b"], "c"),
      ),
      Input(mock_utxo_ref("0", 2), create_tld_registrar_output("", 1)),
      Input(mock_utxo_ref("12", 12), create_tld_user_token_output),
    ],
    mint: add(
      from_asset(tld_reference_cs, create_reference_token_tn(tld), -1),
      tld_reference_cs,
      create_user_token_tn(tld),
      -1,
    ),
  }

test success_tld_reference_burn() {
  tld_reference_spend(
    TLDReferenceDatum(tld, [], sld_reference_cs, "", []),
    SpendReference,
    burn_remove_succeed_tx,
  ) && tld_reference_mint(InitRemoveReference, burn_remove_succeed_tx)
}
