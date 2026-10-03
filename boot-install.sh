#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
disk="$script_dir/vm/nixos.qcow2"
ovmf_vars="$script_dir/vm/OVMF_VARS.fd"
ovmf_code="/usr/share/OVMF/OVMF_CODE_4M.fd"
installer="$script_dir/isos/nixos-minimal-26.05-x86_64.iso"

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  printf 'Error: command not found: qemu-system-x86_64\n' >&2
  exit 1
fi
for file in "$disk" "$ovmf_vars" "$ovmf_code" "$installer"; do
  if [[ ! -f "$file" ]]; then
    printf 'Error: file not found: %s\n' "$file" >&2
    exit 1
  fi
done
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  printf 'Error: read and write access to /dev/kvm is required.\n' >&2
  exit 1
fi

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
