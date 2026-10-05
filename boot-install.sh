#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vm-common.sh
source "$script_dir/vm-common.sh"
vm_enter_tools "${BASH_SOURCE[0]}" "$@"

disk="$script_dir/vm/nixos.qcow2"
ovmf_vars="$script_dir/vm/OVMF_VARS.fd"
ovmf_code="$(vm_ovmf_code)"
installer="$script_dir/isos/nixos-minimal-26.05-x86_64.iso"
vm_require_files "$disk" "$ovmf_vars" "$ovmf_code" "$installer"
vm_require_kvm

exec qemu-system-x86_64 \
  -machine q35,accel=kvm \
  -m 4096 -smp 4 -cpu host \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
  -drive if=pflash,format=raw,file="$ovmf_vars" \
  -drive file="$disk",format=qcow2,if=virtio \
  -cdrom "$installer" \
  -boot order=d \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
  -vga virtio -display gtk
