{
  config,
  pkgs,
  braveOriginPackage,
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
      zed-editor
      fnm
      python3
      uv
      rustc
      cargo
      rustfmt
      clippy
      rust-analyzer
      # Native extensions and Rust crates need a compiler and linker.
      gcc
      gnumake
      pkg-config
    ];
  };

  programs = {
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
    };
  };
}
