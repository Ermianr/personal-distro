{
  description = "Personal NixOS desktop for development and gaming.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    wayland-vdagent = {
      url = "github:v-dermichev/wayland-vdagent";
      flake = false;
    };
    serpantinum = {
      url = "github:ilyamiro/serpantinum";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    inputs@{
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      serpantinum,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      devTools = import ./dev { inherit pkgs nixpkgs; };
      # Brave Origin is absent from pinned stable nixpkgs; only this package uses unstable.
      braveOriginPackage = nixpkgs-unstable.legacyPackages.${system}.brave-origin;
      waylandVdagentSrc = inputs."wayland-vdagent";
      displayColorsPackage = pkgs.callPackage ./pkgs/display-colors { };
      loginBackground = "/home/razor/Imágenes/Fondos/login.jpg";
      sddmAstronautTheme = pkgs.sddm-astronaut.override {
        embeddedTheme = "astronaut";
        themeConfig = {
          Background = loginBackground;
          Locale = "es_ES";
          HourFormat = "HH:mm";
          TranslatePlaceholderUsername = "Usuario";
          TranslatePlaceholderPassword = "Contraseña";
          TranslateLogin = "Iniciar sesión";
          TranslateLoginFailedWarning = "Usuario o contraseña incorrectos";
          TranslateCapslockWarning = "Bloq Mayús está activado";
          TranslateSuspend = "Suspender";
          TranslateHibernate = "Hibernar";
          TranslateReboot = "Reiniciar";
          TranslateShutdown = "Apagar";
          TranslateSessionSelection = "Sesión";
          TranslateVirtualKeyboardButtonOn = "Mostrar teclado virtual";
          TranslateVirtualKeyboardButtonOff = "Ocultar teclado virtual";
        };
      };
      serpantinumPackage = serpantinum.packages.${system}.default.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          # Pick a palette noninteractively when wallpapers are changed from the shell UI.
          substituteInPlace src/quickshell/wallpaper/WallpaperEngine.qml \
            --replace-fail 'matugen image ' 'matugen image --source-color-index 0 '
        '';
      });
      homeCfg = {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          sharedModules = [ serpantinum.homeManagerModules.default ];
          extraSpecialArgs = {
            inherit
              waylandVdagentSrc
              serpantinumPackage
              displayColorsPackage
              braveOriginPackage
              ;
          };
          users.razor = ./home/razor.nix;
        };
      };
      mkSystem =
        host:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit loginBackground sddmAstronautTheme; };
          modules = [
            host
            home-manager.nixosModules.home-manager
            homeCfg
            serpantinum.nixosModules.default
          ];
        };
    in
    {
      devShells.${system}.default = devTools.environment.env;
      formatter.${system} = devTools.formatter;
      apps.${system} = devTools.apps;

      packages.${system} = {
        brave-origin = braveOriginPackage;
        display-colors = displayColorsPackage;
        serpantinum = serpantinumPackage;
        sddm-astronaut = sddmAstronautTheme;
      };

      checks.${system}.serpantinum-session = import ./tests/serpantinum-session.nix {
        inherit pkgs;
        homeManagerModule = home-manager.nixosModules.home-manager;
        serpantinumModule = serpantinum.nixosModules.default;
        inherit homeCfg loginBackground sddmAstronautTheme;
      };

      nixosConfigurations = {
        desktop = mkSystem ./hosts/desktop/configuration.nix;
        desktop-vm = mkSystem ./hosts/desktop-vm/configuration.nix;
      };
    };
}
