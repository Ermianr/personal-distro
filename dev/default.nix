{ pkgs, nixpkgs }:
let
  nixFormatter = pkgs.nixfmt-tree.override {
    settings = {
      tree-root-file = "flake.nix";
      walk = "git";
      # Treat filenames starting with a dash as paths, not formatter options.
      formatter.nixfmt.options = [ "--" ];
    };
  };
  mkRepoCommand =
    name: runtimeInputs: text:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.git ] ++ runtimeInputs;
      text = ''
        if (( $# == 1 )) && [[ "$1" == "--help" || "$1" == "-h" ]]; then
          echo "Usage: ${name} (from the repository)"
          exit 0
        fi
        if (( $# != 0 )); then
          echo "This command takes no arguments. Use ${name} --help." >&2
          exit 2
        fi
        if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
          echo "Run this command inside the Git repository." >&2
          exit 1
        fi
        cd "$repo_root"
      ''
      + text;
    };
  # Include untracked sources, but skip ignored files, deleted paths and symlinks.
  repoFileSelection = patterns: label: ''
    mapfile -d "" -t candidates < <(
      git ls-files -z --cached --others --exclude-standard --deduplicate -- ${pkgs.lib.escapeShellArgs patterns}
    )
    files=()
    for file in "''${candidates[@]}"; do
      if [[ -f "$file" && ! -L "$file" ]]; then
        files+=("./$file")
      fi
    done
    if (( ''${#files[@]} == 0 )); then
      echo "No ${label} files found to check."
      exit 0
    fi
  '';
  nixFileSelection = repoFileSelection [ "*.nix" ] "Nix";
  qmlFileSelection = repoFileSelection [ "*.qml" ] "QML";
  bashFileSelection = repoFileSelection [ "*.sh" "*.bash" ] "Bash";
  nixFormatCheck = mkRepoCommand "nix-format-check" [ pkgs.nixfmt ] (
    nixFileSelection
    + ''
      exec nixfmt --check -- "''${files[@]}"
    ''
  );
  nixLint = mkRepoCommand "nix-lint" [ pkgs.statix pkgs.deadnix ] (
    nixFileSelection
    + ''
      status=0
      for file in "''${files[@]}"; do
        if ! statix check --format errfmt "$file"; then
          status=1
        fi
      done
      if ! deadnix --fail -- "''${files[@]}"; then
        status=1
      fi
      exit "$status"
    ''
  );
  nixAudit = mkRepoCommand "nix-audit" [ nixFormatCheck nixLint pkgs.nix ] ''
    status=0
    echo "Checking Nix formatting..."
    if ! nix-format-check; then
      status=1
    fi
    echo "Checking Nix with statix and deadnix..."
    if ! nix-lint; then
      status=1
    fi
    for profile in desktop desktop-vm; do
      echo "Evaluating profile $profile..."
      if ! nix eval --raw --no-update-lock-file --no-write-lock-file \
        ".#nixosConfigurations.$profile.config.system.build.toplevel.drvPath" > /dev/null; then
        status=1
      fi
    done
    exit "$status"
  '';
  qmlImportFlags = pkgs.lib.escapeShellArgs [
    "-I"
    "${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}"
    "-I"
    "${pkgs.quickshell}/${pkgs.qt6.qtbase.qtQmlPrefix}"
  ];
  # Expose Qt and Quickshell imports to both CLI tools and editor language servers.
  qmlTools =
    pkgs.runCommand "personal-distro-qml-tools"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta = {
          description = "QML tools with Qt and Quickshell imports";
          mainProgram = "qmlls";
        };
      }
      ''
        mkdir -p "$out/bin"
        makeWrapper ${pkgs.qt6.qtdeclarative}/bin/qmllint "$out/bin/qmllint" \
          --add-flags ${pkgs.lib.escapeShellArg qmlImportFlags}
        makeWrapper ${pkgs.qt6.qtdeclarative}/bin/qmlls "$out/bin/qmlls" \
          --add-flags ${pkgs.lib.escapeShellArg qmlImportFlags} \
          --add-flags --no-cmake-calls
        ln -s ${pkgs.qt6.qtdeclarative}/bin/qmlformat "$out/bin/qmlformat"
      '';
  qmlFormat = mkRepoCommand "qml-format" [ qmlTools ] (
    qmlFileSelection
    + ''
      exec qmlformat --inplace "''${files[@]}"
    ''
  );
  qmlFormatCheck = mkRepoCommand "qml-format-check" [ qmlTools pkgs.coreutils pkgs.diffutils ] (
    qmlFileSelection
    + ''
      status=0
      formatted=$(mktemp)
      trap 'rm -f "$formatted"' EXIT
      for file in "''${files[@]}"; do
        if ! qmlformat "$file" > "$formatted"; then
          status=1
          continue
        fi
        if ! cmp -s -- "$file" "$formatted"; then
          echo "QML formatting required: $file" >&2
          status=1
        fi
      done
      exit "$status"
    ''
  );
  qmlLint = mkRepoCommand "qml-lint" [ qmlTools ] (
    qmlFileSelection
    + ''
      exec qmllint --max-warnings 0 "''${files[@]}"
    ''
  );
  bashFormat = mkRepoCommand "bash-format" [ pkgs.shfmt ] (
    bashFileSelection
    + ''
      exec shfmt --write -- "''${files[@]}"
    ''
  );
  bashFormatCheck = mkRepoCommand "bash-format-check" [ pkgs.shfmt ] (
    bashFileSelection
    + ''
      exec shfmt --diff -- "''${files[@]}"
    ''
  );
  bashLint = mkRepoCommand "bash-lint" [ pkgs.bash pkgs.shellcheck ] (
    bashFileSelection
    + ''
      status=0
      for file in "''${files[@]}"; do
        if ! bash -n -- "$file"; then
          status=1
        fi
      done
      if ! shellcheck -- "''${files[@]}"; then
        status=1
      fi
      exit "$status"
    ''
  );
  bashAudit = mkRepoCommand "bash-audit" [ bashFormatCheck bashLint ] ''
    status=0
    echo "Checking Bash formatting..."
    if ! bash-format-check; then
      status=1
    fi
    echo "Checking Bash syntax and ShellCheck findings..."
    if ! bash-lint; then
      status=1
    fi
    exit "$status"
  '';
  bashLsp = pkgs.writeShellApplication {
    name = "bash-lsp";
    runtimeInputs = [
      pkgs.bash-language-server
      pkgs.shellcheck
      pkgs.shfmt
    ];
    text = ''
      exec bash-language-server start "$@"
    '';
  };
  mkApp = description: package: {
    type = "app";
    program = pkgs.lib.getExe package;
    meta = { inherit description; };
  };
  # PyPI wheels need an FHS loader on NixOS; Python itself stays pinned by Nix.
  devEnvironment = pkgs.buildFHSEnv {
    name = "personal-distro-dev";
    targetPkgs = p: [
      p.python3
      p.uv
      p.git
      p.nix
      p.nixd
      p.nixfmt
      p.statix
      p.deadnix
      nixFormatter
      nixFormatCheck
      nixLint
      nixAudit
      qmlTools
      qmlFormat
      qmlFormatCheck
      qmlLint
      p.shellcheck
      p.shfmt
      p.bash-language-server
      bashFormat
      bashFormatCheck
      bashLint
      bashAudit
      bashLsp
    ];
    multiArch = false;
    profile = ''
      export UV_PYTHON=${pkgs.python3}/bin/python3
      export UV_PYTHON_DOWNLOADS=never
      export NIX_PATH=nixpkgs=${nixpkgs}
    '';
    runScript = "bash --noprofile --norc";
  };
  devApp = {
    type = "app";
    program = "${devEnvironment}/bin/personal-distro-dev";
    meta.description = "Development environment for Nix, Python, QML and Bash";
  };
in
{
  environment = devEnvironment;
  formatter = nixFormatter;
  apps = {
    dev = devApp;
    nix-lsp = mkApp "Nix language server" pkgs.nixd;
    nix-format-check = mkApp "Check Nix formatting" nixFormatCheck;
    nix-lint = mkApp "Lint Nix with statix and deadnix" nixLint;
    nix-audit = mkApp "Audit Nix and evaluate desktop profiles" nixAudit;
    qml-lsp = mkApp "QML language server with Qt and Quickshell imports" qmlTools;
    qml-format = mkApp "Format repository QML files" qmlFormat;
    qml-format-check = mkApp "Check QML formatting" qmlFormatCheck;
    qml-lint = mkApp "Lint QML with qmllint" qmlLint;
    bash-lsp = mkApp "Bash language server with ShellCheck and shfmt" bashLsp;
    bash-format = mkApp "Format repository Bash scripts" bashFormat;
    bash-format-check = mkApp "Check Bash formatting" bashFormatCheck;
    bash-lint = mkApp "Check Bash syntax and ShellCheck findings" bashLint;
    bash-audit = mkApp "Audit Bash formatting, syntax and lint" bashAudit;
  };
}
