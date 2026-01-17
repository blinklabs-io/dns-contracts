use cardano/assets.{from_asset, merge}
use cardano/transaction.{Input, Transaction, placeholder}
use constants.{
  registrar_hns_vkey, registrar_signature, stake_cred, tld, tld_owner_signature,
  tld_owner_vkey, tld_reference_cs, tld_registrar_cs,
}
use test_utils.{create_tld_registrar_output, mock_utxo_ref}
use tld_registration/tld_registrar as registrar
use types.{
  OwnerAction, RegisterTLD, RegistrarAction, RegistrarRedeemer, TLDRegisterDatum,
}
use utils.{create_reference_token_tn}

// helper: mint 
fn tld_registrar_mint(red: RegistrarRedeemer, tx: Transaction) -> Bool {
  registrar.tld_registrar.mint(
    registrar_hns_vkey,
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
    outputs: [create_tld_registrar_output(tld_owner_vkey, 0)],
    mint: from_asset(tld_registrar_cs, tld_reference_cs, 1),
  }

// constant: register tld redeemer
const register_red =
  RegisterTLD(tld, tld_owner_vkey, registrar_signature, tld_reference_cs)

test success_tld_mint() {
  tld_registrar_mint(register_red, tld_mint_succeed_tx)
}

test fail_tld_mint_registrar_signature() fail {
  tld_registrar_mint(
    RegisterTLD(tld, tld_owner_vkey, tld_owner_signature, tld_reference_cs),
    tld_mint_succeed_tx,
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
    registrar_hns_vkey,
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
    outputs: [create_tld_registrar_output(tld_owner_vkey, 1)],
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
    OwnerAction(""),
    tld_owner_spend_succeed_tx2,
  )
}

test success_tld_owner_spend2() {
  tld_registrar_spend(
    tld_dat,
    OwnerAction(tld_owner_signature),
    tld_owner_spend_succeed_tx,
  )
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
    mint: from_asset(tld_registrar_cs, tld_reference_cs, -1),
  }

test success_tld_burn() {
  tld_registrar_spend(
    tld_dat,
    RegistrarAction(registrar_signature),
    tld_burn_succeed_tx,
  ) && tld_registrar_mint(
    RegistrarAction(registrar_signature),
    tld_burn_succeed_tx,
  )
}

test fail_tld_burn_own_in_token() fail {
  tld_registrar_spend(
    TLDRegisterDatum("tld", tld_owner_vkey, 1),
    RegistrarAction(registrar_signature),
    tld_burn_succeed_tx,
  ) && tld_registrar_mint(register_red, tld_burn_succeed_tx)
}

test fail_tld_burn_registrar_signer() fail {
  tld_registrar_spend(
    tld_dat,
    RegistrarAction(registrar_signature),
    tld_burn_succeed_tx,
  ) && tld_registrar_mint(
    RegisterTLD(tld, tld_owner_vkey, tld_owner_signature, tld_reference_cs),
    tld_burn_succeed_tx,
  )
}

test fail_tld_burn_output() fail {
  let tx =
    Transaction {
      ..tld_burn_succeed_tx,
      outputs: [create_tld_registrar_output(tld_owner_signature, 1)],
    }
  tld_registrar_spend(tld_dat, RegistrarAction(registrar_signature), tx) && tld_registrar_mint(
    register_red,
    tx,
  )
}

test fail_tld_burn_mint() fail {
  let tx =
    Transaction {
      ..tld_burn_succeed_tx,
      mint: merge(
        from_asset(tld_registrar_cs, tld, -1),
        from_asset(tld_registrar_cs, "tld", 1),
      ),
    }
  tld_registrar_spend(tld_dat, RegistrarAction(registrar_signature), tx) && tld_registrar_mint(
    register_red,
    tx,
  )
}
