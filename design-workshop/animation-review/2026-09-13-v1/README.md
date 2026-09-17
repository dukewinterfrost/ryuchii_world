# Digital Companion · Animation review

All 18 animation candidates are complete: 4 care actions each for Botamon and Koromon, plus 10 care/battle actions for Agumon. The delivery contains 175 selected frames, all 128×128 RGBA. Motion remains awaiting John's review; nothing was promoted into the game.

- [Figma page 05](https://www.figma.com/design/syQM2pShfeCTfXms0HmzTB?node-id=68-460) contains all 18 frame sheets in character columns.
- Open `review/index.html` for playback, per-action replay/stepping, speed controls and approved-pose comparison. The optional repeat mode adds a 600 ms hold between one-shot previews; exported one-shots remain one-shot.
- `review/frames/<clip>/` contains individually numbered PNGs.
- Each clip has a transparent strip, a six-column sheet, a GIF preview and timing JSON with frame paths/hashes.
- `digital-companion-animations-v1.zip` is the complete portable review package.

The original approved artwork and provider frames remain unchanged. Generation receipts are in `jobs/`. `animation-refinements.json` overlays corrected requests on the preserved original plan. `clip-selections.json` records selected genuine frames for Agumon happy and Botamon hop. `frame-selection.json` records 19 extractions of detached overhead effects; all character pixels and registration are preserved. Connected anatomy errors were rejected, refined or omitted during frame selection. No motion was fabricated from duplicated stills.

The run retains 36 provider jobs, including rejected/refined passes and the original idle pilot. All 28 jobs selected by the current plan are complete. The replenished balance fell from 2,000 to 1,942 generations: 58 used during this resumed run, including refinement and an unsuccessful provider cleanup experiment. The prior trial run and its preparation receipts remain archived separately in this same directory.

## Reproduce the review

Use Python with Pillow, then run `python3 batch.py check` and `python3 batch.py package` from this directory. Both are offline and validate saved source hashes. `run_queue.py --execute --allow-billable` handles genuinely incomplete or newly authorized jobs with two in flight, balance checks, durable submission receipts and GET-only recovery. All current jobs are complete, so do not restart generation or preparation.

Serve the review with `python3 -m http.server 4193 --bind 127.0.0.1 --directory review`, or open its self-contained HTML directly. The project-owned sprite compiler can handle runtime integration after motion review.

The reusable skill is installed at `/Users/johncohrn/.codex/skills/sprite-generator-workflow/SKILL.md`.
