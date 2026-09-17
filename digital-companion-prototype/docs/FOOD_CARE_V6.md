# Favorite foods and cravings — save v6

Feed opens a scrollable, keyboard-accessible pantry of nine foods. The thought
bubble is also a shortcut to that pantry. Favorites and active cravings are
labelled in the picker; favorites also appear on the creature's status sheet.
Food is unlimited for this prototype, separate from battle consumables.

## Tuning

- Botamon: pudding; Koromon: strawberry; Agumon: drumstick.
- All meals retain the existing +30 Fullness and weight effect. Feeding is
  rejected at 96 Fullness or above.
- A favorite adds +3 Happiness to the existing +5. Satisfying a craving adds
  another +6 Happiness and +3 base Bond, subject to existing diminishing rewards.
- First craving: 120 engaged seconds, with Fullness at most 85. Subsequent
  requests wait 240–420 engaged seconds after the previous request ends.
- Cravings last 120 real seconds. Every second request is the species favorite;
  the others rotate deterministically through the pantry. Missed cravings have
  no penalty. Eating enough to exceed 85 Fullness dismisses a request harmlessly.
- Offline time does not create requests. Existing requests can expire offline.
  Training does not advance the request timer. Reloading preserves the active
  food, expiry, sequence and cooldown; it does not reroll or re-award bonuses.

Tune food names, favorites and timing in `scripts/core/food_rules.gd`; feeding
rewards remain in `CareRules.apply_command`. GameState commits feeding and its
craving reward together, including rollback on save failure. The UI never edits
authoritative food state. Save schema v6 migrates v1–v5 through the existing
version chain, preserving identity, progression, inventory and waste.

## Artwork provenance

Source: the user's [Digital Companion — Pixel Workshop](https://www.figma.com/design/syQM2pShfeCTfXms0HmzTB/Digital-Companion-%E2%80%94-Pixel-Workshop?node-id=0-1).
Exported read-only from the original Figma nodes as 1×, 128×128 transparent PNGs.
The reference screenshot was not cropped or substituted. Nearest-neighbor
sampling keeps the original pixel edges. No new artwork was generated and no
Figma canvas content was changed.

| Runtime asset | Figma node / layer | Food |
|---|---|---|
| `assets/food/food-0.png` | `22:156` / `CustomEmoji_Digimon_0` | Sweet potato |
| `assets/food/food-1.png` | `22:157` / `CustomEmoji_Digimon_1` | Pizza |
| `assets/food/food-2.png` | `22:158` / `CustomEmoji_Digimon_2` | Shrimp |
| `assets/food/food-3.png` | `22:159` / `CustomEmoji_Digimon_3` | Pudding |
| `assets/food/food-4.png` | `22:160` / `CustomEmoji_Digimon_4` | Rice ball |
| `assets/food/food-5.png` | `22:161` / `CustomEmoji_Digimon_5` | Strawberry |
| `assets/food/food-6.png` | `22:162` / `CustomEmoji_Digimon_6` | Drumstick |
| `assets/food/food-7.png` | `22:163` / `CustomEmoji_Digimon_7` | Steak |
| `assets/food/food-8.png` | `22:164` / `CustomEmoji_Digimon_8` | Cake |

These remain restricted, private-prototype Digimon assets; export is not a
distribution license. Emotes elsewhere on the sheet were deliberately excluded.

## Verification

`tests/food_care_runner.gd` covers migration, each favorite and icon, engaged and
offline timing, fullness gates, harmless expiry, reward accounting, persistence,
invalid saved values, failed-save rollback, portrait/desktop bubble placement,
modal visibility and actual picker feeding. It intentionally injects one save
failure. Run with `--test-mode`; add `--capture` with a graphical renderer to
save isolated screenshots under `/tmp/food-care-*` and `/tmp/food-picker-*`.
The suite never loads or changes the player's save.

### Current verification result

The 36 food checks passed headlessly and in the graphical renderer. Screenshots
were inspected at 360×640, 390×844 and 1280×720. Care rules, care UI, migration,
persistence, battle v2/v3, live battle, 3D battle presentation and the 67 native
sprite/environment pipeline tests passed. The two native pipeline fixtures now
copy the existing shader dependencies along with scripts/scenes.

The complete regression script is **not fully green**: the headless care camera
suite passes its 94 assertions but emits a dummy-renderer material teardown
error; the same suite passes cleanly in the graphical renderer. The older
Green Shade spike test also fails five attack-fallback / camera-clamp assertions.
Those expectations and gameplay systems were not changed for the food feature.
