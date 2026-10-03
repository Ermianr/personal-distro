{ pkgs, waylandVdagentSrc, ... }:
let
  waylandVdagent = pkgs.callPackage ../pkgs/wayland-vdagent {
    inherit waylandVdagentSrc;
  };
in
{
  home.packages = [ waylandVdagent ];
  systemd.user.services.wayland-vdagent = {
    Unit = {
      Description = "SPICE Wayland clipboard and resize bridge";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${waylandVdagent}/bin/wayland-vdagent";
      Restart = "on-failure";
      RestartSec = "2s";
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
