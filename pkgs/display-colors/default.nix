{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  quickshell,
  qt6,
  hyprland,
}:
stdenvNoCC.mkDerivation {
  pname = "display-colors";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [
    makeWrapper
    qt6.wrapQtAppsHook
  ];
  buildInputs = [
    quickshell
    qt6.qtwayland
  ];
  dontConfigure = true;
  dontBuild = true;
  dontWrapQtApps = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python3 ${../../tests/display-colors.py} display-colors.py
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/display-colors"
    cp display-colors.py *.qml "$out/share/display-colors/"
    substituteInPlace "$out/share/display-colors/ColorControls.qml" \
      --replace-fail '"display-colors"' "\"$out/bin/display-colors\""
    runHook postInstall
  '';
  postFixup = ''
    makeWrapper ${python3}/bin/python3 "$out/bin/display-colors" \
      --add-flags "$out/share/display-colors/display-colors.py" \
      --set DISPLAY_COLORS_QML "$out/share/display-colors/shell.qml" \
      --set-default QT_QPA_PLATFORM wayland \
      --prefix PATH : ${
        lib.makeBinPath [
          hyprland
          quickshell
        ]
      } \
      "''${qtWrapperArgs[@]}"
    ln -s display-colors "$out/bin/personal-tweaks"
  '';
  meta = {
    description = "Standalone desktop tweaks with Matugen colors for Hyprland";
    mainProgram = "personal-tweaks";
    platforms = lib.platforms.linux;
  };
}
