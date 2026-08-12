use aiken/builtin.{verify_ecdsa_secp256k1_signature}
use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}

// provide public key and signature in redeemer
// does not make much sense but okey for testing signature verification
pub type HNSData {
  hns_vkey: ByteArray,
  hns_signature: ByteArray,
}

// simply verify public key hash signed message to mint token
validator verify_hns_sig(msg: ByteArray) {
  mint(redeemer: HNSData, _policy_id: PolicyId, _self: Transaction) {
    verify_ecdsa_secp256k1_signature(
      redeemer.hns_vkey,
      msg,
      redeemer.hns_signature,
    )
  }

  else(_) {
    fail
  }
}

// Comprehensive tests for the verify_hns_sig validator.
// These tests verify the core functionality of the validator: ECDSA signature verification.

// Test case 1: Successful signature verification with valid inputs.
test success_valid_signature() {
  // Replace with actual valid secp256k1 public key bytes
  let valid_vkey = #"031e23f3f44c147912f9ae88bf5534fd51a2d976ab19415c4c33105baf7369ce24"

  // Replace with the actual message bytes that were signed
  let valid_msg = #"1da9a222c3e0e4f2b298327d159500a6cff91bfb23c555444a5a12a307e94d0d"

  // Replace with the actual valid secp256k1 signature bytes for the message and vkey
  let valid_signature = #"b98b87d36938bbe167b4cdb7945b37ea96a4ffca0e62c4b637a985fa294d7c5429c006a14d97f29fc0903fa89bd6c6e2d5e68123e26bc78eb1b408eaaf8e8e85"

  let redeemer = HNSData {
    hns_vkey: valid_vkey,
    hns_signature: valid_signature,
  }
  let msg = valid_msg

  // Expect the builtin function to return True for valid inputs.
  expect
    builtin.verify_ecdsa_secp256k1_signature(
      redeemer.hns_vkey,
      msg,
      redeemer.hns_signature,
    ) == True
}

// Test case 2: Signature verification fails with an invalid public key.
test fail_invalid_vkey() {
  // Replace with an invalid secp256k1 public key bytes (different from valid_vkey)
  let invalid_vkey = #"030e23f3f44c147912f9ae88bf5534fd51a2d976ab19415c4c33105baf7369ce24"

  // Replace with the actual message bytes that were signed (same as success test)
  let valid_msg = #"1da9a222c3e0e4f2b298327d159500a6cff91bfb23c555444a5a12a307e94d0d"

  // Replace with the actual valid secp256k1 signature bytes (same as success test)
  let valid_signature = #"b98b87d36938bbe167b4cdb7945b37ea96a4ffca0e62c4b637a985fa294d7c5429c006a14d97f29fc0903fa89bd6c6e2d5e68123e26bc78eb1b408eaaf8e8e85"

  let redeemer = HNSData {
    hns_vkey: invalid_vkey,
    hns_signature: valid_signature,
  }
  let msg = valid_msg

  // Expect the builtin function to return False for an invalid public key.
  expect
    builtin.verify_ecdsa_secp256k1_signature(
      redeemer.hns_vkey,
      msg,
      redeemer.hns_signature,
    ) == False
}

// Test case 3: Signature verification fails with an invalid message.
test fail_invalid_msg() {
  // Replace with actual valid secp256k1 public key bytes (same as success test)
  let valid_vkey = #"031e23f3f44c147912f9ae88bf5534fd51a2d976ab19415c4c33105baf7369ce24"

  // Replace with an invalid message bytes (different from valid_msg)
  let invalid_msg = #"0000a222c3e0e4f2b298327d159500a6cff91bfb23c555444a5a12a307e94d0d"

  // Replace with the actual valid secp256k1 signature bytes (same as success test)
  let valid_signature = #"b98b87d36938bbe167b4cdb7945b37ea96a4ffca0e62c4b637a985fa294d7c5429c006a14d97f29fc0903fa89bd6c6e2d5e68123e26bc78eb1b408eaaf8e8e85"

  let redeemer = HNSData {
    hns_vkey: valid_vkey,
    hns_signature: valid_signature,
  }
  let msg = invalid_msg

  // Expect the builtin function to return False for an invalid message.
  expect
    builtin.verify_ecdsa_secp256k1_signature(
      redeemer.hns_vkey,
      msg,
      redeemer.hns_signature,
    ) == False
}

// Test case 4: Signature verification fails with an invalid signature.
test fail_invalid_signature() {
  // Replace with actual valid secp256k1 public key bytes (same as success test)
  let valid_vkey = #"031e23f3f44c147912f9ae88bf5534fd51a2d976ab19415c4c33105baf7369ce24"

  // Replace with the actual message bytes that were signed (same as success test)
  let valid_msg = #"1da9a222c3e0e4f2b298327d159500a6cff91bfb23c555444a5a12a307e94d0d"

  // Replace with an invalid secp256k1 signature bytes (different from valid_signature)
  let invalid_signature = #"000087d36938bbe167b4cdb7945b37ea96a4ffca0e62c4b637a985fa294d7c5429c006a14d97f29fc0903fa89bd6c6e2d5e68123e26bc78eb1b408eaaf8e8e85"

  let redeemer = HNSData {
    hns_vkey: valid_vkey,
    hns_signature: invalid_signature,
  }
  let msg = valid_msg

  // Expect the builtin function to return False for an invalid signature.
  expect
    builtin.verify_ecdsa_secp256k1_signature(
      redeemer.hns_vkey,
      msg,
      redeemer.hns_signature,
    ) == False
}
