#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vm-common.sh
source "$script_dir/vm-common.sh"
vm_enter_tools "${BASH_SOURCE[0]}" "$@"

vm_dir="$script_dir/vm"
disk="$vm_dir/nixos.qcow2"
ovmf_vars="$vm_dir/OVMF_VARS.fd"
ovmf_code="$(vm_ovmf_code)"
vm_require_files "$disk" "$ovmf_vars" "$ovmf_code"
vm_require_kvm

# The private directory restricts the unauthenticated SPICE socket to this user.
spice_runtime_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/personal-distro-spice.XXXXXX")"

spice_socket="$spice_runtime_dir/spice.sock"
qmp_socket="$spice_runtime_dir/qmp.sock"
qemu_pid=""

# Ask the guest to shut down like a power button; SIGTERM alone cuts its power.
stop_vm() {
  printf 'Shutting down the VM…\n'
  printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_powerdown"}' |
    socat - "UNIX-CONNECT:$qmp_socket" >/dev/null 2>&1 || true
  for _ in {1..600}; do
    kill -0 "$qemu_pid" 2>/dev/null || return 0
    sleep 0.1
  done
  printf 'Warning: the guest did not shut down within 60 seconds; stopping QEMU.\n' >&2
  kill "$qemu_pid" 2>/dev/null || true
}

cleanup() {
  if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
    stop_vm
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
  -qmp unix:"$qmp_socket",server=on,wait=off \
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
