# Repository guide

## Structure

NixOS flake for `desktop` (HP Victus, AMD/NVIDIA) and `desktop-vm` (QEMU/SPICE),
with Home Manager and Serpantinum for user `razor`.

- `flake.nix` / `flake.lock`: profiles, packages and pinned inputs.
- `hosts/`: machine hardware; `modules/base.nix`: shared system settings.
- `home/`: shell, Hyprland, applications and display-color integration.
- `pkgs/`: display-color controls and Wayland SPICE agent.
- `dev/`, `pyproject.toml`, `uv.lock`: pinned development tools; `tests/`: controller/session checks.
- `assets/`: seed wallpapers. `vm/`, `isos/`, caches and build outputs stay ignored.

## Language and style

Use English for filenames, identifiers, comments, docstrings, logs, error messages,
`AGENTS.md` and other contributor documentation. Use Spanish for end-user UI,
end-user documentation, commit messages and all agent replies to the user;
developer commands and diagnostics remain English.

- Nix/Bash: two spaces; lowercase hyphenated filenames. Python: four spaces,
  double quotes, snake_case and type annotations. QML: qmlformat defaults.
- Prefer small, explicit functions and existing modules over extra abstractions.
  Remove unused code; avoid duplicate services and unnecessary dependencies.
- Validate external data at boundaries; use `TypedDict` for structured Python
  data and narrow untrusted JSON before use. Quote shell paths and fail clearly.
- Comment non-obvious reasons and constraints, rather than restating the code.
- Keep changes focused. Use pinned formatters/lints; review findings instead of
  suppressing them. Document relevant validation and any skipped checks in PRs.

## Commit messages

- Write commit subjects and bodies in clear, natural Spanish.
- Use a concise subject that describes the concrete change. Avoid vague messages
  and unnecessary jargon.
- Add a body when needed to explain the reason for the change or relevant
  validation. Keep filenames, identifiers and commands in their original form.

## Useful commands

- `nix develop`: interactive FHS development shell on NixOS.
  `nix run .#dev -- -c '<command>'`: non-interactive equivalent.
- `nix fmt`; `nix run .#nix-audit`: Nix formatting, lint and both profile evaluations.
- `nix run .#qml-format`; `nix run .#qml-format-check`; `nix run .#qml-lint`.
- `nix run .#bash-format`; `nix run .#bash-audit`: Bash formatting/syntax/lint.
- `uv sync --locked`; `uv run --locked ruff check .`;
  `uv run --locked ruff format --check .`; `uv run --locked pyrefly check`.
- `uv run --locked python tests/display-colors.py pkgs/display-colors/display-colors.py`.
- `uv run --locked python tests/connectivity.py pkgs/display-colors/connectivity.py`.
- `nix build .#display-colors .#serpantinum --no-link`: package checks/builds.
- `nix build .#nixosConfigurations.desktop.config.system.build.toplevel --no-link`:
  physical profile; replace `desktop` with `desktop-vm` for the VM.
- `nix build .#checks.x86_64-linux.serpantinum-session`: graphical integration test.
- `bash boot-vm.sh`; `bash update-vm.sh --help`: launch/update the existing VM.
  Updating activates the VM and reboots it unless `--no-reboot` is specified.

## Validation and safeguards

Run checks for each changed language; embedded code also needs its package build.
Build `desktop` after kernel/NVIDIA changes. Session changes require the graphical
test and builder access to `/dev/kvm`; if only the builder lacks access, build the
`.driver` output, create `/tmp/serpantinum-test`, and run
`bin/nixos-test-driver --no-interactive -o /tmp/serpantinum-test` as a user with KVM
access. Keep test output outside the repository.

Preserve pinned inputs and lock files unless deliberately updating dependencies.
Preserve intentional runtime choices, including the Zen kernel.
Keep uv development-only; align `.python-version`, Ruff, Pyrefly and Nix Python.
Nix owns runtime dependencies. File checks include tracked/untracked regular
sources and skip ignored, deleted and symlinked paths.

Use upstream Serpantinum modules with its nixpkgs following this flake. Apply
settings before `reloadSystemd`; preserve other writable UI preferences and
user-replaced wallpapers. SDDM gets traversal access and read access to `login.jpg`,
not permission to list the home directory. Use the shell's notification, Polkit,
idle and lock components without duplicate agents.

Activate only on the intended target. Before physical installation, verify disk
UUIDs, EFI mount and GPU PCI IDs; set the initially locked `razor` password before
reboot. Never commit credentials, VM images or generated outputs. Keep `README.md`
minimal and user-facing; implementation details belong in code comments.
