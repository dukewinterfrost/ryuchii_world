# Editable combat content

Edit `moves.csv`, `items.csv`, `natures.csv`, and `tuning.csv` in Excel, Numbers, or a text editor. Preserve the first-row column names and stable IDs. Export UTF-8 comma-separated CSV; quote cells that contain commas. A UTF-8 BOM and reordered columns are supported.

The battle sandbox **Reload tables** action validates all four files, then starts a fresh battle using the new snapshot. Failed edits show the file, row, column, and reason while keeping the previous valid configuration. Existing battles and v4 replays retain their complete configuration and content hash. After an app restart with invalid content, live battle creation must show the loader error and remain unavailable until corrected. Care save identities remain available independently of balance files.

## Units and rounding

- Times are seconds in CSV; the loader rounds each phase to the nearest tick at 30 ticks/second. The total attack duration is rounded charge + rounded active + rounded recovery. `0.033333` gives one tick. Use the sandbox's effective timing display when tuning.
- Distances are arena units. Runtime ground coordinates use 1,000 fixed units per arena unit.
- Projectile speed is arena units/second, converted to fixed units/tick. `projectile_radius` is a collision **radius**; `melee_width` is the **full width**, so the baseline width 12 gives a collision half-width of 6. Visual scale does not change collision geometry.
- `power_multiplier=1.5` becomes integer power 150. `damage_variance=0.1` means ±10%; successful collisions determine hits.
- `movement_while_casting` and `equippable` accept `true` or `false`. List multiple species with `|`.
- Multipliers use a 1,000 basis in the normalized snapshot. `rush_speed_multiplier=2.5` becomes 2500; haste `movement_multiplier=1.35` becomes 1350.

## Stable content and placeholders

Each species must keep its free, non-equippable melee fallback and its existing special. `opening_tackle` is an innate, free rush available to all species. The three Agumon starter abilities remain equippable for save compatibility. Adding equippable abilities requires the existing learning/loadout flow to grant them; a new table row does not silently teach a move.

`animation` currently references `basic_attack` or `special_attack`. `effect` selects the procedural placeholder family `impact`, `fire`, `bubble`, or `rush`. These references are validated, and the existing approved creature artwork remains authoritative. New effect families require presentation support before they can be referenced.

Item `amount` is HP/MP restoration or barrier absorption. Haste has `amount=0`; its **movement_multiplier** is the single source of its speed increase. Item durations are seconds. Inventory starter grants and win rewards are explicit gameplay rules, so adding a row never grants stock automatically.

Nature weights are integers from 0 to 100. `opening_tackle` maps saved personality names to the aggressive opener without renaming those personalities. The Speed curve's authored tuning is `speed_base + speed_bonus × speed / (speed + speed_half_stat)` arena units/second; all three terms are configurable.

## Loader contract

`CombatContent.load_tables(directory)` returns `{ok, config, errors, error}` without changing the cache. `reload_tables(directory)` commits only a valid complete load and also returns `previous_config` (the retained valid cache). `defaults()` returns an independent copy of the current valid snapshot, or `{}` when first load failed; `last_errors()` explains failure. Callers must not substitute an unvalidated battle configuration.

`moves_for_species(species, config)`, `move_metadata(config)`, and `item_metadata(config)` expose independent copies. `normalize_snapshot(config)` restores integer values after JSON parsing. `validate_snapshot(config)` validates pinned replay content without file access; `snapshot_hash(config)` sorts dictionary keys, normalizes integral JSON floats, excludes the hash field itself, and returns `sha256:…`.

Snapshot shape: `{schema_version: "combat-content-v1", ticks_per_second: 30, scale: 1000, moves, items, natures, tuning, sha256}`. The pure simulator receives this snapshot; it does not read files or mutable metadata. `GameDefinitions.refresh_combat_metadata()` refreshes care/loadout display metadata after an intentional global reload; a sandbox reload can use the snapshot directly.

The `.csv.import` files deliberately use Godot's **Keep File** importer. Future export presets must include `assets/combat/*.csv` in their non-resource include filter so these runtime data files are shipped.

Verify with `tests/combat_content_test_runner.gd` using the isolated `--test-mode` flag.
