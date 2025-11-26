#!/bin/bash

source env.sh

raw=$TX_PATH/04-init-system.raw
signed=$TX_PATH/04-init-system.sign

USER=$1
SLD=$2
SLD_HEX=$(printf '%s' $SLD | xxd -p)
USER_ADDR=$(cat $WALLET_PATH/$USER.addr)
# wallet holding tld user token
OWNER_ADDR=$(cat $WALLET_PATH/owner1.addr)

# some input utxo
UTXO_IN=$(get_address_biggest_lovelace $USER_ADDR)

# reference token locked in valdiator
#create_reference_token_tn() {
#    local self="$1"
#    echo -n "r${self}" | b2sum -b -l 256 | awk '{print $1}'
#}
# user token held in wallet
#create_user_token_tn() {
#    local self="$1"
#    echo -n "u${self}" | b2sum -b -l 256 | awk '{print $1}'
#}

# token name of tld user token locked at tld reference validator
# fd7a691b56fe270c6672a627c0e202371fb44e03e479dba5a0455aca925468f5
TLD_U_TN=$(create_user_token_tn "hello-handshake")
# token name of tld reference token held in by tld owner
#671102f1a7ff75e55aa1066e593b708425732612ba9330ac035f93b180b0eaf9
TLD_R_TN=$(create_reference_token_tn "hello-handshake")
# token name of sld reference token minted to sld reference valdiator
# ab69124de6a888978b26457a2c8d3389b47bedf49a2ed7ce3dc9b52b1f280539
# blake2b_256 hash of r + <sld>
SLD_U_TN=$(create_user_token_tn $SLD)
# token name of sld user token minted to user wallet (sld owner)
# 39c85ed1b436a3e74e2932aeab5ef602642f9e8580c5ff75f4e74bef3592d11e
# blake2b_256 hash of u + <sld>
SLD_R_TN=$(create_reference_token_tn $SLD)
# tld reference valdiator address
# addr_test1zp55edyd4yv7j29nu5wyvj8s2yex4s2sa255xeuja3axudvxu36kavd5fjg7km4qk6umypqlvq9sa6ghyzhl9k8glg8q6prskn
TLD_REF_ADDR=$(cat $Validator_Path/tld_reference.addr)
# policy id of tld tokens
# 694cb48da919e928b3e51c4648f051326ac150eaa9436792ec7a6e35
CS_TLD=$(cardano-cli conway transaction policyid --script-file $Validator_Path/tld_reference.plutus)
# sld reference validator address where all sld reference tokens are locked
# addr_test1zzt9zt2vgfkez2ay2vq5ua9904j4m7eesq25cn0pqmmfxgyxu36kavd5fjg7km4qk6umypqlvq9sa6ghyzhl9k8glg8qc9ljcz
SLD_REF_ADDR=$(cat $Validator_Path/sld_reference.addr)
# policy id of sld tokens
# 96512d4c426d912ba453014e74a57d655dfb3980154c4de106f69320
CS_SLD=$(cardano-cli conway transaction policyid --script-file $Validator_Path/sld_reference.plutus)


# tld reference input
TLD_UTXO_IN=$(get_UTxO_by_token $TLD_REF_ADDR "$CS_TLD.$TLD_R_TN")

# tld user token input
TLD_UTXO_IN_U=$(get_UTxO_by_token $OWNER_ADDR "$CS_TLD.$TLD_U_TN")

# get urrent sld list from tld reference datum
cardano-cli query utxo --testnet-magic ${TESTNET_MAGIC} --address $TLD_REF_ADDR --out-file utxos
cur_slds=$(cat utxos | jq -r --arg ref "$TLD_UTXO_IN" '.[$ref].inlineDatum.fields[1].list | map(.bytes)')
rm utxos

# add new sld hex and sort
updated_slds=$(echo "$cur_slds" | jq -c --arg new "$SLD_HEX" \
  '{list: (. + [$new] | sort | map({bytes: .}))}')

# tld reference script
TLD_REFERENCE_REF_TX="ef635b55fce6abc39cd4c843722d9d574cb719114e224f2cd1c8747d5abfc19e#1"
# sld reference script
SLD_REFERENCE_REF_TX="ef635b55fce6abc39cd4c843722d9d574cb719114e224f2cd1c8747d5abfc19e#2"

# redeemer to unlock tld reference token
tld_ref_red=$REDEEMER_PATH/tld_reference_add.json
jq -n '{
    constructor: 2,
    fields: []
  }' > $tld_ref_red

# tld reference token datum
# 68656c6c6f2d68616e647368616b65 = tld hex (hello-handshake)
# $sld_list = all slds minted -> new ones added
# $cs = sld policy id
# "" = possible link to next utxo if datum gets to bi
# [] = records
tld_reference_datum=$DATUM_PATH/tld_reference.json
jq -n --arg cs "$CS_SLD" --argjson sld_list "$updated_slds" '{
    constructor: 0,
    fields: [
      {bytes: "68656c6c6f2d68616e647368616b65"},
      $sld_list,
      {bytes: $cs},
      {bytes: ""},
      {list: []}
    ]
  }' > $tld_reference_datum

# 68656c6c6f2d68616e647368616b65 = tld hex (hello-handshake)
# [68656c6c6f2d736c64] = slds to mint
# [] = slds to burn
sld_ref_red=$REDEEMER_PATH/sld_reference_add.json
jq -n --arg sld "$SLD_HEX" '{
    constructor: 0,
    fields: [
    {bytes: "68656c6c6f2d68616e647368616b65"},
    {list: [{bytes: $sld}]},
    {list: []}
    ]
  }' > $sld_ref_red

# 68656c6c6f2d68616e647368616b65 = tld hex (hello-handshake)
# 68656c6c6f2d736c64 = sld hex
sld_reference_datum=$DATUM_PATH/sld_reference.json
jq --arg sld "$SLD_HEX" -n --arg cs "$CS_SLD" '{
    constructor: 0,
    fields: [
      {bytes: "68656c6c6f2d68616e647368616b65"},
      {bytes: $sld},
      {list: []}
    ]
  }' > $sld_reference_datum

cardano-cli conway transaction build \
    --testnet-magic ${TESTNET_MAGIC} \
    --change-address $USER_ADDR \
    --tx-in $UTXO_IN \
    --tx-in $TLD_UTXO_IN_U \
    --tx-in-collateral $UTXO_IN \
    --tx-in $TLD_UTXO_IN \
    --spending-tx-in-reference $TLD_REFERENCE_REF_TX \
    --spending-plutus-script-v3 \
    --spending-reference-tx-in-inline-datum-present \
    --spending-reference-tx-in-redeemer-file $tld_ref_red \
    --tx-out $TLD_REF_ADDR+2000000+"1 $CS_TLD.$TLD_R_TN" \
    --tx-out-inline-datum-file $tld_reference_datum \
    --tx-out $OWNER_ADDR+1262830+"1 $CS_TLD.$TLD_U_TN" \
    --mint "1 $CS_SLD.$SLD_U_TN + 1 $CS_SLD.$SLD_R_TN" \
    --mint-tx-in-reference $SLD_REFERENCE_REF_TX \
    --mint-plutus-script-v3 \
    --mint-reference-tx-in-redeemer-file $sld_ref_red \
    --policy-id $CS_SLD \
    --tx-out $SLD_REF_ADDR+1435230+"1 $CS_SLD.$SLD_R_TN" \
    --tx-out-inline-datum-file $sld_reference_datum \
    --out-file $raw

cardano-cli conway transaction sign \
    --testnet-magic ${TESTNET_MAGIC} \
    --tx-body-file $raw \
    --out-file $signed \
    --signing-key-file $WALLET_PATH/$USER.skey \
    --signing-key-file $WALLET_PATH/owner1.skey

cardano-cli conway transaction submit \
    --testnet-magic ${TESTNET_MAGIC} \
    --tx-file $signed

tx_submitted $signed $TLD_REF_ADDR