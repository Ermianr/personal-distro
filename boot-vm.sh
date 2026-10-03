#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

vm_dir="$script_dir/vm"
disk="$vm_dir/nixos.qcow2"
ovmf_vars="$vm_dir/OVMF_VARS.fd"
ovmf_code="/usr/share/OVMF/OVMF_CODE_4M.fd"

for file in "$disk" "$ovmf_vars" "$ovmf_code"; do
  if [[ ! -f "$file" ]]; then
    printf 'Error: file not found: %s\n' "$file" >&2
    exit 1
  fi
done

for cmd in qemu-system-x86_64 remote-viewer; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Error: command not found: %s\n' "$cmd" >&2
    exit 1
  fi
done

if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  printf 'Error: read and write access to /dev/kvm is required.\n' >&2
  exit 1
fi

# The private directory restricts the unauthenticated SPICE socket to this user.
spice_runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/personal-distro-spice.XXXXXX")"

spice_socket="$spice_runtime_dir/spice.sock"
qemu_pid=""

cleanup() {
  if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
  fi

  rm -rf -- "$spice_runtime_dir"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Use a USB tablet for SDDM's cursor before the user-session SPICE agent starts.
# Disable vmmouse so it cannot take over from the USB tablet.
qemu-system-x86_64 \
  -machine q35,accel=kvm,vmport=off \
  -cpu host \
  -m 4096 \
  -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
  -drive if=pflash,format=raw,file="$ovmf_vars" \
  -drive file="$disk",format=qcow2,if=virtio \
  -boot order=c \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device qemu-xhci,id=usb \
  -device usb-tablet,bus=usb.0 \
  -device virtio-serial-pci \
  -chardev spicevmc,id=vdagent,name=vdagent \
  -device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
  -vga virtio \
  -spice unix=on,addr="$spice_socket",disable-ticketing=on \
  -audiodev spice,id=audio0 \
  -device intel-hda \
  -device hda-output,audiodev=audio0 \
  -display none &

qemu_pid=$!

for _ in {1..100}; do
  if [[ -S "$spice_socket" ]]; then
    break
  fi

  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    wait "$qemu_pid" || true
    printf 'Error: QEMU exited before creating the SPICE socket.\n' >&2
    exit 1
  fi

  sleep 0.1
done

if [[ ! -S "$spice_socket" ]]; then
  printf 'Error: QEMU did not create the SPICE socket within 10 seconds.\n' >&2
  exit 1
fi

viewer_args=(
  --auto-resize always
)

if [[ "${REMOTE_VIEWER_DEBUG:-0}" == "1" ]]; then
  viewer_args+=(
    --debug
    --verbose
  )
fi

remote-viewer \
  "${viewer_args[@]}" \
  "spice+unix://$spice_socket"
