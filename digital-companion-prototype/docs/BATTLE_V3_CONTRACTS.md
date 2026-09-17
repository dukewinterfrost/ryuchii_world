# Battle v3 integration contract

`BattleSimulator` creates battle-v3 by default. `step`, `replay`, and
`replay_record` dispatch battle-v2 to the frozen `BattleSimulatorV2` implementation.
The v2 golden hash remains unchanged. `BattlePlaybackModel` dispatches its initial
state with `create_from_record` and never calls GameState or persistence.

## Session creation and skills

`create_session(battle_id, seed, player, opponent, arena = {}, max_ticks = 3600,
visual_revisions = {}, initial_supplies = {}, pinned_items = {}, encounter_id = "",
arena_content_sha256 = "")`
adds optional deterministic content arguments to the old API. Live GameState passes
`state.inventory.items` as `initial_supplies`. Omission means no supplies.

`player_snapshot_from_state(state)` includes `state.skills` in the pinned fighter.
Skills use `{learned: [move_id], equipped: [{move_id, auto: bool}]}`. Three slots
maximum; fallback attacks cannot be learned or equipped. Babies use their built-in
special automatically; Rookie AI uses enabled loadout moves in slot order.
All stages retain a permanent free melee fallback. Zero MP forces approach even
under keep-distance/defend orders. Definitions are normalized from GameDefinitions
into the snapshot, then pinned in replays so future source changes have no effect.

## Commands and durable consumption

Commands are dictionaries with `kind`, `command_id`, `fighter_id`, and optional
`tick` (next simulation tick if absent):

- `kind: "order"`, `order: "auto" | "attack" | "defend" | "keep_distance"`.
- `kind: "move_request"`, `move_id`: a learned/equipped Rookie move.
- `kind: "item_use"`, `item_id: "small_recovery" | "mp_recovery"`.

New command IDs must be globally unique within the saved companion lifetime;
use the battle ID plus a monotonic input serial. Old `{fighter_id, order}` callers
remain compatible, but v3 records normalize them to discriminated commands with
deterministic IDs. Both move requests and items are restricted to the first
fighter (the companion). Replays execute accepted commands without persistence.

`preflight_command(session, command)` returns `{ok, command}` or `{ok:false,error}`
without mutations. This is useful for immediate UI feedback, but an enqueue-time
check is not sufficient for inventory accounting.

**On the actual next simulation tick, synchronously in this order:**

1. Take the queued inputs and call `preflight_commands(session, inputs)`; it returns
   `{ok, commands:[normalized accepted], rejected:[{command,error}]}`. This reserves
   command IDs, item cooldown, remaining quantities, and restored MP on an isolated
   command-only shadow, processing input order exactly as `step` will.
2. Make a candidate save copy. Deduct each accepted item from `inventory.items`,
   append its ID to `inventory.consumed_command_ids`, and durably save that copy.
   A previously consumed ID must be rejected before preflight. Never persist
   speculative rejected inputs. The shared 150-tick cooldown accepts at most one
   item in a tick, including different item types.
3. If saving fails, do not swap the candidate into live state. Drop item commands
   and give save-failure feedback. Re-preflight other commands if desired (a move
   request could have depended on the rejected MP restoration).
4. Call `step(session, accepted_commands)` with no intervening simulation advance.
   On successful save, item availability and cooldown are guaranteed to match the
   preflight state. The simulator spends its battle-local quantity and restores
   HP/MP before movement and attack resolution on that tick.

Full meter, dead fighter, empty supplies, duplicate ID, invalid target, and item
cooldown are no-ops. A crash after durable spend but before the effect leaves the
item spent; replay has no effect on durable inventory. Battles are session-only.
Win reward grant and exactly-once settlement remain GameState/CareRules concerns.

## Runtime fields and feedback

- Session `supplies`, `initial_supplies`, `item_definitions`, `item_ready_tick`,
  `used_command_ids`, and accepted `commands` are plain deterministic data.
- Actor `pending_move`, `move_ready_tick`, `move_expires_tick`, and `current_move`
  support UI feedback. Requests replace any older pending move and expire 150
  ticks after acceptance. They wait for reaction and committed recovery, approach
  range, and spend MP only when the attack commits. The pending timer expires even
  during recovery. Disabling auto does not disable explicit requested use.
- Logs emit `move_requested`, `move_expired`, `item_used`, and `action_started`;
  action events include `move_id`, and item events include `item_id`, `restored`,
  `command_id`. Rejected commands are returned by preflight; they are never recorded.
- Simulation `action` remains `basic_attack` for melee and `special_attack` for
  projectiles so existing presentation continues working. `current_move` gives
  the exact move identity and timing. Animation cannot inflict damage.

`replay_record` adds pinned `initial_supplies` and `item_definitions`; fighters pin
normalized moves and skills. `replay` rejects commands that were impossible at
their recorded tick, including duplicates, missing supplies, and invalid cooldowns.
For an environment-backed arena, `content_revisions.environment` stores the complete
Environment content pin. A nonempty contextual encounter is also copied into the
record and must map to the embedded arena and region. Verified arena packages add
their `contentSha256` to `content_revisions.arena`; legacy records without one keep
their prior shape. These presentation/content identities cannot alter battle math.
