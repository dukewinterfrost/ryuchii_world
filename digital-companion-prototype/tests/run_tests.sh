#!/bin/sh
set -eu

test_project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_godot=${GODOT_PATH:-/Applications/Godot.app/Contents/MacOS/Godot}
test_python=${SPRITE_PYTHON:-$test_project_dir/.venv-sprites/bin/python}
if [ ! -x "$test_godot" ]; then
  echo "Godot executable not found at $test_godot" >&2
  exit 127
fi
if [ ! -x "$test_python" ]; then
  test_python=python3
fi
test_log_dir=$(mktemp -d /tmp/digital-companion-suite.XXXXXX)
test_index=0
test_resume_pending=${COMPANION_TEST_FROM:-}
echo "Verification logs: $test_log_dir"

run_godot() {
  test_engine_log=$(mktemp "$test_log_dir/engine.XXXXXX")
  "$test_godot" --log-file "$test_engine_log" "$@"
}

# Godot sometimes returns exit0 for script/parse failures. Require each suite's
# PASS marker and scan its complete output. Only the deliberately injected save
# failures are allowed, by exact message and expected per-suite count.
run_checked() {
  test_label=$1
  test_expected_save_errors=$2
  test_pass_marker=$3
  shift 3
  if [ -n "$test_resume_pending" ]; then
    if [ "$test_label" != "$test_resume_pending" ]; then
      return 0
    fi
    test_resume_pending=
  fi
  test_index=$((test_index + 1))
  test_log_file="$test_log_dir/$test_index.log"
  echo "Running $test_label"
  if ! "$@" >"$test_log_file" 2>&1; then
    cat "$test_log_file" >&2
    return 1
  fi
  cat "$test_log_file"
  if rg -n 'SCRIPT ERROR:|Parse Error:|Compile Error:|FAIL:|^FAILED|Traceback \(most recent call last\)' "$test_log_file"; then
    echo "$test_label reported an execution or test failure" >&2
    return 1
  fi
  if rg -i '(RIDs|ObjectDB|allocations|Texture).*leaked|resources still in use at exit' "$test_log_file"; then
    echo "$test_label leaked Godot resources" >&2
    return 1
  fi
  test_save_error_pattern='^ERROR: Saving failed\. Your in-memory progress is still active; keep the app open and try again\.$'
  test_save_error_count=$(rg -c "$test_save_error_pattern" "$test_log_file" || true)
  if [ "${test_save_error_count:-0}" -ne "$test_expected_save_errors" ]; then
    echo "$test_label produced an unexpected number of injected save errors" >&2
    return 1
  fi
  if rg '^ERROR:' "$test_log_file" | rg -v "$test_save_error_pattern"; then
    echo "$test_label reported an unexpected engine error" >&2
    return 1
  fi
  if [ "$test_pass_marker" != none ] && ! rg -q "$test_pass_marker" "$test_log_file"; then
    echo "$test_label did not emit its success marker" >&2
    return 1
  fi
}

run_checked "Godot import/parse" 0 none run_godot --headless --path "$test_project_dir" --import -- --test-mode
run_checked "care rules" 0 '^PASS:' run_godot --headless --path "$test_project_dir" --script res://tests/test_runner.gd -- --test-mode
run_checked "care v4, habitat and training rules" 0 '^Care v4: [0-9]+ checks, 0 failures$' run_godot --headless --path "$test_project_dir" --script res://tests/care_v4_test_runner.gd -- --test-mode
run_checked "home regions and save v5" 0 '^PASS:' run_godot --headless --path "$test_project_dir" --script res://tests/home_v5_test_runner.gd -- --test-mode
run_checked "food favorites, cravings and save v6" 1 '^Food care: [0-9]+ checks, 0 failures$' run_godot --headless --path "$test_project_dir" --script res://tests/food_care_runner.gd -- --test-mode
run_checked "persistence hardening" 2 '^PASS:' run_godot --headless --path "$test_project_dir" --script res://tests/persistence_hardening_runner.gd -- --test-mode
run_checked "update state integration" 4 '^PASS:' run_godot --headless --path "$test_project_dir" --script res://tests/update_state_test_runner.gd -- --test-mode
run_checked "legacy spatial combat" 0 '^PASS:' run_godot --headless --path "$test_project_dir" --script res://tests/spatial_battle_test_runner.gd -- --test-mode
run_checked "battle v3 moves, items and replay" 0 '^PASS:' run_godot --headless --path "$test_project_dir" --script res://tests/battle_v3_test_runner.gd -- --test-mode
run_checked "battle Sprite-in-3D presentation" 0 '^Battle Sprite-in-3D: [0-9]+ checks, 0 failures$' run_godot --headless --path "$test_project_dir" res://tests/battle_3d_test_runner.tscn -- --test-mode
run_checked "live battle integration" 1 '^PASS:' run_godot --headless --path "$test_project_dir" --script res://tests/battle_test_runner.gd -- --test-mode
run_checked "native assets/review" 0 '^Asset resource checks: [0-9]+ passed / [0-9]+ total$' run_godot --headless --path "$test_project_dir" --script res://tests/asset_resource_test_runner.gd -- --asset-review
run_checked "arena visual depth" 0 '^PASS:' run_godot --headless --path "$test_project_dir" --script res://tests/arena_depth_test_runner.gd -- --asset-review
run_checked "placeholder effects" 0 '^PASS:' run_godot --headless --path "$test_project_dir" --script res://tests/placeholder_effects_runner.gd -- --asset-review --placeholders
run_checked "sprite pipeline" 0 '^OK$' env PYTHONPATH="$test_project_dir/tools${PYTHONPATH:+:$PYTHONPATH}" SPRITE_NATIVE_TESTS=1 GODOT_PATH="$test_godot" "$test_python" -m unittest discover -s "$test_project_dir/tests" -p 'test_*pipeline.py' -v
run_checked "five-region content packages" 0 '^OK$' env PYTHONPATH="$test_project_dir/tools${PYTHONPATH:+:$PYTHONPATH}" "$test_python" -m unittest discover -s "$test_project_dir/tests" -p 'test_five_region_content.py' -v
run_checked "live battle controls" 0 '^Battle controls: [0-9]+ checks, 0 failures$' run_godot --headless --path "$test_project_dir" res://tests/battle_controls_runner.tscn -- --test-mode
run_checked "care UI and habitat controls" 0 '^PASS:' run_godot --headless --path "$test_project_dir" res://tests/care_ui_runner.tscn -- --test-mode
run_checked "live home 3D, projection and fallback" 0 '^PASS:' run_godot --headless --path "$test_project_dir" res://tests/home_3d_runtime_runner.tscn -- --test-mode
run_checked "care camera follow, overview and manual pan" 0 '^Care camera: [0-9]+ checks, 0 failures$' run_godot --headless --path "$test_project_dir" --script res://tests/care_camera_runner.gd -- --test-mode
run_checked "care full-window map view" 0 '^Care map view: [0-9]+ checks, 0 failures$' run_godot --headless --path "$test_project_dir" --script res://tests/care_map_view_runner.gd -- --test-mode
run_checked "live scene smoke" 0 '^PASS:' run_godot --headless --path "$test_project_dir" res://tests/scene_smoke_runner.tscn -- --test-mode
run_checked "Green Shade Sprite-in-3D spike" 0 '^PASS:' run_godot --headless --path "$test_project_dir" res://tests/environment_3d_spike_runner.tscn -- --test-mode
run_checked "environment runtime architecture" 0 '^PASS:' run_godot --headless --path "$test_project_dir" res://tests/environment_runtime_architecture_runner.tscn -- --test-mode
run_checked "five-region runtime content" 0 '^PASS: 84 five-region content checks$' run_godot --headless --path "$test_project_dir" --script res://tests/five_region_content_runner.gd -- --test-mode
run_checked "editable environment workshop" 0 '^PASS: [0-9]+ environment workshop checks; 0 failures$' run_godot --headless --path "$test_project_dir" --script res://tests/environment_workshop_runner.gd -- --test-mode
run_checked "camera-facing care presentation" 0 '^PASS: [0-9]+ care reference checks; 0 failures$' run_godot --headless --path "$test_project_dir" --script res://tests/care_reference_runner.gd -- --test-mode
if [ -n "$test_resume_pending" ]; then
  echo "Unknown resume suite: $test_resume_pending" >&2
  exit 2
fi
if [ -n "${COMPANION_TEST_FROM:-}" ]; then
  echo "PASS: remaining suites from $COMPANION_TEST_FROM"
else
  echo "PASS: complete care v4, persistence, habitat, training, battle v2/v3, animation pipeline, 3D environment and scene suite"
fi
