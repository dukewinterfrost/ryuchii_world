# Slime and fairy encounters

The live training battle now runs battle-v5: one companion against one to three enemies. Victory advances a saved intro counter: one Slime, three Slimes, two Slimes with a Mender Fairy, then seeded mixed trios. Mixed trios contain two slimes and a third slime or fairy. Losses, draws, abandonment, and failed saves do not advance the intro. Retrying settlement cannot advance it twice.

Tap an enemy or its health card to focus it. An attack already committed retains its original aim; the next free decision uses the focus. A defeated focus automatically clears. Cards show each enemy's HP and current cast.

| Creature | Free melee | Three abilities |
|---|---|---|
| Slime | Slime Bump | Slime Shot, Bounce Rush, Heavy Slam |
| Metal Slime | Slime Bump | Harden, Body Rush, Crushing Slam |
| Spitter Slime | Slime Bump | Quick Spit, Heavy Glob, Elastic Dash |
| Mender Fairy | Fairy Strike | Mend, Ward, Spark |
| Spark Fairy | Fairy Strike | Quick Spark, Heavy Spark, Diving Rush |

These are role variants; no elemental resistance system was added. Starting values are intended for playtesting. Automatic moves consume MP and respect cooldowns; free melee remains available after MP runs out.

Mend selects the living allied slime with the lowest HP percentage below 60%, breaking ties by roster order. It restores 25% of maximum HP (rounded down, at least one), capped at maximum. Default cast is 1 second, cooldown 8 seconds, cost 8 MP. The target must be in range and visible both when selected and at release. It cannot heal enemies or revive defeated allies. Ward and Harden provide finite, expiring damage absorption. Healing and wards have visual feedback; damage and targeting remain simulator-owned.

## Editing balance in Excel

Open **Game Balance.xlsx** in the project root (a link to `outputs/mob-balance/Game Balance.xlsx`). Edit the tables or yellow Value cells, save, and double-click **Apply Game Balance.command**. Restart the game after applying. The isolated sandbox's **Reload balance** reads the applied workbook export for a new battle.

The workbook is the canonical authoring source. `tools/apply_game_balance.py` uses only Python's standard library, validates it with the actual Godot content loader, then atomically replaces `assets/balance/game-balance.json`. Invalid imports leave the previous bundle intact. `--check` validates without writing. Do not hand-edit the generated bundle or use the historical combat CSVs to tune live play.

Sheets cover creatures, moves, encounters, items, AI weights, combat timing, care effects and timers, food preferences, training, evolution, rewards, starter inventories, building/cooking costs, and initial player stats. Existing saves retain earned stats and inventories. Technical save limits, collision geometry, and historical simulator constants remain code contracts.

Move timing is authored in seconds and quantized to 30 Hz. Distances use world units. `heal_percent` and `trigger_percent` are fractions: **0.25 means 25%**. Pipe characters separate move lists and encounter members. Keep the four encounter IDs/order and existing saved IDs stable. The importer rejects formulas, duplicate IDs, invalid numeric bounds, unknown references, missing required moves, and malformed formations. New creatures require exactly three distinct equipped moves and a free melee fallback.

## Sandbox and new mobs

Run `open-battle-sandbox.command`. Choose **1 Slime**, **3 Slimes**, **Slimes + Healer**, **Mixed trio**, or an individual metal/spitter/offensive-fairy fixture, then **Same seed** or **New seed**. These battles cannot alter the companion save or award rewards. The original 1v1/3v3 debugging fixtures remain available.

The installed `$mob-creator` skill is at `~/.codex/skills/mob-creator/SKILL.md`. It was used for this batch and covers role/move design, workbook integration, deterministic AI, source provenance, animation generation, and playable verification. The runtime species registry is assembled from the Creatures table; add a matching asset package and move references through the skill. Slime IDs use `slime_` and fairy IDs use `fairy_` for encounter and healing eligibility.

## Art status and PixelLab continuation

Figma source: file `syQM2pShfeCTfXms0HmzTB`, slime node `161:541`, fairy node `167:544`. Originals, hashes, crop boxes, and palette transformations are recorded in `assets-source/mobs/2026-09-21/source-manifest.json`.

All five mobs currently use **source-derived fallback animation**, not approved PixelLab output. Eight clips are available: idle, movement, basic attack, special attack, guard, evade, hit, defeat. Slime movement uses the sheet's legless jump poses. Grab/walk poses with appendages are excluded. Every selected slime frame was visually reviewed for legs; all variants use those same legless poses. Metal/spitter/striker colors are temporary palette variants, not new plated anatomy.

PixelLab accepted one movement pilot: job `121b5bc3-4aca-4b50-a78e-3871d7568446`. Polling is blocked by certificate verification: this network presents a Cisco Secure Access certificate for `api.pixellab.ai` that the local client cannot verify. TLS verification remains enabled. No duplicate job or bulk submissions were made.

After the connection is trusted again, resume:

```sh
.venv-sprites/bin/python tools/animate_mobs.py slime_basic move
```

The recorded job and exact original input are under `assets-source/mobs/2026-09-21/jobs/slime_basic-move/`. The adapter binds requests to source bytes and resumes the existing ID. Review the pilot in motion before generating the remaining clips. Reject **any legs, feet, arms, hands, or walking limbs** in any slime frame. Generated clips must follow `sprite-generator-workflow` review and immutable promotion before replacing fallback art. No motion approval has been fabricated.

## Compatibility and verification

battle-v5 pins its normalized moves, species registry, stats, supplies, and visual revisions. The v2/v3/v4 dispatchers remain for existing replays. Save schema 11 adds `battle.mob_wins`; schema-10 and older saves migrate with zero intro wins while preserving existing progress. Historical fixture generators were updated to omit new fields; the v2 migration test now uses a literal historical shape.

Verified on September 21, 2026:

- 90 mob checks: group sizes, safe spawning, every loadout, seeded replay equality, healing thresholds/caps/LoS/range, no-MP fallback, ward, focus/committed aim, and saved progression/retry.
- Six workbook tests: real XLSX roundtrip, runtime validation of four tuning edits, malformed references, duplicates, nonfinite values, and failed-import atomicity.
- 39 sandbox checks, 74 live battle-control checks, portrait targeting at 360/390/430 pixels, and 3D targeting.
- Legacy spatial/v3/v4 and frozen-content replay suites, save/care integration, 509 3D battle checks, and sprite pipeline tests passed.
- The broader environment suite is **not wholly green**: the Green Shade spike reports three legacy attack-fallback assertions and two camera-frustum clamp failures, and the native scene-builder suite reports 422 placement/floor failures. Those environment implementations were already present in this dirty workspace and were not replaced by this feature. Rootbound's 7,480 checks pass. See the terminal test logs for exact failures; these are not suppressed in the suite.
