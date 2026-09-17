# Spatial combat, battle-v2

`BattleSimulator` is a pure fixed-tick state machine. It does not read files, nodes,
clocks, rendering, input devices, or the care save. `BattleArena` owns the same ground
geometry used by navigation and combat. The live scene translates input into orders
and renders the returned state; persistence settles only a terminal result.

## Public interfaces

```gdscript
create_session(battle_id, seed, player_snapshot, opponent_snapshot,
    arena = {}, max_ticks = 3600, visual_revisions = {}) -> Dictionary
step(session, commands = []) -> Array # mutates session; returns new events
replay_record(session) -> Dictionary
replay(record) -> Dictionary
simulate(battle_id, seed, player, opponent,
    max_ticks = 3600, arena = {}, visual_revisions = {}) -> Dictionary
ground_position(actor) -> Vector2
```

Creation/replay return `ok: false, error: String` for rejected inputs. Creation copies
fighter snapshots, arena content and visual pins. An omitted arena uses the test
graybox. Input seeds are normalized to the existing project RNG's 31-bit domain;
the canonical seed is recorded. Snapshots retain the six established stats,
natures, species specials, damage power and MP cost conventions.

`visual_revisions` is optional for synthetic tests; real sessions provide each
fighter ID mapped to `{assetId, revision}`. `content_revisions` records these as
`visuals`, alongside the arena identity/revision and `combat: "battle-v2"`. Replays
embed the complete arena, both fighter snapshots, visual pins, simulation version,
maximum and elapsed ticks, and accepted orders. Presentation may load only those
pinned asset revisions, not silently substitute a newly promoted revision.

Session fields include `tick`, `complete`, `max_ticks`, `fighters`, `fighter_order`,
`actors`, `projectiles`, `log`, `commands`, and `result`. Actors are keyed by fighter
ID and expose `hp`, `mp`, `pos`, `previous_pos`, `facing`, `action`, `action_tick`,
`action_duration`, `order`, and `pending_order`. Positions are integer ground units
multiplied by **1000**. Facing is N/NE/E/SE/S/SW/W/NW and faces the opponent/locked aim,
independently of movement. Sprite frame timing must follow action ticks; sprite
animation signals must never cause attacks or damage.

## Timing, orders and replay

- Exactly 30 ticks make one simulation second. The maximum/default battle duration
  is 3600 ticks (120 seconds); timeout is always a draw. The renderer may process
  several ticks per frame without changing outcomes.
- `step` accepts `{fighter_id, order, tick?}`. Omitted tick means the next simulation
  tick. Explicit ticks must match that tick; unknown IDs/orders, malformed inputs,
  and future/past tick submissions are rejected, not queued. Accepted commands are
  recorded in supplied array order; the last command to a fighter on a tick wins.
- Orders are `auto`, `attack`, `defend`, `keep_distance`. Acknowledgment is immediate,
  but the intent takes effect after reaction latency and committed-action recovery.
  Orders persist until replaced. They do not directly control position or cancel
  windups. UI input must be disabled during replay.
- Replay validates its version, embedded arena, visual pins, duration, and ordered
  inputs before stepping. It supports both partial-session inspection and completed
  battle playback. Calls after terminal completion do nothing.
- Project-owned RNG, integer square-root normalization, stable actor order, and
  N/W/E/S navigation ties are frozen by `battle-v2`. Change the version and golden
  fixtures when intentionally changing these rules. No engine physics or navigation
  avoidance participates in authoritative outcomes.

## Movement, intuition and hit geometry

Fighter bodies are conservative ground-aligned AABBs with a **14-unit half-extent**.
The schema's `maxBodyRadius` is also an AABB clearance half-extent; it must accommodate
the fighters. Graphics are not used to infer body size. All moves sweep these bodies
against ground/obstacles and the other fighter; relative motion checks prevent two
simultaneously moving bodies crossing corners between ticks.

Speed gives `1550 + min(speed, 100) * 85` fixed-point distance per tick (speed8 is
66.9 ground units/second). Evasion travels at 1.75 times that speed for 12 ticks.
Brains gives `max(3, 20 - min(brains, 34) / 2)` integer reaction ticks. At brains12,
escape selection additionally compares both perpendicular exits and retreat based
on boundary clearance. Lower-brains companions choose the first feasible side.
These are v1 tuning curves, not a claim of exact Digimon World mechanics.

Both actors observe the preceding tick before either chooses an action. Only visible
telegraphs and already-released projectiles create threats. Brains8 companions can
react naturally; no future enemy AI decisions are queried, no dodge chance cancels
a hit, and blocked escape routes result in guarding rather than teleportation.

Basic attack: 20 windup ticks, 3 active ticks, 36 total ticks. The locked attack ray
reaches 58 ground units and has a 6-unit half-width. It intersects the exact convex
volume swept by the target's expanded AABB, excluding phantom corners produced by
an enclosing min/max rectangle. A target is hit at most once per action.

Special attack: 27 windup ticks, one release tick, 50 total ticks. The projectile
has a 4-unit half-extent, moves 7 ground units/tick, and expires after 270 ground
units. Its relative segment sweeps both its own movement and the target's movement.
The earliest obstacle blocks it before a later target hit; obstacle ties win.
Already-released projectiles remain independent of their owner's subsequent actions.

Guard lasts 24 ticks, halves damage, and restores at most3 MP on completion, capped
at the snapshot's maximum. Actual hits may flinch an uncommitted moving/idle fighter
for6 ticks; they do not cancel already-committed attacks. Stable actor/projectile
ordering resolves same-tick exchanges. Nature and broad orders influence approach,
circling, spacing, melee/special preferences, and guarding.

## Arena contract and initial content

`schemaVersion: 1`, `kind: "arena"`, `assetId`, `revision`, `projection` (square or
isometric), `ground: {width, height, cellSize}`, `maxBodyRadius`, `spawns: {player,
opponent}`, `obstacles`, and `tiles` are required. Optional `tileSet` pins an asset
ID/revision. Each tile has `cell`, `atlas`, `alternative`; cell coordinates must be
inside the ground grid. Each obstacle has a unique ID, integer `[x,y,width,height]`
rectangle and explicit independent `movement`, `projectile`, `sight`, `occlusion`
booleans. `projectile` blocks both ranged trajectories and melee attack rays.

Ground dimensions are80–4096, cells8–128, and dimensions must divide into whole
cells (at most16384). At most512 obstacles are accepted. Validation checks bounds,
spawn/body separation, three clear one-cell exits at each spawn, and a reachable
finite-body path between spawn regions. The asset compiler applies additional
production layout-quality gates; runtime validation does not assert aesthetic
approval or that every decorative corner is reachable.

Navigation follows stable four-neighbor shortest grid paths with each center and
edge swept for actual body clearance. It uses direct movement when unobstructed,
replans at most once/second for an existing path, and clamps travel at near waypoints
to avoid high-speed oscillation. Projection affects only the view, never geometry.

Placed tiles with explicit `combat.occlusion` use Y-sorted child artwork at the
front/bottom of their canonical tile-derived footprint. Other tiles remain in the
ground pass. This allows an actor to pass behind or in front of a canopy without
making it a movement, projectile, or sight blocker. Square and isometric atlas
placement is unchanged; native TileSet light-occluder polygons are separate from
this visual depth ordering.

`assets/arenas/graybox.json` is a640×480 open engineering fixture.
`assets/arenas/forest.json` is a360×540 portrait engineering arena with a central
rock, solid tree trunk, nonblocking canopy, and projectile-permeable shrub. These
are **handcrafted test layouts**, not newly generated or human-approved artwork.
The review scene may use the existing forest backdrop and explicit debug shapes
until artwork is approved and promoted through the pipeline.

## Verification

Run `godot --headless --path . --script tests/spatial_battle_test_runner.gd -- --test-mode`.
The suite includes the shared Python/Godot arena corpus; malformed snapshots and
replays; disconnected layouts and thin blockers; all-tick body/HP/MP/fixed-point
invariants over12 seeds; square/isometric equivalence; measured reaction delay;
early-game physical dodges; moving-target projectile collision; exact diagonal
melee near misses; high-speed waypoint routing; immutable visual pins; command
recovery gates; rendering batch independence; full120-second timeout; and a
versioned byte-for-byte golden fixture. Care, save, reward, focus/pause, and scene
integration are covered by the other project suites, not this pure core.

`tests/arena_depth_test_runner.gd` adds headless depth/ownership/flag checks to the
full suite. Run it without `--headless`, with `-- --asset-review --gpu --capture`,
to assert actual red-actor/blue-tile pixels behind and in front for both
projections; synthetic screenshots go to `work/sprites/qa/arena-depth-*.png`.
