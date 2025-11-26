#!/bin/bash

# Path

#find_and_set_repo_home() {
#    local target_folder="decentralized-dns-contracts"
#
#    local repo_path
#    repo_path=$(find /home -type d -name "$target_folder" -not -path '*/\.*' -print -quit 2>/dev/null)
#
#    if [ -n "$repo_path" ]; then
#        echo "$repo_path"
#    else
#        echo "$target_folder not found."
#        exit
#    fi
#}

#export REPO_HOME=$(find_and_set_repo_home)
export NETWORK_DIR_PATH="$HOME/blinklabs/decentralized-dns-contracts/preprod"
export TESTNET_MAGIC=1

##
export TX_PATH="$NETWORK_DIR_PATH/tx"

export WALLET_PATH="$NETWORK_DIR_PATH/wallets"

##### Datums
export DATUM_PATH="$NETWORK_DIR_PATH/datums"

##### Redeemers
export REDEEMER_PATH="$NETWORK_DIR_PATH/redeemers"

##### Validators
export Validator_Path="$NETWORK_DIR_PATH/validators"

create_reference_token_tn() {
    local self="$1"
    echo -n "r${self}" | b2sum -b -l 256 | awk '{print $1}'
}

create_user_token_tn() {
    local self="$1"
    echo -n "u${self}" | b2sum -b -l 256 | awk '{print $1}'
}

get_address_biggest_lovelace() {
    cardano-cli query utxo --address $1 --testnet-magic ${TESTNET_MAGIC} |
        tail -n +3 |
        awk '{printf "%s#%s %s \n", $1 , $2, $3}' |
        sort -rn -k2 |
        head -n1 |
        awk '{print $1}'
}

get_UTxO_by_token() {
    for i in {1..50}; do
        utxoAttachedHex=$(
            cardano-cli query utxo --address $1 --testnet-magic ${TESTNET_MAGIC} |
                tail -n +3 |
                awk '{printf "%s %s#%s %s\n",$6, $1, $2, $7}' |
                sort -gr |
                awk -v i="$i" 'NR == i {printf("%s", $3)}'
        )
        if [ "$utxoAttachedHex" == "$2" ]; then
            cardano-cli query utxo --address $1 --testnet-magic ${TESTNET_MAGIC} |
                tail -n +3 |
                awk '{printf "%s %s#%s\n",$6, $1, $2}' |
                sort -gr |
                awk -v i="$i" 'NR == i {printf("%s", $2)}'
            return
        fi
    done
}

get_UTxO_lovelace_amount() {
    local ADDRESS="$1"
    local UTxO="$2"

    local utxo_info
    utxo_info=$(cardano-cli query utxo --address "$ADDRESS" --testnet-magic "${TESTNET_MAGIC}" | tail -n +3)

    local utxo_entries
    IFS=$'\n' read -r -d '' -a utxo_entries <<<"$utxo_info"

    for i in {1..50}; do
        for entry in "${utxo_entries[@]}"; do
            entry_parts=($entry)
            utxo_hash=${entry_parts[0]}
            utxo_id=${entry_parts[1]}

            if [[ "$utxo_hash#$utxo_id" == "$UTxO" ]]; then
                echo "${entry_parts[2]}"
                return 0
            fi
        done
    done

    return 1
}

# $1 = tx file path
# $2 = address first output
tx_submitted() {
    tx_Id=$(cardano-cli conway transaction txid --tx-file $1)
    cardano-cli query utxo --testnet-magic ${TESTNET_MAGIC} --address $2 --out-file tmp.utxos
    presence=$(jq -r ".[\"$tx_id#0\"]" "tmp.utxos")

    start_time_seconds=$(date +%s)

    if [[ "$TESTNET_MAGIC" == "42" ]]; then
        while [ "$presence" == "null" ] && [[ $(($run_time_seconds - $start_time_seconds)) -lt 5 ]]; do
            run_time_seconds=$(date +%s)

            cardano-cli query utxo --testnet-magic ${TESTNET_MAGIC} --address $2 --out-file tmp.utxos
            presence=$(jq -r ".[\"$tx_Id#0\"]" "tmp.utxos")
        done
        sleep 1
    else

        while [ "$presence" == "null" ] && [[ $(($run_time_seconds - $start_time_seconds)) -lt 600 ]]; do
            run_time_seconds=$(date +%s)

            cardano-cli query utxo --testnet-magic ${TESTNET_MAGIC} --address $2 --out-file tmp.utxos
            presence=$(jq -r ".[\"$tx_Id#0\"]" "tmp.utxos")
            sleep 5
        done
    fi

    if [ "$presence" != "null" ]; then
        rm tmp.utxos
        echo "Transaction ID: $tx_Id"
    else
        rm tmp.utxos
        echo "Transaction submission failed."
    fi
}
