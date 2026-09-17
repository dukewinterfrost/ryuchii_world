#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./tools/sprites validate --candidate work/sprites/care-woodland-foliage/2026-09-15.001/3305576bfa113936 --require-native
exec /Applications/Godot.app/Contents/MacOS/Godot --path . \
  --log-file /tmp/care-foliage-interactive.log \
  --script res://tests/care_reference_runner.gd -- \
  --test-mode --interactive \
  --foliage-candidate res://work/sprites/care-woodland-foliage/2026-09-15.001/3305576bfa113936
