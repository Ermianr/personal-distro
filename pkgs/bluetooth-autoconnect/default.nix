{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
}:
let
  bluetoothPython = python3.withPackages (pythonPackages: [ pythonPackages.dbus-fast ]);
in
stdenvNoCC.mkDerivation {
  pname = "bluetooth-autoconnect";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontConfigure = true;
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${bluetoothPython}/bin/python3 ${../../tests/bluetooth-autoconnect.py} bluetooth-autoconnect.py
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm0644 bluetooth-autoconnect.py "$out/share/bluetooth-autoconnect/bluetooth-autoconnect.py"
    makeWrapper ${bluetoothPython}/bin/python3 "$out/bin/bluetooth-autoconnect" \
      --add-flags "$out/share/bluetooth-autoconnect/bluetooth-autoconnect.py"
    runHook postInstall
  '';
  meta = {
    description = "Reconnect paired and trusted Bluetooth devices before login";
    mainProgram = "bluetooth-autoconnect";
    platforms = lib.platforms.linux;
  };
}
