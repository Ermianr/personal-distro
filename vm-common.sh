#!/usr/bin/env bash
# Shared setup for boot-vm.sh and boot-install.sh; source it, do not run it.
# NixOS has no /usr/share/OVMF or global QEMU, so both come from the flake's
# pinned nixpkgs. OVMF_CODE may point to another 4 MiB OVMF code image.

vm_fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# vm_enter_tools SCRIPT ARGS...: rerun SCRIPT with the pinned VM tools on PATH.
vm_enter_tools() {
  local script="$1"
  shift
  [[ -z "${PERSONAL_DISTRO_VM_TOOLS:-}" ]] || return 0
  command -v nix >/dev/null 2>&1 || vm_fail "Command not found: nix."
  PERSONAL_DISTRO_VM_TOOLS=1 exec nix shell --inputs-from "$vm_project_dir" \
    nixpkgs#qemu_kvm nixpkgs#virt-viewer nixpkgs#socat -c bash "$script" "$@"
}

# Print the OVMF code image; its 4 MiB layout matches the existing VARS file.
vm_ovmf_code() {
  local firmware
  if [[ -n "${OVMF_CODE:-}" ]]; then
    printf '%s\n' "$OVMF_CODE"
    return
  fi
  firmware="$(nix build --inputs-from "$vm_project_dir" nixpkgs#OVMF.fd \
    --no-link --print-out-paths)" || vm_fail "Could not build the OVMF firmware."
  printf '%s\n' "$firmware/FV/OVMF_CODE.fd"
}

vm_require_files() {
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || vm_fail "File not found: $file"
  done
}

vm_require_kvm() {
  [[ -r /dev/kvm && -w /dev/kvm ]] ||
    vm_fail "Read and write access to /dev/kvm is required."
}

vm_project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
