use aiken/builtin.{blake2b_224}
use cardano/address.{Address, Inline, Script}

pub const tld = "hello-handshake"

pub const registrar_hns_vkey =
  #"036e79d991d0afac5e08854d5f7a07bd159bfe3fa10e481ae32c6abb4bcef5edd5"

pub const registrar_signature =
  #"f25dce228ae3cefcf2123e6dbd32f2a44636fe61f7df844d09f64f800a4d558f37979bad326d14394760940b319daba2442d71e53b4aae1ed8d8d59ccb8d59d2"

pub const tld_owner_vkey =
  #"03b0ecbc0c277027b7ddaca374817f754e55694f1e993bd012d55bad76af15a302"

pub const tld_owner_signature =
  #"3b5e199280f3edbe714b4928469822a53d8acce9a1cdfddbddcb2169a13596991de1b0a7ea626bc98dbd3ab9b482608dacfdcaefbbb305f98e7bfeb530c45e99"

pub const stake_cred = Inline(Script(blake2b_224("stake_cred")))

pub const tld_registrar_cs = blake2b_224("tld_registrar_cs")

pub const tld_registrar_addr =
  Address(Script(tld_registrar_cs), Some(stake_cred))

pub const tld_reference_cs = blake2b_224("tld_reference_cs")

pub const tld_reference_addr =
  Address(Script(tld_reference_cs), Some(stake_cred))

pub const sld = "some-sld"

pub const sld_reference_cs = blake2b_224("sld_reference_cs")

pub const sld_reference_addr =
  Address(Script(sld_reference_cs), Some(stake_cred))
