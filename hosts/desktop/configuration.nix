{ pkgs, ... }:
{
  imports = [
    ../../modules/base.nix
    ./hardware-configuration.nix
    ./nvidia.nix
  ];

  networking.hostName = "desktop";

  # The default amdgpu backlight curve leaves this panel too dim; 0x40000 sets
  # DC_DISABLE_CUSTOM_BRIGHTNESS_CURVE so brightness levels map directly.
  boot.kernelParams = [ "amdgpu.dcdebugmask=0x40000" ];

  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot/efi";
    };
    timeout = 5;
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      useOSProber = true;
      configurationLimit = 3;
      theme = pkgs.catppuccin-grub.override { flavor = "mocha"; };
    };
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    i2c.enable = true;
  };

  programs.steam.enable = true;
  programs.gamemode.enable = true;
  users.users.razor.extraGroups = [
    "gamemode"
    "i2c"
  ];

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8 * 1024;
      priority = 0;
    }
  ];

  # Stable names avoid card0/card1 reordering; both GPUs retain their connected outputs.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]", KERNELS=="0000:06:00.0", SYMLINK+="dri/amd-igpu"
    SUBSYSTEM=="drm", KERNEL=="card[0-9]", KERNELS=="0000:01:00.0", SYMLINK+="dri/nvidia-dgpu"
  '';

  home-manager.users.razor.xdg.configFile."uwsm/env-hyprland".text = ''
    export AQ_DRM_DEVICES="/dev/dri/amd-igpu:/dev/dri/nvidia-dgpu"
  '';
}
