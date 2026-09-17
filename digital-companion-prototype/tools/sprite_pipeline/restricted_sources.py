"""Immutable source hashes whose known provenance restricts runtime use.

The DigimonUP extraction did not include a redistribution/commercial license.
Matching bytes therefore remain private-prototype-only even if a source plan is
renamed or its authoring metadata claims a broader classification.
"""

from __future__ import annotations

DIGIMONUP_ORIGINAL_HASHES = frozenset({
    "sha256:8697886e9bab1bd9fbc3e71916f7aafd0ab0302fc6db1ad006b4584055f111c9",
    "sha256:5e59100e91d4cb3802bda6de24dc1754709cd9853d3b3e46ebc1c2f6bbcb5622",
    "sha256:1a1a4e145f21f09199e3ed0afd6f63eb8851011d1bdc20855cb6e461f9b0c364",
    "sha256:e4adf13337326fb76bbd021aa13967db86304492aa388e0fb5313731f386296b",
    "sha256:d58d3fcc09b6fb1c2ab3d65de5c342b1d1bb026966f73ebff092f22a4643758e",
    "sha256:5a9c24f75e729743710ea2c39bf23a8c4c8bd2d3d2196004794da1983ffb054e",
    "sha256:49ad21ab4993e00508ffcd48f43cf72ef27b5d3b23e2e4d252f729d73d0399bb",
    "sha256:0906718f9f27534f275c1c987d61073032d44df25f414dbb1dc2287c1fae82fc",
    "sha256:7fabc01d3071c247fd9564775c450315f2dfb1709e611d5a1969a201deb8bf0f",
    "sha256:67fd2bf3f8801b96eff920b974f0f8161726747ef78e7015da987dfbe4b21219",
    "sha256:2c6a9543d69168eb40553b28bb90f5baebc3dbe226375d90883dc539dd426464",
    "sha256:2d28b4768a817d9a762e20d4c5c5bd59597f12177ab37681937c2ab90373741d",
    "sha256:11efdf86077f25fd4787dbc3b46df8c1ca128dba5ddba0fd84e1d3b0c328ef28",
    "sha256:a8e193044454c53314b67ae9aecd475929e14561cf3cf524dfb3796d28674089",
    "sha256:9e6bfda1579eec0e74e5593c1bc2fe7f8da2294a78ab888616de6f5827e96c6d",
})

# Deterministic derivatives remain under the source's restriction. Retain old
# review hashes too so renaming an obsolete cut cannot launder its provenance.
DIGIMONUP_DERIVED_HASHES = frozenset({
    "sha256:7f89c24546a0e33210c75b49a49cf204184d999e40e3084542b322d2f91611e6",
    "sha256:d593f577d47cde7b5ec2e0c44e2b44ab9b66d16139e5cf575fd6bde13bcba293",
    "sha256:cb1b34b737c151bf35fa01af3114f02eba9e21a7e9206ffffc47d2654889e5fb",
    "sha256:aaaf44cffd9fdfaa7d2296ae53e0232fb14c21cd72b7a509a8956f30c6533a5c",
    "sha256:aa702efe117884b192d4f1ecf3f08fc981359da69904ea11c64ebab1440118c3",
    "sha256:6f3f0192bc0c2c73b645bd2e9887fef6f6f813f2c8efd6327a5b6f0a643b20f4",
    "sha256:19288ac666f16eb0a2ea3300bde18287601f3a4a159e491746cd6b93645f50e6",
    "sha256:52fce50a1cd2f2572e87bfc93e34967f798282932cafd1ac091f4048242b01f4",
    "sha256:d6f709f390ad53fbece6380cf440e9f859fbaea42f98eb4968b91ffac2be7981",
})

DIGIMONUP_PRIVATE_HASHES = DIGIMONUP_ORIGINAL_HASHES | DIGIMONUP_DERIVED_HASHES


def restricted_classification(source_hashes) -> str | None:
    """Return the strict classification required by any known source bytes."""
    return "private-prototype-only" if DIGIMONUP_PRIVATE_HASHES.intersection(source_hashes) else None
