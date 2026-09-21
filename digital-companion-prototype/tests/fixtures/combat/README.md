# Frozen battle replay fixtures

These records pin two original engines. The terminal SHA-256 covers `JSON.stringify(session)` for the full completed session, including actors, RNG state, commands, combat log, and result.

- **v3** captured before implementation from `battle_simulator.gd` SHA-256 `d68f5c553d5b72ce796f840fea446cd41bbbd602469995a52b2776f6fff331c4` with original `game_definitions.gd` SHA-256 `d907c64d80151e2936cdd79b07bb1dd735cd88a385aa76967113ae79b59c2867`. The frozen copy changes only its class name and definitions import. Seed 20260909, 900-tick maximum, equal Agumon stats HP110/MP48/offense10/defense8/speed8/brains8, Bold. Opponent wins at tick 737 with 18 HP.
- **v2** captured from the existing untouched `battle_simulator_v2.gd` using the same seed, roster, arena, and tick limit; its battle ID uses the v2 suffix.

JSON parsing represents numbers as floats. Normalize integral values to integers before hashing a recreated session, matching the original fixture's types. `combat_content_test_runner.gd` verifies each entire terminal hash and then proves edited live move/item tables cannot affect either legacy engine.
