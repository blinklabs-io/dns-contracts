#!/bin/bash

source env.sh

raw=$TX_PATH/03-init-system.raw
signed=$TX_PATH/03-init-system.sign

USER=$1
USER_ADDR=$(cat $WALLET_PATH/$USER.addr)
REF_ADDR=$(cat $WALLET_PATH/reference.addr)

UTXO_IN=$(get_address_biggest_lovelace $USER_ADDR)
echo "UTXO_IN: $UTXO_IN"

TLD_ADDR=$(cat $Validator_Path/tld_registrar.addr)
CS_REGISTRAR=$(cardano-cli conway transaction policyid --script-file $Validator_Path/tld_registrar.plutus)
TLD_REF_ADDR=$(cat $Validator_Path/tld_reference.addr)
CS_TLD=$(cardano-cli conway transaction policyid --script-file $Validator_Path/tld_reference.plutus)
CS_SLD=$(cardano-cli conway transaction policyid --script-file $Validator_Path/sld_reference.plutus)

TLD_UTXO_IN=$(get_UTxO_by_token $TLD_ADDR "$CS_REGISTRAR.$CS_TLD")
echo "TLD_UTXO_IN: $TLD_UTXO_IN"

USER_HNS_SIG=$(cat $WALLET_PATH/$USER.hns | jq -r '.signature')
echo "USER_HNS_SIG: $USER_HNS_SIG"

USER_HNS_VKEY=$(cat $WALLET_PATH/$USER.hns | jq -r '.publicKey')
echo "USER_HNS_VKEY: $USER_HNS_VKEY"

TLD_REGISTRAR_REF_TX="ef635b55fce6abc39cd4c843722d9d574cb719114e224f2cd1c8747d5abfc19e#0"
TLD_REFERENCE_REF_TX="ef635b55fce6abc39cd4c843722d9d574cb719114e224f2cd1c8747d5abfc19e#1"

tld_red=$(jq -n --arg sig $USER_HNS_SIG '{
    constructor: 2,
    fields: [
      {bytes: $sig}
    ]
  }')

echo $tld_red > $REDEEMER_PATH/tld_register_owner_action.json
echo "tld_red: $(cat $REDEEMER_PATH/tld_register_owner_action.json | jq)"

tld_register_datum=$(jq -n --arg vkey $USER_HNS_VKEY '{
    constructor: 0,
    fields: [
      {bytes: "68656c6c6f2d68616e647368616b65"},
      {bytes: $vkey},
      {int: 1}
    ]
  }')

echo $tld_register_datum > $DATUM_PATH/tld_register.json
echo "tld_register_datum: $(cat $DATUM_PATH/tld_register.json | jq)"

tld_ref_red=$(jq -n '{
    constructor: 0,
    fields: []
  }')

echo $tld_ref_red > $REDEEMER_PATH/tld_reference_mint.json
echo "tld_ref_red: $(cat $REDEEMER_PATH/tld_reference_mint.json | jq)"

tld_reference_datum=$(jq -n --arg cs "$CS_SLD" '{
    constructor: 0,
    fields: [
      {bytes: "68656c6c6f2d68616e647368616b65"},
      {list: []},
      {bytes: $cs},
      {bytes: ""},
      {list: []}
    ]
  }')

echo $tld_reference_datum > $DATUM_PATH/tld_reference.json
echo "tld_reference_datum: $(cat $DATUM_PATH/tld_reference.json | jq)"

TLD_U_TN=$(create_user_token_tn "hello-handshake")
TLD_R_TN=$(create_reference_token_tn "hello-handshake" )

echo "user: $TLD_U_TN"
echo "reference: $TLD_R_TN"

cardano-cli conway transaction build \
    --testnet-magic ${TESTNET_MAGIC} \
    --change-address $USER_ADDR \
    --tx-in $UTXO_IN \
    --tx-in-collateral $UTXO_IN \
    --tx-in $TLD_UTXO_IN \
    --spending-tx-in-reference $TLD_REGISTRAR_REF_TX \
    --spending-plutus-script-v3 \
    --spending-reference-tx-in-inline-datum-present \
    --spending-reference-tx-in-redeemer-file $REDEEMER_PATH/tld_register_owner_action.json \
    --tx-out $TLD_ADDR+1525740+"1 $CS_REGISTRAR.$CS_TLD" \
    --tx-out-inline-datum-file $DATUM_PATH/tld_register.json \
    --mint "1 $CS_TLD.$TLD_U_TN + 1 $CS_TLD.$TLD_R_TN" \
    --mint-tx-in-reference $TLD_REFERENCE_REF_TX \
    --mint-plutus-script-v3 \
    --mint-reference-tx-in-redeemer-file $REDEEMER_PATH/tld_reference_mint.json \
    --policy-id $CS_TLD \
    --tx-out $TLD_REF_ADDR+1530050+"1 $CS_TLD.$TLD_R_TN" \
    --tx-out-inline-datum-file $DATUM_PATH/tld_reference.json \
    --tx-out $USER_ADDR+2000000+"1 $CS_TLD.$TLD_U_TN" \
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