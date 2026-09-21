# Battle-v4 prototype verification and pacing

Recorded September 17, 2026. These are deterministic simulation measurements, not a substitute for players judging clarity and enjoyment.

Build: uncommitted working tree on `codex/reactive-auto-battles`, based on commit `768466e573f3bf7134a9f165728a8b8655362129`, Godot `4.7.2.stable.official.ed1daf0bf` on macOS. Normalized combat content pin: `sha256:3deff80cb34400fb5c31fe195c250691d5397039a7eb1c5a6967190ed6ae1b3a`. This identifies the actual table snapshot used by the measurements; simulation code changes require a new run even if that content pin stays unchanged.

## Reproduce

Run `tests/battle_v4_test_runner.gd` through Godot headless (the checked repository runner includes it). Its `BALANCE` output covers 24 paired seeds per control policy, followed by the regression PASS marker.

- Both creatures: Agumon; HP 110, MP 48, Offense 10, Defense 8, Speed 8, Brains 8.
- Graybox arena, standard starting positions, three automatic starter abilities enabled, no items, 120-second cap.
- Seeds 100–123. For zero-based index `i`, player nature is `[Bold, Gentle, Jolly, Calm, Earnest, Stubborn][i % 6]`, and opponent nature is the same list at `(i + 2) % 6`.
- Tables: the initial `assets/combat` CSV content, with 0.8-second tackle charge, 2.5× movement, and 0.9-second recovery unchanged.
- P10/P90 are sorted observations at zero-based indices 2/21; median is the mean of indices 11/12. Final player HP averages include defeats at zero HP.

| Policy | P10 | Median | P90 | Draws | Player wins | Mean final player HP | Total hit events | Autonomous/manual dodge events |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Autonomous | 42.7 s | 54.0 s | 71.6 s | 0/24 | 12/24 | 12.6 | 696 | 280 |
| Periodic commands | 48.5 s | 58.0 s | 72.0 s | 0/24 | 8/24 | 3.9 | 778 | 278 |
| Visible-threat response | 47.9 s | 66.6 s | 78.8 s | 0/24 | 22/24 | 21.7 | 887 | 300 |

The periodic policy requests Guard every 75 ticks and Heavy Claw every 180 ticks at offset 20. It does not read threats. The response policy requests Guard three ticks before a visible melee release when in reach, Dodge near visible projectile release or a nearby projectile, Guard when a visible active rush is within three ticks of contact, and Quick Bite when the enemy is recovering and within range. It reads only current exposed state. Commands rejected by commitment or cooldown are not buffered.

The response policy improves wins by 10 out of 24 paired seeds and mean remaining HP by 9.1 over autonomous play. Blind periodic input performs worse. This is useful evidence that timing matters; these simple policies are not a balanced competitive benchmark or an accessibility claim. Hit totals include guarded, absorbed and perfect-guard connections, so they are not equivalent to damaging hits.

## Same-nature check

An additional diagnostic used seeds 1–12, with both fighters assigned the nature at `(seed - 1) % 6`, and the same stats and arena above. No commands or items:

| Nature | Seed / duration / dodge events | Seed / duration / dodge events |
|---|---|---|
| Bold | 1 / 49.6 s / 12 | 7 / 48.8 s / 17 |
| Gentle | 2 / 57.0 s / 14 | 8 / 73.6 s / 14 |
| Jolly | 3 / 52.3 s / 11 | 9 / 64.3 s / 18 |
| Calm | 4 / 58.8 s / 11 | 10 / 48.2 s / 6 |
| Earnest | 5 / 32.9 s / 3 | 11 / 40.8 s / 6 |
| Stubborn | 6 / 42.4 s / 11 | 12 / 46.8 s / 8 |

All twelve ended by knockout. Some aggressive matches are shorter than the 45-second target; the aggregate median and typical spread meet the intended prototype pacing. More samples and human playtests should determine whether those shorter encounters are enjoyable.

## Findings and fixes

Initial simulation measurements were too fast, with a 31.5-second mixed-nature median. Attacks could chain immediately after recovery. The rules now include a deliberate autonomous reposition beat using the authored tactical commitment interval, and creatures register visible threats while committed so their response deadline does not start late. Explicit player ability requests can use openings during this autonomous pause.

A head-on rush collision bug allowed two bodies to finish slightly overlapping. Both escape paths were then blocked, making aggressive matchups stationary. Rush collision now checks both the relative swept motion and the other actor's current body. A regression asserts non-overlap on every tick and available escape paths after both rushes. Every same-nature diagnostic now includes dodges.

Rush engagement uses the lesser of the authored activation range and physical travel plus contact reach, with a small approach margin. Slow creatures therefore approach sufficiently before bracing. Shared authoritative remaining-travel geometry drives the telegraph, including Haste expiry. Collision stops the rush into its full authored recovery without sliding.

## Automated coverage and remaining playtest

The focused simulator suite verifies integer JSON replay reconstruction, replay independence from changed balance content, command identity and next-tick boundaries, manual/AI defense separation, early/perfect/late guards, paid cast cancellation without ghost projectiles, queued-move replacement/expiry, item spending and non-stacking, zero-MP attacks for each species, full-range Speed scaling, swept projectiles and rushes, 3v3 enemy targeting and friendly-fire exclusion, simultaneous knockouts, and rendering-rate independence. Frozen v2/v3 suites and golden replay fixtures cover historical behavior.

Still required from human playtesting: recognizing attack tells without overlays, understanding failed or committed inputs, feeling the difference between personalities, operating defenses while the item drawer is open, and judging whether dodging/guarding/punishing remains exciting across repeated encounters. Approved creature art and procedural attack/effect cues remain intentional prototype placeholders.
