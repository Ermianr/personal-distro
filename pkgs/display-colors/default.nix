{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  quickshell,
  qt6,
  hyprland,
  grim,
}:
let
  connectivityPython = python3.withPackages (pythonPackages: [ pythonPackages.dbus-fast ]);
in
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
    ${connectivityPython}/bin/python3 ${../../tests/connectivity.py} connectivity.py
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/display-colors"
    cp display-colors.py connectivity.py *.qml "$out/share/display-colors/"
    substituteInPlace "$out/share/display-colors/ColorControls.qml" \
      --replace-fail '"display-colors"' "\"$out/bin/display-colors\""
    for page in WifiPage BluetoothPage; do
      substituteInPlace "$out/share/display-colors/$page.qml" \
        --replace-fail '"personal-tweaks-connectivity"' "\"$out/bin/personal-tweaks-connectivity\""
    done
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
          grim
          quickshell
        ]
      } \
      "''${qtWrapperArgs[@]}"
    ln -s display-colors "$out/bin/personal-tweaks"
    makeWrapper ${connectivityPython}/bin/python3 "$out/bin/personal-tweaks-connectivity" \
      --add-flags "$out/share/display-colors/connectivity.py"
  '';
  meta = {
    description = "Standalone desktop tweaks for Hyprland: display colors, Wi-Fi and Bluetooth";
    mainProgram = "personal-tweaks";
    platforms = lib.platforms.linux;
  };
}
