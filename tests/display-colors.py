import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any, override

SOURCE = Path(sys.argv.pop(1)).resolve()


class DisplayColorsTest(unittest.TestCase):
    @override
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.config = self.directory / "config/display-colors/settings.json"
        self.session = self.directory / "session.json"
        self.session.write_text(
            json.dumps(
                {
                    "outputs": [{"name": "eDP-1", "id": 0}, {"name": "DP-1", "id": 1}],
                    "shader": "",
                }
            )
        )
        binary_directory = self.directory / "bin"
        binary_directory.mkdir()
        binary = binary_directory / "hyprctl"
        binary.write_text(
            f"#!{sys.executable}\n"
            + """
import json
import os
from pathlib import Path
import re
import sys

path = Path(os.environ["TEST_SESSION"])
session = json.loads(path.read_text())
if sys.argv[1:] == ["-j", "monitors"]:
    print(json.dumps(session["outputs"]))
elif sys.argv[1:] == ["-j", "getoption", "decoration.screen_shader"]:
    print(json.dumps({"str": session["shader"]}))
elif sys.argv[1:3] == ["-r", "eval"]:
    match = re.search(r'screen_shader = (".*?")', sys.argv[3])
    session["shader"] = json.loads(match.group(1))
    path.write_text(json.dumps(session))
    print("ok")
else:
    sys.exit(1)
"""
        )
        binary.chmod(0o755)
        self.environment = {
            **os.environ,
            "XDG_CONFIG_HOME": str(self.directory / "config"),
            "XDG_STATE_HOME": str(self.directory / "state"),
            "TEST_SESSION": str(self.session),
            "PATH": str(binary_directory) + os.pathsep + os.environ["PATH"],
        }

    def run_command(self, *arguments: str, success: bool = True) -> dict[str, Any]:
        result = subprocess.run(
            [sys.executable, str(SOURCE), *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if not success:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("Traceback", result.stderr)
            return {}
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def session_state(self) -> dict[str, Any]:
        return json.loads(self.session.read_text())

    def change_session(self, **values: object) -> None:
        self.session.write_text(json.dumps({**self.session_state(), **values}))

    def test_increase_and_disable_preserve_independent_values(self) -> None:
        self.run_command(
            "set", "--output", "eDP-1", "--separation", "140", "--saturation", "165"
        )
        shader = Path(self.session_state()["shader"]).read_text()
        self.assertIn("wl_output == 0", shader)
        self.assertNotIn("wl_output == 1", shader)
        self.assertIn("separation = 1.40000000", shader)
        self.assertIn("saturation = 1.65000000", shader)
        result = self.run_command("set", "--output", "eDP-1", "--enabled", "false")
        self.assertEqual(self.session_state()["shader"], "")
        self.assertEqual(result["outputs"][0]["separation"], 140)
        self.assertEqual(result["outputs"][0]["saturation"], 165)
        self.assertFalse(result["outputs"][0]["enabled"])
        self.run_command("set", "--output", "eDP-1", "--enabled", "true")
        self.assertNotEqual(self.session_state()["shader"], "")

    def test_reapply_resolves_monitor_ids_and_preserves_disconnected_settings(
        self,
    ) -> None:
        self.run_command("set", "--output", "eDP-1", "--saturation", "150")
        previous = self.session_state()["shader"]
        self.change_session(shader="", outputs=[{"name": "eDP-1", "id": 7}])
        self.run_command("apply")
        self.assertNotEqual(self.session_state()["shader"], previous)
        self.assertIn(
            "wl_output == 7", Path(self.session_state()["shader"]).read_text()
        )
        self.change_session(outputs=[])
        self.run_command("apply")
        self.assertEqual(self.session_state()["shader"], "")
        self.change_session(outputs=[{"name": "eDP-1", "id": 8}])
        result = self.run_command("apply")
        self.assertEqual(result["outputs"][0]["saturation"], 150)

    def test_invalid_input_does_not_change_saved_values(self) -> None:
        self.run_command("set", "--output", "eDP-1", "--separation", "120")
        previous = self.config.read_text()
        for value in ("nan", "inf", "-1", "201"):
            self.run_command(
                "set", "--output", "eDP-1", "--saturation", value, success=False
            )
            self.assertEqual(self.config.read_text(), previous)
        self.run_command(
            "set", "--output", "desconectado", "--saturation", "150", success=False
        )
        self.assertEqual(self.config.read_text(), previous)

    def test_corrupt_settings_are_reported_without_overwriting(self) -> None:
        self.config.parent.mkdir(parents=True)
        self.config.write_text("{}\n{}\n")
        self.run_command(
            "set", "--output", "eDP-1", "--saturation", "150", success=False
        )
        self.assertEqual(self.config.read_text(), "{}\n{}\n")
        self.assertEqual(self.session_state()["shader"], "")

    def test_invalid_settings_types_do_not_change_saved_values(self) -> None:
        self.config.parent.mkdir(parents=True)
        invalid_values: list[Any] = [True, None, "150", {}, [], float("nan"), 10**1000]
        invalid_settings: list[dict[str, Any]] = [{"version": True, "outputs": {}}] + [
            {"version": 1, "outputs": {"eDP-1": {"separation": value}}}
            for value in invalid_values
        ]
        for settings in invalid_settings:
            with self.subTest(settings=settings):
                previous = json.dumps(settings)
                self.config.write_text(previous)
                self.run_command("apply", success=False)
                self.assertEqual(self.config.read_text(), previous)
                self.assertEqual(self.session_state()["shader"], "")

    def test_saved_metadata_cannot_override_monitor_identity(self) -> None:
        self.config.parent.mkdir(parents=True)
        self.config.write_text(
            json.dumps(
                {
                    "version": 1,
                    "outputs": {
                        "eDP-1": {"name": "DP-1", "description": "wrong screen"}
                    },
                }
            )
        )
        result = self.run_command("status")
        self.assertEqual(result["outputs"][0]["name"], "eDP-1")
        self.assertEqual(result["outputs"][0]["description"], "")

    def test_invalid_monitor_and_shader_responses_are_reported(self) -> None:
        invalid_outputs: list[Any] = [
            {},
            [None],
            [{"name": "", "id": 0}],
            [{"name": "eDP-1", "id": True}],
            [{"name": "eDP-1", "id": -1}],
            [{"name": "eDP-1", "id": 0, "description": []}],
        ]
        for outputs in invalid_outputs:
            with self.subTest(outputs=outputs):
                self.change_session(outputs=outputs)
                self.run_command("status", success=False)
        self.change_session(outputs=[{"name": "eDP-1", "id": 0}])
        invalid_shaders: list[Any] = [None, 42, []]
        for shader in invalid_shaders:
            with self.subTest(shader=shader):
                self.change_session(shader=shader)
                self.run_command("apply", success=False)

    def test_watcher_retries_after_invalid_monitor_response(self) -> None:
        self.run_command("set", "--output", "eDP-1", "--saturation", "150")
        self.change_session(shader="", outputs=[None])
        runtime = self.directory / "runtime"
        socket_path = runtime / "hypr/test/.socket2.sock"
        socket_path.parent.mkdir(parents=True)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(str(socket_path))
            listener.listen()
            listener.settimeout(5)
            with subprocess.Popen(
                [sys.executable, str(SOURCE), "watch"],
                env={
                    **self.environment,
                    "XDG_RUNTIME_DIR": str(runtime),
                    "HYPRLAND_INSTANCE_SIGNATURE": "test",
                },
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            ) as watcher:
                try:
                    with listener.accept()[0] as connection:
                        # Wait for the failed restore to close the first connection.
                        connection.settimeout(5)
                        self.assertEqual(connection.recv(1), b"")
                    self.change_session(outputs=[{"name": "eDP-1", "id": 2}])
                    with listener.accept()[0]:
                        deadline = time.monotonic() + 5
                        while not self.session_state()["shader"]:
                            self.assertLess(time.monotonic(), deadline)
                            time.sleep(0.05)
                        self.assertIn(
                            "wl_output == 2",
                            Path(self.session_state()["shader"]).read_text(),
                        )
                        self.assertIsNone(watcher.poll())
                finally:
                    watcher.terminate()
                    _, errors = watcher.communicate(timeout=5)
                self.assertIn("Hyprland returned an invalid monitor", errors)
                self.assertNotIn("Traceback", errors)

    def test_reset_disables_neutral_shader_and_other_filter_is_preserved(self) -> None:
        self.run_command("set", "--output", "eDP-1", "--saturation", "180")
        result = self.run_command("reset", "--output", "eDP-1")
        self.assertEqual(result["outputs"][0]["saturation"], 100)
        self.assertEqual(self.session_state()["shader"], "")
        previous = self.config.read_text()
        self.change_session(shader="/otro/filtro.frag")
        self.run_command("apply")
        self.run_command(
            "set", "--output", "eDP-1", "--saturation", "150", success=False
        )
        self.assertEqual(self.config.read_text(), previous)
        self.assertEqual(self.session_state()["shader"], "/otro/filtro.frag")


if __name__ == "__main__":
    unittest.main()
