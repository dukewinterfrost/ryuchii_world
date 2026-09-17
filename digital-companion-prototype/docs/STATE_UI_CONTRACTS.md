# Authoritative UI integration

Views read `get_state()` (deep copies) and observe `state_changed`. Mutations return
`{ok,error?}` unless noted. Saved transactions roll back on failure. Evolution
signals are emitted only after saving the evolved candidate.

- `start_training(stat)` returns an active session `id`; `get_training_status()`
  supplies `active,id?,stat?,elapsed?,duration,paused`. `cancel_training()` discards
  progress. `training_changed(status)` updates controls. `complete_training(id)`
  is the future mini-game seam; it still requires the live matching, fully elapsed
  session. The GameState timer pauses on focus loss; sessions are never saved.
- `apply_habitat_layout(layout)` validates and reconciles placed/unplaced decor in
  one transaction. Cancel is purely local draft disposal. `set_habitat_camera(zoom,
  follow)` and `set_habitat_theme(theme)` save preferences. Schema v5 keeps one
  active regional layout in `habitat`, inactive layouts in `habitats`, and the
  canonical selected ID in `home_region`; global inventory is reconciled without
  returning decorations that are still placed in another home. Persisted
  `inventory.decor_owned` totals exactly equal unplaced plus all-region placed
  counts. See
  `docs/HOME_REGIONS_V5.md`.
- `set_creature_cell(Vector2i)` reports only consecutive legal grid steps and
  returns bool; it updates the autosaved current ground cell. It cannot teleport.
  The care view cancels and rehydrates from state when a step is rejected.
- `get_potty_status()` returns `warning,guiding,path,can_guide,automatic,remaining`.
  `begin_potty_guidance()` returns a cardinal cell path. Animate its traversal,
  reporting each cell, then call `complete_potty_guidance()` on actual arrival.
  It validates warning/deadline and entrance before a saved reward.
  `cancel_potty_guidance()` discards the transient route. Automatic presentation
  must not call guided completion; interval simulation performs automatic use
  against the active habitat manifest and its blockers.
- `set_skill_loadout([{move_id,auto},...])` validates learned unique moves and
  three-slot maximum, only outside battle and at Rookie.
- `set_preferences(muted,reduced_motion)` durably stores `meta.preferences`.
  Older v4 saves may omit it: views default both booleans to false.
- `queue_battle_order(order)`, `queue_battle_move(move_id)`, and
  `queue_battle_item(item_id)` return `{ok,command_id,tick,command}` or error.
  `queue_battle_command(command)` additionally accepts an explicit command ID for
  deterministic testing or duplicate-input suppression. Generated IDs use a
  cryptographic session nonce and monotonically increasing serial across matches.
- `battle_command_resolved({ok,command,error?})` reports actual next-tick outcome,
  including failed durable inventory writes. Rejected requests consume nothing.
  The tick preflight batch is replayed exactly after saving item debits; replay
  itself never touches GameState or durable inventory. Abandonment does not refund.

Do not pause battle while a picker is open. Focus-loss pause remains automatic.
