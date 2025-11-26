#!/bin/bash

source env.sh

raw=$TX_PATH/01-init-system.raw
signed=$TX_PATH/01-init-system.sign

USER=$1
USER_ADDR=$(cat $WALLET_PATH/$USER.addr)
REF_ADDR=$(cat $WALLET_PATH/reference.addr)

UTXO_IN=$(get_address_biggest_lovelace $USER_ADDR)
echo "UTXO_IN: $UTXO_IN"

cardano-cli conway transaction build \
    --testnet-magic ${TESTNET_MAGIC} \
    --change-address $USER_ADDR \
    --tx-in $UTXO_IN \
    --tx-in-collateral $UTXO_IN \
    --tx-out $REF_ADDR+8770850 \
    --tx-out-reference-script-file $Validator_Path/tld_registrar.plutus \
    --tx-out $REF_ADDR+19981160 \
    --tx-out-reference-script-file $Validator_Path/tld_reference.plutus \
    --tx-out $REF_ADDR+8370020 \
    --tx-out-reference-script-file $Validator_Path/sld_reference.plutus \
    --out-file $raw 

cardano-cli conway transaction sign \
    --testnet-magic ${TESTNET_MAGIC} \
    --tx-body-file $raw \
    --out-file $signed \
    --signing-key-file $WALLET_PATH/$USER.skey

cardano-cli conway transaction submit \
    --testnet-magic ${TESTNET_MAGIC} \
    --tx-file $signed

tx_submitted $signed $REF_ADDR