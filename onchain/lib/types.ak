use cardano/assets.{PolicyId}

pub type TLDRegisterDatum {
  // top level domain on handshake
  tld: ByteArray,
  // tld owner handshake public key
  owner_hns_key: ByteArray,
  // amount tld reference tokens minted
  minted: Int,
}

pub type RegistrarRedeemer {
  RegisterTLD {
    tld: ByteArray,
    owner: ByteArray,
    registrar_signature: ByteArray,
    tld_reference_policy_id: PolicyId,
  }
  RegistrarAction { registrar_signature: ByteArray }
  OwnerAction { owner_signature: ByteArray }
}

pub type DNSRecord {
  lhs: ByteArray,
  ttl: Option<Int>,
  class: ByteArray,
  rtype: ByteArray,
  rdata: ByteArray,
}

pub type TLDReferenceDatum {
  // top level domain on handshake
  tld: ByteArray,
  // slds
  slds: List<ByteArray>,
  // policy id of sld reference
  sld_reference_policy_id: PolicyId,
  // next sld (link), if datum gets too big
  next: ByteArray,
  // tld records
  records: List<DNSRecord>,
}

pub type TLDReferenceAction {
  InitRemoveReference
  MintAdditionalReference
  SpendReference
  BurnReference
}

pub type SLDReferenceDatum {
  // top level domain on handshake
  tld: ByteArray,
  // sld -> present in TLDReferenceDatum
  sld: ByteArray,
  // sld records TLDReferenceDatum
  records: List<DNSRecord>,
}

pub type MintSld {
  tld: ByteArray,
  mint_slds: List<ByteArray>,
  burn_slds: List<ByteArray>,
}
