# Home clearing day–night lighting

The built-in care clearing follows the device's local clock. Dawn begins at 05:00, sunrise is at 06:00, daylight is established at 08:00, sunset is at 18:00, and night is established at 20:00. Nights use soft moonlight and a full moon; moon phases and weather are not included.

In a debug build, press **F7** or open **Field → Lighting preview**. Drag the 24-hour slider to inspect any time. **Use local time** smoothly returns to the real clock. **Hide** closes the panel without clearing the temporary override. Leaving the built-in clearing discards it. No override is saved.

The close companion view primarily shows ground lighting. Open **Field → Explore map** for the sun, moon, and stars above the treeline. Celestial elements remain behind foreground scenery and may be occluded as the camera moves.

## Integration

- `TimeOfDayController.sample_time(hour)` is a pure, wrapping 24-hour palette/celestial sampler. Its clock polls local device time every five seconds and resamples on focus. Corrections blend along the shortest path across midnight, with a capped frame delta after suspension. Tests can inject `clock_source`.
- `EnvironmentView3D.day_night` exists only for the built-in clearing. `register_home_lighting(branch)` immediately registers new presentation objects; home decor and waste call this after building their nodes. Bindings retain original sprite colors and duplicate mesh materials per instance. Tree exit removes bindings.
- Sky cards share screen coordinates for a continuous distant sky. The home instance lowers their authored placement to expose the sky in Field framing. The forest panorama shader keys the upper cyan opening and small painted stars while retaining the landscape, clouds, and dark canopy. Its upper edge blends into the procedural sky. This mask is specific to the current panorama; new background artwork needs its own mask review.
- Ground and foliage shaders default to a white tint, so other environments keep their authored appearance. UI, navigation, simulation, save data, and battle lighting are unaffected.

## Verification

Run from the project directory with Godot 4.7:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/day_night_runner.gd -- --test-mode
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/day_night_runner.gd -- --test-mode --capture
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/home_3d_runtime_runner.tscn -- --test-mode
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/environment_runtime_architecture_runner.tscn -- --test-mode
```

The graphical run uses the project's Compatibility renderer and writes `/tmp/day-night-home-{hour}.png`, `/tmp/day-night-wide-{hour}.png`, and preview/pan captures. Every runner uses an isolated synthetic save.
