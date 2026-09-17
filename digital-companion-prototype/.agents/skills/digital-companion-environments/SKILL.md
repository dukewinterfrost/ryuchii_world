---
name: digital-companion-environments
description: Build and review sprite-in-3D biome kits, home habitats, and battle arenas for the digital-companion Godot prototype. Use for environment source preparation, plane-stack composition, map geometry, camera/depth tuning, pipeline review, or promotion; not for character animation alone.
---

# Digital Companion Environments

Produce a coherent 3D presentation from pixel-art planes while keeping gameplay geometry deterministic and two-dimensional.

## Non-negotiable boundaries

- Treat DigimonUP-derived material as `private-prototype-only` and `not-cleared` for public or commercial distribution. When using those sources, read [references/digimonup-source-inventory.md](references/digimonup-source-inventory.md) and verify the selected bytes before ingesting them.
- Keep navigation, collision, sight, projectile, and occlusion behavior in explicit ground-space data. Never infer a footprint from transparency, perspective, or a painted silhouette.
- Preserve source bytes. Use `./tools/sprites ingest` to copy and SHA-256-bind a source role. If a bound role must change, create a new source revision.
- Do not submit billable generation unless the user explicitly authorizes that submission. The authorization-bearing path is `generate --execute --allow-billable`; a failed or uncertain POST is never retried without provider-account reconciliation.
- Do not record `review --approve` unless a human actually reviewed the displayed artifact and supplied the decision, reviewer, and notes. Do not promote without a valid final approval receipt.
- Reusing a source or completing this workflow does not clear its licensing.

## Route the task

- For one of the five DigimonUP biome kits, load the source inventory reference.
- For slicing, plane stacks, presentation profiles, home/battle composition, or visual QA, load [references/depth-authoring-and-review.md](references/depth-authoring-and-review.md).
- For schema and CLI details, read `docs/SPRITE_PIPELINE.md` and inspect `./tools/sprites <command> --help`; the checked-in CLI is authoritative.

## Production workflow

1. **Audit sources.** Identify the minimum style-authority layers, verify hashes, classify licensing, and choose a new immutable asset revision. Do not treat nearby filename variants as approved inputs merely because they exist.
2. **Bind a review sample.** Create a manual or generation-backed source plan, ingest exact source roles, and declare the sample roles in the plan's review gate. Record source paths as provenance, not as runtime dependencies.
3. **Author the biome kit.** Split art into ground, facade, roof, side, canopy, rear, and ambient roles. Build repeated landmarks as plane stacks with one separate ground footprint. Bind every deterministic resized or masked output through `derivedImages` (parent, script, recipe, and output hashes). Reuse the same kit in the home and battle layouts.
4. **Compose gameplay maps.** Home maps are 40 by 48 cells and battle maps are 30 by 36 cells, with 32 ground units per cell unless a checked-in contract supersedes those plan defaults. Validate spawns, routes, exits, potty anchors, decoration zones, and battle evasion space against explicit blockers.
5. **Review depth.** Inspect center, camera-left, camera-right, near, and far viewpoints at every target portrait size, then inspect 0/0.25/0.5/0.75/1-pixel camera translations. Reject exposed card edges, straight canopy crop bars, narrow slice joins, accordion-like layer separation, transparency/depth-order failures, pixel shimmer, inconsistent scale, or artwork that contradicts a footprint.
6. **Compile and validate.** Compile only after sample approval. Validate the immutable candidate and run the project tests relevant to the changed contract and runtime view.
7. **Obtain final approval and promote.** Preview first; promotion follows a real hash-bound final approval and never happens implicitly.

## Pipeline commands

The checked-in CLI supports `environment` and `habitat` source plans in addition to animation, atlas, tileset, and arena. Build and promote the environment first because habitats and environment-backed arenas accept only a promoted environment revision and pin its `contentSha256` during compilation.

```sh
./tools/sprites new --asset <biome>-environment --revision <revision> --kind environment --provider manual
./tools/sprites ingest --plan <environment-plan.json> --input <absolute-sample.png> --role sample
./tools/sprites ingest --plan <environment-plan.json> --input <absolute-texture.png> --role <declared-source-role>
./tools/sprites review --plan <environment-plan.json> --stage keyposes
```

An environment plan must bind every role referenced by `terrainChunks`, `spritePlanes`, and `ambientPlanes`. Its `sample` gate is approved before compilation. After that real decision, compile, validate, preview, approve, and promote the environment:

```sh
./tools/sprites review --plan <environment-plan.json> --stage keyposes --approve --reviewer '<reviewer>' --notes '<decision>'
./tools/sprites compile --plan <environment-plan.json>
./tools/sprites validate --candidate <absolute-environment-candidate>
./tools/sprites review --candidate <absolute-environment-candidate>
./tools/sprites review --candidate <absolute-environment-candidate> --approve --reviewer '<reviewer>' --notes '<decision>' --no-launch
./tools/sprites promote --candidate <absolute-environment-candidate> --review <absolute-final-review.json>
```

Then create a habitat, edit its `habitat.environment` binding to the promoted environment's asset ID and revision, and author the explicit layout before compiling it:

```sh
./tools/sprites new --asset <biome>-home --revision <revision> --kind habitat --provider manual
./tools/sprites compile --plan <habitat-plan.json>
./tools/sprites validate --candidate <absolute-habitat-candidate>
./tools/sprites review --candidate <absolute-habitat-candidate>
```

Environment-backed arenas remain `--kind arena`: add `arena.environment` and `arena.presentation.staticPlacements` to the generated arena plan. Compile pins the same promoted environment content without altering combat geometry. Use the same final-review and promotion commands for habitat and arena candidates.

Normal `compile` emits native `environment.tres`, `habitat.tres`, or `arena.tres` resources. `compile --no-native` is for isolated compiler tests and cannot be promoted.

## Completion report

Report the source revision and hashes used, compiled asset IDs/revisions, validation and test results, review status, and anything deliberately left unapproved. Call out private-prototype licensing whenever DigimonUP-derived bytes are included.
