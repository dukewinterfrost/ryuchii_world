# Battle effect sources

Researched 17 September 2026 against the nine moves in `assets/combat/moves.csv`. Prices and license statements below were checked on creator/source pages. Move assignments are our proposed adaptations, not promises made by the artists. This is a source library; no runtime effects or collision geometry were changed.

## Recommended direction

Use **PVFX Foundry as the first cohesive combat-pack candidate**, **Foozle for compact elemental projectiles**, and **second's bubble animation for the baby moves**. Keep CodeManu as a punchier alternate for impacts/shields. Pick one main style in the battle camera before mixing them. Kenney supplies useful building blocks, but its smooth particle textures need styling to match our pixel creatures.

| Source | What it supplies | Price and license | Acquisition |
| --- | --- | --- | --- |
| [PVFX Foundry — nerijs](https://nerijs.itch.io/pvfx-foundry) | 35 effects; 96×96 transparent sheets, 20 FPS, fixed-grid and packed variants, timing/pivot metadata. Broadest coverage for this game. Procedural imagery; creator discloses AI assistance for code/text. | $0 option; CC0 | Source verified; ZIP not acquired |
| [Pixel Magic Effects — Foozle / lordfitoi](https://foozlecc.itch.io/pixel-magic-sprite-effects) | 10 animated effects at 32×32: fire, water, earth, wind, portal and explosion. Strong small-sprite candidate for Pepper Breath and future elements. | $0 option; CC0 | Source verified; ZIP not acquired |
| [Free VFX Asset Pack — CodeManu](https://codemanu.itch.io/vfx-free-pack) | 22 effects, 30/60 FPS, sheets and individual frames. Small/Big Hit, Impact, Hyperspeed and Electric Shield are useful candidates. | $0 option; **license-label conflict** described below | Source and promotional preview inspected; ZIP not acquired |
| [Free Pixel Effects Pack — CodeManu](https://codemanu.itch.io/pixelart-effect-pack) | Older alternate: 20 effects with 100×100 cells. | $0 option; same license-label conflict | Source verified; ZIP not acquired |
| [2D Bubble Animation — second](https://opengameart.org/content/2d-bubble-animation) | Nine individual 16×16 bubble frames. | Free; CC0 | Downloaded and image-decoded |
| [Pink Bubble Popping Animation — Natural_Privateer](https://opengameart.org/content/pink-bubble-popping-animation-16x16) | 48×48 sheet with 16×16 cells; alternate pop treatment. | Free; CC0 | Downloaded and image-decoded |
| [Particle Pack — Kenney](https://kenney.nl/assets/particle-pack) | Slash/scratch, smoke, circles, sparks, flame and other particle textures. Static building blocks, not finished move animations. | Free; CC0 | Downloaded; archive has 96 transparent 512×512 PNGs including rotations, plus black-background variants |
| [2D Spell Effects — Mikodrak](https://opengameart.org/content/2d-spell-effects) | Ten transparent PNG sequences: fireball, lightning/energy, black explosion, rain and other magic. Softer rendered style; useful comparison/backup. | Free; CC0 | Downloaded; 231 PNG frames in ten folders, plus 11 preview GIFs |

The itch.io free-download pages were reached, but the in-app download attempts did not yield local archives. Those rows are deliberately recorded as source-verified, not downloaded. The ordinary “Download Now → No thanks, just take me to the downloads” path is available on their source pages. No purchases, accounts, or creator messages were made.

## Current move coverage

These are presentation recipes. A complete move often needs a charge cue, travelling effect, impact and recovery accent, rather than one animation stretched over its entire lifetime.

| Move ID | Preferred candidate / recipe | Available local alternative | Adaptation still needed |
| --- | --- | --- | --- |
| `tackle` | CodeManu Small Hit + PVFX Landing Dust | Kenney `spark_01`, `smoke_01` | Place burst at confirmed contact; small grounded puff |
| `headbutt` | CodeManu Big Hit, compact scale | Kenney `spark_02` | Differentiate from Tackle with a short ring/stronger burst |
| `claw` | PVFX Crescent Slash | Kenney `scratch_01`, `slash_01` | Mirror with facing; keep slash clear of the creature silhouette |
| `pepper_breath` | Foozle Fire Ball; CodeManu Fast Pixel Fire for impact | Mikodrak `fx3_fireBall` sequence; Kenney flame/spark textures | Separate mouth charge, projectile loop and collision burst; verify intended facing |
| `quick_bite` | CodeManu Small Hit with two closing arcs | Kenney `slash_02` + compact spark | **No dedicated teeth/bite clip verified**; compose arcs or author a bite silhouette |
| `heavy_claw` | PVFX Crescent Slash + stronger impact | Kenney `scratch_01` + `spark_02` | Longer anticipation; bigger visual burst, same authoritative hit region |
| `acid_bubbles` | second Bubble + PVFX Acid Splash | second's nine frames + Kenney circle/spark | Green tint and small splash; tint is not baked into downloaded originals |
| `bubble_blow` | second Bubble + Natural_Privateer pop | Both downloaded bubble sources | Blue/pearl variant; inspect pop cell order and author timing |
| `opening_tackle` | PVFX Landing Dust + CodeManu Hyperspeed/Impact | Kenney smoke, streak and spark textures | Grounded dust on rush; short directional trail; impact only on collision |

## Shared commands, items and future elements

| Use | Candidate | Design work |
| --- | --- | --- |
| Guard / Perfect Guard | PVFX Arcane Parry; CodeManu Electric Shield | Calm guard outline versus brief perfect-guard burst on the **defender** |
| Barrier | CodeManu Electric Shield or PVFX Venom Ward recolored | Persistent low-opacity ring + separate absorb/break cue; keep attack tells visible |
| Dodge / Haste | PVFX Landing Dust/Leaf Gust; CodeManu Hyperspeed | Short directional streaks; limit emitters in 3v3 |
| HP / MP recovery | PVFX Radiant Heal, with distinct colors/symbols | Rise from creature; avoid relying solely on red/blue color |
| Ability charging | PVFX Focus Charge or Kenney circle/spark combination | Sample from the real cast phase; do not invent a second gameplay timer |
| Future ice / earth / wind | PVFX Frost Nova/Earth Rupture; Foozle earth/wind clips | Visual options sourced; no new moves or status mechanics implied |
| Future poison / lightning | PVFX Acid Splash/Electric Impact; Mikodrak lightning sequence | Distinguish impact from a lingering status indicator |

## Sound companions

| Source | Useful coverage | License / state |
| --- | --- | --- |
| [Impact Sounds — Kenney](https://kenney.nl/assets/impact-sounds) | 130 OGG files. `impactPunch_medium_*`, `impactPunch_heavy_*`, `impactSoft_*` and `footstep_grass_*` are audition candidates for strikes and movement. | CC0; downloaded; not auditioned or mixed |
| [RPG Audio — Kenney](https://kenney.nl/assets/rpg-audio) | 51 individual OGG files plus one preview. `knifeSlice`, `knifeSlice2`, `chop` and cloth/leather sounds can support claw/bite/dodge layers. This is foley, not a complete magic library. | CC0; downloaded; not auditioned or mixed |
| [Basic Spell Impacts — lentikula](https://lentikula.itch.io/freecc0-basic-spell-impacts-sfx) | 20 WAV spell impacts: five each for fire, water, ice and lightning, 48 kHz/24-bit. | Free / CC0 per creator; source verified, ZIP not acquired |

## Licenses and pack distribution

Prefer CC0 for the reusable asset library: it permits commercial use, modification and redistribution. Preserve creator/source records even when credit is optional. See the [official CC0 summary](https://creativecommons.org/publicdomain/zero/1.0/).

Both CodeManu pages say public domain in their license paragraph, while their asset metadata says **CC BY 4.0**. Do not silently relabel these CC0. If selected, retain CodeManu credit (and Davit Masia for the older pack), title/source link, the CC BY 4.0 link, supplied notices and a record of modifications. Do not impose additional restrictions on those assets. This follows the more restrictive published label; [CC BY terms](https://creativecommons.org/licenses/by/4.0/) explain the obligations. They remain optional to the CC0-first set.

[NYKNCK's creator profile](https://nyknck.itch.io/) permits commercial projects with credit but prohibits asset redistribution. That makes those packs unsuitable for a generally redistributable source-asset bundle under those stated terms; they were not added. [Henry Software's Pixel Effects](https://henrysoftware.itch.io/pixel-effects) is a $7 CC0 alternative at the checked price, not a free download. No purchase is needed for the initial coverage above.

## Files and next integration step

Downloaded originals, archives, source URLs and SHA-256 hashes live in [`assets-source/battle-effects/2026-09-17/`](../assets-source/battle-effects/2026-09-17/README.md). The folder is excluded from automatic Godot imports by `.gdignore`. `download-manifest.json` records acquisitions and `asset-inventory.json` records decoded image dimensions/alpha and audio file paths. Original bytes are unchanged.

For an implementation pass, first compare Pepper Breath, Claw and Bubble Blow at the actual battle-camera scale. Import only selected transparent frames through the project's atlas pipeline; these sources are not approved runtime artwork merely because they were downloaded. Map logical effects to distinct charge/projectile/impact/recovery resources in the renderer. The current content loader only accepts `impact`, `fire`, `bubble`, `rush`; putting a new file path in `moves.csv` will not load it automatically.

Retain the existing 30 Hz authoritative events, pinned replay content and separate collision sizes. PVFX's 50 ms frames do not divide into 30 Hz ticks: sample presentation time/interpolation instead of altering combat timings. Check on bright/dark arenas, with six creatures, and with reduced motion. No package's visual radius should replace the move table's collision radius.
