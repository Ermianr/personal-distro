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
    ${pkgs.acl}/bin/setfacl -m g:sddm:--x -- \
      ${lib.escapeShellArg config.users.users.razor.home} \
      ${lib.escapeShellArg picturesDir} ${lib.escapeShellArg wallpaperDir}
    if ! ${pkgs.util-linux}/bin/runuser -u sddm -- ${pkgs.coreutils}/bin/test -r "$login_background"; then
      ${pkgs.acl}/bin/setfacl -m g:sddm:r-- -- "$login_background"
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
      };
    };
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
    xserver.xkb.layout = "es";
  };

  time.timeZone = "America/Bogota";
  i18n.defaultLocale = "es_ES.UTF-8";
  console.keyMap = "es";

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
    nix-ld.enable = true;
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
    git
    bibata-cursors
    sddmAstronautTheme
  ];

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
