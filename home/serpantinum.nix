{
  config,
  lib,
  pkgs,
  serpantinumPackage,
  ...
}:
let
  wallpaperDir = "${config.xdg.userDirs.pictures}/Fondos";
  defaultWallpaper = "${wallpaperDir}/wallpaper.jpg";
  managedSettings = (pkgs.formats.json { }).generate "serpantinum-managed-settings.json" (
    lib.filterAttrsRecursive (_: value: value != null) config.programs.serpantinum.settings
  );
  applySettings = pkgs.writeShellScript "serpantinum-apply-settings" ''
    set -euo pipefail
    settings_path="${config.xdg.configHome}/serpantinum/settings.json"
    defaults="${serpantinumPackage}/share/serpantinum/config/serpantinum/settings.json"
    ${pkgs.jq}/bin/jq -se 'length == 1 and (.[0] | type == "object")' "$settings_path" >/dev/null
    if ! ${pkgs.jq}/bin/jq -e --slurpfile defaults "$defaults" --slurpfile managed ${managedSettings} \
      '. == ($defaults[0] * . * $managed[0])' "$settings_path" >/dev/null; then
      settings_tmp=$(${pkgs.coreutils}/bin/mktemp "$settings_path.XXXXXX")
      trap '${pkgs.coreutils}/bin/rm -f "$settings_tmp"' EXIT
      ${pkgs.jq}/bin/jq --slurpfile defaults "$defaults" --slurpfile managed ${managedSettings} \
        '$defaults[0] * . * $managed[0]' "$settings_path" > "$settings_tmp"
      ${pkgs.coreutils}/bin/chmod --reference="$settings_path" "$settings_tmp"
      ${pkgs.coreutils}/bin/mv "$settings_tmp" "$settings_path"
    fi
  '';
  prepareWallpaper = pkgs.writeShellScript "serpantinum-prepare-wallpaper" ''
    set -euo pipefail
    wallpaper_cache="${config.xdg.cacheHome}/serpantinum/wallpaper"
    state_dir="${config.xdg.stateHome}/serpantinum"
    theme_template="${config.xdg.configHome}/matugen/hyprland.lua"
    ${pkgs.coreutils}/bin/mkdir -p "$wallpaper_cache" "$state_dir"
    monitors=$(${pkgs.hyprland}/bin/hyprctl -j monitors | ${pkgs.jq}/bin/jq -er '.[].name')
    theme_wallpaper=""
    while IFS= read -r monitor; do
      if [ ! -f "$wallpaper_cache/current_$monitor" ] ||
        [ ! -f "$(${pkgs.coreutils}/bin/cat "$wallpaper_cache/current_$monitor")" ]; then
        printf '%s' ${lib.escapeShellArg defaultWallpaper} > "$wallpaper_cache/current_$monitor"
        printf '%s' wallpaper.jpg > "$wallpaper_cache/current_''${monitor}_name"
      fi
      if [ -z "$theme_wallpaper" ]; then
        theme_wallpaper=$(${pkgs.coreutils}/bin/cat "$wallpaper_cache/current_$monitor")
      fi
    done <<< "$monitors"
    if [ ! -s "$state_dir/qs_matugen_colors.json" ] ||
      [ ! -s "$state_dir/ghostty.conf" ] ||
      [ ! -s "$state_dir/hyprland-colors.lua" ] ||
      ! ${pkgs.coreutils}/bin/cmp -s "$theme_template" "$state_dir/hyprland-template.lua"; then
      # Refresh changed templates using the selected wallpaper, including on upgrades.
      ${pkgs.matugen}/bin/matugen image "$theme_wallpaper" --source-color-index 0
      ${pkgs.coreutils}/bin/install -m 0600 "$theme_template" "$state_dir/hyprland-template.lua"
    fi
  '';
in
{
  programs.serpantinum = {
    enable = true;
    package = serpantinumPackage;
    systemd.environment.QT_QPA_PLATFORM = "wayland";
    settings = {
      inherit wallpaperDir;
      general = {
        language = "es";
        weatherUnit = "metric";
        weatherInterval = 30;
      };
      bar = {
        position = "top";
        style = "fill";
        width = 100;
        workspaceCount = 10;
        time.format = "HH:mm";
        modules = {
          left = [
            "left"
            "workspaces"
            "media"
          ];
          center = [ "timedate" ];
          right = [
            "tray"
            [
              "kb"
              "wifi"
              "bt"
              "vol"
              "bat"
            ]
          ];
        };
      };
      launcher.terminalCommand = "ghostty -e";
      theme = {
        fontFamily = "Rubik";
        borderRadius = 12;
        matugen = true;
      };
      notifications = {
        dnd = false;
        position = "top right";
        sound = true;
      };
      idle = {
        enabled = true;
        actions = {
          dim.enabled = false;
          dpms.enabled = false;
          lock = {
            enabled = true;
            timeout = 600;
          };
          suspend.enabled = false;
        };
      };
      display.monitors."eDP-1" = {
        # These flags control night light, not whether the monitor is turned on.
        enabled = false;
        auto = false;
        # Keep in sync with the Hyprland monitor scale, as the shell's display tab does.
        scale = 1.2;
      };
    };
  };

  home = {
    packages = with pkgs; [
      rubik
      # Upstream scripts require pactl, which is not included in the shell wrapper.
      pulseaudio
    ];
    file."${config.xdg.stateHome}/serpantinum/first_launch.done".text = "";

    activation = {
      # Wallpapers stay writable and are seeded only when missing.
      serpantinumWallpapers = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ] ''
        run ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg wallpaperDir}
        if [ ! -e ${lib.escapeShellArg defaultWallpaper} ]; then
          run ${pkgs.coreutils}/bin/install -m 0644 ${../assets/wallpaper.jpg} ${lib.escapeShellArg defaultWallpaper}
        fi
      '';

      serpantinumManagedSettings =
        lib.hm.dag.entryBetween
          [ "reloadSystemd" ]
          [
            "serpantinumSettings"
            "linkGeneration"
          ]
          ''
            run ${applySettings}
          '';
    };
  };

  services.easyeffects.enable = true;

  xdg.configFile = {
    "matugen/config.toml".source = (pkgs.formats.toml { }).generate "matugen-config.toml" {
      config = { };
      templates = {
        serpantinum = {
          input_path = "${serpantinumPackage}/share/serpantinum/assets/matugen/templates/serpantinum_matugen_colors.json.template";
          output_path = "${config.xdg.stateHome}/serpantinum/qs_matugen_colors.json";
        };
        ghostty = {
          input_path = "${config.xdg.configHome}/matugen/ghostty.conf";
          output_path = "${config.xdg.stateHome}/serpantinum/ghostty.conf";
        };
        hyprland = {
          input_path = "${config.xdg.configHome}/matugen/hyprland.lua";
          output_path = "${config.xdg.stateHome}/serpantinum/hyprland-colors.lua";
          post_hook = "${pkgs.hyprland}/bin/hyprctl reload";
        };
      };
    };
    "matugen/ghostty.conf".text = ''
      background = {{colors.surface.default.hex_stripped}}
      foreground = {{colors.on_surface.default.hex_stripped}}
      cursor-color = {{colors.primary.default.hex_stripped}}
      cursor-text = {{colors.on_primary.default.hex_stripped}}
      selection-background = {{colors.secondary_container.default.hex_stripped}}
      selection-foreground = {{colors.on_secondary_container.default.hex_stripped}}
    '';
    "matugen/hyprland.lua".text = ''
      hl.config({
        general = {
          col = {
            active_border = "rgba({{colors.primary.default.hex_stripped}}ff)",
            inactive_border = "rgba({{colors.outline_variant.default.hex_stripped}}ff)",
          },
        },
        decoration = {
          shadow = {
            color = "rgba({{colors.inverse_primary.default.hex_stripped}}10)",
          },
        },
      })
    '';

  };

  systemd.user.services = {
    serpantinum.Service.ExecStartPre = toString prepareWallpaper;
  }
  // lib.genAttrs [ "clipboard-text" "clipboard-image" ] (name: {
    Unit = {
      Description = "Clipboard history";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type ${lib.removePrefix "clipboard-" name} --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  });
}
