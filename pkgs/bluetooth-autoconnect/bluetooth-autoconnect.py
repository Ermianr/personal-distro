"""Reconnect saved Bluetooth devices while respecting local disconnects."""

import asyncio
import logging
import time
from typing import TypedDict, cast

from dbus_fast import BusType, DBusError, Message, MessageType, Variant
from dbus_fast.aio import MessageBus

BLUEZ = "org.bluez"
DEVICE_INTERFACE = "org.bluez.Device1"
ADAPTER_INTERFACE = "org.bluez.Adapter1"
POLL_INTERVAL = 5.0
CONNECT_TIMEOUT = 20.0
RETRY_INITIAL = 5.0
RETRY_MAX = 60.0
LOGGER = logging.getLogger("bluetooth-autoconnect")


class Device(TypedDict):
    adapter: str
    eligible: bool
    connected: bool


class Snapshot(TypedDict):
    powered: set[str]
    devices: dict[str, Device]


def fields(value: object) -> dict[str, object]:
    if isinstance(value, dict) and all(isinstance(key, str) for key in value):
        return cast(dict[str, object], value)
    return {}


def property_value(properties: dict[str, object], name: str, signature: str) -> object:
    value = properties.get(name)
    if isinstance(value, Variant) and value.signature == signature:
        return value.value
    return None


def parse_snapshot(body: list[object]) -> Snapshot:
    if len(body) != 1 or not isinstance(body[0], dict):
        raise ValueError("Invalid BlueZ object-manager reply")
    powered: set[str] = set()
    devices: dict[str, Device] = {}
    for path, interfaces in fields(body[0]).items():
        if not path.startswith("/org/bluez/"):
            continue
        adapter = fields(fields(interfaces).get(ADAPTER_INTERFACE))
        if property_value(adapter, "Powered", "b") is True:
            powered.add(path)
        properties = fields(fields(interfaces).get(DEVICE_INTERFACE))
        parent = property_value(properties, "Adapter", "o")
        connected = property_value(properties, "Connected", "b")
        if not isinstance(parent, str) or not isinstance(connected, bool):
            continue
        if path.rsplit("/", 1)[0] != parent:
            continue
        devices[path] = {
            "adapter": parent,
            "eligible": (
                property_value(properties, "Paired", "b") is True
                and property_value(properties, "Trusted", "b") is True
                and property_value(properties, "Blocked", "b") is False
            ),
            "connected": connected,
        }
    return {"powered": powered, "devices": devices}


async def call(
    bus: MessageBus,
    path: str,
    interface: str,
    member: str,
) -> list[object]:
    reply = await bus.call(
        Message(
            destination=BLUEZ,
            path=path,
            interface=interface,
            member=member,
        )
    )
    if reply.message_type == MessageType.ERROR:
        raise DBusError(reply.error_name or "org.freedesktop.DBus.Error.Failed", "")
    return list(reply.body)


class Reconnector:
    def __init__(self, bus: MessageBus) -> None:
        self.bus = bus
        self.powered: set[str] = set()
        self.completed: set[str] = set()
        self.pending: dict[str, asyncio.Task[None]] = {}
        self.retry_after: dict[str, float] = {}
        self.retry_delay: dict[str, float] = {}

    async def connect(self, path: str) -> None:
        try:
            async with asyncio.timeout(CONNECT_TIMEOUT):
                await call(self.bus, path, DEVICE_INTERFACE, "Connect")
        except (DBusError, TimeoutError) as error:
            # Unavailable devices back off without delaying other connections.
            delay = self.retry_delay.get(path, RETRY_INITIAL)
            self.retry_after[path] = time.monotonic() + delay
            self.retry_delay[path] = min(delay * 2, RETRY_MAX)
            LOGGER.debug("Connection to %s postponed: %s", path, error)
        else:
            self.completed.add(path)
            self.retry_delay.pop(path, None)
            LOGGER.info("Connected device %s", path)

    async def refresh(self) -> None:
        body = await call(
            self.bus, "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"
        )
        state = parse_snapshot(body)
        newly_powered = state["powered"] - self.powered
        self.powered = state["powered"]
        devices = state["devices"]
        self.completed.intersection_update(devices)
        for path, device in devices.items():
            if device["adapter"] in newly_powered or not device["eligible"]:
                self.completed.discard(path)
                self.retry_after.pop(path, None)
                self.retry_delay.pop(path, None)
        for path, task in list(self.pending.items()):
            device = devices.get(path)
            if (
                device is None
                or not device["eligible"]
                or device["adapter"] not in self.powered
            ):
                task.cancel()
            if task.done():
                del self.pending[path]
                if not task.cancelled():
                    task.result()
        for path, device in devices.items():
            if device["connected"]:
                # Leave subsequent disconnects to the user and BlueZ's native policy.
                # A pending Connect may still need the audio session to supply a profile.
                if device["eligible"] and path not in self.pending:
                    self.completed.add(path)
            elif (
                device["eligible"]
                and device["adapter"] in self.powered
                and path not in self.completed
                and path not in self.pending
                and time.monotonic() >= self.retry_after.get(path, 0.0)
            ):
                self.pending[path] = asyncio.create_task(self.connect(path))

    async def close(self) -> None:
        for task in self.pending.values():
            task.cancel()
        await asyncio.gather(*self.pending.values(), return_exceptions=True)


async def run() -> None:
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    reconnector = Reconnector(bus)
    try:
        while True:
            await reconnector.refresh()
            await asyncio.sleep(POLL_INTERVAL)
    finally:
        await reconnector.close()
        bus.disconnect()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        return 0
    except (DBusError, OSError, ValueError) as error:
        LOGGER.error("Bluetooth reconnection failed: %s", error)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
