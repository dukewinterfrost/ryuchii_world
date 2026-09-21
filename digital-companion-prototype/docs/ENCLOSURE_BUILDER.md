# Enclosure builder

## Experience and scope
Select Build, choose a building, and see a ground grid and its exact footprint. Drag or nudge the preview; rotate its footprint and entrance. Green means placeable, red explains why placement is blocked. Apply commits the whole draft and its material cost together. Cancel restores the saved enclosure without spending anything. Existing owned items can be moved or stored for free. Construction is immediate in this prototype.

The references are interaction inspiration: readable footprints and placement feedback from strategy builders, compact useful facilities and gentle resource decisions from cozy builders. No source-game assets are copied.

## Starting balance (placeholders)
| Object | Cells | Wood | Stone | Fiber | Use |
| --- | --- | --- | --- | --- | --- |
| Potty | 4×4 | 8 | 4 | 0 | Automatic bathroom use at discipline 50; reachable entrance required |
| Campfire | 5×4 | 10 | 8 | 0 | Cook meat or potato; consume one raw ingredient and one wood |
| Pond | 8×6 | 0 | 20 | 6 | Rinse/cool down: recover 25 fatigue, reduce virus by 3; 60-second cooldown |
| Rug | 5×4 | 0 | 0 | 6 | Decoration |
| Planter | 2×2 | 3 | 0 | 2 | Decoration |

Starter construction grant: 60 wood, 60 stone, 30 fiber, 6 raw meat, 6 potatoes. Existing owned decorations remain owned. A clearly labeled prototype supply refill makes repeat testing possible until gathering exists. Material art is intentionally placeholder text. Cooking creates a saved prepared meal; serving uses the existing food effects. No new temperature or hygiene meter is invented; pond cooling is fatigue relief and rinsing reduces virus.

## Authority and persistence
- HabitatRules owns cells, rotated footprints, occupancy and reachable facility entrances.
- EnclosureRules owns material quotes, atomic inventory/layout changes, cooking and pond effects.
- GameState commits candidate states through the existing save transaction. Save v10 migrates earlier saves once; failed writes leave the previous state intact.
- Drafts never alter the live companion position, camera, theme, materials or scenery. New purchases increase decor_owned; storage conserves ownership. Refunds are stored objects, not exploitable material refunds.
- Decorative scenery overlapping committed building footprints is suppressed from the saved layout on load. Native trees are removable scenery; boundaries and authored non-removable obstacles remain blocked. Scenery returns when a building is stored/moved away; permanent terrain clearing is deferred.
- Facilities must remain reachable after any edit. Sleeping/training blocks facility use. Do not teleport the companion to manufacture access.

## Art and integration map
| Skill/integration | Purpose | Contract |
| --- | --- | --- |
| game-feature-planning | Ground feature in existing Godot mechanics | This spec, placeholder register and acceptance evidence |
| PixelLab REST API + project sprite adapter | Generate original native pixel art | Durable submission receipt before POST; GET-only resume; originals, prompts and hashes retained |
| figma-use | Store plan, specs, originals and optimized review assets | Existing Digital Companion Pixel Workshop, new enclosure page |
| Kie.ai / Nano Banana 2 (optional) | Concept exploration only if direct PixelLab output needs it | Not needed for first pass; preserve provider choice and original references |
| Godot 4 | Grid, save transaction, care routing and rendering | Existing project presentation and rules, 2D fallback supported |

Potty and campfire source canvases 128×128, pond 160×128. Campfire uses a static stone/log/spit base and separate 64×64 flame. Target animation: four native frames at 8 fps, shared texture/clock, no particles or shadow-casting light per fire; an unanimated frame remains valid until a loop is reviewed. Inspect transparent art on a matte before promotion. Figma holds review assets and the design specification; local files retain machine-readable generation receipts and runtime data.

## Implementation sequence
1. Inspect current save/UI/scenery and preserve existing work.
2. Generate one still per object plus detached flame; archive in Figma with footprints, costs and behaviors.
3. Implement material economy, migration, quote/commit and facility rules with focused tests.
4. Connect build controls, preview validity, facility actions and automatic scenery suppression.
5. Verify save reload, cancel/invalid placement, relocation/storage, blocked access, cooking/pond and both presentation paths. Run project checks and inspect the actual scene.

## Acceptance and uncertainties
- Invalid/overlapping/out-of-bounds placement and blocked entrances cannot charge materials.
- Re-applying an unchanged layout never charges twice. Insufficient materials rejects the entire draft.
- Cancel restores scenery and leaves inventory unchanged. Reload preserves construction and inventory.
- Old saves keep their companions and ownership; crowded placements relocate to fit larger footprints and receive construction stock exactly once.
- High discipline plus reachable potty prevents bathroom accidents; low discipline retains guided training.
- Cooking consumes ingredients exactly once; missing campfire or inaccessible facility rejects use.
- Pond recovers fatigue with an enforced saved cooldown, never bypassing sleep/training.
- Check visuals for readable silhouettes, tile/entrance alignment, transparent edges and foliage overlap.
- Starting costs, cooldowns, dimensions and relief amounts are hypotheses for playtesting. Automated checks do not establish fun or final animation approval.

## Implementation and verification · 2026-09-20
Implemented in `EnclosureRules`, the existing habitat rules, GameState, care controls and native environment presentation. Save schema is v10. Facility commands walk to the nearest reachable entrance and recheck access before committing. The build camera widens temporarily and restores its previous zoom on exit. Reduced motion holds the flame on its first frame. Scenery suppression is cached by layout and preserves the existing parallax visibility rules.

PixelLab produced 4 potty, 4 campfire-base, 4 pond and 16 flame variations. Selected stills are source variant 1. A separate animation request returned 5 frames for a requested 4-frame loop; the last is byte-identical to the first. Runtime uses the four unique consecutive frames, retaining all original provider output. Native alpha was preserved. Runtime flame atlas is 256×64; no particle emitter or flame shadow is added. The account balance was 1,942 before this work and 1,856 afterward (observed decrease: 86 subscription generations; no credit purchase). Kie.ai was not needed.

[Figma review and source archive](https://www.figma.com/design/syQM2pShfeCTfXms0HmzTB?node-id=156-150) contains the brief, selected stills, every source variation and the optimized flame sheet. Local prompts, durable job receipts, hashes and selection rationale are in `assets-source/enclosure/2026-09-20/`.

Verified:
- 34 focused enclosure checks pass, including costs, overlap, blocked access, insufficient funds, storage, repeated application, real v8 migration, save reload, pond cooldown, discipline-only potty use and native-tree replacement.
- Rendered Godot run verifies an actual walk to the pond and effects at arrival. Phone-sized screenshots of play and build modes were reviewed; the initial menu overflow and flame depth were corrected. 2D fallback is also captured.
- Relevant existing suites passed: care v4 (38), home regions (59), care UI (27), home 3D (49), camera (94), state/save transaction checks, food and status suites, and scene smoke.
- The complete project suite was attempted and resumed after the failing group to finish remaining checks. The older Green Shade Sprite-in-3D spike reports five failures: three attack/fallback expectations and two camera-frustum clamp expectations. This is a limitation of the overall checkout's verification; no claim is made that the full suite is green. Enclosure implementation does not change those attack or camera-clamping functions. Remaining architecture, environment content/workshop, scene-builder and Rootbound suites passed.

Visual evidence: `docs/reviews/enclosure-builder/`. Run `tests/enclosure_runner.gd` headlessly with `-- --test-mode`; run `tests/enclosure_visual_runner.gd` with the renderer and `-- --test-mode`. Visual tests use an isolated save, not the player's save.

## Placeholder register
| Placeholder | Limitation | Replace when / completion criterion |
| --- | --- | --- |
| Materials and refill button | Test stock, no gathering economy or material icons | Gathering rewards and resource icons exist; remove the explicit prototype refill |
| Costs and pond balance | Starting values only | Playtesting confirms useful decisions without repeated menu friction |
| Food ingredients | Separate prototype stock; original unlimited food pantry still exists | A unified limited pantry economy is designed |
| Building art | Agent-reviewed first generated direction | User art review accepts or revises these original designs |
| Rotation art | Layered geometry rotates with the footprint; flame stays camera-facing and 2D fallback retains single-view sprites | Directional fallback art may be added after review |
| Construction | Instant on Apply, no worker/build timer | Add timed construction only if pacing tests justify it |
| Scenery clearance | Suppressed while occupied, regrows after storage/move | Add permanent clearing persistence if that behavior is desired |
| Pond interaction | Walk, immediate rinse/cooling effect and happy reaction | Authored bathing animation if needed for readability |


## Larger models and depth · 2026-09-20
The live 3D home uses ground-aligned miniature models instead of enlarged upright image cards. Potty 4×4, campfire 5×4, pond 8×6, rug 5×4 and planter 2×2 are authoritative footprints for cost previews, scenery suppression, collision and entrances. Costs are unchanged.

EnclosureModels caches the shared meshes. Separate ground contact, side and top surfaces produce depth and natural companion occlusion. The potty has a wood platform/back, pedestal and hollow ceramic bowl. The fire has a stone ring, crossed logs and raised spit with the original PixelLab four-frame flame. Pond water sits inside the raised stone rim with entry steps and original PixelLab reeds. Rug geometry rests on the ground; the planter has a raised rim, soil and leaves. Palette shading and subtle surface grain keep the geometry compatible with pixel scenery. These are stylized prototype models, not final art approval.

The shared day/night controller tints surfaces and water; flame remains warm. Reduced motion freezes flame and water shimmer. No per-fire particles, dynamic lights or shadow casting were added. Two-dimensional fallback retains the original PixelLab art at the larger sizes. No new paid generations were needed for this revision.

Save v10 validates historical geometry before migrating the active and inactive region layouts. It preserves valid placements, searches nearest valid cells when larger props collide, and returns unplaceable objects to storage. Materials, ownership, companion location and camera are preserved. Tests cover both pure migration and a real v9 repository envelope.

Verification: 34 enclosure checks, 16 renderer depth checks, 38 care-v4 checks, 49 home-3D checks, production-forest pond walking/effects and 2D fallback. The isolated import fixtures now include synthetic enclosure textures; all 67 sprite/environment pipeline tests pass. Day/night and front/behind renders were reviewed. The broader checkout is not fully green: the environment spike reports five attack/camera failures, and scene_builder_runner reports 422 failures out of 2,124 checks concerning lower-woodland root positions, terrain burial and floor height. These assertions concern existing transition scenery rather than EnclosureModels. Architecture (61), region content (84), workshop (122), care reference (26) and Rootbound ledge (7,480) pass in this run. The earlier scene-builder pass recorded above is historical, not the current result.

[Figma scale/depth archive](https://www.figma.com/design/syQM2pShfeCTfXms0HmzTB?node-id=177-150) contains twelve production-forest captures and implementation notes. Local evidence is in docs/reviews/enclosure-depth. The two before-* images are legacy fixture captures, not a matched production-forest comparison. Run tests/enclosure_depth_runner.gd with a renderer and -- --test-mode to reproduce the new captures. All visual runners use isolated save state.
