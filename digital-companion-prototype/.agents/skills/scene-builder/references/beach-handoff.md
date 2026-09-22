# Beach scene handoff — next task, not an implemented map

Start with the beach reference and intended player experience when the user
requests the next scene. Keep the existing forest intact and verify which
native or packaged beach scene should be active before editing.

## Reuse the composition method, not the forest numbers

- Readable center: warm dry sand with restrained shell, pebble and grass detail.
- Transition edge: use the user's newer flat-top/sheer-drop direction, adapted
  as a cut sand/rock shelf above the lower shore. Do not reintroduce forest-style
  sloping hills. A beach does not need a closed tree perimeter.
- Near framing: a few palm/grass/rock cards positioned asymmetrically. Keep the
  main approach and horizon open; don't copy the forest's density or tree count.
- Far layers: separate surf, water, distant land and sky, with deliberate
  horizon alignment. Put ocean cards below/behind the shore and verify alpha
  ordering; no-depth-test water must not cover a nearer companion.
- Values: cooler/darker transition and foreground accents can frame bright sand,
  but test sunrise and night so the shoreline doesn't become a black moat.
- Background secondary movement should be subtle and independent of grounded
  rocks. Wave animation is presentation-only and needs reduced-motion behavior.

## Existing project inputs to inspect

- `assets/environment_workshop/shellfish-beach/` currently contains ground/floor
  and facade/interior/roof working assets. Their existence is not evidence of
  promotion, approval, or commercial rights.
- `assets/environment_workshop/texture-index.json` and the source plans identify
  those textures. For DigimonUP ingestion, read the environment skill's
  `references/digimonup-source-inventory.md` and verify exact bytes first.
- Review beach native scenes under `scenes/environment_workshop/`, the current
  home/arena resolvers, and the pinned regional manifests. Home and battle share
  a kit but keep their distinct geometry and saved-region behavior.
- `HomeDayNightLighting` currently binds native forest paths such as
  `ForestParallax/Sky` and treats `bg1_sky` as the existing artwork mode. A beach
  needs deliberate sky/water bindings; copying the forest ground shader or
  those path assumptions blindly will not produce a beach-ready lighting rig.

## First beach checkpoint

Build one native reviewable composition from available authorized assets before
bulk variants or generation: sand, shore transition, two or more separated
background depths, a few native prop groups and the companion. Run the camera
envelope and route checks, then inspect center/left/right/near/far at the three
portrait sizes plus wide overview and day/night. Use layers-on/off evidence to
verify shore gaps are concealed. Ask for additional source art or billable
generation approval only if an actual missing slice cannot be covered safely
with the existing kit. Do not promote based on an agent's own visual check.
