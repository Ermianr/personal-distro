{
  lib,
  rustPlatform,
  waylandVdagentSrc,
}:
let
  manifest = builtins.fromTOML (builtins.readFile "${waylandVdagentSrc}/Cargo.toml");
in
rustPlatform.buildRustPackage {
  pname = manifest.package.name;
  version = manifest.package.version;
  # The pinned crate uses the pure Rust backend and does not link libwayland.
  src = waylandVdagentSrc;
  patches = [ ./hyprland-lua-resize.patch ];
  cargoLock.lockFile = ./Cargo.lock;
  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';
  meta = {
    description = "SPICE clipboard bridge for Wayland compositors";
    mainProgram = "wayland-vdagent";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
