import asyncio
import importlib.util
import sys
import unittest
from pathlib import Path
from types import ModuleType
from typing import Any, cast, override
from unittest.mock import patch

from dbus_fast import DBusError, Message, MessageType, Variant
from dbus_fast.aio import MessageBus

SOURCE = Path(sys.argv.pop(1)).resolve()
ADAPTER = "/org/bluez/hci0"
KEYBOARD = f"{ADAPTER}/dev_AA_AA_AA_AA_AA_AA"
HEADPHONES = f"{ADAPTER}/dev_BB_BB_BB_BB_BB_BB"
ADAPTER_INTERFACE = "org.bluez.Adapter1"
DEVICE_INTERFACE = "org.bluez.Device1"


def load_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("bluetooth_autoconnect", SOURCE)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {SOURCE}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Loaded by path, so attributes are only known at runtime.
autoconnect: Any = load_module()


def device(
    adapter: str = ADAPTER,
    *,
    paired: bool = True,
    trusted: bool = True,
    blocked: bool = False,
    connected: bool = False,
) -> dict[str, dict[str, Variant]]:
    return {
        DEVICE_INTERFACE: {
            "Adapter": Variant("o", adapter),
            "Paired": Variant("b", paired),
            "Trusted": Variant("b", trusted),
            "Blocked": Variant("b", blocked),
            "Connected": Variant("b", connected),
        }
    }


class FakeBus:
    def __init__(self) -> None:
        self.objects = {ADAPTER: {ADAPTER_INTERFACE: {"Powered": Variant("b", True)}}}
        self.connections: list[str] = []
        self.unavailable: set[str] = set()
        self.waiting: set[str] = set()

    async def call(self, message: Message) -> Message:
        if message.member == "GetManagedObjects":
            return Message(
                message_type=MessageType.METHOD_RETURN,
                reply_serial=1,
                signature="a{oa{sa{sv}}}",
                body=[self.objects],
            )
        if message.member != "Connect" or message.path is None:
            raise AssertionError(f"Unexpected method {message.member}")
        path = message.path
        self.connections.append(path)
        if path in self.waiting:
            await asyncio.Future[None]()
        if path in self.unavailable:
            raise DBusError("org.bluez.Error.Failed", "Device unavailable")
        self.objects[path][DEVICE_INTERFACE]["Connected"] = Variant("b", True)
        return Message(message_type=MessageType.METHOD_RETURN, reply_serial=1)


class ReconnectionTest(unittest.IsolatedAsyncioTestCase):
    @override
    async def asyncSetUp(self) -> None:
        self.bus = FakeBus()
        self.reconnector = autoconnect.Reconnector(cast(MessageBus, self.bus))

    @override
    async def asyncTearDown(self) -> None:
        await self.reconnector.close()

    async def refresh(self) -> None:
        await self.reconnector.refresh()
        await asyncio.sleep(0)

    async def test_unavailable_headphones_do_not_delay_the_keyboard(self) -> None:
        self.bus.objects[KEYBOARD] = device()
        self.bus.objects[HEADPHONES] = device()
        self.bus.waiting.add(HEADPHONES)
        await self.refresh()
        self.assertCountEqual(self.bus.connections, [KEYBOARD, HEADPHONES])
        self.assertTrue(self.bus.objects[KEYBOARD][DEVICE_INTERFACE]["Connected"].value)
        self.assertFalse(
            self.bus.objects[HEADPHONES][DEVICE_INTERFACE]["Connected"].value
        )

    async def test_only_saved_trusted_unblocked_devices_on_powered_adapters(
        self,
    ) -> None:
        self.bus.objects[KEYBOARD] = device()
        for index, properties in enumerate(
            (
                device(paired=False),
                device(trusted=False),
                device(blocked=True),
                device(connected=True),
                device("/org/bluez/hci1"),
            )
        ):
            adapter = properties[DEVICE_INTERFACE]["Adapter"].value
            self.bus.objects[f"{adapter}/dev_CC_CC_CC_CC_CC_0{index}"] = properties
        malformed = device()
        malformed[DEVICE_INTERFACE]["Trusted"] = Variant("s", "true")
        self.bus.objects[HEADPHONES] = malformed
        await self.refresh()
        self.assertEqual(self.bus.connections, [KEYBOARD])

    async def test_device_available_later_retries_after_failure_and_timeout(
        self,
    ) -> None:
        self.bus.objects[KEYBOARD] = device()
        for mode in (self.bus.unavailable, self.bus.waiting):
            with self.subTest(
                mode="timeout" if mode is self.bus.waiting else "failure"
            ):
                self.bus.objects[KEYBOARD] = device()
                self.bus.connections.clear()
                self.reconnector = autoconnect.Reconnector(cast(MessageBus, self.bus))
                mode.add(KEYBOARD)
                with (
                    patch.object(autoconnect, "RETRY_INITIAL", 0.01),
                    patch.object(autoconnect, "CONNECT_TIMEOUT", 0.01),
                ):
                    await self.refresh()
                    await self.refresh()
                    self.assertEqual(self.bus.connections, [KEYBOARD])
                    await asyncio.sleep(0.03)
                    mode.clear()
                    await self.refresh()
                    self.assertEqual(self.bus.connections, [KEYBOARD, KEYBOARD])
                await self.reconnector.close()

    async def test_manual_disconnect_is_respected_until_adapter_power_cycle(
        self,
    ) -> None:
        self.bus.objects[KEYBOARD] = device()
        await self.refresh()
        await self.refresh()
        self.bus.objects[KEYBOARD][DEVICE_INTERFACE]["Connected"] = Variant("b", False)
        await self.refresh()
        await self.refresh()
        self.assertEqual(self.bus.connections, [KEYBOARD])
        self.bus.objects[ADAPTER][ADAPTER_INTERFACE]["Powered"] = Variant("b", False)
        await self.refresh()
        self.bus.objects[ADAPTER][ADAPTER_INTERFACE]["Powered"] = Variant("b", True)
        await self.refresh()
        self.assertEqual(self.bus.connections, [KEYBOARD, KEYBOARD])

    async def test_newly_saved_devices_and_adapters_are_detected(self) -> None:
        await self.refresh()
        self.bus.objects[HEADPHONES] = device(trusted=False)
        await self.refresh()
        self.assertEqual(self.bus.connections, [])
        self.bus.objects[HEADPHONES][DEVICE_INTERFACE]["Trusted"] = Variant("b", True)
        other_adapter = "/org/bluez/hci1"
        other_device = f"{other_adapter}/dev_DD_DD_DD_DD_DD_DD"
        self.bus.objects[other_adapter] = {
            ADAPTER_INTERFACE: {"Powered": Variant("b", True)}
        }
        self.bus.objects[other_device] = device(other_adapter)
        await self.refresh()
        self.assertCountEqual(self.bus.connections, [HEADPHONES, other_device])

    async def test_blocking_or_forgetting_cancels_pending_connections(self) -> None:
        self.bus.objects[KEYBOARD] = device()
        self.bus.objects[HEADPHONES] = device()
        self.bus.waiting.update((KEYBOARD, HEADPHONES))
        await self.refresh()
        self.bus.objects[KEYBOARD][DEVICE_INTERFACE]["Blocked"] = Variant("b", True)
        del self.bus.objects[HEADPHONES]
        await self.refresh()
        await self.refresh()
        self.assertEqual(self.reconnector.pending, {})
        self.assertCountEqual(self.bus.connections, [KEYBOARD, HEADPHONES])


if __name__ == "__main__":
    unittest.main()
