# Five-region sprite-in-3D content set

Revision `2026-09-12.001` defines one shared environment kit, one home habitat,
and one battle arena for each region.

| Region | Environment asset | Home (40×48) | Arena (30×36) | Development art status |
|---|---|---|---|---|
| Green Shade | `environment-green-shade` | `habitat-canopy-clearing` | `arena-rootbound-glade` | Passed spike direction; final human review pending. |
| Shellfish Beach | `environment-shellfish-beach` | `habitat-tidepool-camp` | `arena-breaker-cove` | Source-card placeholder; independent side/roof slices missing. |
| Toy Maze | `environment-toy-maze` | `habitat-wind-up-plaza` | `arena-clockwork-maze` | Source-card placeholder; isolated building sides/roofs missing. |
| Mechatropolis | `environment-mechatropolis` | `habitat-service-deck` | `arena-reactor-causeway` | Source-card placeholder; platform-edge/side cards missing. |
| Nephelis Abyss | `environment-nephelis-abyss` | `habitat-cloudfall-sanctuary` | `arena-rift-platform` | Source-card placeholder; crystal/side cards missing. |

All kits pin `sprite-in-3d-portrait-v1`: 32 ground units per meter, perspective
28° FOV, 50° camera pitch, +8° fixed card tilt, and `KEEP_WIDTH`. Authored card
yaw and layout rotation are zero. Each landmark has at least three depth-tested
planes and one separately authored gameplay footprint. The home and battle
layouts reference that same footprint through explicit blockers/obstacles.

The canonical isolated resolver is
`tests/fixtures/regions/index.json`. It includes stable region IDs, the `forest`
and `forest-arena` compatibility aliases, five contextual encounter IDs, exact
environment content pins, package fingerprints, and links to pending review
artifacts. Debug code may use this index only in isolated/test mode; production
uses approved catalog assets.

## Verification and review

- Every one of the 15 source layers is SHA-256 bound in
  `assets-source/environments/SOURCE_INVENTORY.json` and classified
  `private-prototype-only`, distribution `not-cleared`.
- Terrain uses one deterministic bounded crop per kit, so there are no chunk
  joins in this revision. Automated QA verifies opaque crop pixels, fixed yaw,
  canonical camera values, explicit footprints, and three-plane stacks.
- Each kit has center, left, right, near, and far 390×844 GPU captures. These
  include one actor behind the landmark, one actor in front, and translucent
  depth-tested VFX. Captures are evidence, not approval.
- Habitat validation checks full free-space connectivity, spawn clearance,
  exactly three reachable waste anchors, and usable decoration zones.
- Arena validation checks body-expanded movement, spawn connectivity, cardinal
  exits, evasion patches, and exact visual-footprint/obstacle alignment.

No generation API was called. No billable job, human approval receipt,
promotion, or runtime catalog mutation was performed.

## Native packaging

The native exporter keeps full-resolution textures as immutable PNG payloads in
the candidate's relative `textures/` directory. `environment.tres` contains the
canonical manifest, role-to-relative-path bindings, and a path-to-SHA-256 map;
it does not embed decoded `ImageTexture` pixel arrays. Candidate metadata binds
the same dependency map, and both validation and the headless Godot probe verify
it against the complete package file tree. The probe hashes, decodes, and
render-configures every dependency, so a missing, tampered, or role-swapped PNG
cannot pass. A 2 MiB `.tres` cap prevents regression to the former ~88 MB file.

This resolves the packaging blocker without changing approval state: checked-in
development fixtures remain `nativeResources: false`, and promotion still
requires an independently approved native candidate.
