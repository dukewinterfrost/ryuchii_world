#!/bin/zsh
set -eu
workshop_project_dir="${0:A:h}"
exec /Applications/Godot.app/Contents/MacOS/Godot --editor --path "$workshop_project_dir" res://scenes/environment_workshop/green_shade_home.tscn
