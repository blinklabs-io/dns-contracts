source env.sh
cd ../onchain
aiken blueprint convert -v tld_registrar > ../preprod/validators/tld_registrar.plutus
aiken blueprint convert -v tld_reference > ../preprod/validators/tld_reference.plutus
aiken blueprint convert -v sld_reference > ../preprod/validators/sld_reference.plutus

cardano-cli conway address build --testnet-magic 1 --payment-script-file $Validator_Path/tld_registrar.plutus --stake-verification-key-file $WALLET_PATH/registrar-stake.vkey --out-file $Validator_Path/tld_registrar.addr
cardano-cli conway address build --testnet-magic 1 --payment-script-file $Validator_Path/tld_reference.plutus --stake-verification-key-file $WALLET_PATH/registrar-stake.vkey --out-file $Validator_Path/tld_reference.addr
cardano-cli conway address build --testnet-magic 1 --payment-script-file $Validator_Path/sld_reference.plutus --stake-verification-key-file $WALLET_PATH/registrar-stake.vkey --out-file $Validator_Path/sld_reference.addr