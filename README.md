# Ryuchii World

A Godot companion-care and auto-battler prototype. Feed and train a companion,
decorate its habitat, explore the care map, and enter spatial training battles.
The game currently follows Botamon → Koromon → Agumon.

The Godot project lives in **`digital-companion-prototype/`**, not the repository
root. Its editor title is still **Digital Companion Prototype**.

## Quick start

1. Install the standard **Godot 4.7.2** editor. The project uses GDScript; the
   .NET edition, export templates, Python, and API keys are not needed to play.
2. Clone this private repository using a GitHub account with access:

   ```sh
   git clone https://github.com/dukewinterfrost/ryuchii_world.git
   cd ryuchii_world
   ```

3. In Godot's Project Manager, select **Import**, choose
   `digital-companion-prototype/project.godot`, then open the project.
4. Let the initial asset import finish. Use the editor's **Run Project** button
   to launch the care screen.

On macOS, with Godot installed at `/Applications/Godot.app`, you can instead run:

```sh
./digital-companion-prototype/open-in-godot.command
# Or launch the game directly:
./digital-companion-prototype/open-in-godot.command --play
```

The repository includes the runtime artwork and audio. No asset generation,
external source repository, backend server, database, or paid service is needed
for the current game. macOS is the verified development platform; see the
[setup guide](digital-companion-prototype/docs/GETTING_STARTED.md) for Windows
and Linux launch commands, development dependencies, and troubleshooting.

## For a new contributor

Start with [setup and verification](digital-companion-prototype/docs/GETTING_STARTED.md),
then read the [contributor guide](CONTRIBUTING.md). The detailed
[gameplay guide](digital-companion-prototype/README.md) explains care, progression,
combat, and the sprite workflow.

| Location | Contents |
| --- | --- |
| `digital-companion-prototype/project.godot` | Engine settings and the main scene |
| `digital-companion-prototype/scenes/` | Care, battle, and environment workshop scenes |
| `digital-companion-prototype/scripts/` | Gameplay rules, saves, combat, and presentation |
| `digital-companion-prototype/assets/` | Runtime art, audio, generated packages, and asset catalog |
| `digital-companion-prototype/assets-source/` | Source plans, provenance, and review records |
| `digital-companion-prototype/tests/` | Automated checks and isolated fixtures |
| `digital-companion-prototype/tools/` | Optional Python asset tooling |
| `digital-companion-prototype/docs/` | System contracts, art workflow, and review notes |
| `design-workshop/` | Design references and animation review deliveries |
| `skill-drafts/` | Optional authoring workflow instructions; not a game dependency |

## Verify a change

After installing the development dependencies in the setup guide:

```sh
cd digital-companion-prototype
./tests/run_tests.sh
```

The initial upload has two known failing suites; see the
[verification baseline and known issues](digital-companion-prototype/docs/KNOWN_ISSUES.md)
for results and reproduction commands.

For a non-default Godot installation, set `GODOT_PATH` to the executable's
absolute path. The launcher uses a separate override, `GODOT_BIN`.

## Prototype status and assets

This is a development prototype, not a packaged release. Friends, shopping,
equipment, and multiplayer are not implemented. Export presets are not included.
Headless tests do not replace visual, audio, touch, or device-performance testing.

This repository contains Digimon names, art, sounds, and extracted reference
material marked **private-prototype-only / not-cleared**. Keep the repository
and its assets private; public or commercial distribution requires replacement
or appropriate rights. See the [asset provenance](digital-companion-prototype/assets/asset-provenance.json)
and [environment source inventory](digital-companion-prototype/assets-source/environments/SOURCE_INVENTORY.json).
No open-source license grant is included.
