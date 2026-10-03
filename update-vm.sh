#!/usr/bin/env bash
set -euo pipefail

vm_target="razor@127.0.0.1"
vm_port="2222"
flake_profile="desktop-vm"
reboot_vm="1"

usage() {
  cat <<'EOF'
Uso: bash update-vm.sh [opciones]

Copia el proyecto actual, reconstruye la VM y programa su reinicio.
La VM debe estar encendida y accesible por SSH.

Opciones:
  --target USUARIO@HOST  Destino SSH (por defecto: razor@127.0.0.1).
  --port PUERTO         Puerto SSH (por defecto: 2222).
  --profile NOMBRE      Perfil de NixOS (por defecto: desktop-vm).
  --no-reboot           Aplica la configuración sin reiniciar la VM.
  -h, --help            Muestra esta ayuda.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

quote_argument() {
  # SSH parses a remote shell command, so local argument quoting is insufficient.
  local value="${1//\'/\'\\\'\'}"
  printf "'%s'" "$value"
}

while (($# > 0)); do
  case "$1" in
    --target | --port | --profile)
      (($# >= 2)) || fail "Missing value for $1."
      case "$1" in
        --target) vm_target="$2" ;;
        --port) vm_port="$2" ;;
        --profile) flake_profile="$2" ;;
      esac
      shift 2
      ;;
    --no-reboot)
      reboot_vm="0"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) fail "Unknown option: $1. See --help." ;;
  esac
done

[[ -n "$vm_target" && "$vm_target" != -* ]] || fail "Invalid SSH target."
[[ "$vm_port" =~ ^[0-9]{1,5}$ ]] || fail "Invalid SSH port."
((10#$vm_port >= 1 && 10#$vm_port <= 65535)) || fail "Invalid SSH port."
[[ "$flake_profile" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Invalid profile name."

for cmd in git ssh tar mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Command not found: $cmd."
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! project_dir="$(git -C "$script_dir" rev-parse --show-toplevel)"; then
  fail "The script must reside in a Git checkout of this project."
fi
[[ -f "$project_dir/flake.nix" ]] || fail "flake.nix not found in $project_dir."

umask 077
runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/personal-distro-update.XXXXXX")"
ssh_options=(
  -p "$vm_port"
  -o ConnectTimeout=10
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
  -o ControlMaster=auto
  -o "ControlPath=$runtime_dir/ssh"
  -o ControlPersist=60
)

cleanup() {
  ssh "${ssh_options[@]}" -O exit -- "$vm_target" >/dev/null 2>&1 || true
  rm -rf -- "$runtime_dir"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

collect_sources() {
  local directory="$1"
  local prefix="$2"
  local candidates path
  candidates="$(mktemp "$runtime_dir/files.XXXXXX")"
  git -C "$directory" ls-files --cached --others --exclude-standard -z >"$candidates"

  while IFS= read -r -d '' path; do
    if [[ -f "$directory/$path" || -L "$directory/$path" ]]; then
      printf '%s\0' "$prefix$path"
    elif [[ -d "$directory/$path" ]]; then
      [[ -e "$directory/$path/.git" ]] || fail "Initialize the submodule: $prefix$path."
      collect_sources "$directory/$path" "${prefix}${path%/}/"
    fi
  done <"$candidates"
}

printf 'Preparing current sources from %s…\n' "$project_dir"
collect_sources "$project_dir" "" >"$runtime_dir/manifest"
tar -C "$project_dir" --null --verbatim-files-from --no-recursion \
  --files-from "$runtime_dir/manifest" -czf "$runtime_dir/source.tar.gz"

printf 'Connecting to the VM at %s:%s…\n' "$vm_target" "$vm_port"
remote_source="$(
  ssh "${ssh_options[@]}" -- "$vm_target" 'bash -se' <<'REMOTE'
set -euo pipefail
if [[ ! -e /etc/NIXOS ]] || ! systemd-detect-virt --vm --quiet; then
  printf 'Error: the target must be a NixOS virtual machine.\n' >&2
  exit 1
fi
for cmd in nix nixos-rebuild sudo systemctl systemd-run tar mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Error: command not found in the VM: %s.\n' "$cmd" >&2
    exit 1
  fi
done
umask 077
mkdir -p "$HOME/.cache/personal-distro-updates"
snapshot_dir="$(mktemp -d "$HOME/.cache/personal-distro-updates/update.XXXXXX")"
mkdir "$snapshot_dir/source"
printf '%s\n' "$snapshot_dir/source"
REMOTE
)"
[[ -n "$remote_source" ]] || fail "The VM did not return an update directory."

printf -v extract_command 'tar -xzf - --no-same-owner -C %s' "$(quote_argument "$remote_source")"
ssh "${ssh_options[@]}" -- "$vm_target" "$extract_command" <"$runtime_dir/source.tar.gz"
printf 'Sources copied to %s:%s\n' "$vm_target" "$remote_source"

apply_script="$(
  cat <<'REMOTE'
set -euo pipefail
source_dir="$1"
flake_profile="$2"
reboot_vm="$3"
flake_ref="path:$source_dir"

# The path: reference includes the uploaded uncommitted and untracked sources.
expected_system="$(nix eval --raw "$flake_ref#nixosConfigurations.$flake_profile.config.system.build.toplevel.outPath")"
nixos-rebuild switch --flake "$flake_ref#$flake_profile"
active_system="$(readlink -f /run/current-system)"
if [[ "$active_system" != "$expected_system" ]]; then
  printf 'Error: the active generation does not match the uploaded configuration.\nExpected: %s\nActive: %s\n' \
    "$expected_system" "$active_system" >&2
  exit 1
fi
printf '\nConfiguration applied and verified: %s\n' "$active_system"

if [[ "$reboot_vm" == "1" ]]; then
  # Delay the reboot so the SSH command can finish successfully first.
  systemd-run --quiet --on-active=5s "$(command -v systemctl)" reboot
  printf 'The VM will reboot in five seconds.\n'
else
  printf 'Reboot skipped. Kernel or session changes may require a reboot or a new login.\n'
fi
REMOTE
)"

printf -v apply_command 'sudo bash -c %s -- %s %s %s' \
  "$(quote_argument "$apply_script")" "$(quote_argument "$remote_source")" \
  "$(quote_argument "$flake_profile")" "$(quote_argument "$reboot_vm")"
printf 'Rebuilding profile %s inside the VM…\n' "$flake_profile"
ssh "${ssh_options[@]}" -t -- "$vm_target" "$apply_command"
