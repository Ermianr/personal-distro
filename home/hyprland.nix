{
  config,
  lib,
  pkgs,
  displayColorsPackage,
  ...
}:
let
  execBinding = keys: command: options: {
    _args = [
      keys
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
      options
    ];
  };
  shellBinding = keys: command: execBinding keys "serpantinum ${command}" { };
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    configType = "lua";
    systemd.enable = false;
    settings = {
      monitor = {
        output = "";
        mode = "preferred";
        position = "auto";
        # 1.2 suits the 15.6-inch 1080p panel and divides it into whole logical pixels.
        scale = 1.2;
      };
      config = {
        general = {
          border_size = 1;
          gaps_in = 4;
          gaps_out = 6;
          resize_on_border = true;
        };
        decoration = {
          rounding = 12;
          shadow = {
            enabled = true;
            range = 20;
            render_power = 3;
          };
          blur = {
            enabled = true;
            size = 8;
            passes = 2;
          };
        };
        animations.enabled = true;
        input = {
          kb_layout = "latam";
          touchpad.natural_scroll = true;
        };
        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
        };
        # Let XWayland apps render at native resolution instead of being upscaled blurry.
        xwayland.force_zero_scaling = true;
      };
      bind = [
        (execBinding "SUPER + Return" "ghostty" { })
        (execBinding "SUPER + E" "nautilus" { })
        (execBinding "SUPER + R" "systemctl --user restart serpantinum.service" { })
        (shellBinding "SUPER + D" "msg toggle launcher")
        (shellBinding "SUPER + Space" "msg toggle launcher")
        (shellBinding "SUPER + C" "msg toggle clipboard")
        (execBinding "SUPER + SHIFT + C" "${displayColorsPackage}/bin/personal-tweaks" { })
        (shellBinding "SUPER + N" "msg toggle notifications")
        (shellBinding "SUPER + B" "msg toggle system")
        (shellBinding "SUPER + W" "msg toggle wallpaper")
        (shellBinding "CTRL + SUPER + T" "msg toggle wallpaper")
        (shellBinding "SUPER + H" "msg toggle guide")
        (shellBinding "SUPER + M" "msg toggle music")
        (shellBinding "SUPER + S" "msg toggle calendar")
        (shellBinding "SUPER + L" "lock")
        (shellBinding "Print" "screenshot")
        (shellBinding "SUPER + SHIFT + S" "screenshot")
        (execBinding "XF86AudioRaiseVolume" "serpantinum volume raise" {
          locked = true;
          repeating = true;
        })
        (execBinding "XF86AudioLowerVolume" "serpantinum volume lower" {
          locked = true;
          repeating = true;
        })
        (execBinding "XF86AudioMute" "serpantinum volume mute-toggle" { locked = true; })
        (execBinding "XF86AudioMicMute" "serpantinum volume mic-toggle" { locked = true; })
        (execBinding "XF86MonBrightnessUp" "serpantinum brightness raise" {
          locked = true;
          repeating = true;
        })
        (execBinding "XF86MonBrightnessDown" "serpantinum brightness lower" {
          locked = true;
          repeating = true;
        })
        (execBinding "XF86AudioPlay" "${pkgs.playerctl}/bin/playerctl play-pause" { locked = true; })
        (execBinding "XF86AudioNext" "${pkgs.playerctl}/bin/playerctl next" { locked = true; })
        (execBinding "XF86AudioPrev" "${pkgs.playerctl}/bin/playerctl previous" { locked = true; })
      ];
    };
    extraConfig = ''
      -- Caelestia motion curves: https://github.com/caelestia-dots/caelestia/blob/main/hypr/hyprland/animations.lua
      hl.curve("emphasizedAccel", { type = "bezier", points = { {0.3, 0}, {0.8, 0.15} } })
      hl.curve("emphasizedDecel", { type = "bezier", points = { {0.05, 0.7}, {0.1, 1} } })
      hl.curve("standard", { type = "bezier", points = { {0.2, 0}, {0, 1} } })
      hl.animation({ leaf = "layersIn", enabled = true, speed = 5, bezier = "emphasizedDecel", style = "slide" })
      hl.animation({ leaf = "layersOut", enabled = true, speed = 4, bezier = "emphasizedAccel", style = "slide" })
      hl.animation({ leaf = "fadeLayers", enabled = true, speed = 5, bezier = "standard" })
      hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "emphasizedDecel", style = "slide" })
      hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "emphasizedAccel", style = "slide" })
      hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, bezier = "standard" })
      hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "standard", style = "slide" })
      hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "emphasizedDecel", style = "slidefadevert 15%" })
      hl.animation({ leaf = "fade", enabled = true, speed = 6, bezier = "standard" })
      hl.animation({ leaf = "fadeDim", enabled = true, speed = 6, bezier = "standard" })
      hl.animation({ leaf = "border", enabled = true, speed = 6, bezier = "standard" })
      -- The overlay captures the live screen 200 ms after hiding; a fade-out would be captured.
      hl.layer_rule({ match = { namespace = "^qs-screenshot-overlay$" }, no_anim = true })

      local colors_path = ${builtins.toJSON "${config.xdg.stateHome}/serpantinum/hyprland-colors.lua"}
      local colors_file = io.open(colors_path, "r")
      if colors_file then
        colors_file:close()
        dofile(colors_path)
      end

      hl.bind("SUPER + Q", hl.dsp.window.close())
      hl.bind("SUPER + F", hl.dsp.window.fullscreen({ action = "toggle" }))
      hl.bind("SUPER + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
      hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
      hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
      for key, direction in pairs({ Left = "left", Right = "right", Up = "up", Down = "down" }) do
        hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = direction }))
      end
      for workspace = 1, 10 do
        local key = tostring(workspace % 10)
        hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = workspace }))
        hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
      end
    '';
  };
}
