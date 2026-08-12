use aiken/collection/list.{any}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use utils.{single_value}

validator registrar_token(output_reference: OutputReference) {
  mint(redeemer: AssetName, policy_id: PolicyId, tx: Transaction) {
    let Transaction { inputs, mint, .. } = tx
    any(inputs, fn(input) { input.output_reference == output_reference })? && single_value(
      mint,
      policy_id,
      redeemer,
      1,
    )? || single_value(mint, policy_id, redeemer, -1)?
  }

  else(_) {
    fail
  }
}
