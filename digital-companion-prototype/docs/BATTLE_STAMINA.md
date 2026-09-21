# Battle stamina: pressure, escape, and recovery

Status: proposed prototype extension; not implemented. September 20, 2026.

## Player experience

Spend a short-lived reserve to create an opening, escape pressure, or commit to a physical attack. Recognize when an opponent has overextended and punish before it recovers. Stamina should empty and refill within seconds, creating several pressure/recovery cycles within the existing 45–90-second battle target.

Example: a Bold creature sprints into tackle range, braces, and rushes. Its opponent spends stamina dodging, then fires a ranged ability during the tackle recovery. The attacker is now low on stamina and must walk or guard while its reserve returns. A Calm creature instead spends a short sprint reaching casting distance, stops, and commits to a projectile; it cannot sprint indefinitely while regenerating.

User requirements: running, dodging, and selected physical moves spend stamina; capacity and regeneration depend on stats; nature influences sprint use, including pursuit and escape to attack at range, heal, or buy time. Everything below is an initial design hypothesis for testing.

## Resource and movement rules

- Battle stamina starts full and belongs only to the battle actor. Existing care fatigue, sleep, training costs, and saves keep their current meaning. No cross-system fatigue penalty in this prototype.
- Walking/repositioning is free at 55% of the existing Agility-derived running speed. Running uses that speed and drains stamina; sprinting uses 150% and drains substantially faster. Dodge keeps its current 250% running-speed burst and 0.4-second duration.
- Guard and each species' basic attack remain free. Exhaustion forces a return to walking; it does not stun, disable Guard, or prevent basic attacks. Dodge requires its full cost and otherwise rejects immediately with a reason.
- Running/sprinting cannot regenerate stamina. After the recharge delay, walking, standing, and guarding regenerate at the full rate. Charging, active attacks, and attack recovery pause regeneration, preserving the cost of commitment.
- Dodge and stamina-cost attacks pay once at action start; their movement does not also pay running drain. Canceled charges retain spent stamina, MP, and cooldown. Validate every resource and phase before spending anything or canceling the existing action.
- Movement drain stops when collision prevents movement; blocked-path feedback and deterministic replanning prevent a creature from draining itself against a wall. Partial movement pays proportional drain. Exhaustion never permits extra unpaid sprint distance.
- No random stamina costs or manual-command failure rolls. Seeded variation changes AI choices, not whether an affordable legal command succeeds.

### Editable starting values

Stat formulas use saved `defense` (displayed Endurance) and `speed` (displayed Agility), bounded to the existing 0–999 range. Evaluate as integer/fixed-point arithmetic in simulation.

| Parameter | Prototype value |
| --- | --- |
| Maximum stamina | `80 + 80 * Endurance / (Endurance + 80)` |
| Regeneration per second | `20 + 10 * Endurance / (Endurance + 80) + 10 * Agility / (Agility + 80)` |
| Recharge delay after expenditure | 0.5 seconds |
| Running drain | 12 stamina/second |
| Sprinting drain | 30 stamina/second |
| Dodge cost | 20 |
| Opening tackle cost | 25, paid when bracing starts |
| Quick Bite / Heavy Claw cost | 10 / 25, retaining existing MP costs initially |
| Basic attacks / current magical projectiles | 0 stamina |
| AI recovery mode | Enter below 25%; leave at 60% |
| AI sprint commitment | 0.4–0.8 seconds, interrupted by danger, exhaustion, or reaching the destination |

At Endurance 8 / Agility 8, these formulas give roughly 87 stamina and 22 stamina/second recovery: about 2.9 seconds of continuous sprinting or 4 seconds to refill after the delay. These are formula estimates, not playtest results. Diminishing returns let trained creatures act longer without making extreme stats inexhaustible. Costs remain absolute so capacity growth buys additional actions.

## Nature-driven tactics

| Existing nature | Sprint preference | Conservation behavior |
| --- | --- | --- |
| Bold | Close gaps, opening tackle, chase an exposed enemy | Will spend its dodge reserve on a strong offensive opportunity |
| Earnest | Reach useful attack range and follow through | Usually retain one dodge; recover between planned attacks |
| Stubborn | Maintain pressure and pursue a retreating target | Will overspend offensively; exhaustion still forces recovery |
| Jolly | Lateral repositioning and short flanking bursts | Frequent direction variety, with committed paths rather than jitter |
| Calm | Create casting distance or disengage from pressure | Retain one dodge and favor recovery before pursuing |
| Gentle | Escape danger and create a healing opportunity | Recover earlier and avoid low-value chases |

Author sprint pursuit, escape, flank, and recovery weights plus reserve/threshold values in `natures.csv`; these descriptions are priorities rather than mandatory scripts. Wisdom (`brains`) improves threat reaction and evaluation of clear escape routes, not the speed of manual commands. AI cannot foresee an unannounced attack.

Evaluate a destination before sprinting: legal casting distance with line of sight, an unblocked escape lane, or a reachable attack opening. Once the purpose is satisfied, stop spending. Use existing decision commitments and separate entry/exit thresholds to prevent run/walk flicker. A queued player ability gives repositioning a concrete objective.

Healing motive does not authorize autonomous inventory spending. Creatures may create breathing room when hurt; the player still activates healing items under existing inventory and cooldown rules. Do not invent passive HP regeneration. Guard's existing MP recovery remains a separate mechanism.

## Implementation contract

- Introduce a new replay rules version (proposed battle-v5), freezing v4 before changing stamina behavior. Preserve v2/v3/v4 fixtures and their dispatch paths.
- Add actor stamina, maximum, regeneration delay, fixed-point drain/recovery remainder, locomotion mode, and recovery intent. Fixed per-tick updates must not depend on rendering frame rate.
- Add `stamina_cost` to canonical move content, movement/resource curves to tuning, and nature preferences to the nature table. Validate nonnegative costs, curve denominators, ordered thresholds, and references. Default old content only inside its historical version; never reinterpret an old replay with new rules.
- Replays pin all normalized content, seed, roster, arena, accepted commands, and stamina rules. Sandbox reload starts a fresh battle and keeps the last valid configuration on error.
- Existing manual defense cooldown remains separate from stamina. Reject insufficient stamina immediately without spending cooldown, queuing a later dodge, or canceling an in-progress charge. An affordable Dodge or Guard can still cancel charging under existing rules.
- Ability requests wait up to the existing five seconds for range and resources; show `waiting for stamina` distinctly from charging. Commit resources once charging begins. Basic attacks remain a fallback when a paid move cannot begin.
- Expose authoritative locomotion, exhaustion, and recovery-mode changes for presentation. HUD shows stamina beside HP/MP, Dodge and move costs, and explicit rejection reasons. Keep Guard/Dodge accessible with the item drawer open.
- Reduced motion retains bars, labels, and clear poses; cosmetic breathing, trails, or color must never be the only indicator or alter collision. No asset downloads are required for this prototype.

## Smallest prototype and acceptance

First add an isolated sandbox variant with one aggressive melee creature and one ranged creature, fixed seeds, resource graphs, action/rejection logs, stat overrides, and configurable nature weights. Then test 3v3 crowding before live integration. The main risk is tedious kiting or repeated waiting instead of exciting exchanges.

Automated checks:

1. Same seed/config/commands produces identical results at different presentation rates; old replay fixtures remain unchanged.
2. Higher Endurance increases capacity and regeneration; higher Agility increases movement and regeneration; full stat range remains bounded.
3. Running/sprinting drain correctly, walking recovers only after the delay, and fixed-point remainders avoid rounding exploits. Collision cannot cause unpaid movement or perpetual wall drain.
4. Exact-cost Dodge succeeds; one-unit-short Dodge fails without resource/cooldown spend or canceling a charge. Duplicate commands cannot spend twice.
5. Physical charge cancellation pays once and never releases; free basic attacks and Guard remain available at zero stamina.
6. Recovery thresholds prevent rapid mode oscillation. AI obeys collision, team targeting, commitment, and visible-threat constraints; nature and seed produce measurable tactical differences.
7. Inventory remains player-controlled and durable; save failure cannot spend an item or apply healing. Stamina itself needs no care-save migration.
8. Portrait and reduced-motion layouts communicate exhaustion and retain all defensive controls.

Playtest comparisons: rerun the prior 24-seed equal-stat baseline with and without stamina; record duration, stationary/walking time, sprint purpose, dodge rejection rate, recovery cycles, damage during exhaustion, and longest no-damage interval. Check early/timely/late defense and ranged-versus-melee pairings. Investigate fights outside 45–90 seconds and repeated chase loops rather than declaring success from the median alone.

Human questions: Can players explain why a creature slowed down? Does saving one dodge feel valuable? Does an exhausted opponent create a recognizable opportunity? Do nature differences feel intentional? Does recovery bring relief without boring downtime? Acceptance requires observed answers, not just passing tests.

## Placeholder register

| Placeholder | Purpose and limitation | Replacement trigger | Completion criterion |
| --- | --- | --- | --- |
| Simple stamina bar and text labels | Test resource readability; no final art or bespoke breathing animation | Players miss depletion/recovery despite layout adjustments | Resource state and unavailable actions understandable at portrait scale without color alone |
| Initial curves, costs, and nature weights above | Test short pressure cycles; not established balance | Pacing, kiting, or defense availability contradicts the intended experience | Representative matchups meet pacing and players identify useful spending/conservation decisions |
| Logged sprint destinations and resource graph | Diagnose AI; developer-only visualization | Behaviors stabilize | Deterministic traces explain pursuit, escape, and recovery without exposing diagnostics in the live HUD |

## Design basis and change record

The local [Sakurai reference library](/Users/johncohrn/.codex/skills/game-feature-planning/references/sakurai-lessons.md) summarizes *Squeeze and Release* (00:17–00:45, 01:10–02:10), *Risk and Reward* (00:32–02:39), and *Making Your Game Easy to Tune* (00:32–01:58). Its evidence uses imperfect Japanese automatic captions. Applying those lessons to a rapidly cycling stamina reserve and editable costs is our interpretation; the formulas and values above are not Sakurai's prescriptions.

September 20: user requested stat-driven short-term stamina and nature-driven sprint tactics. Proposed a separate battle resource with free fallback actions. Affected systems: content loader, simulator/version dispatch, AI, HUD, replay fixtures, sandbox, pacing checks. No runtime or save behavior changed in this specification step.
