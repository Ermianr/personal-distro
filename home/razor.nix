{
  config,
  lib,
  pkgs,
  braveOriginPackage,
  zedPackage,
  ...
}:
{
  imports = [
    ./serpantinum.nix
    ./hyprland.nix
    ./display-colors.nix
  ];

  home = {
    stateVersion = "26.05";
    username = "razor";
    homeDirectory = "/home/razor";
    sessionVariables = {
      NIXOS_OZONE_WL = "1";
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      XCURSOR_SIZE = "24";
      XCURSOR_THEME = "Bibata-Modern-Classic";
    };
    packages = with pkgs; [
      braveOriginPackage
      zedPackage
      fnm
      python3
      uv
      rustup
      clang
      gnumake
      pkg-config
      cmake
      ninja
      meson
      mold
      lldb
      clang-tools
      bubblewrap
    ];
    # Binaries installed with `cargo install`.
    sessionPath = [ "$HOME/.cargo/bin" ];
    # NixOS has no global library paths, so expose graphics/audio libraries only
    # to Cargo builds and runs: a session-wide LD_LIBRARY_PATH would also reach
    # Zed and Brave, which come from nixpkgs-unstable.
    file.".cargo/config.toml".source =
      let
        libraries = with pkgs; [
          wayland
          libxkbcommon
          alsa-lib
          vulkan-loader
        ];
      in
      (pkgs.formats.toml { }).generate "cargo-config.toml" {
        env = {
          PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" libraries;
          # winit and wgpu dlopen these at runtime instead of linking them.
          LD_LIBRARY_PATH = lib.makeLibraryPath libraries;
        };
      };
    # Track the current Node LTS; offline activations keep the installed versions.
    activation.fnmNodeLts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if run ${pkgs.fnm}/bin/fnm install --lts; then
        run ${pkgs.fnm}/bin/fnm default lts-latest
      else
        warnEcho "fnm could not install the current Node LTS"
      fi
    '';
    # Track the current stable Rust; offline activations keep the installed toolchain.
    activation.rustupStable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if run ${pkgs.rustup}/bin/rustup toolchain install stable --component rust-analyzer; then
        run ${pkgs.rustup}/bin/rustup default stable
      else
        warnEcho "rustup could not install the current stable Rust"
      fi
    '';
  };

  programs = {
    gh.enable = true;
    java = {
      enable = true;
      package = pkgs.temurin-bin-25;
    };
    git = {
      enable = true;
      settings = {
        init.defaultBranch = "main";
        user = {
          email = "ermianrazor@gmail.com";
          name = "Kevin García Saldarriaga";
        };
      };
    };
    fish = {
      enable = true;
      interactiveShellInit = ''
        set -g fish_greeting
        fnm env --use-on-cd --shell fish | source
      '';
    };
    starship = {
      enable = true;
      enableFishIntegration = true;
    };
    ghostty = {
      enable = true;
      systemd.enable = true;
      settings = {
        font-family = "FiraCode Nerd Font Mono";
        gtk-single-instance = true;
        background-opacity = 0.9;
        window-padding-x = 14;
        window-padding-y = 14;
        window-padding-balance = true;
        config-file = "?${config.xdg.stateHome}/serpantinum/ghostty.conf";
      };
    };
  };

  gtk = {
    enable = true;
    colorScheme = "dark";
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    # Let qtct choose the style without forcing QT_STYLE_OVERRIDE on applications.
    style.package = [
      pkgs.libsForQt5.qtstyleplugin-kvantum
      pkgs.qt6Packages.qtstyleplugin-kvantum
    ];
    qt5ctSettings.Appearance = {
      # The explicit palette also covers Qt Quick applications.
      color_scheme_path = "${pkgs.libsForQt5.qt5ct}/share/qt5ct/colors/darker.conf";
      custom_palette = true;
      icon_theme = config.gtk.iconTheme.name;
      standard_dialogs = "xdgdesktopportal";
      style = "kvantum";
    };
    qt6ctSettings.Appearance = config.qt.qt5ctSettings.Appearance // {
      color_scheme_path = "${pkgs.qt6Packages.qt6ct}/share/qt6ct/colors/darker.conf";
    };
  };

  xdg = {
    configFile = {
      "Kvantum/kvantum.kvconfig".text = ''
        [General]
        theme=KvGnomeDark
      '';
      "gtk-3.0/bookmarks".source = ./bookmarks;
      "uwsm/env".source = "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
      "uwsm/env-hyprland".text = ''
        export HYPRCURSOR_SIZE=24
        export HYPRCURSOR_THEME=Bibata-Modern-Classic
      '';
    };
    userDirs = {
      enable = true;
      createDirectories = true;
      desktop = "${config.home.homeDirectory}/Escritorio";
      documents = "${config.home.homeDirectory}/Documentos";
      download = "${config.home.homeDirectory}/Descargas";
      music = "${config.home.homeDirectory}/Música";
      pictures = "${config.home.homeDirectory}/Imágenes";
      videos = "${config.home.homeDirectory}/Vídeos";
      projects = null;
      publicShare = null;
      templates = null;
    };
  };
}
