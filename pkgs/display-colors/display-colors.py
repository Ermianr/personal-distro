#!/usr/bin/env python3
import argparse
import contextlib
import fcntl
import hashlib
import json
import math
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
from collections.abc import Generator
from pathlib import Path
from typing import TypedDict


class OutputSettings(TypedDict):
    separation: float
    saturation: float
    red: float
    green: float
    blue: float
    enabled: bool
    white_balance_enabled: bool


class Settings(TypedDict):
    version: int
    outputs: dict[str, OutputSettings]


class Monitor(TypedDict):
    name: str
    id: int
    description: str


class OutputStatus(OutputSettings):
    name: str
    description: str


class Status(TypedDict):
    outputs: list[OutputStatus]


DEFAULT_VALUES: OutputSettings = {
    "separation": 100.0,
    "saturation": 100.0,
    "red": 100.0,
    "green": 100.0,
    "blue": 100.0,
    "enabled": False,
    "white_balance_enabled": False,
}


def config_dir() -> Path:
    return (
        Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        / "display-colors"
    )


def state_dir() -> Path:
    return (
        Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        / "display-colors"
    )


def percentage(value: str | int | float) -> float:
    if isinstance(value, bool):
        raise ValueError("Percentage must be a number between 0 and 200.")
    try:
        number = float(value)
    except (ValueError, OverflowError) as error:
        raise ValueError("Percentage must be a number between 0 and 200.") from error
    if not math.isfinite(number) or not 0 <= number <= 200:
        raise ValueError("Percentage must be between 0 and 200.")
    return number


def channel_gain(value: str | int | float) -> float:
    number = percentage(value)
    if number > 100:
        raise ValueError("Channel gain must be between 0 and 100.")
    return number


def load_settings() -> Settings:
    path = config_dir() / "settings.json"
    if not path.exists():
        return {"version": 1, "outputs": {}}
    data = json.loads(path.read_text())
    if (
        not isinstance(data, dict)
        or type(data.get("version")) is not int
        or data["version"] != 1
        or not isinstance(data.get("outputs"), dict)
    ):
        raise ValueError(f"Invalid settings file: {path}")
    settings: Settings = {"version": 1, "outputs": {}}
    for name, values in data["outputs"].items():
        if (
            not name
            or not isinstance(values, dict)
            or not isinstance(values.get("enabled", False), bool)
            or not isinstance(values.get("white_balance_enabled", False), bool)
        ):
            raise ValueError(f"Invalid monitor settings: {name}")
        percentages = {}
        for key in ("separation", "saturation", "red", "green", "blue"):
            value = values.get(key, 100)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                raise ValueError(f"Invalid {key} for monitor: {name}")
            validator = channel_gain if key in ("red", "green", "blue") else percentage
            percentages[key] = validator(value)
        # Copy known fields only so saved JSON cannot override monitor identity in status.
        settings["outputs"][name] = {
            "separation": percentages["separation"],
            "saturation": percentages["saturation"],
            "red": percentages["red"],
            "green": percentages["green"],
            "blue": percentages["blue"],
            "enabled": values.get("enabled", False),
            "white_balance_enabled": values.get("white_balance_enabled", False),
        }
    return settings


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextlib.contextmanager
def settings_lock() -> Generator[None]:
    directory = state_dir()
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / "settings.lock").open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def hyprctl(*arguments: str) -> str:
    result = subprocess.run(
        ["hyprctl", *arguments], capture_output=True, text=True, timeout=10
    )
    if result.returncode:
        raise RuntimeError(
            result.stderr.strip()
            or result.stdout.strip()
            or "Could not connect to Hyprland."
        )
    return result.stdout.strip()


def connected_outputs() -> list[Monitor]:
    data = json.loads(hyprctl("-j", "monitors"))
    if not isinstance(data, list):
        raise RuntimeError("Hyprland did not return a monitor list.")
    outputs: list[Monitor] = []
    for output in data:
        if (
            not isinstance(output, dict)
            or not isinstance(output.get("name"), str)
            or not output["name"]
            or type(output.get("id")) is not int
            or output["id"] < 0
            or not isinstance(output.get("description", ""), str)
        ):
            raise RuntimeError("Hyprland returned an invalid monitor.")
        outputs.append(
            {
                "name": output["name"],
                "id": output["id"],
                "description": output.get("description", ""),
            }
        )
    return outputs


def shader_source(settings: Settings, outputs: list[Monitor]) -> str | None:
    branches = []
    # Monitor IDs change after reconnects; resolve saved connector names on each apply.
    for output in outputs:
        values = settings["outputs"].get(output["name"], DEFAULT_VALUES)
        separation = values["separation"] if values["enabled"] else 100
        saturation = values["saturation"] if values["enabled"] else 100
        white_balance = [
            values[channel] if values["white_balance_enabled"] else 100
            for channel in ("red", "green", "blue")
        ]
        if separation == saturation == 100 and all(
            gain == 100 for gain in white_balance
        ):
            continue
        gains = ", ".join(f"{gain / 100:.8f}" for gain in white_balance)
        branches.append(
            f"    if (wl_output == {output['id']}) {{\n"
            f"        separation = {separation / 100:.8f};\n"
            f"        saturation = {saturation / 100:.8f};\n"
            f"        white_balance = vec3({gains});\n"
            "    }\n"
        )
    if not branches:
        return None
    # Avoid time/cursor uniforms to preserve damage tracking. Clamp once after both effects.
    return (
        """#version 320 es
precision highp float;
precision highp int;
in vec2 v_texcoord;
uniform sampler2D tex;
uniform int wl_output;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 pixel = texture(tex, v_texcoord);
    float separation = 1.0;
    float saturation = 1.0;
    vec3 white_balance = vec3(1.0);
"""
        + "".join(branches)
        + """    vec3 rgb = pixel.rgb;
    // Match the standalone white-balance preview without an enhancement or clipping pass.
    if (separation == 1.0 && saturation == 1.0) {
        fragColor = vec4(pixel.rgb * white_balance, pixel.a);
        return;
    }
    float average = (rgb.r + rgb.g + rgb.b) / 3.0;
    rgb = mix(vec3(average), rgb, separation);
    float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    rgb = mix(vec3(luminance), rgb, saturation);
    // Apply panel gains after clipping enhancement to retain the corrected white point.
    fragColor = vec4(clamp(rgb, 0.0, 1.0) * white_balance, pixel.a);
}
"""
    )


def apply_settings(settings: Settings, outputs: list[Monitor]) -> None:
    directory = state_dir()
    source = shader_source(settings, outputs)
    shader_path = ""
    if source is not None:
        digest = hashlib.sha256(source.encode()).hexdigest()[:16]
        path = directory / f"colors-{digest}.frag"
        if not path.exists():
            atomic_write(path, source)
        shader_path = str(path)
    current = screen_shader()
    own_shader = current.startswith(str(directory / "colors-"))
    if current not in ("", "[[EMPTY]]") and not own_shader:
        if source is None:
            return
        raise RuntimeError(
            "Another screen shader is active. Disable it before adjusting display colors."
        )
    if current != shader_path and not (not shader_path and current == "[[EMPTY]]"):
        set_screen_shader(shader_path)
    # Keep recent files because Hyprland loads the shader on the next frame.
    for old_path in directory.glob("colors-*.frag"):
        if str(old_path) != shader_path and time.time() - old_path.stat().st_mtime > 60:
            old_path.unlink(missing_ok=True)


def screen_shader() -> str:
    option = json.loads(hyprctl("-j", "getoption", "decoration.screen_shader"))
    if not isinstance(option, dict) or not isinstance(option.get("str"), str):
        raise RuntimeError("Hyprland returned an invalid screen shader option.")
    return option["str"]


def set_screen_shader(path: str, reload: bool = True) -> None:
    lua = (
        "hl.config({ decoration = { screen_shader = "
        + json.dumps(path, ensure_ascii=False)
        + " } })\n"
    )
    # Reloading recompiles the shader and repaints every output, but screencopy can
    # return a fully transparent frame while it runs. Screencopy renders a fresh frame
    # anyway, so captures change the option without reloading.
    result = hyprctl(*(["-r"] if reload else []), "eval", lua)
    if result != "ok":
        raise RuntimeError(f"Could not apply the filter: {result}")


def capture_screen(arguments: list[str]) -> int:
    with settings_lock():
        current = screen_shader()
        if not current.startswith(str(state_dir() / "colors-")):
            return subprocess.run(["grim", *arguments], check=False).returncode
        # Frozen screenshots must contain original pixels: displaying them applies the
        # screen filter again. Keep the watcher and UI from restoring it during capture.
        handler = signal.signal(
            signal.SIGTERM, lambda signum, _frame: sys.exit(128 + signum)
        )
        try:
            set_screen_shader("", reload=False)
            return subprocess.run(["grim", *arguments], check=False).returncode
        finally:
            try:
                set_screen_shader(current)
            finally:
                signal.signal(signal.SIGTERM, handler)


def status(settings: Settings, outputs: list[Monitor]) -> Status:
    output_status: list[OutputStatus] = []
    for output in outputs:
        values = settings["outputs"].get(output["name"], DEFAULT_VALUES)
        output_status.append(
            {
                "name": output["name"],
                "description": output["description"],
                "separation": values["separation"],
                "saturation": values["saturation"],
                "red": values["red"],
                "green": values["green"],
                "blue": values["blue"],
                "enabled": values["enabled"],
                "white_balance_enabled": values["white_balance_enabled"],
            }
        )
    return {"outputs": output_status}


def apply_saved() -> None:
    with settings_lock():
        apply_settings(load_settings(), connected_outputs())


def watch_session() -> None:
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not signature or not runtime_dir:
        raise RuntimeError("Start the service inside the Hyprland session.")
    path = str(Path(runtime_dir) / "hypr" / signature / ".socket2.sock")
    last_error = ""
    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.connect(path)
                apply_saved()
                last_error = ""
                pending = b""
                while data := connection.recv(65536):
                    pending += data
                    lines = pending.split(b"\n")
                    pending = lines.pop()
                    if any(
                        line.split(b">>", 1)[0]
                        in (b"configreloaded", b"monitoradded", b"monitorremoved")
                        for line in lines
                    ):
                        time.sleep(0.1)
                        apply_saved()
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
            message = str(error)
            if message != last_error:
                print(
                    f"Could not restore the filter: {message}",
                    file=sys.stderr,
                    flush=True,
                )
                last_error = message
        time.sleep(1)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ajusta el realce de color y el balance de blanco por monitor."
    )
    parser._positionals.title = "órdenes"
    parser._optionals.title = "opciones"
    commands = parser.add_subparsers(dest="command")
    commands.add_parser("ui", help="Abrir los controles")
    commands.add_parser("status", help="Consultar monitores y ajustes")
    commands.add_parser("apply", help="Restaurar el filtro guardado")
    commands.add_parser("watch", help="Restaurar el filtro al cambiar la sesión")
    capture = commands.add_parser(
        "capture", help="Capturar sin duplicar el filtro de color"
    )
    capture.add_argument("arguments", nargs=argparse.REMAINDER, help="Opciones de grim")
    setter = commands.add_parser(
        "set", help="Guardar y aplicar los ajustes de un monitor"
    )
    setter.add_argument("--output", required=True, help="Nombre del monitor")
    setter.add_argument(
        "--separation", type=percentage, help="Separación de color, de 0 a 200 %%"
    )
    setter.add_argument(
        "--saturation", type=percentage, help="Saturación, de 0 a 200 %%"
    )
    setter.add_argument(
        "--enabled",
        choices=("true", "false"),
        help="Activar o desactivar separación y saturación",
    )
    setter.add_argument(
        "--white-balance-enabled",
        choices=("true", "false"),
        help="Activar o desactivar el balance de blanco",
    )
    for channel, label in (("red", "rojo"), ("green", "verde"), ("blue", "azul")):
        setter.add_argument(
            f"--{channel}",
            type=channel_gain,
            help=f"Canal {label} del balance de blanco, de 0 a 100 %%",
        )
    resetter = commands.add_parser("reset", help="Restablecer los colores neutros")
    resetter.add_argument("--output", required=True, help="Nombre del monitor")
    arguments = parser.parse_args()
    try:
        if arguments.command in (None, "ui"):
            os.execvp(
                "quickshell", ["quickshell", "-p", os.environ["DISPLAY_COLORS_QML"]]
            )
        if arguments.command == "watch":
            watch_session()
            return 0
        if arguments.command == "capture":
            options = arguments.arguments
            if options[:1] == ["--"]:
                options = options[1:]
            return capture_screen(options)
        with settings_lock():
            settings = load_settings()
            outputs = connected_outputs()
            if arguments.command in ("set", "reset"):
                if arguments.output not in {output["name"] for output in outputs}:
                    raise ValueError(f"Monitor is not connected: {arguments.output}")
                values = (
                    settings["outputs"].get(arguments.output, DEFAULT_VALUES).copy()
                )
                if arguments.command == "reset":
                    values = DEFAULT_VALUES.copy()
                else:
                    for key in ("separation", "saturation", "red", "green", "blue"):
                        if getattr(arguments, key) is not None:
                            values[key] = getattr(arguments, key)
                    if arguments.enabled is not None:
                        values["enabled"] = arguments.enabled == "true"
                    if arguments.white_balance_enabled is not None:
                        values["white_balance_enabled"] = (
                            arguments.white_balance_enabled == "true"
                        )
                settings["outputs"][arguments.output] = values
                apply_settings(settings, outputs)
                atomic_write(
                    config_dir() / "settings.json",
                    json.dumps(settings, indent=2, allow_nan=False) + "\n",
                )
            elif arguments.command == "apply":
                apply_settings(settings, outputs)
            print(json.dumps(status(settings, outputs), ensure_ascii=False))
        return 0
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        RuntimeError,
        subprocess.TimeoutExpired,
    ) as error:
        print(f"Could not adjust display colors: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
