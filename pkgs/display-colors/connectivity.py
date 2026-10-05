"""BlueZ pairing agent and hidden Wi-Fi connector for Personal Tweaks.

Quickshell can drive NetworkManager and BlueZ, but it cannot export D-Bus objects
or create hidden-network profiles. This helper fills both gaps and talks to the
QML window through JSON lines on stdin/stdout.
"""

import argparse
import asyncio
import json
import string
import sys
from typing import TypedDict, cast

from dbus_fast import BusType, DBusError, Message, MessageType, Variant
from dbus_fast.aio import MessageBus
from dbus_fast.annotations import DBusObjectPath, DBusStr, DBusUInt16, DBusUInt32
from dbus_fast.service import ServiceInterface, dbus_method

AGENT_PATH = "/org/personaltweaks/BluetoothAgent"
PROMPT_TIMEOUT = 60.0
NM_BUS = "org.freedesktop.NetworkManager"
NM_PATH = "/org/freedesktop/NetworkManager"
NM_DEVICE_TYPE_WIFI = 2
NM_ACTIVE_ACTIVATED = 2
NM_ACTIVE_DEACTIVATED = 4
ACTIVATION_TIMEOUT = 45.0


class Reply(TypedDict):
    id: int
    accept: bool
    value: str


def emit(event: dict[str, object]) -> None:
    print(json.dumps(event), flush=True)


def parse_reply(line: str) -> Reply | None:
    try:
        data: object = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    fields = cast(dict[str, object], data)
    request_id = fields.get("id")
    accept = fields.get("accept")
    value = fields.get("value", "")
    if (
        not isinstance(request_id, int)
        or not isinstance(accept, bool)
        or not isinstance(value, str)
    ):
        return None
    return {"id": request_id, "accept": accept, "value": value}


async def call(
    bus: MessageBus,
    destination: str,
    path: str,
    interface: str,
    member: str,
    signature: str = "",
    body: list[object] | None = None,
) -> list[object]:
    reply = await bus.call(
        Message(
            destination=destination,
            path=path,
            interface=interface,
            member=member,
            signature=signature,
            body=body or [],
        )
    )
    if reply.message_type == MessageType.ERROR:
        detail = reply.body[0] if reply.body else ""
        raise DBusError(reply.error_name or "org.freedesktop.DBus.Error.Failed", detail)
    return list(reply.body)


async def get_property(bus: MessageBus, path: str, interface: str, name: str) -> object:
    body = await call(
        bus,
        NM_BUS,
        path,
        "org.freedesktop.DBus.Properties",
        "Get",
        "ss",
        [interface, name],
    )
    value = body[0]
    return value.value if isinstance(value, Variant) else value


class PairingAgent(ServiceInterface):
    """Forward BlueZ prompts to the window and wait for its answer."""

    def __init__(self) -> None:
        super().__init__("org.bluez.Agent1")
        self.pending: dict[int, asyncio.Future[Reply]] = {}
        self.next_id = 0

    async def ask(self, kind: str, device: str, code: str = "") -> Reply:
        self.next_id += 1
        request_id = self.next_id
        future: asyncio.Future[Reply] = asyncio.get_running_loop().create_future()
        self.pending[request_id] = future
        emit({"type": kind, "id": request_id, "device": device, "code": code})
        try:
            reply = await asyncio.wait_for(future, PROMPT_TIMEOUT)
        except TimeoutError:
            emit({"type": "cancel"})
            raise DBusError("org.bluez.Error.Canceled", "No answer") from None
        finally:
            self.pending.pop(request_id, None)
        if not reply["accept"]:
            raise DBusError("org.bluez.Error.Rejected", "Rejected by the user")
        return reply

    def answer(self, reply: Reply) -> None:
        future = self.pending.get(reply["id"])
        if future is not None and not future.done():
            future.set_result(reply)

    @dbus_method()
    def Release(self) -> None:
        emit({"type": "cancel"})

    @dbus_method()
    async def RequestPinCode(self, device: DBusObjectPath) -> DBusStr:
        pin = (await self.ask("pin", device))["value"]
        # Legacy PIN codes are 1-16 printable characters.
        if not 1 <= len(pin) <= 16 or not pin.isprintable():
            raise DBusError("org.bluez.Error.Rejected", "Invalid PIN")
        return pin

    @dbus_method()
    def DisplayPinCode(self, device: DBusObjectPath, pincode: DBusStr) -> None:
        emit({"type": "display", "id": 0, "device": device, "code": pincode})

    @dbus_method()
    async def RequestPasskey(self, device: DBusObjectPath) -> DBusUInt32:
        passkey = (await self.ask("passkey", device))["value"]
        if not passkey.isdigit() or len(passkey) > 6:
            raise DBusError("org.bluez.Error.Rejected", "Invalid passkey")
        return int(passkey)

    @dbus_method()
    def DisplayPasskey(
        self, device: DBusObjectPath, passkey: DBusUInt32, entered: DBusUInt16
    ) -> None:
        del entered
        emit({"type": "display", "id": 0, "device": device, "code": f"{passkey:06d}"})

    @dbus_method()
    async def RequestConfirmation(
        self, device: DBusObjectPath, passkey: DBusUInt32
    ) -> None:
        await self.ask("confirm", device, f"{passkey:06d}")

    @dbus_method()
    async def RequestAuthorization(self, device: DBusObjectPath) -> None:
        await self.ask("authorize", device)

    @dbus_method()
    async def AuthorizeService(self, device: DBusObjectPath, uuid: DBusStr) -> None:
        # Devices paired here are trusted, so BlueZ only asks for unknown peers.
        del uuid
        await self.ask("service", device)

    @dbus_method()
    def Cancel(self) -> None:
        for request_id, future in self.pending.items():
            if not future.done():
                future.set_result({"id": request_id, "accept": False, "value": ""})
        emit({"type": "cancel"})


async def run_agent() -> int:
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    agent = PairingAgent()
    bus.export(AGENT_PATH, agent)
    try:
        manager = ("org.bluez", "/org/bluez", "org.bluez.AgentManager1")
        await call(
            bus, *manager, "RegisterAgent", "os", [AGENT_PATH, "KeyboardDisplay"]
        )
        await call(bus, *manager, "RequestDefaultAgent", "o", [AGENT_PATH])
    except DBusError as error:
        emit({"type": "error", "id": 0, "device": "", "code": error.text})
        return 1
    emit({"type": "ready", "id": 0, "device": "", "code": ""})

    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(
        lambda: asyncio.StreamReaderProtocol(reader), sys.stdin
    )
    # The agent lives as long as the window keeps stdin open.
    while line := await reader.readline():
        reply = parse_reply(line.decode(errors="replace"))
        if reply is not None:
            agent.answer(reply)
    try:
        await call(bus, *manager, "UnregisterAgent", "o", [AGENT_PATH])
    except DBusError:
        pass
    bus.disconnect()
    return 0


def valid_ssid(ssid: str) -> bool:
    return 1 <= len(ssid.encode()) <= 32


def valid_psk(password: str) -> bool:
    if password == "":
        return True
    if len(password) == 64:
        return all(character in string.hexdigits for character in password)
    return 8 <= len(password) <= 63 and password.isascii() and password.isprintable()


async def find_wifi_device(bus: MessageBus) -> str | None:
    body = await call(bus, NM_BUS, NM_PATH, NM_BUS, "GetDevices")
    devices: list[object] = (
        cast(list[object], body[0]) if body and isinstance(body[0], list) else []
    )
    for device in devices:
        if not isinstance(device, str):
            continue
        device_type = await get_property(
            bus, device, "org.freedesktop.NetworkManager.Device", "DeviceType"
        )
        if device_type == NM_DEVICE_TYPE_WIFI:
            return device
    return None


async def wait_for_activation(bus: MessageBus, active: str) -> bool:
    deadline = asyncio.get_running_loop().time() + ACTIVATION_TIMEOUT
    while asyncio.get_running_loop().time() < deadline:
        try:
            state = await get_property(
                bus, active, "org.freedesktop.NetworkManager.Connection.Active", "State"
            )
        except DBusError:
            # NetworkManager removes failed activations.
            return False
        if state == NM_ACTIVE_ACTIVATED:
            return True
        if state == NM_ACTIVE_DEACTIVATED:
            return False
        await asyncio.sleep(0.5)
    return False


async def connect_hidden(ssid: str, password: str) -> tuple[bool, str]:
    if not valid_ssid(ssid):
        return False, "El nombre de la red debe tener entre 1 y 32 bytes."
    if not valid_psk(password):
        return False, "La contraseña debe tener entre 8 y 63 caracteres."
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    try:
        device = await find_wifi_device(bus)
        if device is None:
            return False, "No hay un adaptador Wi-Fi disponible."
        settings: dict[str, dict[str, Variant]] = {
            "connection": {
                "id": Variant("s", ssid),
                "type": Variant("s", "802-11-wireless"),
            },
            "802-11-wireless": {
                "ssid": Variant("ay", ssid.encode()),
                "mode": Variant("s", "infrastructure"),
                "hidden": Variant("b", True),
            },
        }
        if password:
            settings["802-11-wireless-security"] = {
                "key-mgmt": Variant("s", "wpa-psk"),
                "psk": Variant("s", password),
            }
        profile, active = (
            await call(
                bus,
                NM_BUS,
                NM_PATH,
                NM_BUS,
                "AddAndActivateConnection",
                "a{sa{sv}}oo",
                [settings, device, "/"],
            )
        )[:2]
        if not isinstance(profile, str) or not isinstance(active, str):
            return False, "NetworkManager devolvió una respuesta inesperada."
        if await wait_for_activation(bus, active):
            return True, ""
        # Do not keep a profile that never worked, such as one with a wrong password.
        try:
            await call(
                bus,
                NM_BUS,
                profile,
                "org.freedesktop.NetworkManager.Settings.Connection",
                "Delete",
            )
        except DBusError:
            pass
        return False, "No se pudo conectar. Revisa el nombre de la red y la contraseña."
    except DBusError as error:
        return False, "NetworkManager rechazó la conexión: " + error.text
    finally:
        bus.disconnect()


def main() -> int:
    parser = argparse.ArgumentParser(description="Conectividad de Personal Tweaks")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("agent", help="Atender emparejamientos Bluetooth")
    hidden = commands.add_parser(
        "connect-hidden", help="Conectar a una red Wi-Fi oculta"
    )
    hidden.add_argument("--ssid", required=True)
    arguments = parser.parse_args()
    if arguments.command == "agent":
        return asyncio.run(run_agent())
    # The password arrives on stdin so it never appears in the process list.
    password = sys.stdin.readline().rstrip("\n")
    ok, message = asyncio.run(connect_hidden(arguments.ssid, password))
    print(json.dumps({"ok": ok, "message": message}), flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
