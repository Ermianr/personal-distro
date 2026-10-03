{ config, pkgs, ... }:
{
  services.xserver.videoDrivers = [
    "amdgpu"
    "nvidia"
  ];
  hardware.graphics.enable32Bit = true;

  hardware.nvidia = {
    modesetting.enable = true;
    # Open kernel modules require a Turing or newer GPU.
    open = true;
    powerManagement.enable = true;

    # The pinned Zen 7.2 kernel requires this NVIDIA kernel API compatibility patch.
    package = config.boot.kernelPackages.nvidiaPackages.stable.overrideAttrs (previous: {
      passthru = previous.passthru // {
        open = previous.passthru.open.overrideAttrs (previousOpen: {
          patches = (previousOpen.patches or [ ]) ++ [
            (pkgs.fetchpatch {
              url = "https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/94bcd86886298f7798837a38dc1ff361d60a9c8d/nvidia/nvidia-utils/0001-make-Add-support-for-7.2-Kernel.patch";
              hash = "sha256-K5T7xBWxl2I5Pw/GyHumi4Iq/i6M2jcshI80nSXf/AE=";
            })
          ];
        });
      };
    });

    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      # PRIME uses decimal PCI addresses; keep these aligned with the DRM udev rules.
      amdgpuBusId = "PCI:6:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
}
