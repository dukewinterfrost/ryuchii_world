# Care and Evolution Vertical

## State and time

The care model is deliberately independent of Godot runtime state. Callers pass
an explicit Unix timestamp and optional engaged seconds into `advance_time`.
This makes offline progression and automated tests deterministic.

- Hunger decreases by one point every 300 elapsed seconds and bottoms out at
  zero without death or bond loss.
- Poop is scheduled every 900 seconds and capped at three visible piles.
- Dirty exposure accumulates virus at six points per poop-hour. New piles only
  contribute after their actual spawn time.
- If a fourth or later scheduled poop occurs while all three visual slots are
  occupied, it records a care mistake and schedules the next interval.
- Cleaning removes one pile, lowers virus, and modestly improves discipline,
  happiness, and bond.
- Active time accrues only during a 30-second engagement window following real
  player input, not merely because the game window was left open.

All rates are named constants near the top of `care_rules.gd` so playtest tuning
does not require touching scene code.

## Progression

Every accepted care command records an action and may add permanent bond.
Repeated identical actions use multipliers of `1.0`, `0.55`, `0.25`, and `0.1`
to prevent spam from replacing varied care.

Botamon evolves when all of the following are true:

- 600 engaged seconds;
- 24 bond;
- at least one valid feed, play, and chat during the Baby stage.

Koromon evolves when all of the following are true:

- 1,800 total engaged seconds;
- 70 bond;
- at least one new valid feed, play, and chat during the In-Training stage.

Agumon is the final stage in this prototype. Evolution never removes bond,
nature, lifetime action counts, or care history.

## Dialogue

`companion_reply` is a deterministic basic-mode dialogue service. It combines
species, the persistent birth nature, care state, and a small closed set of
utterance patterns. This provides a stable offline fallback seam for a later
model-backed service without putting inference into the care simulation.

## Deliberate boundary with auto-battle

The saved `battle_profile` supplies HP, MP, offense, defense, speed, and brains
to the training-battle vertical. The care scene only requests a match and opens
its replay; attacks, AI choices, damage, and event ordering remain in the pure,
seedable `BattleSimulator`. See `BATTLE_VERTICAL.md` for that data contract.
