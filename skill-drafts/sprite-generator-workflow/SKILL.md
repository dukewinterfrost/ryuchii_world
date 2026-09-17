---
name: sprite-generator-workflow
description: Create consistent game sprites through reference review, one representative keyframe per action, approved animation generation, and sprite-sheet review. Use for character sprite sets, PixelLab animations, or updating a sprite-generation workflow.
---

# Sprite generator workflow

Carry a character from reference art to reviewable animation assets while preserving identity and the game's action contract. Reuse a project-owned sprite pipeline when one exists. Keep original art, provider output and compiled candidates in separate versioned locations.

## Choose the current stage

- **New visual direction:** inventory references and gameplay actions, generate one representative keyframe per required action, and arrange a review board. Use the available imagegen skill for raster keyframes. Do not generate full sequences before the requested keyframe review.
- **Approved keyframes:** a message such as “these look good, run them through the animation machine” approves that displayed set for animation. Record the actual decision and exact source hashes; continue without asking for the same approval again. Preserve any provider choice made earlier in the task.
- **Existing animations:** inspect actual frames, timings and provenance before changing them. Fix the requested clips instead of regenerating the character set.

Read [PixelLab operations](references/pixellab.md) when using that provider. Read [Digital Companion project](references/digital-companion.md) for this game's paths, action coverage and existing tools. Do not treat those project conventions as requirements for unrelated games.

## Establish the action contract

Read both the animation manifests and the gameplay action selectors. Distinguish authored clips from runtime fallbacks. Record the character/action/facing matrix, loop versus one-shot behavior, representative pose, intended duration and any events. Do not invent extra directions or battle actions for characters that do not use them.

For reference images, identify each image's role: identity, palette/style, anatomy or action. Inspect local images before using them. Keep head/body proportions, eye shape, appendages, outlines and palette consistent. Generate each distinct keyframe as a separate asset; a contact sheet is for review, not a substitute for independently usable sprites.

## Prepare approved art for animation

An enlarged pixel-looking concept is not automatically a native sprite. Check real dimensions and alpha. A painted checkerboard is an opaque background, not transparency. Before bulk preparation, complete one preparation-and-animation pilot and inspect actual provider usage. Budget cleanup as well as animation against the available balance; small cleanup endpoints can cost more than expected.

Preserve approved originals. Recover the native grid and background with the chosen pipeline, inspect the result, then normalize to the game's canvas. Use one registration transform per character so hops, recoils and anticipation retain their offsets. Do not crop and recenter every animation frame independently. Record transformations and hashes; stop to resolve visible identity loss or clipping before generating from damaged inputs.

## Animate the approved pose

Use a small representative pilot to verify provider behavior before submitting the remaining set. This is agent QA, not a new user approval gate unless a meaningful choice or limitation requires it.

- For a loop, guide a complete cycle from the approved pose back to itself; keep the camera, facing and root fixed.
- For an action whose approved keyframe is its peak, preserve that pose as an explicit endpoint. When needed, generate neutral-to-peak and peak-to-neutral segments and join them without a duplicate seam frame. Starting every one-shot at its peak can omit anticipation.
- For defeat or another terminal pose, finish at the approved terminal frame instead of adding an unrequested recovery.
- Keep projectiles and scene effects separate when the game renders those separately.

Record each submission before POST and save its returned job ID before polling. Resume an accepted job by ID; never blindly repeat an uncertain paid POST. Keep returned PNG bytes and actual frame counts. Bounded concurrency and per-job state allow useful progress to survive an interrupted run.

Treat identity drift as a real failure: legless creatures must not gain feet, short points must not become rabbit ears, and a smooth dinosaur skull must not grow a crest. PixelLab v3 can add emote symbols or exaggerate anatomy even when the prompt excludes them. Inspect intermediate frames, not only endpoints. Prefer concrete, restrained body movement; refine only affected segments and retain each previous request and its receipt.

## Review and package

Inspect animation playback as well as the frame strip. Check identity drift, changing anatomy, clipping, foot sliding, palette flicker, loop seams, action readability and timing. Structural checks are not visual approval.

Curating genuine frames from multiple completed takes is allowed when it produces a coherent action. Record the selected job, frame index and source hash in playback order; distinguish the selected frame count from the complete source pool. Never call fabricated or duplicated stills generated animation. For detached overlays, a project-owned source-pixel extraction can separate effects while preserving all character pixels and registration. Apply it only to visually reviewed components, save the masks/selection receipts, and retain raw originals. Connected effects or changed anatomy need refinement or frame rejection, not blind erasure. Inspect transparent outputs on a solid matte as well as the checkerboard.

Deliver individual frames, transparent strips/atlases, explicit timing metadata and a playable preview. If the task uses Figma, add a new review page with labeled strips and references; confirm playback in the actual presentation UI before calling a GIF or prototype animated. Figma uploads can produce a still thumbnail even when the file is a GIF. Provide a verified local player or GIF as needed.

For Figma writes, use the installed figma-use guidance, keep node IDs in a local ledger, and use upload_assets for raster images. Instance-child IDs may be rejected by upload schema validation: upload to a regular asset node, then apply the returned imageHash to the instance fill. Load the actual fonts before edits and screenshot checks.

Figma instance-child resize calls may leave the original geometry unchanged. Use a component with explicit row variants for sprite sheets, then swap variants. Resolve text-property keys after combining variants, because their IDs can change. Restore instance height to hug content after swaps. Do not set placeholder on an instance when the API rejects that override.

Generated animations remain candidates until the user reviews the motion. Do not infer runtime promotion or approval of generated frames from earlier keyframe approval. When the user requests integration, use the project's compiler and validation rather than swapping raw AI images into the game.

End with the review location, completed and blocked clips, saved assets, and any actual provider limitations. Keep secrets and base64 request bodies out of logs, manifests and skill files.
