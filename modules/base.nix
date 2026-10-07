{
  config,
  lib,
  pkgs,
  loginBackground,
  sddmAstronautTheme,
  ...
}:
let
  wallpaperDir = builtins.dirOf loginBackground;
  picturesDir = builtins.dirOf wallpaperDir;
  prepareLoginBackground = pkgs.writeShellScript "prepare-login-background" ''
    set -euo pipefail
    login_background=${lib.escapeShellArg loginBackground}
    # These paths belong to razor, and setfacl as root would grant SDDM access to a
    # symlink's target anywhere on the system. Skip them without blocking the greeter;
    # -P also rejects a final component swapped for a symlink after the check.
    for path in ${lib.escapeShellArg picturesDir} ${lib.escapeShellArg wallpaperDir} "$login_background"; do
      if [ -L "$path" ]; then
        printf 'warning: %s is a symbolic link; SDDM will not be given access to it.\n' "$path" >&2
        exit 0
      fi
    done
    for directory in ${lib.escapeShellArg picturesDir} ${lib.escapeShellArg wallpaperDir}; do
      if [ ! -d "$directory" ]; then
        ${pkgs.coreutils}/bin/install -d -m 0755 -o razor -g users -- "$directory"
      fi
    done
    # Seed the background once; later activations preserve user replacements.
    if [ ! -e "$login_background" ]; then
      ${pkgs.coreutils}/bin/install -m 0644 -o razor -g users -- ${../assets/login.jpg} "$login_background"
    fi
    # SDDM needs directory traversal and image access, never a home directory listing.
    ${pkgs.acl}/bin/setfacl -P -m g:sddm:--x -- \
      ${lib.escapeShellArg config.users.users.razor.home} \
      ${lib.escapeShellArg picturesDir} ${lib.escapeShellArg wallpaperDir} ||
      printf 'warning: could not give SDDM access to the background directories.\n' >&2
    if ! ${pkgs.util-linux}/bin/runuser -u sddm -- ${pkgs.coreutils}/bin/test -r "$login_background"; then
      ${pkgs.acl}/bin/setfacl -P -m g:sddm:r-- -- "$login_background" ||
        printf 'warning: could not give SDDM access to %s.\n' "$login_background" >&2
    fi
  '';
in
{
  boot.kernelPackages = pkgs.linuxPackages_zen;

  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
    gc = {
      automatic = true;
      dates = "daily";
    };
  };

  systemd = {
    services = {
      # Trim only the system profile; keep user and Home Manager rollback roots.
      nix-gc.preStart = ''
        ${config.nix.package}/bin/nix-env \
          --profile /nix/var/nix/profiles/system \
          --delete-generations +3
      '';
      display-manager = {
        preStart = lib.mkBefore ''
          ${prepareLoginBackground}
        '';
        unitConfig.RequiresMountsFor = [ config.users.users.razor.home ];
      };
      # The NixOS module installs Flatpak without remotes; fast-moving apps come from Flathub.
      flatpak-repo = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          ${config.services.flatpak.package}/bin/flatpak remote-add --system --if-not-exists \
            flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        '';
      };
    };
    # The SDDM greeter has no use for audio, and its WirePlumber aborts when the greeter exits.
    user =
      let
        skipSystemUsers.unitConfig.ConditionUser = "!@system";
      in
      {
        sockets = lib.genAttrs [ "pipewire" "pipewire-pulse" ] (_: skipSystemUsers);
        services = lib.genAttrs [ "pipewire" "pipewire-pulse" "wireplumber" ] (_: skipSystemUsers);
      };
    # NixOS passes the XKB layout only to Weston; KWin's greeter reads it from kxkbrc.
    tmpfiles.settings.sddm-keyboard = {
      "${config.users.users.sddm.home}/.config".d = {
        user = "sddm";
        group = "sddm";
        mode = "0755";
      };
      "${config.users.users.sddm.home}/.config/kxkbrc"."L+".argument = toString (
        pkgs.writeText "sddm-kxkbrc" ''
          [Layout]
          LayoutList=${config.services.xserver.xkb.layout}
          Use=true
        ''
      );
    };
  };

  networking.nameservers = [
    "1.1.1.1"
    "1.0.0.1"
  ];

  services = {
    resolved = {
      enable = true;
      settings.Resolve = {
        Domains = [ "~." ];
        Cache = true;
        # Legacy LAN name resolution is unused here and answers spoofable queries.
        LLMNR = "false";
      };
    };
    # WirePlumber keeps a remembered output even when headphones appear, and once that output
    # vanishes it may fall back to EasyEffects' own sink, which leaves EasyEffects without an output.
    # Newly connected hardware sinks (jack profile switch, Bluetooth) therefore become the default.
    pipewire.extraConfig.pipewire-pulse.switch-on-connect."pulse.cmd" = [
      {
        cmd = "load-module";
        args = "module-switch-on-connect";
      }
    ];
    gnome.gnome-keyring.enable = true;
    upower.enable = true;
    displayManager = {
      sddm = {
        enable = true;
        package = pkgs.kdePackages.sddm;
        wayland = {
          enable = true;
          # Weston's kiosk shell lacks the greeter's layer-shell and leaves the pointer invisible.
          compositor = "kwin";
        };
        theme = "sddm-astronaut-theme";
        extraPackages = sddmAstronautTheme.propagatedBuildInputs;
        settings = {
          General.InputMethod = "qtvirtualkeyboard";
          Theme = {
            CursorTheme = "Bibata-Modern-Classic";
            CursorSize = 24;
          };
        };
      };
      defaultSession = "hyprland-uwsm";
    };
    gvfs.enable = true;
    flatpak.enable = true;
    xserver.xkb.layout = "latam";
  };

  time.timeZone = "America/Bogota";
  i18n.defaultLocale = "es_ES.UTF-8";
  console.keyMap = "la-latin1";

  # Administration goes through sudo with razor's password. Mutable users keep an
  # existing root password, so installed systems also need `sudo passwd -l root`.
  users.users.root.hashedPassword = "!";
  security.sudo.extraConfig = ''
    Defaults pwfeedback
  '';

  users.users.razor = {
    isNormalUser = true;
    description = "razor";
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    # Keep fresh installations locked until the installer runs `passwd razor`.
    initialHashedPassword = "!";
  };

  system.stateVersion = "26.05";

  programs = {
    fish.enable = true;
    # fnm downloads upstream Node binaries that use the standard Linux loader.
    nix-ld = {
      enable = true;
      # X11, font and PulseAudio libraries for prebuilt desktop binaries.
      libraries = with pkgs; [
        libx11
        libxext
        libxrender
        libxtst
        libxi
        freetype
        fontconfig
        libpulseaudio
      ];
    };
    hyprland = {
      enable = true;
      withUWSM = true;
    };
    # Upstream supplies NetworkManager, PipeWire, RTKit, and power profile integration.
    serpantinum.enable = true;
  };

  system.activationScripts.loginBackgroundAccess = {
    deps = [ "users" ];
    # User activation resets the home mode, so restore SDDM's traversal ACL afterward.
    text = ''
      ${pkgs.acl}/bin/setfacl -m g:sddm:--x -- ${lib.escapeShellArg config.users.users.razor.home}
    '';
  };

  zramSwap.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    nautilus
    # GTK4/libadwaita viewers follow the dark adw-gtk3 desktop like Nautilus.
    loupe
    celluloid
    git
    bibata-cursors
    sddmAstronautTheme
  ];

  # System defaults keep ~/.config/mimeapps.list writable for apps and user choices.
  xdg.mime.defaultApplications =
    lib.genAttrs [
      "image/avif"
      "image/bmp"
      "image/gif"
      "image/heic"
      "image/jpeg"
      "image/jxl"
      "image/png"
      "image/svg+xml"
      "image/tiff"
      "image/webp"
      "image/vnd.microsoft.icon"
    ] (_: "org.gnome.Loupe.desktop")
    // lib.genAttrs [
      "video/3gpp"
      "video/mp2t"
      "video/mp4"
      "video/mpeg"
      "video/ogg"
      "video/quicktime"
      "video/webm"
      "video/x-flv"
      "video/x-m4v"
      "video/x-matroska"
      "video/x-ms-wmv"
      "video/x-msvideo"
    ] (_: "io.github.celluloid_player.Celluloid.desktop");

  fonts.packages = with pkgs; [
    corefonts
    vista-fonts
    noto-fonts
    nerd-fonts.fira-code
    inter
    roboto
    open-sans
  ];
}
