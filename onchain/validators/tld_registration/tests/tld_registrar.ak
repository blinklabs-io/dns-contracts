use cardano/assets.{from_asset, merge}
use cardano/transaction.{Input, Transaction, placeholder}
use constants.{
  registrar_nft_cs, stake_cred, tld, tld_owner_signature, tld_owner_vkey,
  tld_reference_cs, tld_registrar_cs,
}
use test_utils.{
  create_registrar_nft_output, create_tld_reference_output,
  create_tld_registrar_output, create_tld_user_token_output,
  mock_pub_key_address, mock_utxo_ref,
}
use tld_registration/tld_reference
use tld_registration/tld_registrar as registrar
use types.{
  InitRemoveReference, OwnerAction, RegisterTLD, RegistrarAction,
  RegistrarRedeemer, TLDReferenceAction, TLDRegisterDatum,
}
use utils.{create_reference_token_tn}

// helper: mint 
fn tld_registrar_mint(red: RegistrarRedeemer, tx: Transaction) -> Bool {
  registrar.tld_registrar.mint(
    registrar_nft_cs,
    stake_cred,
    red,
    tld_registrar_cs,
    tx,
  )
}

// constant: mint success transaction
const tld_mint_succeed_tx =
  Transaction {
    ..placeholder,
    outputs: [
      create_tld_registrar_output(tld_owner_vkey, 0),
      create_registrar_nft_output,
    ],
    mint: from_asset(tld_registrar_cs, tld_reference_cs, 1),
  }

// constant: register tld redeemer
const register_red = RegisterTLD(tld, tld_owner_vkey, tld_reference_cs)

test success_tld_mint() {
  tld_registrar_mint(register_red, tld_mint_succeed_tx)
}

test fail_tld_mint_missing_registrar_token() fail {
  tld_registrar_mint(
    register_red,
    Transaction {
      ..tld_mint_succeed_tx,
      outputs: [create_tld_registrar_output(tld_owner_vkey, 0)],
    },
  )
}

test fail_tld_mint_mint() fail {
  tld_registrar_mint(
    register_red,
    Transaction {
      ..tld_mint_succeed_tx,
      mint: from_asset(tld_registrar_cs, tld, 2),
    },
  )
}

// helper: spend 
fn tld_registrar_spend(
  dat: TLDRegisterDatum,
  red: RegistrarRedeemer,
  tx: Transaction,
) -> Bool {
  registrar.tld_registrar.spend(
    registrar_nft_cs,
    stake_cred,
    Some(dat),
    red,
    mock_utxo_ref("0", 0),
    tx,
  )
}

// constant: spend owner success transaction
const tld_owner_spend_succeed_tx =
  Transaction {
    ..placeholder,
    inputs: [
      Input(
        mock_utxo_ref("0", 0),
        create_tld_registrar_output(tld_owner_vkey, 0),
      ),
    ],
    outputs: [
      create_tld_registrar_output(tld_owner_vkey, 1), create_tld_user_token_output,
    ],
    mint: from_asset(tld_reference_cs, create_reference_token_tn(tld), 1),
  }

// constant: spend owner success 2 transaction
const tld_owner_spend_succeed_tx2 =
  Transaction {
    ..placeholder,
    inputs: [
      Input(
        mock_utxo_ref("0", 0),
        create_tld_registrar_output(tld_owner_vkey, 1),
      ),
    ],
    outputs: [create_tld_registrar_output(tld_owner_vkey, 0)],
    mint: from_asset(tld_reference_cs, create_reference_token_tn(tld), -1),
  }

// constant: tld datum
const tld_dat = TLDRegisterDatum(tld, tld_owner_vkey, 0)

test success_tld_owner_spend1() {
  tld_registrar_spend(
    TLDRegisterDatum(tld, tld_owner_vkey, 1),
    OwnerAction("", mock_pub_key_address("u")),
    tld_owner_spend_succeed_tx2,
  )
}

// signature over blake2b_256(tld ++ serialise_data(receiver_address) ++
// serialise_data(output_reference)), with receiver_address =
// mock_pub_key_address("u") and output_reference = mock_utxo_ref("0", 0)
// (the fixed output_reference tld_registrar_spend always passes)
const owner_action_vkey =
  #"0272944b78c9c229cea12a5781602fa3c29e49d71031d44be1575aae4e47832bfe"

const owner_action_signature =
  #"7a93f21fd0b43c576dc0fee6383af1258c68caac7e1c8a854c33f8fa66d61048703356da111403169d7f7644c1a5ff73a397064e45a364268074378159429ce5"

test success_tld_owner_spend2() {
  tld_registrar_spend(
    TLDRegisterDatum(tld, owner_action_vkey, 0),
    OwnerAction(owner_action_signature, mock_pub_key_address("u")),
    Transaction {
      ..tld_owner_spend_succeed_tx,
      outputs: [
        create_tld_registrar_output(owner_action_vkey, 1),
        create_tld_user_token_output,
      ],
    },
  )
}

test fail_owner_action_wrong_destination() fail {
  tld_registrar_spend(
    TLDRegisterDatum(tld, owner_action_vkey, 0),
    OwnerAction(owner_action_signature, mock_pub_key_address("someone_else")),
    Transaction {
      ..tld_owner_spend_succeed_tx,
      outputs: [
        create_tld_registrar_output(owner_action_vkey, 1),
        create_tld_user_token_output,
      ],
    },
  )
}

test fail_owner_action_missing_user_token_output() fail {
  tld_registrar_spend(
    TLDRegisterDatum(tld, owner_action_vkey, 0),
    OwnerAction(owner_action_signature, mock_pub_key_address("u")),
    Transaction {
      ..tld_owner_spend_succeed_tx,
      outputs: [create_tld_registrar_output(owner_action_vkey, 1)],
    },
  )
}

test fail_owner_action_replayed_signature_new_outref() fail {
  registrar.tld_registrar.spend(
    registrar_nft_cs,
    stake_cred,
    Some(TLDRegisterDatum(tld, owner_action_vkey, 0)),
    OwnerAction(owner_action_signature, mock_pub_key_address("u")),
    mock_utxo_ref("1", 0),
    Transaction {
      ..tld_owner_spend_succeed_tx,
      inputs: [
        Input(
          mock_utxo_ref("1", 0),
          create_tld_registrar_output(owner_action_vkey, 0),
        ),
      ],
      outputs: [
        create_tld_registrar_output(owner_action_vkey, 1),
        create_tld_user_token_output,
      ],
    },
  )
}

// helper: tld_reference mint
fn tld_reference_mint(red: TLDReferenceAction, tx: Transaction) -> Bool {
  tld_reference.tld_reference.mint(
    tld_registrar_cs,
    stake_cred,
    red,
    tld_reference_cs,
    tx,
  )
}

// constant: a minted==0 OwnerAction tx that mints -1 of the reference token
// instead of +1. OwnerAction itself does not check the sign/magnitude of
// tld_reference_mint_am, only that it's non-zero.
const owner_action_negative_minted_tx =
  Transaction {
    ..placeholder,
    inputs: [
      Input(
        mock_utxo_ref("0", 0),
        create_tld_registrar_output(owner_action_vkey, 0),
      ),
    ],
    outputs: [
      create_tld_registrar_output(owner_action_vkey, -1),
      create_tld_user_token_output,
      create_tld_reference_output([], [], ""),
    ],
    mint: from_asset(tld_reference_cs, create_reference_token_tn(tld), -1),
  }

test success_owner_action_alone_allows_negative_minted() {
  tld_registrar_spend(
    TLDRegisterDatum(tld, owner_action_vkey, 0),
    OwnerAction(owner_action_signature, mock_pub_key_address("u")),
    owner_action_negative_minted_tx,
  )
}

test fail_owner_action_negative_minted_rejected_by_tld_reference() fail {
  tld_registrar_spend(
    TLDRegisterDatum(tld, owner_action_vkey, 0),
    OwnerAction(owner_action_signature, mock_pub_key_address("u")),
    owner_action_negative_minted_tx,
  ) && tld_reference_mint(InitRemoveReference, owner_action_negative_minted_tx)
}

// constant: burn tld success transaction
const tld_burn_succeed_tx =
  Transaction {
    ..placeholder,
    inputs: [
      Input(
        mock_utxo_ref("0", 0),
        create_tld_registrar_output(tld_owner_vkey, 1),
      ),
    ],
    outputs: [create_registrar_nft_output],
    mint: from_asset(tld_registrar_cs, tld_reference_cs, -1),
  }

test success_tld_burn() {
  tld_registrar_spend(tld_dat, RegistrarAction, tld_burn_succeed_tx) && tld_registrar_mint(
    RegistrarAction,
    tld_burn_succeed_tx,
  )
}

test fail_tld_burn_own_in_token() fail {
  tld_registrar_spend(
    TLDRegisterDatum("tld", tld_owner_vkey, 1),
    RegistrarAction,
    tld_burn_succeed_tx,
  ) && tld_registrar_mint(register_red, tld_burn_succeed_tx)
}

test fail_tld_burn_registrar_signer() fail {
  tld_registrar_spend(tld_dat, RegistrarAction, tld_burn_succeed_tx) && tld_registrar_mint(
    RegisterTLD(tld, tld_owner_vkey, tld_reference_cs),
    tld_burn_succeed_tx,
  )
}

test fail_tld_burn_output() fail {
  let tx = Transaction {
    ..tld_burn_succeed_tx,
    outputs: [create_tld_registrar_output(tld_owner_signature, 1)],
  }
  tld_registrar_spend(tld_dat, RegistrarAction, tx) && tld_registrar_mint(
    register_red,
    tx,
  )
}

test fail_tld_burn_mint() fail {
  let tx = Transaction {
    ..tld_burn_succeed_tx,
    mint: merge(
      from_asset(tld_registrar_cs, tld, -1),
      from_asset(tld_registrar_cs, "tld", 1),
    ),
  }
  tld_registrar_spend(tld_dat, RegistrarAction, tx) && tld_registrar_mint(
    register_red,
    tx,
  )
}

test fail_tld_burn_missing_registrar_token() fail {
  let tx = Transaction { ..tld_burn_succeed_tx, outputs: [] }
  tld_registrar_spend(tld_dat, RegistrarAction, tx) && tld_registrar_mint(
    RegistrarAction,
    tx,
  )
}
