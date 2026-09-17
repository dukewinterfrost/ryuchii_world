#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
exec /Applications/Godot.app/Contents/MacOS/Godot --path . \
  --log-file /tmp/companion-battle-fields.log \
  res://scenes/environment_workshop/battle_fields.tscn -- --test-mode
