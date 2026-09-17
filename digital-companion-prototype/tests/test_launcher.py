"""Launcher contract tests; never start Godot or access a real companion save."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


LAUNCHER = Path(__file__).resolve().parents[1] / "open-in-godot.command"


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="companion-launcher-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.project = self.root / "Godot Projects" / "companion"
        (self.project / "scenes").mkdir(parents=True)
        (self.project / "project.godot").touch()
        (self.project / "scenes/care_scene.tscn").touch()
        self.launcher = self.project / "open-in-godot.command"
        shutil.copy2(LAUNCHER, self.launcher)
        self.engine = self.root / "Fake Godot"
        self.engine.write_text(
            '#!/bin/zsh\nprint -r -- "CWD=$PWD"\n'
            'print -r -- "TMPDIR=$TMPDIR"\n'
            'for arg in "$@"; do print -r -- "ARG=$arg"; done\n'
        )
        self.engine.chmod(0o755)

    def launch(self, *args, engine=None):
        env = dict(os.environ, GODOT_BIN=str(engine or self.engine))
        return subprocess.run(
            ["/bin/zsh", str(self.launcher), *args], cwd=self.root,
            env=env, capture_output=True, text=True, check=False,
        )

    def test_editor_uses_explicit_scene_and_stable_paths(self):
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertIn(f"CWD={self.project}", lines)
        self.assertIn(f"TMPDIR={self.project}/.godot/tmp/", lines)
        self.assertEqual([s[4:] for s in lines if s.startswith("ARG=")], [
            "--editor", "--path", str(self.project), "--log-file",
            str(self.project / ".godot/launcher-editor.log"),
            "res://scenes/care_scene.tscn",
        ])

    def test_play_and_extra_arguments_keep_argument_boundaries(self):
        result = self.launch("--play", "--headless", "--", "name with spaces")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = [s[4:] for s in result.stdout.splitlines() if s.startswith("ARG=")]
        self.assertEqual(args, [
            "--path", str(self.project), "--log-file",
            str(self.project / ".godot/launcher-play.log"),
            "res://scenes/care_scene.tscn", "--headless", "--", "name with spaces",
        ])

    def test_explicit_editor_matches_default(self):
        self.assertEqual(self.launch().stdout, self.launch("--editor").stdout)

    def test_help_does_not_require_engine(self):
        result = self.launch("--help", engine=self.root / "missing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--play:", result.stdout)
        self.assertNotIn("ARG=", result.stdout)

    def test_missing_engine_is_actionable(self):
        result = self.launch(engine=self.root / "missing")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Godot was not found", result.stderr)

    def test_missing_scene_fails_before_starting_engine(self):
        (self.project / "scenes/care_scene.tscn").unlink()
        result = self.launch()
        self.assertEqual(result.returncode, 1)
        self.assertIn("care scene is missing", result.stderr)
        self.assertNotIn("ARG=", result.stdout)


if __name__ == "__main__":
    unittest.main()
