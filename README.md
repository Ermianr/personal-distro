# Escritorio NixOS

Configuración para `razor` con Hyprland y Serpantinum en español.
`desktop` está preparado para el HP Victus con AMD/NVIDIA; `desktop-vm`, para QEMU/SPICE.

## Antes de instalar en la PC

- Verifica `hosts/desktop/hardware-configuration.nix` con el hardware real:
  UUID de las particiones y montaje EFI en `/boot/efi`.
- Comprueba los identificadores de ambas GPU con `lspci`: deben coincidir en
  `hosts/desktop/nvidia.nix` y las reglas DRM de `hosts/desktop/configuration.nix`.
  Los módulos NVIDIA abiertos requieren una GPU Turing o posterior.
- El arranque configurado es UEFI con GRUB; Secure Boot no está configurado.

Construye el perfil antes de instalar o aplicar cambios:

```bash
nix --extra-experimental-features 'nix-command flakes' build \
  .#nixosConfigurations.desktop.config.system.build.toplevel --no-link
```

Con las particiones montadas en `/mnt`, instala desde el entorno de instalación:

```bash
sudo nixos-install --flake .#desktop
sudo nixos-enter --root /mnt -c 'passwd razor'
```

La cuenta `razor` queda bloqueada inicialmente: establece su contraseña antes
de reiniciar. En una instalación existente, aplica con
`sudo nixos-rebuild switch --flake .#desktop`.

Si Windows no aparece en GRUB tras instalar, repite ese último comando desde
NixOS, con `/boot/efi` montado, para volver a ejecutar la detección automática.

## Uso

`Super+Enter` abre Ghostty con Fish y el prompt de Starship para `razor`;
`Super+W`, los fondos; `Super+Shift+C`, Personal Tweaks, con ajustes de color por
pantalla y una paleta que se adapta al fondo mediante Matugen.
En `desktop`, el panel usa siempre el modo de brillo directo de AMD.
SDDM usa el tema astronaut y `~/Imágenes/Fondos/login.jpg`, inicializado
desde `assets/login.jpg`. Los fondos de `~/Imágenes/Fondos` son reemplazables.

Python, uv y Rust (Cargo, rustfmt, Clippy y rust-analyzer) están disponibles en la
terminal. Para instalar Node.js con fnm, ejecuta `fnm install --lts` y
`fnm use lts-latest`; Fish cambia de versión al entrar en proyectos con `.nvmrc`
o `.node-version`.

Para la VM existente: `bash boot-vm.sh`. Para aplicar el repositorio en ella:
`bash update-vm.sh` (requiere SSH en el puerto 2222 y reinicia la VM).
`bash update-vm.sh --help` muestra las opciones.
