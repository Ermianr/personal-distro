import asyncio
import contextlib
import importlib.util
import io
import json
import sys
import unittest
from pathlib import Path
from types import ModuleType
from typing import Any

SOURCE = Path(sys.argv.pop(1)).resolve()


def load_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("connectivity", SOURCE)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {SOURCE}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Loaded by path, so attributes are only known at runtime.
connectivity: Any = load_module()


def events(output: str) -> list[dict[str, object]]:
    return [json.loads(line) for line in output.splitlines()]


class ConnectivityTest(unittest.TestCase):
    def assert_window_events(self, emitted: list[dict[str, object]]) -> None:
        # BluetoothPage.qml ignores events without these exact field types.
        for event in emitted:
            self.assertEqual(set(event), {"type", "id", "device", "code"}, event)
            self.assertIsInstance(event["type"], str)
            self.assertIs(type(event["id"]), int)
            self.assertIsInstance(event["device"], str)
            self.assertIsInstance(event["code"], str)

    def test_parse_reply_accepts_only_complete_answers(self) -> None:
        self.assertEqual(
            connectivity.parse_reply('{"id": 3, "accept": true, "value": "1234"}'),
            {"id": 3, "accept": True, "value": "1234"},
        )
        self.assertEqual(
            connectivity.parse_reply('{"id": 3, "accept": false}'),
            {"id": 3, "accept": False, "value": ""},
        )
        for line in (
            "not json",
            "[]",
            '{"accept": true}',
            '{"id": "3", "accept": true}',
            '{"id": 3, "accept": 1}',
            '{"id": 3, "accept": true, "value": 1234}',
        ):
            with self.subTest(line=line):
                self.assertIsNone(connectivity.parse_reply(line))

    def test_wifi_credentials_follow_802_11_limits(self) -> None:
        self.assertTrue(connectivity.valid_ssid("Casa"))
        self.assertTrue(connectivity.valid_ssid("x" * 32))
        self.assertFalse(connectivity.valid_ssid(""))
        # The limit applies to UTF-8 bytes, not characters.
        self.assertFalse(connectivity.valid_ssid("ñ" * 17))
        for password in ("", "12345678", "x" * 63, "a" * 64):
            with self.subTest(password=password):
                self.assertTrue(connectivity.valid_psk(password))
        for password in ("1234567", "x" * 65, "g" * 64, "contraseña"):
            with self.subTest(password=password):
                self.assertFalse(connectivity.valid_psk(password))

    def test_agent_events_reach_the_window_on_answer_cancel_and_timeout(
        self,
    ) -> None:
        async def scenario() -> list[str]:
            agent = connectivity.PairingAgent()
            outcomes = []
            answered = asyncio.create_task(agent.ask("pin", "/dev/a"))
            await asyncio.sleep(0)
            agent.answer({"id": 1, "accept": True, "value": "0000"})
            outcomes.append((await answered)["value"])
            cancelled = asyncio.create_task(agent.ask("confirm", "/dev/b", "123456"))
            await asyncio.sleep(0)
            connectivity.PairingAgent.Cancel(agent)
            for request in (cancelled, agent.ask("authorize", "/dev/c")):
                try:
                    await request
                except connectivity.DBusError as error:
                    outcomes.append(error.type)
            return outcomes

        connectivity.PROMPT_TIMEOUT = 0.05
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            outcomes = asyncio.run(scenario())
        self.assertEqual(
            outcomes, ["0000", "org.bluez.Error.Rejected", "org.bluez.Error.Canceled"]
        )
        emitted = events(output.getvalue())
        self.assert_window_events(emitted)
        self.assertEqual(
            [event["type"] for event in emitted],
            ["pin", "confirm", "cancel", "authorize", "cancel"],
        )

    def test_display_and_release_events_reach_the_window(self) -> None:
        agent = connectivity.PairingAgent()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            connectivity.PairingAgent.DisplayPasskey(agent, "/dev/a", 42, 0)
            connectivity.PairingAgent.DisplayPinCode(agent, "/dev/a", "0000")
            connectivity.PairingAgent.Release(agent)
        emitted = events(output.getvalue())
        self.assert_window_events(emitted)
        self.assertEqual(
            [(event["type"], event["code"]) for event in emitted],
            [("display", "000042"), ("display", "0000"), ("cancel", "")],
        )


if __name__ == "__main__":
    unittest.main()
