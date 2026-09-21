# Battle-v4 independent verification

Recorded September 17, 2026 on `codex/reactive-auto-battles`, using Godot `4.7.2.stable.official.ed1daf0bf` on macOS. Verification used the current working tree, including the unrelated care/environment changes already present. No commit, push, real companion save, or live reward was required. Every Godot suite ran with `--test-mode`, and test saves/logs used temporary paths.

Build baseline: `768466e573f3bf7134a9f165728a8b8655362129`, with uncommitted implementation/review changes. Normalized combat content: `sha256:3deff80cb34400fb5c31fe195c250691d5397039a7eb1c5a6967190ed6ae1b3a`.

## Regression results

The strict `tests/run_tests.sh` runner was run from the beginning. Its failure exit was preserved, then `COMPANION_TEST_FROM` continued after each failing suite so every suite was inspected. Final combat changes were rerun from `battle v4 reactive combat`, and the final presentation changes from the newly registered `battle v4 visual cues and portrait layout` suite. Required PASS markers, injected-save-error counts, unexpected errors, and resource-leak checks remained enabled.

| Suite | Latest result |
| --- | --- |
| Godot import/parse | Pass |
| Care rules | 75 checks, pass |
| Care v4, habitat and training | 38 checks, pass |
| Home regions / save v5 | 59 checks, pass |
| Food / save v6 | 36 checks, pass |
| Care statuses / sleep / wishes v7 | 116 checks, pass |
| Persistence hardening | 31 checks, pass |
| Update-state integration | 78 checks, pass |
| Frozen spatial combat | 73 checks, pass |
| Frozen v3 moves / items / replay | 94 checks, pass |
| Combat tables / frozen replay content | 64 checks, pass |
| Reactive v4 simulator | 114 checks, pass |
| V4 saves / live commands | 41 checks, pass |
| Isolated sandbox | 23 checks, pass |
| Battle Sprite-in-3D presentation | 526 checks, pass |
| V4 visual cues / portrait layout / protected impacts | 69 headless checks; 75 native checks including six PNG captures, pass |
| Live battle integration | 64 checks, pass |
| Native assets | 60 checks, pass |
| Arena depth | 36 checks, pass |
| Placeholder effects | 87 checks, pass |
| Python sprite/environment pipeline | 67 tests, pass |
| Five-region packages | 9 tests, pass |
| Live battle controls | 71 checks, pass |
| Care UI / habitat controls | 27 checks, pass |
| Home 3D / projection / fallback | 49 checks, pass |
| Care camera | 94 checks, pass; prior null-material error did not reproduce |
| Care full-window map | 29 checks, pass |
| Scene smoke / actual 30, 60, 144 FPS replay comparison | 37 checks, strict pass on three consecutive runs with no leaked resources |
| Green Shade Sprite-in-3D spike | 102 checks, exactly five documented baseline assertions fail; frozen-v3 checksum passes |
| Environment runtime architecture | 61 checks, pass |
| Five-region runtime | 84 checks, pass |
| Editable environment workshop | 122 checks, pass |
| Camera-facing care presentation | 26 checks, pass |

The suite is not fully green: the [known spike failures](KNOWN_ISSUES.md) cover missing/fallback attack-body expectations and left/right camera clamps. These are the only remaining failures after the final focused reruns. They were not weakened or reclassified as battle-v4 successes. The previously documented care-camera null-material warning was absent in this run; that observation alone is not a diagnosis or claimed fix.

Local diagnostic logs: `/tmp/battle-v4-independent-full.log`, `/tmp/battle-v4-independent-rest1.log`, `/tmp/battle-v4-independent-rest2.log`, `/tmp/battle-v4-independent-rest3.log`, and `/tmp/battle-v4-independent-final-combat.log`. Temporary paths are local evidence, not repository artifacts.

The independent final segment `/tmp/battle-v4-independent-final-visual-segment.log` exposed an intermittent smoke audio cleanup issue after 30 assertions passed. Verbose output identified WAV/playback references. Fixed delays were insufficient because synchronous simulated bouts could accumulate a frame delta that immediately expired the test timer. The final smoke test tracks actual WAV ownership with weak references and a two-second wall-clock deadline, asserting backend release before completed-test teardown. The production Skip path now stops existing voices and consumes skipped history without sound; normal replay sounds and the identical terminal result are explicitly checked. Return also stops voices. The strict leak filter remains unchanged.

Three consecutive final strict runs accepted all **37 smoke checks** with no leaks, then stopped only on the five documented spike assertions: `/tmp/battle-v4-strict-smoke-refdrain-1.log`, `/tmp/battle-v4-strict-smoke-refdrain-2.log`, and `/tmp/battle-v4-strict-smoke-refdrain-3.log`. After that narrow audio change, visual checks remained 69/0 and controls 71/0 (`/tmp/battle-v4-visual-skip-audio-final.log`, `/tmp/battle-v4-controls-skip-audio-final.log`). Native sandbox capture `/tmp/battle-v4-sandbox-final-native.log` passes all 23 checks, with HP bars drawn above the sprites.

## Independent source review

Reviewed the v4 simulator and facade, normalized content loader, version dispatcher and replay playback, live command queue, save repository/migration/rewards, sandbox isolation, and presentation event/state adapters.

- The pure v4 simulation receives pinned content and uses integer authoritative timing/geometry plus seeded `BattleRng`. Real-time clocks, file reads, engine RNG and rendering deltas are outside its authoritative rules. The fractional duration in the completed result is reporting only.
- Move definitions and item effects are loaded once from validated tables; fighter snapshots must match the pinned configuration. Historical v2/v3 defaults and whole-state golden fixtures remain separate from the live content path. Replay reconstruction restores JSON integers and validates accepted commands against recorded ticks.
- Manual defense starts at the accepted simulation tick and does not roll for success. Next-tick preflight observes phase boundaries, cancellation retains paid MP/cooldowns, and active/recovery rejection does not queue a delayed defense. AI reactions begin only after exposed threats have been sampled.
- Normal movement, rush bodies and projectiles use swept geometry. Rush checks both moving and current body positions; widened rush damage is occluded separately from its physical center path. Target selection excludes teammates, committed actions retain their target/direction, hit collection precedes damage, and team completion permits simultaneous elimination.
- The live queue runs shadow preflight, commits accepted item inventory and consumed IDs durably, then steps the simulator. Failed saves restore the prior care state, omit item effects, and revalidate other commands. Reward settlement starts from the latest care state and saves the completion marker with the reward.
- Save-v8 migration preserves legacy care/inventory values and grants tactical starters once. Stable item identities are separate from editable balance metadata. Win rewards use an explicit allowlist. Sandbox reloads retain their own configuration, and failed table/fixture reloads retain the previous session without touching the live cache or save.

The review produced concrete corrections: safe arena validation before the two-fighter wrapper copies spawns; redraw of sibling HP meters after sandbox resizing even when processing is stopped; normalized numeric comparison for editable 3D arena matching; and explicit frozen-v3 ownership of historical presentation checksums while retaining live-v4 rendering-purity comparisons. Melee/rush impacts now consume the pinned move `visual_scale` in both adapters, with tests demonstrating changed effect size and unchanged collision cues/session state. Paired perfect-guard/zero-damage events preserve the defender's shield cue and reward sound rather than replacing them with hurt feedback; barrier absorption similarly uses protective feedback. Saved reduced-motion preferences are applied on initial 2D setup.

The added tests exercise observable boundaries rather than merely duplicating formulas: exact next-tick releases, failed durable promotion and retry, unchanged disk generations, malformed CSV columns and fields, no ghost projectile after cancellation, fast sweeps and head-on rush escape, JSON and changed-table replay independence, multi-team hits, and live scene output at multiple frame rates. The sandbox resize regression listens for an actual redraw while asserting the tick remains unchanged.

## Pacing and review limits

The independently reproduced 24-seed autonomous sample has median **54.0 s**, P10/P90 **42.7/71.6 s**, and no draws. A policy responding to visible threats won 22/24 versus 12/24 for autonomous play and 8/24 for blind periodic input. These are controlled simulation observations; some aggressive same-nature encounters remain below the 45-second pacing target. Exact stats, seeds, policies and measurements are in [BATTLE_V4_PLAYTEST.md](BATTLE_V4_PLAYTEST.md).

Native portrait screenshots were reviewed during implementation, including the persistent defense controls, expanded inventory and cast-label placement. The final native run passed 75 checks, including six PNG capture assertions (`/tmp/ryuchii-v4-native-delivery.log`); the 360×640 item drawer and 390×844 charged battle were visually inspected with readable controls/labels and visible arena. That review identified and corrected a drawer covering the field, overlapping cast text and stale sandbox HP positions. It is a developer visual inspection, not a human gameplay study. Physical touch reachability, audible cue recognition, readable threats without debug geometry, successful opening punishment, personality recognition and enjoyment over repeated encounters still require human playtests. The [broader-content gate](BATTLE_V4_PLACEHOLDERS.md#broader-content-gate) remains open.

The personal planning skill is installed at `/Users/johncohrn/.codex/skills/game-feature-planning/SKILL.md`; its linked brief, prototype/playtest, placeholder templates and timestamped Sakurai notes exist. The [reviewable skill copy](../../skill-drafts/game-feature-planning/SKILL.md) has the same relative resource layout.
