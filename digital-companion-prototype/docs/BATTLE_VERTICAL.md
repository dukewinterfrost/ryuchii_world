# Live spatial training battle

## Boundary and ownership

The initial battle is one player companion against Training Agumon in a separate,
portrait forest arena. Companions autonomously approach, circle, space, guard,
attack and evade. Player coaching orders are Auto, Attack, Defend and Keep Distance;
there is no direct movement control. Teams, items, PvP and cross-launch match
resumption are deferred.

The pure `BattleSimulator` owns 30 Hz fixed-point combat. `GameState` owns the live
session and settlement. The battle scene reads the authoritative session and asks
GameState to advance one tick; animation signals do not resolve hits. A completed
match can be replayed at 1×, 2× or 4×, or skipped to its end. Live combat has no skip
to a precomputed result.

See `SPATIAL_COMBAT.md` for the versioned geometry, perception, timing and replay
contracts. Existing HP, MP, offense, defense, speed, brains and species specials
are preserved. Speed changes movement/evasion, while brains changes reaction
latency and escape judgment. There is no random dodge-success roll.

When an arena pins an approved Environment, `BattleWorldPresentation3D` renders it
inside an `EnvironmentView3D` SubViewport beneath the existing Control HUD. Fighter
ground coordinates map to XZ; `AnimatedSprite3D`, contact-shadow quads, prop plane
stacks, and depth-tested `WorldVFX3D` are presentation only. No 3D collision or
physics result is read back into the simulator. A missing, stale, or unapproved
Environment clears any previously active package, activates the existing 2D arena
safely, and displays a fallback notice. The 3D field fills the portrait viewport;
the HUD remains a separate CanvasLayer above it.

## Live-session interface

- `start_training_battle(seed_value=-1, encounter_id="")` derives the contextual
  encounter from the active home region (an explicit debug/test encounter may be supplied) and returns a copied session
  at tick zero, with no result or reward. It rejects overlapping live matches and
  unsaved completed matches. The new battle ID uses a `battle-v2` prefix; old saved
  IDs remain valid historical records.
- `active_battle_result` is the authoritative session dictionary. Views may read
  it without copying its entire log each frame, but must not mutate it.
  `get_active_battle()` returns a defensive copy for snapshots/status.
- `queue_battle_order(order)` returns `{ok, order, tick}` for a valid next-tick
  command. Multiple commands on one tick preserve input order. Paused, completed
  and missing sessions reject orders.
- `advance_training_battle()` advances exactly one tick with the queued commands,
  returns new events and automatically invokes settlement on terminal completion.
  It does nothing while `battle_paused` is true.
- `finish_training_battle()` settles only the existing completed session. It returns
  `{ok, awarded, battle_id, reward}` on success; failed persistence returns
  `{ok:false, error, retryable:true}`. The session exposes `reward_saved`, `reward`
  and `settlement_error` for UI feedback and the retry button.
- `clear_active_battle()` returns false for an unsaved completed match. An unfinished
  match may be abandoned without reward; a durably settled match may be closed.

Focus loss/application pause sets `battle_paused`; focus return/resume clears it.
The scene must discard its rendering accumulator while paused so returning to the
window does not simulate a backlog of missed battle time. Care time remains under
the existing care rules and is independent of the battle's simulation clock.

## Content selection and replay

Starting a battle captures each fighter's actual asset ID/revision from the
companion asset library. Replays use `build_pinned` for those exact revisions,
never the current catalog as a substitute. Legacy side-view art remains available
while directional artwork awaits human approval; visible fallback indicators must
not claim that eight-direction coverage is complete.

Contextual encounter IDs resolve to the five arena assets: Rootbound Glade, Breaker
Cove, Clockwork Maze, Reactor Causeway, and Rift Platform. The live UI does not
offer an arena selector; review/debug tooling may enumerate them all. `forest` and
`forest-arena` remain aliases for `encounter.green-shade.rootbound-glade`, and `graybox` remains a
test-only diagnostic. Locked story regions cannot start live encounters. The default
follows the selected home and Green Shade falls back to the handcrafted forest arena until
the new arena and Environment are explicitly approved and promoted.

Environment-backed arenas contain a complete `{assetId, revision, contentSha256}`
pin and static visual placements. The Environment library verifies that pin against
the runtime catalog, candidate metadata, every payload hash, and native resource
identity, loading only one active package. `ArenaAssetLibrary` independently requires
the catalog key, entry, contextual encounter, JSON manifest, native Resource, review
state, package hash, every payload hash, region, and Environment dependency to agree.
Replays embed the full arena (including
ground, spawns, obstacles and presentation placements), the Environment pin, the
arena candidate `contentSha256`, contextual encounter ID, visual revisions, and
unchanged deterministic inputs. Legacy environment-free records retain their old shape.

`BattlePlaybackModel.setup(completed_session)` freezes the source and validates
that replaying its recorded inputs reconstructs the supplied terminal result.
An incomplete or inconsistent source sets `error` and produces no replay session.
`advance(delta)` steps a fresh session at 30 Hz using the recorded command ticks.
`get_session()` exposes replay positions read-only; `source_result()` returns a
copy of the original completed session. Speed and skip never call GameState,
change care, submit commands to the live session, or award rewards.

## Persistence and failure behavior

Starting a battle does not write, increment the serial, or reserve a result. At
completion, GameState applies the reward to the **latest** care state, then saves
that state and its completed-battle marker together. Changes to hunger, happiness,
bond, naming or other care progress during the battle must not be overwritten by
the start snapshot.

If persistence fails, GameState restores the latest pre-reward care state but keeps
the terminal battle in memory. The repository discards the uncommitted staged file,
so reloading cannot resurrect an unawarded reward. Retry recomputes the reward
against any additional care changes and commits the same battle ID once. Until
success, leaving the completed match or starting another is blocked. Closing the
app still abandons an unsaved volatile session; the UI warns to keep it open.

The existing save schema and modest, penalty-free rewards are unchanged:

| Outcome | Bond | Training points |
| --- | ---: | ---: |
| Win | +2 | +3 |
| Draw | +1 | +2 |
| Loss | +1 | +1 |

Repeated settlement, replay and post-reload duplicate claims do not award again.
Completed replay data is session-local; persistent/resumable battles are not part
of this initial implementation.

## Verification and safe diagnostics

Run `tests/run_tests.sh`. It runs care rules, save/migration hardening, pure spatial
combat, live lifecycle/replay integration, native resources/review, Python pipeline
tests (including native export) and the scene smoke suite. It scans full outputs
for parse/script errors even when Godot exits zero, and permits only the exact
expected save-failure injection messages.

All test/demo/review processes use `--test-mode`, `--battle-demo` or `--asset-review`
to isolate the autoload from the real companion save. Direct/F6 review-scene launches
are also detected before repository access. Repository integration tests instantiate
their own GameState objects with unique fixture save paths and clean up only those
files. The review scene runs pure simulation previews, never reward settlement.
Explicitly marked `devFixture` arena/habitat review packages may resolve only an
adjacent, hash/native-verified Environment while GameState is isolated. That path
never adds the fixture to the production catalog and cannot activate during play.
