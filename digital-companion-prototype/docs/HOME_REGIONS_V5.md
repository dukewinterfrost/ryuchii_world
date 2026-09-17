# Home regions and save v5

The live home keeps care, movement, decoration collision, and pathfinding on a
deterministic 40x48 ground grid. `CareHabitatView` mirrors the acknowledged
ground position into `CompanionPresentation3D`; `EnvironmentView3D` is only a
presentation child. A touch is ray-projected to the horizontal XZ plane and is
discarded when the ray misses the environment movement bounds. Godot 3D
physics is never consulted for movement or placement validity.

The active layout remains in `state.habitat`. `state.home_region` contains its
canonical region ID, and `state.habitats` holds only inactive regional layouts.
This means there is exactly one active home and no duplicated active save
record. Decorations remain a global inventory: switching moves layouts without
changing counts, applying a draft reconciles only that region's old and new
placements, and an item placed in another region remains unavailable. The
durable `inventory.decor_owned` ledger is the entitlement authority: for every
item ID, unplaced inventory plus placements across all regional layouts must
equal the owned total. Saves with forged gains, silent loss, or duplicate
regional instance IDs are rejected. Early v5 saves that predate this ledger are
repaired once by inferring the smallest lossless total from their existing
inventory and placements; their original bytes remain in the rollback generation.

Schema v5 adds `progression.story_flags` with these future hooks:

- `story.region.shellfish_beach`
- `story.region.toy_maze`
- `story.region.mechatropolis`
- `story.region.nephelis_abyss`

Green Shade is always open. `forest` and `forest-arena` are compatibility
aliases for `green-shade`. A v4 migration translates the old 20x24 layout by
`(+10,+12)`, preserving item identity, rotation, counts, camera preferences,
and creature position in the center of Green Shade. The original v4 envelope
is retained as the repository backup before the v5 primary is written.

`HabitatAssetLibrary` resolves a promoted habitat from the immutable runtime
catalog, verifies its package and environment dependency, and activates only
that one environment. If only 3D presentation fails, the verified habitat's
grid, blockers, spawn, waste anchors, and decoration zones remain authoritative
in 2D while the active environment package is cleared. Only the absence of a
verified habitat selects the deterministic 2D 40x48 engineering field. Files under
`tests/fixtures/regions` are accepted only when the caller explicitly enables
review fixtures and the package declares `devFixture: true`; those files remain
pending human review and cannot enter production resolution.

Automatic potty catch-up receives the same active habitat manifest as movement,
so an authored blocker cannot disappear when rendering is unavailable. Switching
homes cancels the old route and edit state, resets the manual camera offset, then
hydrates the incoming region's acknowledged cell, 2D/3D companion positions,
follow mode, and zoom. A rejected movement step performs the same resynchronization.
Disabling Follow freezes the visible camera focus in world space. Subsequent
creature movement and ordinary state refreshes cannot drag this manual view.
Drag panning is direct (including over scenery outside the editable grid), while
Follow uses exponential easing; reduced motion removes easing.

Home zoom is a logical 0–200% control: 0% fits all four map corners for the current
viewport, 100% is the default companion close-up, and 200% is the closest view.
Zero is never used as a physical camera scale or divisor. Zoom/follow preferences
remain per-region save fields; existing numeric values stay valid, and zero is
now accepted without replacing a save. Manual focus is transient and independent
of creature position; at 0% the view centers on the full map, then zooming back in
restores the chosen manual focus. Battle framing is unchanged.

Live 3D decorations and waste are world presentations, not debug overlays.
Planters, potties, and waste use small nearest-filtered alpha-cut `Sprite3D`
cards rooted at the ground footprint; rugs use an unshaded textured ground plane.
All keep depth testing enabled. Debug rectangles remain review-only.

Five review-only home manifests currently use revision `2026-09-12.001`:

| Region | Home asset |
|---|---|
| Green Shade | `habitat-canopy-clearing` |
| Shellfish Beach | `habitat-tidepool-camp` |
| Toy Maze | `habitat-wind-up-plaza` |
| Mechatropolis | `habitat-service-deck` |
| Nephelis Abyss | `habitat-cloudfall-sanctuary` |

Run `tests/run_tests.sh` for migration, cross-region inventory, all-map
reachability, 3D projection, camera, edit, and production-fallback coverage.
