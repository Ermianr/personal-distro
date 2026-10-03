{ displayColorsPackage, ... }:
{
  home.packages = [ displayColorsPackage ];
  xdg.desktopEntries.personal-tweaks = {
    name = "Personal Tweaks";
    comment = "Personalizar el escritorio y los colores de pantalla";
    exec = "${displayColorsPackage}/bin/personal-tweaks";
    icon = "preferences-desktop-display";
    categories = [
      "Settings"
      "HardwareSettings"
    ];
    terminal = false;
  };
  wayland.windowManager.hyprland.settings.window_rule = [
    {
      name = "personal-tweaks";
      match.title = "^Personal Tweaks$";
      float = true;
      center = true;
    }
  ];

  systemd.user.services.display-colors = {
    Unit = {
      Description = "Restore display color settings";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${displayColorsPackage}/bin/display-colors watch";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
