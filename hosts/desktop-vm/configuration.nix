{ ... }:
{
  imports = [
    ../../modules/base.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "desktop-vm";

  # Override shell defaults for devices absent from this QEMU profile.
  hardware = {
    bluetooth.enable = false;
    i2c.enable = false;
  };

  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 3;
    };
    efi.canTouchEfiVariables = true;
  };

  services.openssh.enable = true;

  services.spice-vdagentd.enable = true;
  home-manager.users.razor.imports = [ ../../home/spice-vdagent.nix ];
}
