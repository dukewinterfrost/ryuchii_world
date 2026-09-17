# DigimonUP environment source inventory

Use this reference only when working from the five selected DigimonUP biomes. These files are external authoring inputs, never runtime paths.

## Rights and provenance

- Source tree: `/Users/johncohrn/Documents/Digimon/Digimon Up Assets/Texture2D`
- Project classification: `private-prototype-only`
- Distribution status: `not-cleared`
- Project policy sources: `README.md` (Private asset notice) and `assets/asset-provenance.json`.
- No license or credit file was found near the extracted source tree during the 2026-09-12 audit.
- This is a project handling classification, not a finding of ownership or a license grant. Public or commercial use requires licensed or original replacements.

## Primary style-authority set

Hashes below were inspected on 2026-09-12. Recompute before ingest and stop if a value differs.

| Biome | File relative to source tree | PNG size | SHA-256 |
|---|---|---:|---|
| Green Shade | `Green_Shade_Ground.png` | 2048×1319 | `8697886e9bab1bd9fbc3e71916f7aafd0ab0302fc6db1ad006b4584055f111c9` |
| Green Shade | `Green_Shade_Top.png` | 2048×663 | `5e59100e91d4cb3802bda6de24dc1754709cd9853d3b3e46ebc1c2f6bbcb5622` |
| Green Shade | `Green_Shade_Tree.png` | 2048×744 | `1a1a4e145f21f09199e3ed0afd6f63eb8851011d1bdc20855cb6e461f9b0c364` |
| Shellfish Beach | `Shellfish_Beach_Ground.png` | 2048×879 | `e4adf13337326fb76bbd021aa13967db86304492aa388e0fb5313731f386296b` |
| Shellfish Beach | `Shellfish_Beach_Top.png` | 2048×898 | `d58d3fcc09b6fb1c2ab3d65de5c342b1d1bb026966f73ebff092f22a4643758e` |
| Shellfish Beach | `Shellfish_Beach_Rock.png` | 2048×544 | `5a9c24f75e729743710ea2c39bf23a8c4c8bd2d3d2196004794da1983ffb054e` |
| Toy Maze | `Toy Maze_Ground.png` | 1655×1288 | `49ad21ab4993e00508ffcd48f43cf72ef27b5d3b23e2e4d252f729d73d0399bb` |
| Toy Maze | `Toy Maze_Top.png` | 2048×748 | `0906718f9f27534f275c1c987d61073032d44df25f414dbb1dc2287c1fae82fc` |
| Toy Maze | `Toy Maze_Village2.png` | 1963×834 | `7fabc01d3071c247fd9564775c450315f2dfb1709e611d5a1969a201deb8bf0f` |
| Mechatropolis | `Mechatropolis_Ground.png` | 2048×950 | `67fd2bf3f8801b96eff920b974f0f8161726747ef78e7015da987dfbe4b21219` |
| Mechatropolis | `Mechatropolis_Top.png` | 2048×432 | `2c6a9543d69168eb40553b28bb90f5baebc3dbe226375d90883dc539dd426464` |
| Mechatropolis | `Mechatropolis_Deco.png` | 2048×262 | `2d28b4768a817d9a762e20d4c5c5bd59597f12177ab37681937c2ab90373741d` |
| Nephelis Abyss | `Nephelis Abyss_Ground.png` | 1431×1253 | `11efdf86077f25fd4787dbc3b46df8c1ca128dba5ddba0fd84e1d3b0c328ef28` |
| Nephelis Abyss | `Nephelis Abyss_Top.png` | 2048×829 | `a8e193044454c53314b67ae9aecd475929e14561cf3cf524dfb3796d28674089` |
| Nephelis Abyss | `Nephelis Abyss_TopDeco.png` | 2048×809 | `9e6bfda1579eec0e74e5593c1bc2fe7f8da2294a78ab888616de6f5827e96c6d` |

Verify a selected file with:

```sh
shasum -a 256 '/Users/johncohrn/Documents/Digimon/Digimon Up Assets/Texture2D/<file>.png'
file '/Users/johncohrn/Documents/Digimon/Digimon Up Assets/Texture2D/<file>.png'
```

Then bind it through `./tools/sprites ingest`; do not copy it directly into `assets/`.

## Unbound variants

The same directory also contains alternate `Ground`, `Top`, `_B`, `_C`, `_D`, object, building, decoration, and lighting-looking variants for several biomes. Their filenames do not establish purpose, quality, or approval. Inventory and hash a variant only when its visual role is understood and it is deliberately selected for a new revision.
