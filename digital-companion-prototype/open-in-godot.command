#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h}
godot_bin=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
project_tmp="$project_dir/.godot/tmp"
main_scene="res://scenes/care_scene.tscn"
launch_mode="editor"

case "${1:-}" in
  --play) launch_mode="play"; shift ;;
  --editor) shift ;;
  --help|-h)
    print -r -- "Usage: ./open-in-godot.command [--editor|--play] [Godot arguments...]"
    print -r -- "Default: open the care scene in the editor. Press Cmd+B on macOS to play."
    print -r -- "--play: launch the care scene directly, without opening the editor."
    exit 0
    ;;
esac

if [[ ! -x "$godot_bin" ]]; then
  print -ru2 -- "Godot was not found at: $godot_bin"
  print -ru2 -- "Install Godot there or launch with GODOT_BIN=/path/to/Godot ./open-in-godot.command"
  exit 1
fi

if [[ ! -f "$project_dir/project.godot" || ! -f "$project_dir/scenes/care_scene.tscn" ]]; then
  print -ru2 -- "The companion project or care scene is missing beside this launcher: $project_dir"
  exit 1
fi

# Use a predictable working directory even when launched from Finder or another
# terminal directory. This does not replace macOS Documents-folder permission:
# the editor's Play process needs that permission separately from the terminal.
cd "$project_dir"
mkdir -p "$project_tmp"
export TMPDIR="$project_tmp/"

print -r -- "Opening Digital Companion ($launch_mode): $project_dir"
if [[ "$launch_mode" == "editor" ]]; then
  print -r -- "Play: Cmd+B on macOS (or the top-right Play button)."
  print -r -- "If Play shows the Project Manager or getcwd/null errors, allow Godot's Documents Folder access in System Settings > Privacy & Security > Files & Folders."
  exec "$godot_bin" --editor --path "$project_dir" --log-file "$project_dir/.godot/launcher-editor.log" "$main_scene" "$@"
else
  exec "$godot_bin" --path "$project_dir" --log-file "$project_dir/.godot/launcher-play.log" "$main_scene" "$@"
fi
