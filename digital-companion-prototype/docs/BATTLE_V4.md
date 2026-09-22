# Battle v4: reactive auto battles

This is the accepted feature contract and starting tuning, not a claim that every acceptance scenario has passed. The implementation builds on the existing 30 Hz pure simulation, durable item spending, contextual arenas, and replay isolation. Historical v2/v3 behavior remains versioned. See [the placeholder register](BATTLE_V4_PLACEHOLDERS.md) for temporary presentation and the evidence required before broader content work.

## Player experience and scope

The player recognizes a threat, chooses to dodge, guard, or commit to an ability, exploits the opening, and repositions. Creatures keep fighting autonomously. Player input creates decisive opportunities without manually steering them or requiring random command success.

Target evenly matched 1v1 fights lasting 45–90 simulation seconds. The first playable live mode is 1v1; an isolated 3v3 fixture on a larger field verifies team assumptions. Friend networking, recruitment, matchmaking, persistent parties, and cross-launch battle resumption are later work.

Use Speed for movement with configurable diminishing returns over the full supported stat range. Brains affects autonomous reaction timing and escape judgment. Seeded RNG varies tactical choices, commitment intervals, circling direction, reaction variation, and damage (initially ±10%). It never vetoes accepted manual defense. Hits require geometry, and AI reacts only to observable threats.

## Behavior and initial tuning

### Movement and opening tackle

Creatures approach, circle, retreat, pursue openings, and react to telegraphed threats. A short decision commitment prevents jitter. Existing Bold, Stubborn, and Earnest natures use aggressive weights without changing saved names.

Aggressive actors prioritize the `opening_tackle` move: first approach into range, brace for 0.8 seconds, then rush along the direction locked at charge start. Rush movement is 2.5× running speed and recovery lasts 0.9 seconds. A miss leaves an opening. Swept collision prevents passing through obstacles or bodies; either stops the rush. Aggression is a tactical priority, not permission to skip a charge tell.

### Manual defense

| Command | Duration | Behavior | Initial cooldown |
| --- | --- | --- | --- |
| Dodge | 0.4 s | Immediate 2.5× movement burst along a clear selected escape direction; no invulnerability | 2 s shared with Guard |
| Guard | 0.8 s | Immediate protection reducing damage by 60% | 2 s shared with Dodge |
| Perfect Guard | First 0.2 s of manual Guard | Negate the first connecting attack; stagger a melee attacker for 0.5 s | Uses the same Guard command |

Manual commands override autonomous movement and defense immediately at their accepted simulation tick. Autonomous reactions neither delay manual input nor consume manual readiness. Ordinary autonomous guard cannot perfect-guard. A blocked dodge gives immediate feedback and never teleports. Dodge and Guard stay reachable with the item drawer open.

### Abilities and commitment

Retain three equipped abilities, their automatic-use switches, and each species' permanent free basic attack. Baby specials belong in the same move table as all other moves. The HUD shows the equipped abilities directly, including MP cost, remaining cooldown, pending request, and charging state.

All attacks have charge, active/release, and recovery phases. A manual request waits for legal range and availability; the newest request replaces the old one and expires after five seconds. MP is spent and per-move cooldown begins when charge starts. Default charging holds position and locks aim; movement during casting is a move setting.

Manual Dodge or Guard cancels charging without refunding MP or cooldown. A canceled cast must not produce a later hit or projectile. Active/release and recovery are committed: defense is rejected immediately during those phases, never queued to fire later. Running out of MP leaves the free attack and approach behavior available.

### Items and feedback

Keep HP and MP recovery. Add `barrier` (30 absorbed damage, six-second expiration) and `haste` (35% movement bonus, six-second expiration). The four items share a five-second item cooldown. Active tactical effects do not stack; repeated use is rejected before inventory spending. Grant two starter copies of each tactical item once, and explicitly award one of each for wins. Adding an item to a catalog must not automatically add it to rewards.

Charge bars, ground attack indicators, anticipation/impact/recovery poses, trails, hit flashes, recoil, and distinct sounds communicate authoritative events. Shake and sprite offsets never affect positions, collision, or input timing. Reduced motion suppresses unnecessary displacement while retaining attack and defense information.

## Editable content and sandbox

`assets/combat/moves.csv` is the canonical source for live move balance. Keep CSVs as raw content rather than importing them as localization tables. Author time in seconds and distance in arena units; the `CombatContent` loader outside the simulator converts once to 30 Hz integer timing/fixed-point geometry and returns normalized configuration. Combat and care/loadout presentation consume the same normalized definitions. Keep v3's frozen defaults outside this live content path.

| Field group | Required authoring capability |
| --- | --- |
| Identity | Stable ID, name, species availability, equippable flag |
| Cost/damage | MP cost, power multiplier, damage variance |
| Timing | Cast, active, recovery, cooldown |
| Geometry | Range, melee width, projectile speed, collision size, lifetime |
| Behavior | Melee/projectile/rush type, cast movement, rush multiplier, automatic-use weight |
| Presentation | Animation/effect references and visual scale distinct from collision size |

Companion `items.csv`, `natures.csv`, and `tuning.csv` in the same directory hold item effects, nature weights, and shared combat tuning. Validate unique IDs, references, numeric bounds, and move-type requirements, with row/column errors. Missing or malformed content must fail visibly rather than partially replacing a valid configuration.

The isolated sandbox (`res://scenes/battle_sandbox.tscn`, launched with `open-battle-sandbox.command`) supports fixed-seed restart, new-seed restart, table reload into a fresh battle, collision/telegraph overlays, stat overrides, and unlimited test supplies. Show effective rounded timing. An in-progress session pins its original configuration; an invalid reload preserves the last valid sandbox configuration. Sandbox activity must not write the real save or settle live rewards.

## Simulation, versioning, and persistence contract

- Live simulation version is `battle-v4`. Freeze the old v3 simulator and required defaults alongside v2, and dispatch historical records by their version.
- A v4 replay embeds the seed, accepted commands, complete roster, arena, and complete normalized combat configuration. Replay uses those values, not current tables, and cannot change inventory or care state.
- Roster members carry `fighter_id`, `team_id`, `controller_id`, and spawn position. Preserve the existing two-fighter session entry point as a wrapper. Target the nearest reachable hostile, retain that target during committed actions, exclude allies from hits, and finish when only one team remains. Simultaneous elimination is a draw.
- Add `defense_request` with `defense: "dodge" | "guard"` to discriminated commands. Preserve unique `command_id`, `fighter_id`, and actual-next-tick preflight. Actor state exposes cast phase, per-move cooldowns, manual-defense readiness, target, and temporary item effects.
- Events expose charge start/cancellation, release, defense, perfect guard, rush collision, and effect expiration. Presentation reads these events and state; it cannot deal damage or spend resources.
- Keep actual-next-tick shadow preflight, durable accepted-item spending, duplicate-ID rejection, and simulator step in that order. If saving fails, omit item effects, retain the pre-spend live state, and revalidate dependent commands. A crash after durable spend may lose the effect but must not restore the spent item.
- Settle a completed battle against the latest care state exactly once, with its completed-battle marker in the same durable save. Keep save-failure retry behavior. Migrate from the current care schema forward, preserving concurrent care fields and avoiding repeated tactical starter grants.
- Preserve focus-loss pause and discard paused rendering backlog. Keep contextual arena selection and pinned approved artwork. Replay speed and sandbox controls remain isolated from live settlement.

Existing detailed durability/arena contracts are recorded in [BATTLE_V3_CONTRACTS.md](BATTLE_V3_CONTRACTS.md) and [BATTLE_VERTICAL.md](BATTLE_VERTICAL.md); v4 extends those guarantees and supersedes their older feature-scope descriptions.

## Delivery and verification

Deliver the reusable skill/specification first, then content/sandbox/replay fixtures, then combat behavior, then live HUD/persistence/presentation integration. Preserve unrelated care work throughout.

| Acceptance scenario | Required evidence |
| --- | --- |
| Reproducibility | Same seed, configuration, and accepted input reproduce the same result at different rendering frame rates. |
| Historical compatibility | Frozen v2 and v3 replay fixtures remain unchanged when live tables change. |
| Movement and RNG | Increasing Speed increases measured movement; varied seeds produce different tactical sequences without anticipation of hidden attacks. |
| Timed tackle response | Early, timely, and late defense have legible different consequences; an escaped tackle leaves punishable recovery. |
| Cast cancellation | Resources spend once; a canceled charge never emits a delayed attack/projectile. Committed-phase defense rejects immediately. |
| Collision | Fast projectile and rush sweeps stop at obstacles and the appropriate fighter; no tunneling or friendly fire. |
| Failure handling | Invalid rows, full meters, empty inventory, active effects, duplicate commands, and persistence failure are safe, visible no-ops. |
| Teams | 3v3 targets enemies, retains committed targets, handles target defeat, and settles simultaneous elimination correctly. |
| Layout and accessibility | Portrait controls stay reachable with drawers open; reduced motion preserves cues; focus loss pauses without catch-up. |
| Pacing and engagement | Seeded equal-stat measurements assess the 45–90-second target; human playtests establish readable threats and useful intervention. |

Run focused combat, replay, persistence, sandbox, and UI checks plus `tests/run_tests.sh`. Report unrelated pre-existing failures separately. Automated duration checks are balance evidence, not proof of engagement. Record build/content/seed, stat setup, inputs, observations, and remaining uncertainty before declaring the prototype ready for broader content.

## Design sources and adaptations

The reusable skill's [Sakurai reference notes](../../skill-drafts/game-feature-planning/references/sakurai-lessons.md) preserve inspected timestamps, Japanese-caption limitations, and source/application separation. For this feature: external tables and fresh-run reload adapt *Making Your Game Easy to Tune*; tackle commitment and recovery adapt *Risk and Reward* and *Squeeze and Release*; explicit attack phases adapt *Breaking Down Attack Animations*; pose/camera review adapts *Attack Poses*; visual-only recoil adapts *Eight Hit Stop Techniques*; persistent defense controls adapt *Clarity vs. Style*; early issue reporting and a current contract adapt *Spec Changes*. All combat values and implementation contracts above are Ryuchii-specific choices.


## Temporary home-forest presentation (2026-09-21)

Live battles and the battle sandbox now use `scenes/environments/care_clearing.tscn`, at the user's request. Scenery scales to the arena dimensions; fighter positions, arena geometry, content pins, and replay simulation remain unchanged. Interior care trees are removed, and authoritative battle obstacle footprints remain visible. Explicit isolated regional-field review still uses its selected workshop scene. Replays shown in the live battler also use this temporary forest presentation; their recorded environment pins are preserved rather than rewritten.

The sandbox uses current curated art for fighters without visual pins; pinned live/replay fighters retain their existing art-resolution policy. Missing-art markers now receive a camera framing envelope. Portrait sandbox labels wrap and the fixture selector no longer expands to its longest entry.

Verification: 74 control checks, 40 sandbox checks (native rendered), 509 battle Sprite-in-3D checks, and 75 native visual checks passed. Reviewed portrait 1v1 sandbox and live item-drawer captures. This change did not run the full repository suite.
