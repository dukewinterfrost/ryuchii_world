# Setup and first run

## Requirements

| Tool | When needed | Version / notes |
| --- | --- | --- |
| Git and repository access | Clone and contribute | This is a private GitHub repository |
| Godot standard editor | Run or edit the game | Verified with `4.7.2.stable.official.ed1daf0bf`; project declares Godot 4.7 |
| Python | Asset tooling and the full test suite | 3.9+; verified with Python 3.9.6 |
| Pillow | Asset tooling and Python tests | Pinned to 11.3.0 in `tools/sprite_pipeline/requirements.txt` |
| ripgrep (`rg`) | The checked shell test runner | Must be available on `PATH` |
| POSIX shell | The full test runner | macOS/Linux; `.command` launchers additionally use zsh |

Use the matching Godot version from the official Godot release archive. The
standard editor is sufficient: the project uses GDScript and the Compatibility
renderer. There is no C# build or Node/npm dependency. Export templates are only
needed if you later configure a platform export.

macOS is the tested development environment. The GUI import steps also apply to
Windows and Linux, but those platforms have not been verified in this handoff.
Several native test fixtures use `/tmp`, so the full shell suite is currently
intended for macOS/Linux rather than native Windows.

## Clone and open

```sh
git clone https://github.com/dukewinterfrost/ryuchii_world.git
cd ryuchii_world
```

A "Repository not found" response can mean your GitHub account has not been
granted access. Use your existing GitHub authentication; do not place a token
in a clone URL or a project file. A GitHub ZIP download also works for playing,
but does not include Git history or support normal commits and pulls.

In Godot's Project Manager, use **Import** and select:

```text
ryuchii_world/digital-companion-prototype/project.godot
```

Open the project and wait for asset import to finish. Press **Run Project** in
the top-right toolbar. The main scene is `res://scenes/care_scene.tscn`; running
an individual scene is a different action from running the project.

On the first run, the care screen creates a local companion save. Feed, pet,
train, or open Tools to decorate. See the [gameplay guide](../README.md) for
progression and battle controls.

### macOS terminal

From the repository root:

```sh
./digital-companion-prototype/open-in-godot.command
./digital-companion-prototype/open-in-godot.command --play
```

The first command opens the editor; the second starts the game. The launcher
expects `/Applications/Godot.app/Contents/MacOS/Godot`. For another installation:

```sh
GODOT_BIN="/absolute/path/to/Godot" ./digital-companion-prototype/open-in-godot.command --play
```

### Linux terminal

With the Godot executable available as `godot` on `PATH`, from the repository root:

```sh
godot --editor --path digital-companion-prototype
godot --path digital-companion-prototype
```

If your distribution names the executable `godot4`, substitute that command;
check `--version` against the version above.

### Windows PowerShell

From the repository root, substitute your Godot executable's actual path:

```powershell
& "C:\Tools\Godot\Godot.exe" --editor --path .\digital-companion-prototype
& "C:\Tools\Godot\Godot.exe" --path .\digital-companion-prototype
```

The `.command` launchers are macOS helpers. Windows users can import the project
through the editor or use the PowerShell commands directly.

## Development dependencies and checks

Playing does not require Python. For asset work and the full checked test suite,
run these commands from the Godot project directory on macOS/Linux:

```sh
cd digital-companion-prototype
python3 -m venv .venv-sprites
.venv-sprites/bin/python -m pip install -r tools/sprite_pipeline/requirements.txt
rg --version
./tests/run_tests.sh
```

Install ripgrep with your operating system's package manager if `rg` is missing.
The test runner prefers the project virtual environment and uses the default
macOS Godot installation. For a different engine or Python installation:

```sh
GODOT_PATH="/absolute/path/to/godot" \
SPRITE_PYTHON="$PWD/.venv-sprites/bin/python" \
./tests/run_tests.sh
```

`GODOT_PATH` selects the engine for tests and the sprite pipeline. `GODOT_BIN`
is the override for `open-in-godot.command`. Set the one used by your command.

The runner imports assets first, checks each suite's success marker, and fails
on unexpected script errors, engine errors, or leaked resources. It prints a
log directory under `/tmp/digital-companion-suite.*`. Some persistence tests
intentionally print save failures; their exact counts are checked by the runner.
A successful run ends with `PASS: complete ... suite`.

The initial upload is not a fully passing baseline: the checked command currently
stops on the camera-cleanup engine error, and the 3D spike has five failing
assertions. Read [known issues and verification results](KNOWN_ISSUES.md) before
interpreting a local failure.

For a quicker import and scene smoke check, with `godot` on `PATH`:

```sh
godot --headless --path . --import -- --test-mode
godot --headless --path . res://tests/scene_smoke_runner.tscn -- --test-mode
```

Always keep the trailing `-- --test-mode` on test scene launches: the autoload
uses that flag to avoid reading or updating real companion progress.

## Optional review and asset tools

Existing runtime assets are checked in. Do not regenerate them just to run the
game. The sprite CLI is available after the Python setup above:

```sh
./tools/sprites --help
```

The [sprite pipeline guide](SPRITE_PIPELINE.md) explains offline compilation,
review records, and promotion into the runtime catalog. Only optional PixelLab
generation needs `PIXELLAB_API_TOKEN` or `PIXELLAB_API_KEY`; generation defaults
to a dry run, and paid execution requires explicit flags. Keep credentials in
your local environment, never in version control.

To inspect environments, open
`scenes/environment_workshop/green_shade_home.tscn` in the editor and use **Run
Current Scene**. The [environment workshop guide](ENVIRONMENT_WORKSHOP.md)
explains which working scenes and textures are editable. On macOS, the
`open-environment-workshop.command` and `open-battle-fields.command` helpers
use the default `/Applications/Godot.app` installation.

The `design-workshop/` directories preserve historical authoring scripts and
review deliveries. Some historical generators retain machine-specific paths;
they are not setup steps or runtime dependencies. The supported asset entry
point is `tools/sprites`.

## Saves, cache, and troubleshooting

- **Save location:** gameplay stores `companion-save.json` and its backup in
  Godot's `user://` directory, outside this checkout. Use the editor's **Project
  → Open User Data Folder** to locate it. Back up that folder before testing
  migrations or starting over; changing Git branches does not reset progress.
- **Missing assets or unknown script classes:** let the first editor import
  finish, or run the headless import command above. `.godot/` is a generated
  cache and intentionally absent from Git. Source assets, `.uid` files, and
  `.import` settings are included.
- **Project Manager appears instead of the game on macOS:** when the checkout
  is in Documents, grant Godot **System Settings → Privacy & Security → Files &
  Folders → Documents Folder**, quit Godot, and reopen with the launcher.
- **Godot executable not found:** use `GODOT_BIN` for the game launcher or
  `GODOT_PATH` for tests. Both expect a path to the executable, not the `.app`
  directory.
- **Pillow import fails:** rerun the virtual-environment installation and verify
  that `SPRITE_PYTHON`, if set, points to that environment's Python.
- **Renderer/graphics problems:** retain the project's Compatibility renderer
  and use the verified Godot version. A successful headless test does not verify
  GPU rendering, audio playback, or touch input; check these in the editor.
- **Test failure:** read the named suite's log. Preserve the error and engine
  version when reporting it; do not infer success from a zero Godot exit code.

No export presets or distributable builds are supplied. Before preparing any
release, review the private asset notices in the repository README and the
existing [release limits](../README.md#release-limits).
