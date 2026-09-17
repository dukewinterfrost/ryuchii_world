# Digital Companion project

Known workspace: `/Users/johncohrn/Documents/ChatGPT/Godot Projects`.
Project: `digital-companion-prototype` below that workspace. Treat these as discovery hints and verify paths when resuming.

## Current tools

- `docs/SPRITE_PIPELINE.md` describes project compilation, review and promotion.
- `tools/sprites` is the CLI. Its runtime prefers `.venv-sprites/bin/python`, or `SPRITE_PYTHON`.
- `tools/sprite_pipeline/pixellab.py` contains a real REST adapter with durable submission intent, job-ID persistence and GET-only resume. Reuse it rather than introducing hidden POST retries.
- `tools/sprite_pipeline/pipeline.py` binds source images by hash, enforces keypose review, compiles candidates and performs explicit promotion.
- `scripts/world/companion_animation_state.gd`, `scripts/core/care_rules.gd` and `scripts/battle/battle_simulator_v2.gd` define actual action use. The pipeline's requiredActions list currently concentrates on combat; care clips such as happy/eat may need explicit extra clips instead of being added blindly to that validator's requiredActions.
- The existing web-project credential is `/Users/johncohrn/Documents/ChatGPT/Tomagachi Web App/.env.pixellab.local`. The credential loader requires a regular 0600 file and reads only the PixelLab variable. Do not copy its contents into a skill or artifact.

## Keyframe review accepted for animation

Figma file: `syQM2pShfeCTfXms0HmzTB`, “Digital Companion — Pixel Workshop”.
Page 3, `49:150`, contains 18 proposed keyframes beside the Digimon Up references.
The user approved this set by saying “These are looking good, run them through the animation machine”.

Source directory: `design-workshop/keyframe-review/2026-09-12-v1/`. Its manifest records prompts, original paths and Figma nodes. Original review images are 1254px square; Botamon initially has an opaque warm-white backdrop, so do not treat those files as finished runtime sprites.

Animation run: `design-workshop/animation-review/2026-09-13-v1/`. Check its approval record, transfer scope, request receipts and status before starting new jobs. `animate.py` handles preparation; `batch.py` handles the saved animation plan and review packaging. Original provider frames and request receipts are retained in this run's `jobs/` directory.

The completed run delivers 18 clips and 175 individually exported frames. All 28 selected plan jobs are complete; 36 provider job receipts are retained, including rejected/refined passes and the original idle pilot. The replenished account started at 2,000 generations and ended at 1,942: 58 generations were used during the resumed run, including refinements and an attempted provider cleanup. These are observed balances.

`animation-refinements.json` overlays corrected job descriptions/IDs on the preserved original plan. `clip-selections.json` records genuine selected frames for Agumon happy and Botamon hop; source pools and playback counts remain distinct. `frame-selection.json` records 19 source-pixel extractions of detached overhead symbols, with original and selected hashes. Raw outputs remain in `jobs/`, extracted candidates in `isolated/`, and the deliverable PNG sequences in `review/frames/<clip>/`. The unused complex-background removal experiment is retained under `cleaned/` and is not selected for delivery.

Sixteen inputs used provider cleanup; Koromon happy and move preserved original alpha with deterministic nearest-neighbor normalization. Completed input checks skip all preparation. Do not replay the old failed unzoom receipts or restart completed jobs.
Run `batch.py check` to validate the exact approved inputs, request bindings and saved frame hashes. `batch.py package` refreshes the self-contained player, GIFs, transparent strips and timing JSON from completed clips only. Both are offline. `batch.py run --execute --allow-billable` advances at most one unfinished job: GET-only for an accepted job, or a new POST after a balance check. Repeat at bounded intervals when processing; existing completed jobs are skipped. Never invoke new submissions with zero balance. An uncertain receipt stops the run for reconciliation. `--limit` controls maximum advanced jobs per invocation, not retries.

`run_queue.py --execute --allow-billable` provides a bounded queue runner with two in-flight jobs and durable GET-only recovery. All current work is complete; use it only for a new authorized refinement or an actual incomplete job. `delivery-summary.json` and `qa.json` record the final counts and checks.

Review location: page `68:459`, “05 · Animation review”, board `68:460`. Page 04 is the user's floor-texture work; preserve it. Figma contains all 18 frame sheets in separate character columns. `review/index.html` provides playback, per-action replay and stepping, speed/filter controls, approved-pose comparison and an optional repeat-preview mode. One-shot exports remain one-shot even when the player repeats them with a hold. GIFs, transparent strips/sheets and timing JSON are exported per clip.

| Character | Care | Battle |
| --- | --- | --- |
| Botamon | idle, move/hop, happy, eat | None |
| Koromon | idle, move/hop, happy, eat | None |
| Agumon | idle, move/walk, happy, eat | basic_attack, special_attack/Pepper Breath, guard, evade, hit, defeat |

Infant eating and several battle states previously used fallbacks; the new pose set covers those existing gameplay actions with dedicated proposed art. Listen can reuse idle; play/celebrate can reuse happy. This review approves one right-facing view, not eight new directional character designs.

The project's standard cells are 128×128 with ground/root pivot (64,120). Use a fixed registration for each species; keep deliberate hop and recoil offsets. Pepper Breath's projectile and impact are separate world effects. No full-animation approval or runtime promotion follows automatically from the keyframe approval.
