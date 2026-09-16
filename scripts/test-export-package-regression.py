"""Offline contract checks; no Godot process or export is launched."""

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "export_package_regression",
    Path(__file__).with_name("export-package-regression.py"),
)
regression = importlib.util.module_from_spec(spec)
spec.loader.exec_module(regression)


class ExportPackageRegressionTests(unittest.TestCase):
    def test_launch_is_explicitly_silent(self):
        args = regression.launch_args(Path("/tmp/Game.app/Game"), Path("/tmp/run.log"))
        self.assertIn("--headless", args)
        self.assertEqual(args[args.index("--audio-driver") + 1], "Dummy")
        self.assertEqual(args[args.index("--log-file") + 1], "/tmp/run.log")
        self.assertEqual(
            args[args.index("--") + 1:],
            ["--verify-settings-storage", "--verify-packaged-audio"],
        )

    def test_environment_selects_a_temporary_settings_file(self):
        with patch.dict("os.environ", {"PROTOCOL47_SETTINGS_PATH": "/old/profile.cfg"}, clear=True):
            environment = regression.launch_environment(Path("/tmp/new/profile.cfg"))
            self.assertEqual(environment["PROTOCOL47_SETTINGS_PATH"], "/tmp/new/profile.cfg")
            self.assertNotIn("GODOT_USER_DATA_DIR", environment)

    def test_requires_actual_fresh_storage_confirmation(self):
        path = Path("/tmp/profile.cfg")
        valid = 'GAME_SETTINGS_STORAGE_READY {"fresh":true,"path":"/tmp/profile.cfg"}'
        self.assertTrue(regression.isolated_storage_confirmed(valid, path))
        self.assertTrue(regression.isolated_storage_confirmed(valid + "\n" + valid, path))
        for invalid in ("", "Godot Engine", valid.replace("true", "false"),
                        valid.replace("/tmp/profile.cfg", "user://protocol47.cfg"),
                        "GAME_SETTINGS_STORAGE_READY malformed", valid + '\nGAME_SETTINGS_STORAGE_READY {}'):
            with self.subTest(output=invalid):
                self.assertFalse(regression.isolated_storage_confirmed(invalid, path))

    def test_requires_packaged_audio_confirmation(self):
        self.assertTrue(regression.packaged_audio_confirmed("GAME_PACKAGED_AUDIO_READY\n"))
        self.assertFalse(regression.packaged_audio_confirmed(""))
        self.assertFalse(regression.packaged_audio_confirmed("GAME_PACKAGED_AUDIO_FAIL\n"))

    def test_rejects_errors_even_if_process_would_exit_zero(self):
        for line in (
            "ERROR: Resources still in use at exit",
            "SCRIPT ERROR: Invalid call",
            "Parse Error: Unknown identifier",
            "Failed loading resource: res://missing.tres",
            "Missing staged App 90 VGUI resource",
            "WARNING: ObjectDB instances leaked at exit",
            "WARNING: ObjectDB instance was leaked at exit",
            "GAME_PACKAGED_SMOKE_FAIL",
            "\x1b[31m  ERROR: Missing file\x1b[0m",
        ):
            with self.subTest(line=line):
                self.assertTrue(regression.rejected_output(line))

    def test_accepts_clean_output_without_inventing_completion(self):
        self.assertEqual(regression.rejected_output("Godot Engine\nGAME_SMOKE_PASS\n"), [])
        # No output is not an error classification, nor proof of gameplay.
        self.assertEqual(regression.rejected_output(""), [])
        self.assertEqual(regression.rejected_output("WARNING: informational message"), [])

    def test_keeps_the_error_line_for_diagnostics(self):
        self.assertEqual(
            regression.rejected_output("Godot Engine\n  ERROR: asset missing\nDone"),
            ["ERROR: asset missing"],
        )


if __name__ == "__main__":
    unittest.main()
