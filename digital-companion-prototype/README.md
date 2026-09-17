# Digital Companion — Care, Training and Auto-Battler

A private Godot 4.7.2 prototype combining the `Botamon → Koromon → Agumon`
care loop with Digimon World 1–inspired, spatial training battles.

New here? Start with the [setup and first-run guide](docs/GETTING_STARTED.md)
and the repository [contributor guide](../CONTRIBUTING.md).

## Play

From this project directory, run `./open-in-godot.command`, then press **Cmd+B**
on macOS (or the top-right Play button) in the editor. Feed, pet, talk, clean up, and develop your companion; choose
**Battles** in the care screen to enter a separate training arena.

To open the game directly without the editor, run `./open-in-godot.command --play`.
Both modes explicitly select the care scene and work from any current directory.
Launcher logs are saved to `.godot/launcher-editor.log` or `.godot/launcher-play.log`.

**macOS permission:** because this project lives in Documents, Godot needs
**System Settings → Privacy & Security → Files & Folders → Godot → Documents Folder**
enabled. If it was denied, editor Play can show the Project Manager instead of
the game and report `getcwd` / `DirAccessUnix` null errors—even when the editor
opens successfully from a terminal. Enable that specific permission, quit Godot,
then reopen with the launcher. Full Disk Access is not required.

### Care, growth and decorating

- **Feed** opens nine pixel-art snacks. Botamon favors pudding, Koromon favors
  strawberries, and Agumon favors drumsticks. Occasional food thought bubbles
  show cravings; tap one to choose a snack. Favorites increase happiness, and
  satisfying a craving adds happiness and bond. Missing one has no penalty.
  See [food tuning, artwork sources and save v6](docs/FOOD_CARE_V6.md).
- Tap the creature portrait to open full-screen **Status**, **Growth**, and
  **Skills**. Fullness means fed; Growth lists the requirements still needed for
  evolution. Skills unlock at Rookie.
- **Training** offers six 30-second sessions. Start with at least 20 fullness and
  no more than 70 fatigue. Completion raises the selected stat, adds fatigue and
  discipline, and uses fullness. Focus loss pauses training; cancelling or closing
  the app grants no training reward. Fatigue recovers outside training, including
  while the app is closed.
- Pet, Praise and Scold have a shared 30-second reward cooldown. Praise trades
  discipline for happiness; Scold does the reverse. Neither grants bond. Cleaning
  removes waste and virus exposure without granting discipline.
- Use **Tools** for cleanup and habitat editing. Place the starter digi potty,
  rug and planter on the grid; move, rotate or return them to inventory. **Apply**
  validates and saves the layout; **Cancel** discards the draft.
- During the 30-second bathroom warning, **Guide to potty** walks the companion
  to a reachable potty. Guided success raises habit by 20 and discipline by 2.
  At 60 habit and 50 discipline, reachable potties are used automatically, even
  offline. Failed or unavailable routes produce ordinary cleanable waste.
- Zoom buttons and wheel/pinch range from **0% (full map)** through the default
  **100% (companion close-up)** to 200%. Follow gently tracks the companion;
  turning it off freezes the view, and dragging pans freely at the chosen zoom.
  Dragging also turns Follow off. Zoom/follow preferences and the Verdant Field /
  practice background choice survive reloads.
- **Field → Explore map** hides the care panels for a full-window habitat view.
  It starts in manual pan at 45% zoom in landscape or 75% in portrait. Drag to
  explore, use +/− or the wheel/pinch to zoom, and **Focus** to follow the companion
  at 100%. **Back** or Escape restores care controls without moving decorations.

Botamon → Koromon retains its 10-minute active-time and bonding gates. Agumon
requires 30 total engaged minutes, balanced care, bond, offense ≥12 and discipline
≥45. Two offense sessions raise the initial offense from 8 to 12. Eligibility
waits safely until all visible requirements are met; existing evolved saves keep
their species. There is no death, forced rebirth or permanent stat loss.

**Inventory** shows consumables and decor. **More** contains Friends, Shop and
Equipment, visibly reserved for a later release.

For an isolated battle demo that does not load or change your companion save:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/battle_scene.tscn -- --battle-demo
```

Live battles run at 30 simulation ticks per second. Companions approach, circle,
attack, guard, and physically evade. Speed controls movement; brains influences
reaction delay and escape decisions. Give broad orders—Auto, Attack, Defend, or
Keep Distance—without directly steering or cancelling committed attacks.

Approved regional arenas render sprite characters and layered environment cards in
a fixed-axis 3D world with real perspective/depth. The 2D deterministic simulation
is unchanged, and missing/unapproved regional art falls back to the established 2D
arena. Arena choice comes from a contextual encounter, not a player-facing picker;
all five regions remain available in isolated review/debug tooling.

At Rookie, equip and order up to three learned moves in the care Skills sheet,
with an automatic-use toggle per move. Agumon starts with Pepper Breath, Quick
Bite and Heavy Claw. Each species also has a permanent zero-MP melee attack.
Open **Moves** or **Items** over the running arena: selection does not pause the
battle. A requested move waits for reaction/recovery and legal range; a newer
request replaces it, and an unusable request expires after five simulation
seconds. MP is spent only when an attack commits.

Starter supplies are three Small Recoveries (+50 battle HP) and three MP
Recoveries (+24 MP). Items share a five-second cooldown and never consume on a
full meter or invalid request. Consumption is saved before the battle effect;
a save failure rejects use. Consumed items remain spent after abandonment or a
crash. A win grants one of each recovery item, settled once alongside its normal
rewards. Loadouts cannot change during battle.

Live combat pauses on focus loss. Results and rewards are settled only after
combat finishes. Completed replays offer speed/skip controls and never award
again. Closing an unfinished battle grants no reward; cross-launch resumption is
not supported. See [battle behavior and save semantics](docs/BATTLE_VERTICAL.md).

Care saves use Godot's platform-specific `user://companion-save.json`, with the
preceding valid generation in `companion-save.json.bak`. The launcher also avoids
editor startup problems caused by stale terminal working directories.
Save schema v6 upgrades earlier saves, retaining identity, stats, progress,
precise waste slots, home regions, and food preferences/cravings; starter
supplies are granted once. Current replays use pinned battle-v3 content
and command identities; battle-v2 records dispatch to the unchanged legacy
simulator. Replay playback never consumes inventory.

## Sprite and environment workflow

For hands-on environment editing, double-click `open-environment-workshop.command`.
Ten native home/battle working scenes expose the camera, floor patches, sprite
planes, and character placement in Godot. Start with the [editing guide](docs/ENVIRONMENT_WORKSHOP.md)
and [Figma floor texture bank](https://www.figma.com/design/syQM2pShfeCTfXms0HmzTB?node-id=66-150).
These working scenes preserve manual edits and do not replace the live game's
pinned environment packages automatically.

The project-owned pipeline supports animations, effects/UI/prop atlases,
square/isometric TileSets, and playable arena bundles. Codex coordinates image
creation; deterministic scripts compile and validate the results.

```sh
python3 -m venv .venv-sprites
.venv-sprites/bin/python -m pip install -r tools/sprite_pipeline/requirements.txt
./tools/sprites --help
./tools/sprites generate --plan assets-source/agumon/combat-v1/source-plan.json
```

Generation defaults to a zero-network dry-run. The workflow is **new → ingest →
keypose/sample review → complete frames → compile → final review → promote**.
Source bytes and approvals are hash-bound; only explicit promotion changes the
runtime catalog. PixelLab paid jobs additionally require both `--execute` and
`--allow-billable`. See [pipeline commands, contracts, and billing safety](docs/SPRITE_PIPELINE.md).

Eight-direction animation support is implemented, but the new directional
artwork is **not production-ready or promoted**. Existing care art remains the
runtime fallback. The [Agumon direction reference](assets-source/agumon/keypose-review-v1/REVIEW.md)
is an unapproved design board: it has a painted checkerboard, lacks real alpha,
and cannot be sliced into a usable fixed-grid sprite sheet. Correct transparent
keyposes, human approval, full animations, and final review are still required.
The [forest composition sample](assets-source/forest-arena/forest-v1/REVIEW.md) is
also unapproved: its object alignment, decorative readability, pixel grid, and
canopy layering need work. It is ingested only as a sample, not a final background
or runtime asset; existing arenas remain available.
Open the [sample PNG](assets-source/forest-arena/forest-v1/sources/c67502d762649ec770338422e6aaf31594ef4362db2b65f39c6285478e3d833e.png)
and its [exact prompt/provenance record](assets-source/forest-arena/forest-v1/generation-record.json).

Create an eight-direction authoring template, or preview the temporary effects:

```sh
./tools/sprites sheet-template --asset my-companion --revision idle-v1 --action idle --frames 4 --duration-ms 125
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/asset_review_scene.tscn -- --asset-review --placeholders
```

Templates use eight columns × eight facing rows, 128×128 RGBA cells, a fixed
(64,120) foot pivot and explicit used-cell manifests. Generated registration
guides stay separate from artwork. The isolated review scene previews feeding,
hearts, sickness, melee/special attacks, fire/poison/freeze/general hits, knockdown
and stun without changing player state. These overlays never become creature
frames. Poison, freeze, sickness, knockdown and stun have no new gameplay status
mechanics in this release; flinch remains supported.

## Verify

```sh
./tests/run_tests.sh
SPRITE_NATIVE_TESTS=1 .venv-sprites/bin/python -m unittest discover -s tests -p test_sprite_pipeline.py -v
```

Focused engine checks can also run without touching real progress:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/spatial_battle_test_runner.gd -- --test-mode
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/asset_resource_test_runner.gd -- --test-mode
```

The pure care rules, integer battle simulator, persistence boundary, presentation,
and asset compiler are separate. Tests cover deterministic replays, physical
collision/evasion, move and item commands, save failures, migration, training,
potty routing, directional resources, approval gates, and save recovery;
the native pipeline tests use synthetic temporary assets, not paid generation.
The checked runner requires each suite's success marker, rejects unexpected
engine errors and resource leaks, and counts intentionally injected save failures
exactly. It prints a temporary log directory for inspection.

## Release limits

Automated lifecycle tests exercise normal care/training commands with an isolated
clock. A real-time 30–60-minute playtest and physical-device touch/performance
testing are still required; automated tests do not establish those results.
Native screenshot checks used Godot's Dummy audio driver. Rapid-shutdown tests
with CoreAudio showed a transient eating-playback resource warning; normal audio
device playback still needs a manual session and is not fully verified here.
Artwork generation, training mini-games, equipment, shopping, friends, multiplayer
and gameplay status conditions remain future work. This release adds no paid
image service or LLM integration.

## Private asset notice

Digimon names, character art, sound, and extracted material are for private
prototype use only and are not cleared for public/commercial distribution.
See `assets/asset-provenance.json`; public releases need licensed or original art.
