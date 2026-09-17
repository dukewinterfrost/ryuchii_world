# Initial upload verification and known issues

Verified on macOS with Godot `4.7.2.stable.official.ed1daf0bf`, Python 3.9.6,
and Pillow 11.3.0 during the initial repository handoff on September 16, 2026.
Validation used a fresh copy of the versioned files, with a new Python virtual
environment and no copied `.godot` cache.

## What was verified

- First asset import and the main care-scene startup completed without script
  or engine errors in headless mode.
- Care, food/save v6, habitat/training, persistence, combat/replay, battle UI,
  native asset checks, and the home 3D runtime checks passed.
- The Python sprite/environment pipeline suite passed 67 tests; five-region
  content packaging passed another 9 tests.
- The care map view, live scene smoke, environment runtime architecture,
  five-region runtime, environment workshop, and care presentation checks passed.
- The private environment export guard passed.

This is not a fully passing test baseline. The two failures below remain in the
uploaded project. The checked runner stops at the first failing suite, so later
suites were also run individually to inspect their results. No test expectation
or error filter was weakened to make the upload appear green.

Headless startup and structural tests do not verify final rendered appearance,
sound playback, physical-device touch input, or a long gameplay session.

## Camera cleanup reports a null material

Reproduce from the Godot project directory, with the engine on `PATH`:

```sh
godot --headless --path . --script res://tests/care_camera_runner.gd -- --test-mode
```

The test reports `Care camera: 94 checks, 0 failures`, but Godot also emits
`ERROR: Parameter "material" is null.` while freeing environment children during
the switch from the 3D home to a 2D fallback. The trace reaches
`EnvironmentView3D._clear_children()` through `unload_environment()`.

The process can exit with code 0 despite that error. `tests/run_tests.sh`
correctly rejects the unexpected engine output. The underlying material-lifetime
or renderer behavior still needs investigation.

## Green Shade 3D spike has five failing assertions

```sh
godot --headless --path . res://tests/environment_3d_spike_runner.tscn -- --test-mode
```

The runner executes 101 checks and reports five failed expectations:

- Missing promoted attack body art should be surfaced as a limitation.
- Pepper Breath should retain a neutral body fallback.
- The fallback should not leave the animation controller locked.
- The left camera clamp should keep the visible frustum inside the ground.
- The right camera clamp should keep the visible frustum inside the ground.

These expectations need reconciliation with the current animation packages and
camera behavior. This handoff does not establish whether each is a stale test
expectation or a gameplay/presentation defect.

To run the checked suites after the spike without claiming a complete pass:

```sh
COMPANION_TEST_FROM='environment runtime architecture' ./tests/run_tests.sh
```

The resume option deliberately reports only the remaining suites. Use the
unmodified full command from the [setup guide](GETTING_STARTED.md) when verifying
a future fix.
