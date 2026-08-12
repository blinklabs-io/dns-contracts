const bcrypto = require('bcrypto');
const { BLAKE2b } = bcrypto;
const secp256k1 = bcrypto.secp256k1;
const random = bcrypto.random;
const fs = require('fs');

// Generate a valid private key
let privKey;
do {
  privKey = random.randomBytes(32);
} while (!secp256k1.privateKeyVerify(privKey));

// Public key (compressed)
const pubKey = secp256k1.publicKeyCreate(privKey, true);

// message = tld ++ serialiseData(receiver_address) ++ serialiseData(output_reference)
// receiver_address/output_reference CBOR default to the Aiken test fixtures
// (mock_pub_key_address("u"), mock_utxo_ref("0", 0)) but can be overridden:
//   node sign.js <receiverAddressCborHex> <outputReferenceCborHex>
const tldHex = Buffer.from('hello-handshake', 'utf8').toString('hex');
const receiverAddressCborHex =
  process.argv[2] ||
  'd8799fd8799f581ccf2020680b6315ff98ffdddde4400839a628e2360a1d1a20ed519439ffd87a80ff';
const outputReferenceCborHex =
  process.argv[3] ||
  'd8799f58200fd923ca5e7218c4ba3c3801c26a617ecdbfdaebb9c76ce2eca166e7855efbb800ff';

const message = Buffer.from(
  tldHex + receiverAddressCborHex + outputReferenceCborHex,
  'hex'
);
const hash = BLAKE2b.digest(message);

// Sign the message
const [signature, recovery] = secp256k1.signRecoverable(hash, privKey);

// Signature without recovery byte
const sig64 = signature; // 64 bytes: r||s

// Prepare the data to be written to a JSON file
const output = {
  privateKey: privKey.toString('hex'),
  publicKey: pubKey.toString('hex'),
  messageHash: hash.toString('hex'),
  signature: sig64.toString('hex')
};

// Write the output to a JSON file
fs.writeFileSync('secp256k1_output.json', JSON.stringify(output, null, 2));

console.log('Data written to secp256k1_output.json');
