#!/bin/bash

source env.sh

raw=$TX_PATH/02-init-system.raw
signed=$TX_PATH/02-init-system.sign

USER=$1
USER_ADDR=$(cat $WALLET_PATH/$USER.addr)
REF_ADDR=$(cat $WALLET_PATH/reference.addr)

UTXO_IN=$(get_address_biggest_lovelace $USER_ADDR)
echo "UTXO_IN: $UTXO_IN"

CS_REGISTRAR=$(cardano-cli conway transaction policyid --script-file $Validator_Path/tld_registrar.plutus)
CS_TLD=$(cardano-cli conway transaction policyid --script-file $Validator_Path/tld_reference.plutus)

TLD_REGISTRAR_REF_TX="ef635b55fce6abc39cd4c843722d9d574cb719114e224f2cd1c8747d5abfc19e#0"
TLD_REFERENCE_REF_TX="ef635b55fce6abc39cd4c843722d9d574cb719114e224f2cd1c8747d5abfc19e#1"
SLD_REFERENCE_REF_TX="ef635b55fce6abc39cd4c843722d9d574cb719114e224f2cd1c8747d5abfc19e#2"

OWNER_HNS_VKEY=$(cat $WALLET_PATH/owner1.hns | jq -r '.publicKey')
echo "OWNER_HNS_VKEY: $OWNER_HNS_VKEY"

mint_red=$(jq -n --arg vkey "$OWNER_HNS_VKEY" --arg ref_cs "$CS_TLD" '{
    constructor: 0,
    fields: [
      {bytes: "68656c6c6f2d68616e647368616b65"},
      {bytes: $vkey},
      {bytes: $ref_cs}
    ]
  }')

echo $mint_red > $REDEEMER_PATH/tld_register.json
echo "mint_red: $(cat $REDEEMER_PATH/tld_register.json | jq)"

tld_register_datum=$(jq -n --arg vkey $OWNER_HNS_VKEY '{
    constructor: 0,
    fields: [
      {bytes: "68656c6c6f2d68616e647368616b65"},
      {bytes: $vkey},
      {int: 0}
    ]
  }')

echo $tld_register_datum > $DATUM_PATH/tld_register.json
echo "tld_register_datum: $(cat $DATUM_PATH/tld_register.json | jq)"

cardano-cli conway transaction build \
    --testnet-magic ${TESTNET_MAGIC} \
    --change-address $USER_ADDR \
    --tx-in $UTXO_IN \
    --tx-in-collateral $UTXO_IN \
    --mint "1 $CS_REGISTRAR.$CS_TLD" \
    --mint-tx-in-reference $TLD_REGISTRAR_REF_TX \
    --mint-plutus-script-v3 \
    --mint-reference-tx-in-redeemer-file $REDEEMER_PATH/tld_register.json \
    --policy-id $CS_REGISTRAR \
    --tx-out $(cat $Validator_Path/tld_registrar.addr)+1525740+"1 $CS_REGISTRAR.$CS_TLD" \
    --tx-out-inline-datum-file $DATUM_PATH/tld_register.json \
    --out-file $raw

cardano-cli conway transaction sign \
    --testnet-magic ${TESTNET_MAGIC} \
    --tx-body-file $raw \
    --out-file $signed \
    --signing-key-file $WALLET_PATH/$USER.skey

cardano-cli conway transaction submit \
    --testnet-magic ${TESTNET_MAGIC} \
    --tx-file $signed

tx_submitted $signed $(cat $Validator_Path/tld_registrar.addr)