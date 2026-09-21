#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
exec /Applications/Godot.app/Contents/MacOS/Godot --path . \
  --log-file /tmp/ryuchii-battle-sandbox.log \
  res://scenes/battle_sandbox.tscn -- --battle-sandbox
