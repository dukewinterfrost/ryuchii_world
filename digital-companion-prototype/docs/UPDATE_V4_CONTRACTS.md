# Save v4 and care integration contracts

## Definitions and durable state

`GameDefinitions` (`scripts/core/game_definitions.gd`) exposes `SPECIES`, `CARE_TUNING`, `TRAINING`, `TRAINING_SECONDS`, `EVOLUTIONS`, `MOVES`, `ITEMS`, `DECOR`, `default_inventory()`, and `default_skills(species)`.

All existing fields retain their meaning and limits. `care.hunger` remains the historic persisted fullness value: 100 means fed; display it as **Fullness**. `CareRules.stats_snapshot` includes a `fullness` alias.

Save v4 adds:

```text
care.fatigue: 0..100
care.potty_habit: 0..100
care.stage_care_mistakes: integer; resets at evolution, lifetime care_mistakes does not
progression.last_social_reward_at: nonnegative Unix seconds, 0 before first reward
progression.training_history: {hp,mp,offense,defense,speed,brains}: completion counts
progression.last_training_id: string
progression.valid_action_counts: existing keys plus pet,praise,scold
habitat: {
  theme: "verdant" | "practice",
  items: [{instance_id:string,item_id:"digi_potty"|"rug"|"planter",x:int,y:int,rotation:0..3}],
  camera: {zoom:0.75..2.0,follow:bool},
  creature_cell:[x:int,y:int]
}
inventory: {
  starter_granted:true,
  items:{small_recovery:int,mp_recovery:int},
  decor:{digi_potty:int,rug:int,planter:int},
  consumed_command_ids:[string]
}
skills: {learned:[move_id],equipped:[{move_id:string,auto:bool}]}
```

Inventory counts represent unplaced/unconsumed inventory; applying a layout must reconcile its placed instances with inventory through GameState in one saved transaction. A new save has no placed props, one of each decor, and three of each consumable. Migration is idempotent and never refills already-v4 supplies. `SaveRepository` migrates v1/v2/v3 to v4 and preserves original legacy backup bytes. A valid v3 Agumon gains the initial Rookie skills without reevaluating historical evolution.

## Care and training

`CareRules.apply_command(state,action,payload="",now_unix=-1)` returns the usual `{state,accepted,message,animation,bond_gain}` plus `rewarded`. Pass the clock explicitly from GameState; omitted time uses `meta.last_update_time`. Pet/Praise/Scold respond during the shared 30-second cooldown, but mutate no stats, counters, diversity, or bond then. Rewarded pet counts as play diversity. Praise/scold grant no bond. Cleaning no longer adds discipline.

`advance_time(state,now_unix,engaged_seconds=0,training_active=false)` remains pure. Pass `training_active=true` during an unfinished training session, including focus-paused training, to suppress fatigue recovery for that interval. Otherwise fatigue recovers one point per elapsed minute, including offline. The caller continues to evaluate evolution after engaged time, actions, training, and reward settlement; `evolve_if_ready` does not run inside time advancement.

`training_readiness(state,stat)` returns `{ok,error}`. GameState must own exactly one transient session `{id,stat,elapsed}`, create unique IDs, reject battle overlap, accrue only focused foreground time, and discard the session on cancellation/relaunch. `complete_training(state,stat,session_id,elapsed_seconds)` rejects unknown sessions' stat IDs, incomplete time, and the last completed ID; it returns `{ok,state,error,gain?}`. This pure helper assumes GameState validated the active ID and eligibility at start; never expose it as an unrestricted player command. Commit the returned candidate before clearing the session or showing rewards, so failed persistence can retry without duplicate awards. Completion records the ID/history, grants the capped selected stat, +15 fatigue, -5 fullness, +2 discipline, -2 happiness.

`evolution_readiness(state)` returns `ready,target,missing_actions,active_ok,bond_ok,unmet_requirements,candidates`; final Agumon returns `{ready:false,reason}`. Each candidate supports stats minimums, care minimums (including happiness), optional `weight_min/weight_max/max_stage_care_mistakes`, and required learned move IDs, sorted by ascending priority. Koromon additionally requires offense12/discipline45. Commit evolution before its signal/presentation.

## Habitat and potty

`HabitatRules` uses a 20×24 grid of 32-unit cells (640×768 world). Camera zoom is a multiplier relative to the fitted habitat view, not raw world-to-screen scale. Views keep screen UI outside the world camera and clamp camera position after zoom/pan/follow. `creature_cell` is the actual current free ground cell: update it through GameState as roaming moves, not by direct view edits.

`validate_layout(layout,creature_cell=Vector2i(-1,-1)) -> {ok,error}` uses saved creature position when omitted. Footprints may not overlap, leave bounds, block the creature with a solid object, or make any potty entrance unreachable. Rugs are non-solid. Quarter-turn rotation uses indices 0,1,2,3. `footprint(item) -> Array[Vector2i]` and `potty_entrance(item) -> Vector2i` support drawing and selection. `path_between_cells(layout,start,goal)` and `path_to_potty(layout,creature_cell=Vector2i(-1,-1))` return cardinal grid paths including start and goal; empty means no legal route. Use these paths for roaming and guidance, not straight-line movement through props.

`bathroom_warning(state,now_unix)` is true from scheduled `next_poop_at - 30` through `next_poop_at`. Show the warning and offer Guide to potty only with a legal path. Animate traversal toward the entrance; then invoke `complete_potty_guidance(state,now_unix,creature_cell)`. It returns `{ok,state,error}`, checks the warning and actual entrance arrival (path size1), advances `next_poop_at` by one normal interval, gives habit+20/discipline+2, saves the arrival cell, and leaves all existing waste IDs untouched. Do not award merely for clicking Guide. If time expires or the path becomes blocked, ordinary interval care produces floor waste.

At habit≥60 and discipline≥50, `advance_time` checks saved-layout reachability and skips all due floor spawns arithmetically, including offline. It gives no habit/discipline reward for automatic use. Existing waste still accrues virus/happiness exposure until individually cleaned. Foreground UI can route a trained companion to the entrance during the warning for presentation; offline need not animate travel. Missing/unreachable potty falls back to normal floor waste.

## Battle integration

Skills use `auto`, not `automatic`, in equipped slots. All basic melee IDs are unequippable. Only Agumon defaults to learned/equipped Pepper Breath, Quick Bite, Heavy Claw. Gameplay disallows loadout changes during live combat.

`inventory.consumed_command_ids` is a unique durable command ledger (≤100000 strings of ≤160 chars). GameState validates/preflights the live command before decrementing `inventory.items`, appending the unique ID, and saving; apply the battle effect only after save success. The battle simulator's own command replay is session-only and must not perform this transaction. `apply_battle_reward` now grants one of each consumable on a win using the existing exactly-once completed-battle-ID guard.

## Checks

Run `tests/care_v4_test_runner.gd`, `tests/test_runner.gd`, and `tests/persistence_hardening_runner.gd` with `--headless --log-file /tmp/godot-tests.log -- --test-mode`. Their fixture saves use unique `/tmp` paths, never real companion saves. The macOS sandbox may emit its unrelated system CA certificate warning; evaluate test exit/check counts and actual script errors separately.
