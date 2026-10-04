{
  pkgs,
  homeManagerModule,
  serpantinumModule,
  loginBackground,
  sddmAstronautTheme,
  homeCfg,
}:
pkgs.testers.runNixOSTest {
  name = "serpantinum-session";
  globalTimeout = 600;
  enableOCR = true;
  node.pkgsReadOnly = false;
  qemu.forceAccel = true;
  nodes.machine = { config, lib, ... }: {
    imports = [
      ../modules/base.nix
      homeManagerModule
      serpantinumModule
      homeCfg
    ];
    _module.args = { inherit loginBackground sddmAstronautTheme; };
    users.users.razor = {
      uid = 1000;
      initialHashedPassword = lib.mkForce null;
      password = "serpantinumtest";
    };
    # Seed existing settings to check that the first activation applies declared presets.
    systemd.tmpfiles.rules = [
      "d /home/razor/.config 0755 razor users - -"
      "d /home/razor/.config/serpantinum 0755 razor users - -"
      ''f /home/razor/.config/serpantinum/settings.json 0644 razor users - {"general":{"language":"en"},"notifications":{"dnd":true},"customPreference":"keep"}''
    ];
    environment = {
      sessionVariables = {
        LIBGL_ALWAYS_SOFTWARE = "1";
        AQ_NO_MODIFIERS = "1";
      };
      etc = {
        "serpantinum-prepare-wallpaper".source =
          config.home-manager.users.razor.systemd.user.services.serpantinum.Service.ExecStartPre;
        # Exercise the same icon lookup used by Quickshell.
        "serpantinum-icon-check.qml".text = ''
          import QtQuick
          import Quickshell

          ShellRoot {
            Image {
              source: "image://icon/applications-system"
              sourceSize: Qt.size(20, 20)
            }
            Image {
              source: "image://icon/com.mitchellh.ghostty"
              sourceSize: Qt.size(20, 20)
            }
            Timer {
              interval: 200
              running: true
              onTriggered: {
                for (const icon of ["applications-system", "com.mitchellh.ghostty"]) {
                  if (!Quickshell.iconPath(icon, true)) {
                    console.error("Icon not found: " + icon);
                    Qt.exit(1);
                    return;
                  }
                }
                Qt.quit();
              }
            }
          }
        '';
        "display-colors-samples.qml".text = ''
          import QtQuick
          import Quickshell

          ShellRoot {
            FloatingWindow {
              title: "Muestras de color"
              color: "transparent"
              implicitWidth: 1000
              implicitHeight: 600
              visible: true
              onClosed: Qt.quit()
              Row {
                anchors.fill: parent
                Repeater {
                  model: ["#6080a0", "#a06080", "#a08060", "#707070"]
                  Rectangle {
                    required property string modelData
                    required property int index
                    width: parent.width / 4
                    height: parent.height
                    color: modelData
                    // Exercise translucent surfaces without changing the neutral gray patch.
                    opacity: index < 2 ? 0.75 : 1
                  }
                }
              }
            }
          }
        '';
      };
      systemPackages = with pkgs; [
        glib.bin
        jq
        libnotify
        wl-clipboard
        cliphist
      ];
    };
    virtualisation = {
      memorySize = 4096;
      cores = 2;
      resolution = {
        x = 1600;
        y = 900;
      };
      qemu.options = [ "-vga none -device virtio-gpu-pci,xres=1600,yres=900" ];
    };
  };
  testScript = ''
    import base64
    import json
    import re
    import shlex
    import subprocess
    from typing import Any

    def as_user(command: str) -> str:
        environment = (
            "export XDG_RUNTIME_DIR=/run/user/1000; "
            "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
            "export WAYLAND_DISPLAY=$(systemctl --user show-environment | sed -n 's/^WAYLAND_DISPLAY=//p'); "
            "export HYPRLAND_INSTANCE_SIGNATURE=$(systemctl --user show-environment | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p'); "
        )
        # Helpers use Bash syntax even when the user's login shell is Fish.
        return "su - razor -s /run/current-system/sw/bin/bash -c " + shlex.quote(environment + command)

    def settings() -> dict:
        return json.loads(machine.succeed("cat /home/razor/.config/serpantinum/settings.json"))

    def framebuffer() -> tuple[int, int, bytes]:
        with machine._managed_screenshot() as screenshot_path:
            magic, dimensions, maximum, pixels = screenshot_path.read_bytes().split(b"\n", 3)
        assert magic == b"P6" and maximum == b"255", (magic, maximum)
        width, height = map(int, dimensions.split())
        return width, height, pixels

    def captured_framebuffer(path: str) -> tuple[int, int, bytes]:
        image = base64.b64decode(machine.succeed("base64 -w0 " + shlex.quote(path)))
        ppm = subprocess.check_output(["pngtopnm", "-"], input=image)
        magic, dimensions, maximum, pixels = ppm.split(b"\n", 3)
        assert magic == b"P6" and maximum == b"255", (magic, maximum)
        width, height = map(int, dimensions.split())
        return width, height, pixels

    def login_background_samples() -> list[tuple[int, ...]]:
        width, height, pixels = framebuffer()
        return [
            tuple(pixels[offset:offset + 3])
            for x, y in [(width // 8, height // 8), (width * 7 // 8, height // 8), (width // 8, height * 7 // 8)]
            for offset in [(y * width + x) * 3]
        ]

    def active_border() -> str:
        option = json.loads(machine.succeed(as_user("hyprctl -i 0 -j getoption general:col.active_border")))
        return option["gradient"].split()[0].lower()

    def assert_matugen_border() -> None:
        colors = json.loads(machine.succeed("cat /home/razor/.local/state/serpantinum/qs_matugen_colors.json"))
        expected = "ff" + colors["blue"].removeprefix("#").lower()
        actual = active_border()
        assert actual == expected, {"actual": actual, "expected": expected}
        shadow = json.loads(machine.succeed(as_user("hyprctl -i 0 -j getoption decoration:shadow:color")))
        # The status JSON lacks inverse_primary, so read the color matugen rendered for Hyprland.
        hyprland_colors = machine.succeed("cat /home/razor/.local/state/serpantinum/hyprland-colors.lua")
        shadow_rgb = re.search(r'color = "rgba\(([0-9a-fA-F]{6})10\)"', hyprland_colors)
        assert shadow_rgb is not None, hyprland_colors
        expected_shadow = int("10" + shadow_rgb.group(1), 16)
        assert shadow["int"] & 0xffffffff == expected_shadow, shadow

    def color_settings() -> dict:
        return json.loads(machine.succeed("cat /home/razor/.config/display-colors/settings.json"))

    def click_at(x: int, y: int) -> None:
        # Select the tablet so QMP can send absolute coordinates to Wayland.
        assert machine.qmp_client is not None
        mice_reply: Any = machine.qmp_client.send("query-mice")
        tablet_id = next(mouse["index"] for mouse in mice_reply["return"] if mouse["absolute"])
        machine.send_monitor_command(f"mouse_set {tablet_id}")
        pointer_events: Any = {"events": [
            {"type": "abs", "data": {"axis": "x", "value": round(x * 32767 / 1600)}},
            {"type": "abs", "data": {"axis": "y", "value": round(y * 32767 / 900)}},
        ]}
        machine.qmp_client.send("input-send-event", pointer_events)
        machine.wait_until_succeeds(as_user(
            f"hyprctl -j cursorpos | jq -e '(.x - {x} | fabs) <= 2 and (.y - {y} | fabs) <= 2'"
        ), timeout=10)
        button_events: Any = {"events": [{"type": "btn", "data": {"button": "left", "down": True}}]}
        machine.qmp_client.send("input-send-event", button_events)
        machine.sleep(1)
        button_events["events"][0]["data"]["down"] = False
        machine.qmp_client.send("input-send-event", button_events)

    def pixel_offset(width: int, x: float, y: float) -> int:
        # Hyprland reports logical coordinates; captures use physical pixels.
        scale = json.loads(machine.succeed(as_user("hyprctl -j monitors")))[0]["scale"]
        return (round(y * scale) * width + round(x * scale)) * 3

    def color_samples(image: tuple[int, int, bytes] | None = None) -> list[tuple[int, ...]]:
        clients = json.loads(machine.succeed(as_user("hyprctl -j clients")))
        client = next(client for client in clients if client["title"] == "Muestras de color")
        width, _, pixels = framebuffer() if image is None else image
        samples = []
        for index in range(4):
            x = client["at"][0] + client["size"][0] * (index + 0.5) / 4
            y = client["at"][1] + client["size"][1] / 2
            offset = pixel_offset(width, x, y)
            samples.append(tuple(pixels[offset:offset + 3]))
        return samples

    def assert_color_effect(baseline: list[tuple[int, ...]], separation: float, saturation: float, gains: tuple[float, float, float] = (1.0, 1.0, 1.0)) -> None:
        errors = machine.succeed(as_user("hyprctl configerrors")).strip()
        assert errors in ("", "ok"), errors
        actual = color_samples()
        for original, transformed in zip(baseline, actual):
            average = sum(original) / 3
            separated = [average + separation * (channel - average) for channel in original]
            luminance = sum(channel * weight for channel, weight in zip(separated, (0.2126, 0.7152, 0.0722)))
            expected = [round(max(0, min(255, luminance + saturation * (channel - luminance))) * gain) for channel, gain in zip(separated, gains)]
            assert all(abs(channel - target) <= 4 for channel, target in zip(transformed, expected)), {
                "original": original, "actual": transformed, "expected": expected,
            }
        if gains == (1.0, 1.0, 1.0):
            assert actual[-1] == baseline[-1], {"gray": actual[-1], "neutral_gray": baseline[-1]}

    terminal_command = "hyprctl -i 0 -j clients | jq -e 'any(.[]; .class == \"com.mitchellh.ghostty\")'"
    machine.start()
    machine.wait_for_unit("home-manager-razor.service")
    fish_shell = machine.succeed("getent passwd razor").strip().split(":")[-1]
    assert fish_shell.endswith("/bin/fish"), fish_shell
    machine.succeed("su - razor -c " + shlex.quote(
        'status is-login; and test "$SHELL" = ' + shlex.quote(fish_shell)
        + '; and test "$NIXOS_OZONE_WL" = 1; and test "$XCURSOR_THEME" = Bibata-Modern-Classic'
    ))
    assert settings()["general"]["language"] == "es", settings()
    assert settings()["customPreference"] == "keep", settings()
    assert settings()["notifications"]["dnd"] is False, settings()
    assert settings()["idle"]["actions"]["lock"]["timeout"] == 600, settings()
    assert settings()["wallpaperDir"] == "/home/razor/Imágenes/Fondos", settings()
    # A preset changed on the machine must survive reactivation while Nix keeps its value.
    machine.succeed("su razor -s /bin/sh -c " + shlex.quote(
        "jq '.general.weatherInterval = 60' ~/.config/serpantinum/settings.json > ~/.config/serpantinum/settings.json.new"
        " && mv ~/.config/serpantinum/settings.json.new ~/.config/serpantinum/settings.json"
    ))
    machine.succeed("systemctl restart home-manager-razor.service")
    assert settings()["general"]["weatherInterval"] == 60, settings()
    assert settings()["general"]["language"] == "es", settings()
    machine.succeed("test -f /home/razor/.local/state/serpantinum/first_launch.done")
    machine.wait_for_unit("display-manager.service")
    try:
        # Check the astronaut theme, Spanish UI and password login through SDDM.
        machine.wait_until_succeeds(
            "pgrep -u sddm -f 'sddm-greeter.*--theme .*/sddm-astronaut-theme'", timeout=120
        )
        machine.wait_for_text("teclado virtual", timeout=120)
        machine.succeed("cmp ${loginBackground} ${../assets/login.jpg}")
        # Seeded backgrounds must remain replaceable without rebuilding NixOS.
        for filename in ["login.jpg", "wallpaper.jpg"]:
            machine.succeed(f"test -f /home/razor/Imágenes/Fondos/{filename}")
            machine.fail(f"test -L /home/razor/Imágenes/Fondos/{filename}")
            machine.succeed(as_user(f"test -w ~/Imágenes/Fondos/{filename}"))
        machine.fail("runuser -u sddm -- test -r /home/razor")
        machine.sleep(2)
        initial_login_samples = login_background_samples()
        machine.screenshot("sddm-login-initial")
        machine.succeed(as_user("install -m 0600 ${../assets/wallpaper.jpg} ~/Imágenes/Fondos/login.jpg"))
        machine.succeed("systemctl restart display-manager.service")
        machine.wait_for_text("teclado virtual", timeout=120)
        machine.succeed("runuser -u sddm -- test -r /home/razor/Imágenes/Fondos/login.jpg")
        # KWin, unlike Weston, reads the greeter keyboard layout from kxkbrc.
        machine.succeed("runuser -u sddm -- grep -qx LayoutList=latam /var/lib/sddm/.config/kxkbrc")
        machine.succeed("cmp /home/razor/Imágenes/Fondos/login.jpg ${../assets/wallpaper.jpg}")
        machine.sleep(2)
        assert login_background_samples() != initial_login_samples
        machine.screenshot("sddm-login")
        machine.send_chars("serpantinumtest", delay=0.15)
        machine.send_key("ret", delay=0.15)
        machine.wait_until_succeeds(as_user("systemctl --user is-active serpantinum.service"), timeout=120)
        machine.wait_until_succeeds(as_user("serpantinum ipc --any-display show | grep -q 'target main'"), timeout=120)
        # Use the service manager environment that starts Serpantinum.
        icon_output = machine.succeed(as_user(
            "systemd-run --user --wait --pipe --collect --quiet "
            "timeout 20 ${pkgs.quickshell}/bin/quickshell -p /etc/serpantinum-icon-check.qml 2>&1"
        ))
        assert "Could not load icon" not in icon_output, icon_output
        errors = machine.succeed(as_user("hyprctl -i 0 configerrors")).strip()
        assert errors in ("", "ok"), errors
        machine.wait_until_succeeds(as_user("systemctl --user is-active clipboard-text.service clipboard-image.service"), timeout=30)
        machine.wait_until_succeeds("test -s /home/razor/.local/state/serpantinum/qs_matugen_colors.json", timeout=30)
        machine.wait_until_succeeds("test -s /home/razor/.local/state/serpantinum/ghostty.conf", timeout=30)
        machine.wait_until_succeeds("test -s /home/razor/.local/state/serpantinum/hyprland-colors.lua", timeout=30)
        machine.succeed(as_user("ghostty +validate-config"))
        assert_matugen_border()
        # Recreate a missing border theme even when other generated themes exist.
        machine.succeed(as_user("rm ~/.local/state/serpantinum/hyprland-colors.lua"))
        machine.succeed(as_user("bash /etc/serpantinum-prepare-wallpaper"))
        assert_matugen_border()
        # Palette changes must update borders and survive a compositor reload.
        previous_border = active_border()
        machine.succeed(as_user("${pkgs.matugen}/bin/matugen color hex '#3366ff'"))
        assert_matugen_border()
        assert active_border() != previous_border
        machine.succeed(as_user("hyprctl -i 0 reload"))
        assert_matugen_border()
        machine.succeed(as_user(
            "${pkgs.matugen}/bin/matugen image \"$HOME/Imágenes/Fondos/wallpaper.jpg\" --source-color-index 0"
        ))
        assert_matugen_border()
        # A changed template must regenerate colors from the selected wallpaper.
        machine.succeed(as_user("cp ${../assets/login.jpg} /tmp/serpantinum-theme-wallpaper.jpg"))
        machine.succeed(as_user(
            "for monitor in $(hyprctl -j monitors | jq -r '.[].name'); do "
            "printf '%s' /tmp/serpantinum-theme-wallpaper.jpg > ~/.cache/serpantinum/wallpaper/current_$monitor; done; "
            "printf '%s' outdated > ~/.local/state/serpantinum/hyprland-template.lua; "
            "bash /etc/serpantinum-prepare-wallpaper"
        ))
        assert_matugen_border()
        machine.succeed(as_user(
            "cmp ~/.config/matugen/hyprland.lua ~/.local/state/serpantinum/hyprland-template.lua"
        ))
        prepared_border = active_border()
        machine.succeed(as_user(
            "${pkgs.matugen}/bin/matugen image /tmp/serpantinum-theme-wallpaper.jpg --source-color-index 0"
        ))
        assert active_border() == prepared_border
        errors = machine.succeed(as_user("hyprctl -i 0 configerrors")).strip()
        assert errors in ("", "ok"), errors
        machine.sleep(2)
        assert "welcome-guide" not in machine.succeed(as_user("hyprctl -i 0 -j layers"))
        machine.screenshot("serpantinum-desktop")

        # Custom wallpaper filenames must survive another activation.
        output_name = json.loads(machine.succeed(as_user("hyprctl -j monitors")))[0]["name"]
        machine.succeed(as_user("cp ${../assets/login.jpg} ~/Imágenes/Fondos/wallpaper.jpg"))
        machine.succeed(as_user("cp ~/Imágenes/Fondos/login.jpg ~/Imágenes/Fondos/'paisaje personal.jpg'"))
        machine.succeed(as_user("serpantinum msg close"))
        widget_state = "/run/user/1000/serpantinum/current_widget"
        machine.wait_until_succeeds("jq -e '.widget == \"hidden\"' " + widget_state, timeout=30)
        machine.send_key("meta_l-w")
        machine.wait_until_succeeds("jq -e '.widget == \"wallpaper\"' " + widget_state, timeout=30)
        machine.sleep(1)
        machine.screenshot("serpantinum-wallpaper-selector")
        machine.succeed(as_user("serpantinum msg close"))
        machine.wait_until_succeeds("jq -e '.widget == \"hidden\"' " + widget_state, timeout=30)
        machine.succeed(as_user(
            "serpantinum ipc --any-display call main handleCommand open wallpaper 'paisaje personal.jpg'"
        ))
        machine.wait_until_succeeds("jq -e '.widget == \"wallpaper\"' " + widget_state, timeout=30)
        machine.sleep(2)
        machine.send_key("ret")
        selected_name = f"/home/razor/.cache/serpantinum/wallpaper/current_{output_name}_name"
        machine.wait_until_succeeds("grep -Fx 'paisaje personal.jpg' " + shlex.quote(selected_name), timeout=30)
        machine.succeed(as_user("serpantinum msg close"))

        # Both effects must increase independently and preserve neutral gray.
        machine.wait_until_succeeds(as_user("systemctl --user is-active display-colors.service"), timeout=30)
        color_command = "display-colors set --output " + shlex.quote(output_name)
        machine.succeed(as_user(
            "systemd-run --user --collect --quiet --unit=display-colors-samples "
            "${pkgs.quickshell}/bin/quickshell -p /etc/display-colors-samples.qml"
        ))
        machine.wait_until_succeeds(as_user(
            "hyprctl -j clients | jq -e 'any(.[]; .title == \"Muestras de color\")'"
        ), timeout=30)
        machine.sleep(1)
        baseline = color_samples()
        assert baseline[0] != baseline[-1], baseline
        machine.screenshot("display-colors-neutral")
        machine.succeed(as_user(color_command + " --enabled true --separation 150 --saturation 100"))
        machine.sleep(1)
        assert_color_effect(baseline, 1.5, 1.0)
        machine.screenshot("display-colors-separation")
        machine.succeed(as_user(color_command + " --separation 100 --saturation 150"))
        machine.sleep(1)
        assert_color_effect(baseline, 1.0, 1.5)
        machine.screenshot("display-colors-saturation")
        # Panel correction follows clipping and remains active with enhancement disabled.
        machine.succeed(as_user(color_command + " --separation 200 --saturation 200 --red 96 --green 99 --blue 98 --white-balance-enabled true"))
        machine.sleep(1)
        assert_color_effect(baseline, 2.0, 2.0, (0.96, 0.99, 0.98))
        # Both saved captures and the frozen selector must contain original pixels,
        # including after a previous capture has populated Hyprland's mirror buffer.
        active_shader = machine.succeed(as_user("hyprctl -j getoption decoration.screen_shader"))
        saved_colors = color_settings()
        for attempt in range(2):
            machine.succeed(as_user(
                "serpantinum screenshot --full "
                "> /tmp/serpantinum-color-capture.log 2>&1"
            ), timeout=30)
            capture_path = machine.succeed(
                "ls -t /home/razor/Imágenes/Capturas\\ de\\ pantalla/Screenshot_*.png | head -n 1"
            ).strip()
            assert color_samples(captured_framebuffer(capture_path)) == baseline
            assert machine.succeed(as_user("hyprctl -j getoption decoration.screen_shader")) == active_shader
            assert color_settings() == saved_colors
            assert_color_effect(baseline, 2.0, 2.0, (0.96, 0.99, 0.98))
        machine.succeed(as_user("serpantinum screenshot"))
        machine.sleep(1)
        freeze_path = machine.succeed(
            "ls -t /run/user/1000/serpantinum/screenshot/freeze_*.png | head -n 1"
        ).strip()
        assert color_samples(captured_framebuffer(freeze_path)) == baseline
        machine.send_key("esc")
        machine.sleep(1)
        assert_color_effect(baseline, 2.0, 2.0, (0.96, 0.99, 0.98))
        machine.succeed(as_user(color_command + " --enabled false"))
        machine.succeed(as_user("hyprctl reload"))
        machine.succeed(as_user("systemctl --user restart display-colors.service"))
        machine.sleep(1)
        assert_color_effect(baseline, 1.0, 1.0, (0.96, 0.99, 0.98))
        machine.screenshot("display-colors-white-balance")
        assert color_settings()["outputs"][output_name]["red"] == 96
        machine.succeed(as_user(color_command + " --white-balance-enabled false"))
        machine.sleep(1)
        assert_color_effect(baseline, 1.0, 1.0)
        assert json.loads(machine.succeed(as_user("hyprctl -j getoption decoration.screen_shader")))["str"] in ("", "[[EMPTY]]")
        assert color_settings()["outputs"][output_name]["red"] == 96
        machine.succeed(as_user(color_command + " --enabled true --red 100 --green 100 --blue 100"))
        machine.succeed(as_user(color_command + " --separation 120 --saturation 130"))
        machine.succeed(as_user("hyprctl reload"))
        machine.sleep(1)
        assert_color_effect(baseline, 1.2, 1.3)
        machine.succeed(as_user("hyprctl -r eval 'hl.config({decoration = {screen_shader = \"\"}})'"))
        machine.sleep(1)
        assert_color_effect(baseline, 1.0, 1.0)
        machine.succeed(as_user("systemctl --user restart display-colors.service"))
        machine.sleep(1)
        assert_color_effect(baseline, 1.2, 1.3)
        assert color_settings()["outputs"][output_name]["separation"] == 120
        assert color_settings()["outputs"][output_name]["saturation"] == 130
        machine.succeed(as_user("systemctl --user stop display-colors-samples.service"))
        # The shortcut must open a real control window without QML errors.
        machine.send_key("meta_l-shift-c")
        machine.wait_until_succeeds(as_user(
            "hyprctl -j clients | jq -e 'any(.[]; .title == \"Personal Tweaks\")'"
        ), timeout=30)
        machine.sleep(1)
        clients = json.loads(machine.succeed(as_user("hyprctl -j clients")))
        color_window = next(client for client in clients if client["title"] == "Personal Tweaks")
        assert color_window["floating"] is True, color_window
        machine.screenshot("display-colors-controls")
        machine.send_key("right")
        machine.wait_until_succeeds(
            "jq -e '.outputs[\"" + output_name + "\"].separation == 121' "
            "/home/razor/.config/display-colors/settings.json", timeout=10
        )
        assert color_settings()["outputs"][output_name]["saturation"] == 130
        machine.send_key("left")
        machine.wait_until_succeeds(
            "jq -e '.outputs[\"" + output_name + "\"].separation == 120' "
            "/home/razor/.config/display-colors/settings.json", timeout=10
        )
        # External controller changes must refresh the open window.
        machine.succeed(as_user(color_command + " --separation 140 --saturation 130"))
        machine.sleep(1)
        machine.send_key("right")
        machine.wait_until_succeeds(
            "jq -e '.outputs[\"" + output_name + "\"].separation == 141' "
            "/home/razor/.config/display-colors/settings.json", timeout=10
        )
        machine.succeed(as_user(color_command + " --separation 120 --saturation 130"))

        # The standalone palette must load and follow Matugen's file changes.
        palette_path = "/home/razor/.local/state/serpantinum/qs_matugen_colors.json"
        palette_backup = machine.succeed("cat " + palette_path)
        def window_background() -> str:
            width, _, pixels = framebuffer()
            x = color_window["at"][0] + color_window["size"][0] - 12
            y = color_window["at"][1] + 80
            offset = pixel_offset(width, x, y)
            return "#" + pixels[offset:offset + 3].hex()

        def assert_background(expected: str) -> None:
            # Newly opened or restyled windows may need a few frames to settle.
            for _ in range(10):
                actual = window_background()
                if actual == expected.lower():
                    return
                machine.sleep(1)
            raise AssertionError((actual, expected))

        # Disable the screen filter before comparing exact rendered palette colors.
        machine.succeed(as_user(color_command + " --enabled false"))
        machine.sleep(1)
        expected_background = json.loads(palette_backup)["base"]
        machine.wait_until_succeeds("test -s " + palette_path, timeout=10)
        machine.wait_until_succeeds(as_user(
            "hyprctl -j clients | jq -e 'any(.[]; .title == \"Personal Tweaks\")'"
        ), timeout=10)
        assert_background(expected_background)
        machine.succeed(as_user(
            "jq '.base = \"#203040\"' " + palette_path + " > /tmp/tweaks-palette.json && "
            "cat /tmp/tweaks-palette.json > " + palette_path
        ))
        machine.sleep(1)
        assert_background("#203040")
        machine.screenshot("personal-tweaks-matugen")
        machine.succeed(as_user(
            "printf '%s' " + shlex.quote(palette_backup) + " > " + palette_path
        ))
        machine.sleep(1)
        assert_background(expected_background)
        machine.succeed(as_user(color_command + " --enabled true"))
        machine.send_key("meta_l-q")
        machine.wait_until_fails(as_user(
            "hyprctl -j clients | jq -e 'any(.[]; .title == \"Personal Tweaks\")'"
        ), timeout=10)
        # The display guide remains upstream; color controls belong to Personal Tweaks.
        machine.succeed(as_user("serpantinum msg open guide display"))
        machine.sleep(2)
        machine.screenshot("serpantinum-display-settings")
        machine.succeed(as_user("serpantinum msg close"))
        errors = machine.succeed(as_user("hyprctl configerrors")).strip()
        assert errors in ("", "ok"), errors

        # Repeated activation must restore declared settings and preserve other preferences.
        machine.succeed(as_user("systemctl --user stop serpantinum.service"))
        # A failed monitor query must stop wallpaper preparation.
        machine.fail(as_user(
            "HYPRLAND_INSTANCE_SIGNATURE=serpantinum-invalid bash /etc/serpantinum-prepare-wallpaper"
        ))
        # Reject multiple JSON documents without overwriting the original file.
        machine.succeed(as_user(
            "cp ~/.config/serpantinum/settings.json /tmp/serpantinum-settings-backup.json && "
            "printf '%s\\n' '{}' '{}' > ~/.config/serpantinum/settings.json"
        ))
        machine.fail("systemctl restart home-manager-razor.service")
        assert machine.succeed("cat /home/razor/.config/serpantinum/settings.json") == "{}\n{}\n"
        machine.succeed(as_user(
            "cp /tmp/serpantinum-settings-backup.json ~/.config/serpantinum/settings.json && "
            "rm ~/.local/state/serpantinum/ghostty.conf"
        ))
        machine.succeed(as_user(
            "jq '.display.monitors[\"eDP-1\"].enabled = true | .display.monitors[\"eDP-1\"].auto = true | .customPreference = \"persist\"' "
            "~/.config/serpantinum/settings.json > /tmp/serpantinum-settings.json && "
            "mv /tmp/serpantinum-settings.json ~/.config/serpantinum/settings.json"
        ))
        machine.succeed("systemctl restart home-manager-razor.service")
        machine.succeed("cmp /home/razor/Imágenes/Fondos/login.jpg ${../assets/wallpaper.jpg}")
        machine.succeed("cmp /home/razor/Imágenes/Fondos/wallpaper.jpg ${../assets/login.jpg}")
        # System activation must also preserve SDDM access to the background.
        machine.succeed("/run/current-system/activate")
        machine.succeed("runuser -u sddm -- test -r /home/razor/Imágenes/Fondos/login.jpg")
        machine.fail("runuser -u sddm -- test -r /home/razor")
        # Presets edited on the machine persist because their Nix values did not change.
        assert settings()["general"]["language"] == "es", settings()
        assert settings()["display"]["monitors"]["eDP-1"]["enabled"] is True, settings()
        assert settings()["display"]["monitors"]["eDP-1"]["auto"] is True, settings()
        assert settings()["customPreference"] == "persist", settings()
        assert color_settings()["outputs"][output_name]["separation"] == 120
        assert color_settings()["outputs"][output_name]["saturation"] == 130
        machine.succeed(as_user("display-colors reset --output " + shlex.quote(output_name)))
        assert json.loads(machine.succeed(as_user("hyprctl -j getoption decoration.screen_shader")))["str"] in ("", "[[EMPTY]]")
        machine.succeed(as_user("systemctl --user start serpantinum.service"))
        machine.wait_until_succeeds(as_user("serpantinum ipc --any-display show | grep -q 'target main'"), timeout=60)
        assert machine.succeed("cat " + shlex.quote(selected_name)).strip() == "paisaje personal.jpg"
        # Recreate the Ghostty theme even when Serpantinum colors already exist.
        machine.succeed("test -s /home/razor/.local/state/serpantinum/ghostty.conf")
        machine.succeed(as_user("ghostty +validate-config"))

        machine.succeed(as_user("printf '%s' 'Prueba de portapapeles' | wl-copy"))
        machine.wait_until_succeeds(as_user("cliphist list | grep -q 'Prueba de portapapeles'"), timeout=30)
        machine.succeed(as_user("notify-send -a personal-distro 'Prueba de notificación' 'Escritorio Serpantinum'"))
        machine.wait_until_succeeds(as_user("busctl --user status org.freedesktop.Notifications"), timeout=30)
        machine.succeed(as_user("serpantinum msg toggle notifications"))
        machine.sleep(1)
        machine.screenshot("serpantinum-notifications")
        machine.succeed(as_user("serpantinum msg close"))

        machine.send_key("meta_l-ret")
        machine.wait_until_succeeds(as_user(terminal_command), timeout=30)
        machine.wait_until_succeeds("pgrep -u razor -x fish", timeout=30)
        # Check numeric workspace shortcuts and window movement.
        for workspace in range(1, 11):
            machine.send_key(f"meta_l-{workspace % 10}")
            machine.wait_until_succeeds(as_user(
                f"hyprctl -i 0 -j activeworkspace | jq -e '.id == {workspace}'"
            ), timeout=10)
        machine.send_key("meta_l-1")
        machine.wait_until_succeeds(as_user("hyprctl -i 0 -j activeworkspace | jq -e '.id == 1'"), timeout=10)
        for workspace in (2, 1):
            machine.send_key(f"meta_l-shift-{workspace}")
            machine.wait_until_succeeds(as_user(
                "hyprctl -i 0 -j clients | jq -e "
                f"'any(.[]; .class == \"com.mitchellh.ghostty\" and .workspace.id == {workspace})'"
            ), timeout=10)
            machine.wait_until_succeeds(as_user(
                f"hyprctl -i 0 -j activeworkspace | jq -e '.id == {workspace}'"
            ), timeout=10)
        # A real screenshot must be saved and copied with all dependencies available.
        # The interactive notification must not keep the test output pipe open.
        machine.succeed(as_user(
            "serpantinum screenshot --full "
            "> /tmp/serpantinum-screenshot.log 2>&1"
        ), timeout=30)
        machine.succeed(as_user(
            "for screenshot in \"$HOME/Imágenes/Capturas de pantalla\"/Screenshot_*.png; do "
            "test -s \"$screenshot\" || exit 1; done"
        ))
        machine.succeed(as_user("test -d \"$HOME/Vídeos/Grabaciones de pantalla\""))
        for directory in ("Pictures", "Videos", "Projects", "Public", "Templates"):
            machine.fail(f"test -e /home/razor/{directory}")
        machine.succeed(as_user("wl-paste --type image/png > /tmp/serpantinum-screenshot.png"))
        machine.succeed("test -s /tmp/serpantinum-screenshot.png")
        machine.send_key("meta_l-q")
        machine.wait_until_fails(as_user(terminal_command), timeout=30)
        machine.succeed(as_user("serpantinum lock"))
        machine.sleep(2)
        machine.screenshot("serpantinum-locked")
        machine.send_chars("incorrect", delay=0.15)
        machine.send_key("ret", delay=0.15)
        machine.wait_until_succeeds(as_user(
            "journalctl --user -b -u serpantinum.service --no-pager | grep -q 'Failed to authenticate'"
        ), timeout=30)
        machine.wait_until_succeeds(as_user(
            "test $(journalctl --user -b -u serpantinum.service --no-pager | grep -c 'Relaying pam message') -ge 2"
        ), timeout=30)
        machine.send_key("meta_l-ret")
        machine.fail(as_user(terminal_command))
        machine.screenshot("serpantinum-rejected-password")
        machine.send_key("ctrl-a")
        machine.send_chars("serpantinumtest", delay=0.15)
        machine.send_key("ret", delay=0.15)
        machine.sleep(4)
        machine.send_key("meta_l-ret")
        machine.wait_until_succeeds(as_user(terminal_command), timeout=30)
        assert settings()["general"]["language"] == "es", settings()
        assert settings()["bar"]["workspaceCount"] == 10, settings()
        assert settings()["customPreference"] == "persist", settings()
        machine.screenshot("serpantinum-unlocked")
    except Exception:
        machine.screenshot("serpantinum-failure")
        raise
    finally:
        print(machine.succeed("journalctl -b -u display-manager.service --no-pager"))
        print(machine.succeed("journalctl -b -u home-manager-razor.service --no-pager"))
        print(machine.succeed(as_user("journalctl --user -u display-colors.service --no-pager")))
        print(machine.succeed("journalctl -b _UID=1000 --no-pager -n 120"))
  '';
}
