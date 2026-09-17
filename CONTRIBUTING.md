# Contributing to Ryuchii World

Follow the [setup guide](digital-companion-prototype/docs/GETTING_STARTED.md)
first. Work inside `digital-companion-prototype/` for engine and asset changes.

## Where to start

| Area | Entry points and contracts |
| --- | --- |
| Care, evolution, food, and training | `scripts/core/care_rules.gd`, `food_rules.gd`, `habitat_rules.gd`; [care rules](digital-companion-prototype/docs/CARE_VERTICAL.md), [food/save v6](digital-companion-prototype/docs/FOOD_CARE_V6.md) |
| Runtime state and persistence | `scripts/core/game_state.gd`, `save_repository.gd`; [state/UI contracts](digital-companion-prototype/docs/STATE_UI_CONTRACTS.md) |
| Combat and replay | `scripts/battle/battle_simulator.gd`, `battle_playback_model.gd`; [battle contracts](digital-companion-prototype/docs/BATTLE_V3_CONTRACTS.md), [battle behavior](digital-companion-prototype/docs/BATTLE_VERTICAL.md) |
| Care and battle screens | `scripts/ui/care_scene.gd`, `care_habitat_view.gd`, `battle_scene.gd` |
| World presentation | `scripts/environment/`, `scripts/world/`, `shaders/`; [care presentation](digital-companion-prototype/docs/CARE_REFERENCE_DIRECTION.md), [environment workshop](digital-companion-prototype/docs/ENVIRONMENT_WORKSHOP.md) |
| Asset compilation and promotion | `tools/sprite_pipeline/`, `assets/runtime-catalog.json`; [sprite pipeline](digital-companion-prototype/docs/SPRITE_PIPELINE.md) |

Paths in the middle column are relative to the Godot project. `project.godot`
registers `GameState` as an autoload and selects `scenes/care_scene.tscn` as the
main scene. Pure gameplay rules, the deterministic combat simulation, persistence,
and visual presentation are kept separate.

## Make and verify a change

1. Create a branch from the current `main` and keep changes focused.
2. Preserve existing save migration and battle replay behavior. Save schema v6
   is current; old replay versions retain their existing simulator path.
3. For code changes, run relevant focused checks, then `./tests/run_tests.sh`
   before proposing the change. The setup guide lists engine/Python overrides.
4. For visual changes, run the actual care or battle scene and review the result
   in the editor. Automated checks cannot approve animation quality, camera
   composition, audio, or touch behavior.
5. Update the relevant guide or contract when behavior changes. In a pull request,
   describe the change, validation performed, and remaining limitations.

Keep `-- --test-mode` on direct test launches. Use the documented isolated asset
review and battle demo routes when reviewing without affecting a real save.

## Files that belong in Git

Commit source scripts, scenes, shaders, runtime asset bytes, source plans,
provenance/review records, `.gd.uid` files, and asset `.import` settings. The
checked-in `assets/generated/` packages are runtime dependencies despite their
name: do not omit them from a checkout.

Keep `.godot/`, Python virtual environments, logs, export builds, and secrets
out of Git. Root and project `.gitignore` rules exclude these local files.
Do not commit player saves or put API credentials in generation records.

## Artwork and release boundaries

Source plans and review fixtures do not automatically approve artwork. Use the
sprite pipeline's review and promotion workflow before changing a live catalog
entry. Environment workshop files preserve manual editing work; consult their
guide before running builders or moving their assets into the live game.

This repository includes private-use Digimon imagery and reference material.
Keep its existing provenance classifications and distribution restrictions.
Before configuring exports, read the private asset notice and run:

```sh
cd digital-companion-prototype
python3 tools/check_restricted_environment_distribution.py
```

That check catches specific source-package/export mistakes; it does not grant
rights to distribute the assets or replace an asset-rights review. Export
presets and an open-source license are not currently provided.
