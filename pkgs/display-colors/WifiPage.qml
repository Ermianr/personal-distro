pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Networking

ColumnLayout {
    id: root
    required property Theme theme
    property string connectivityCommand: "personal-tweaks-connectivity"
    readonly property var wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi) ?? null
    readonly property var networks: wifiDevice ? wifiDevice.networks.values.filter(network => network.name !== "").sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength) || a.name.localeCompare(b.name)) : []
    // The password form lives outside the list so rescans cannot reset what the user types.
    property var selectedNetwork: null
    property var attemptNetwork: null
    property bool attemptWasKnown: false
    property string forgetCandidate: ""
    property bool hiddenOpen: false
    property string hiddenSsidAttempt: ""
    property string hiddenPassword: ""
    property string message: ""
    property bool messageIsError: false
    spacing: 16

    function securityLabel(security: int): string {
        switch (security) {
        case WifiSecurityType.Open:
            return "Abierta";
        case WifiSecurityType.Owe:
            return "Abierta cifrada";
        case WifiSecurityType.WpaPsk:
        case WifiSecurityType.Wpa2Psk:
            return "WPA2";
        case WifiSecurityType.Sae:
            return "WPA3";
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep:
            return "WEP";
        case WifiSecurityType.WpaEap:
        case WifiSecurityType.Wpa2Eap:
        case WifiSecurityType.Wpa3SuiteB192:
        case WifiSecurityType.Leap:
            return "Empresarial";
        default:
            return "Segura";
        }
    }

    function isOpen(network): bool {
        return network.security === WifiSecurityType.Open || network.security === WifiSecurityType.Owe;
    }

    // Enterprise and WEP networks need settings this page does not collect.
    function isSupported(network): bool {
        return isOpen(network) || [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(network.security);
    }

    function signalIcon(strength: real): string {
        if (strength >= 0.75)
            return "\u{F0928}";
        if (strength >= 0.5)
            return "\u{F0925}";
        if (strength >= 0.25)
            return "\u{F0922}";
        return "\u{F091F}";
    }

    function statusText(network): string {
        if (network === attemptNetwork && network.state === ConnectionState.Connecting)
            return "Conectando…";
        if (network.connected)
            return "Conectada · " + securityLabel(network.security);
        const parts = [securityLabel(network.security), Math.round(network.signalStrength * 100) + " %"];
        if (network.known)
            parts.unshift("Guardada");
        return parts.join(" · ");
    }

    function validPassword(password: string): bool {
        if (password.length === 64)
            return /^[0-9a-fA-F]+$/.test(password);
        return password.length >= 8 && password.length <= 63;
    }

    function showMessage(text: string, isError: bool): void {
        message = text;
        messageIsError = isError;
    }

    function connectTo(network): void {
        forgetCandidate = "";
        if (!network.known && !isOpen(network)) {
            selectedNetwork = network;
            passwordField.text = "";
            passwordField.forceActiveFocus();
            showMessage("", false);
            return;
        }
        attemptNetwork = network;
        attemptWasKnown = network.known;
        showMessage("", false);
        network.connect();
    }

    function submitPassword(): void {
        if (!selectedNetwork)
            return;
        if (!validPassword(passwordField.text)) {
            showMessage("La contraseña debe tener entre 8 y 63 caracteres.", true);
            return;
        }
        attemptNetwork = selectedNetwork;
        attemptWasKnown = selectedNetwork.known;
        showMessage("", false);
        selectedNetwork.connectWithPsk(passwordField.text);
        selectedNetwork = null;
        passwordField.text = "";
    }

    function failureText(reason: int, name: string): string {
        switch (reason) {
        case ConnectionFailReason.NoSecrets:
        case ConnectionFailReason.WifiClientFailed:
            return "No se pudo conectar a «" + name + "». Revisa la contraseña.";
        case ConnectionFailReason.WifiAuthTimeout:
            return "«" + name + "» no respondió a tiempo. Revisa la contraseña o acércate al router.";
        case ConnectionFailReason.WifiNetworkLost:
            return "Se perdió la señal de «" + name + "».";
        default:
            return "No se pudo conectar a «" + name + "».";
        }
    }

    function forget(network): void {
        if (forgetCandidate !== network.name) {
            forgetCandidate = network.name;
            forgetReset.restart();
            return;
        }
        forgetCandidate = "";
        network.forget();
        showMessage("Se olvidó «" + network.name + "».", false);
    }

    function connectHidden(): void {
        // Enter bypasses the disabled button, and Quickshell would rerun the helper.
        if (hiddenProcess.running)
            return;
        const ssid = hiddenSsid.text.trim();
        // The helper validates the 32-byte SSID limit after UTF-8 encoding.
        if (ssid === "")
            return;
        if (hiddenPasswordField.text !== "" && !validPassword(hiddenPasswordField.text)) {
            showMessage("La contraseña debe tener entre 8 y 63 caracteres.", true);
            return;
        }
        hiddenPassword = hiddenPasswordField.text;
        hiddenSsidAttempt = ssid;
        hiddenProcess.command = [connectivityCommand, "connect-hidden", "--ssid", ssid];
        hiddenProcess.running = true;
        showMessage("Conectando a «" + ssid + "»…", false);
    }

    Binding {
        when: root.wifiDevice !== null
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.visible && Networking.wifiEnabled
    }

    Connections {
        target: root.attemptNetwork
        function onConnectionFailed(reason: int): void {
            const network = root.attemptNetwork;
            root.showMessage(root.failureText(reason, network.name), true);
            root.attemptNetwork = null;
            // Drop a new profile with a wrong password and ask for it again.
            if (!root.attemptWasKnown) {
                network.forget();
                root.selectedNetwork = network;
                passwordField.forceActiveFocus();
            } else if (reason === ConnectionFailReason.NoSecrets && !root.isOpen(network)) {
                root.selectedNetwork = network;
                passwordField.forceActiveFocus();
            }
        }
        function onConnectedChanged(): void {
            if (root.attemptNetwork?.connected) {
                root.showMessage("Conectado a «" + root.attemptNetwork.name + "».", false);
                root.attemptNetwork = null;
            }
        }
    }

    Timer {
        id: forgetReset
        interval: 4000
        onTriggered: root.forgetCandidate = ""
    }

    Process {
        id: hiddenProcess
        stdinEnabled: true
        stdout: StdioCollector {
            id: hiddenOutput
        }
        onStarted: {
            // Send the password through stdin, never through the command line.
            write(root.hiddenPassword + "\n");
            root.hiddenPassword = "";
        }
    }

    // Quickshell metadata omits QProcess::ExitStatus; exitCode is enough here.
    Connections {
        target: hiddenProcess
        function onExited(exitCode: int): void {
            let result = null;
            try {
                result = JSON.parse(hiddenOutput.text);
            } catch (error) {}
            if (result && typeof result.ok === "boolean" && typeof result.message === "string" && result.ok) {
                root.showMessage("Conectado a «" + root.hiddenSsidAttempt + "».", false);
                root.hiddenOpen = false;
                hiddenSsid.text = "";
                hiddenPasswordField.text = "";
            } else {
                root.showMessage(result && typeof result.message === "string" && result.message ? result.message : "No se pudo conectar a la red oculta.", true);
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        Label {
            text: "Wi‑Fi"
            color: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }
        Label {
            text: "Conéctate a redes inalámbricas y administra las que tienes guardadas."
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    ConnectionRow {
        theme: root.theme
        icon: Networking.wifiEnabled ? "\u{F05A9}" : "\u{F05AA}"
        title: "Wi‑Fi"
        subtitle: {
            if (!Networking.wifiHardwareEnabled)
                return "Desactivado por el interruptor de hardware o el modo avión";
            if (!root.wifiDevice)
                return "No se encontró un adaptador Wi‑Fi";
            if (!Networking.wifiEnabled)
                return "Desactivado";
            const current = root.networks.find(network => network.connected);
            return current ? "Conectado a " + current.name : "Sin conexión";
        }
        active: Networking.wifiEnabled && root.networks.some(network => network.connected)
        actions: TweakSwitch {
            theme: root.theme
            checked: Networking.wifiEnabled && root.wifiDevice !== null
            enabled: Networking.wifiHardwareEnabled && root.wifiDevice !== null
            Accessible.name: "Activar Wi‑Fi"
            onToggled: Networking.wifiEnabled = checked
        }
    }

    ConnectionRow {
        theme: root.theme
        visible: root.selectedNetwork !== null
        expanded: true
        active: true
        icon: "\u{F033E}"
        title: root.selectedNetwork ? "Conectar a «" + root.selectedNetwork.name + "»" : ""
        subtitle: root.selectedNetwork ? "Red " + root.securityLabel(root.selectedNetwork.security) + ". Escribe la contraseña." : ""
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TweakField {
                id: passwordField
                theme: root.theme
                Layout.fillWidth: true
                placeholderText: "Contraseña"
                echoMode: showPassword.checked ? TextInput.Normal : TextInput.Password
                Accessible.name: "Contraseña de la red"
                onAccepted: root.submitPassword()
                Keys.onEscapePressed: root.selectedNetwork = null
            }
            TweakButton {
                id: showPassword
                theme: root.theme
                checkable: true
                text: checked ? "Ocultar" : "Mostrar"
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item {
                Layout.fillWidth: true
            }
            TweakButton {
                theme: root.theme
                text: "Cancelar"
                onClicked: root.selectedNetwork = null
            }
            TweakButton {
                theme: root.theme
                accented: true
                text: "Conectar"
                enabled: passwordField.text.length > 0
                onClicked: root.submitPassword()
            }
        }
    }

    Label {
        visible: root.message !== ""
        text: root.message
        color: root.messageIsError ? root.theme.error : root.theme.muted
        font.family: root.theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    RowLayout {
        visible: Networking.wifiEnabled && root.wifiDevice !== null
        Layout.fillWidth: true
        Label {
            text: "REDES DISPONIBLES"
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 1
            Layout.fillWidth: true
        }
        Label {
            text: root.networks.length ? root.networks.length + " encontradas" : "Buscando…"
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: 11
        }
    }

    Repeater {
        model: Networking.wifiEnabled ? root.networks : []
        delegate: ConnectionRow {
            id: networkRow
            required property var modelData
            theme: root.theme
            icon: root.signalIcon(modelData.signalStrength)
            title: modelData.name
            subtitle: root.statusText(modelData)
            active: modelData.connected
            actions: [
                TweakButton {
                    visible: networkRow.modelData.known
                    theme: root.theme
                    text: root.forgetCandidate === networkRow.modelData.name ? "¿Olvidar?" : "Olvidar"
                    Accessible.name: "Olvidar " + networkRow.modelData.name
                    onClicked: root.forget(networkRow.modelData)
                },
                TweakButton {
                    theme: root.theme
                    accented: !networkRow.modelData.connected
                    text: networkRow.modelData.connected ? "Desconectar" : "Conectar"
                    enabled: !networkRow.modelData.stateChanging && (networkRow.modelData.connected || networkRow.modelData.known || root.isSupported(networkRow.modelData))
                    Accessible.name: text + " " + networkRow.modelData.name
                    onClicked: networkRow.modelData.connected ? networkRow.modelData.disconnect() : root.connectTo(networkRow.modelData)
                }
            ]
        }
    }

    ConnectionRow {
        visible: Networking.wifiEnabled && root.wifiDevice !== null
        theme: root.theme
        expanded: root.hiddenOpen
        icon: "\u{F0415}"
        title: "Red oculta"
        subtitle: "Conéctate escribiendo el nombre de una red que no aparece en la lista"
        actions: TweakButton {
            theme: root.theme
            visible: !root.hiddenOpen
            text: "Añadir"
            onClicked: {
                root.hiddenOpen = true;
                hiddenSsid.forceActiveFocus();
            }
        }
        TweakField {
            id: hiddenSsid
            theme: root.theme
            Layout.fillWidth: true
            placeholderText: "Nombre de la red (SSID)"
            Accessible.name: "Nombre de la red oculta"
            onAccepted: hiddenPasswordField.forceActiveFocus()
            Keys.onEscapePressed: root.hiddenOpen = false
        }
        TweakField {
            id: hiddenPasswordField
            theme: root.theme
            Layout.fillWidth: true
            placeholderText: "Contraseña (vacía si la red es abierta)"
            echoMode: TextInput.Password
            Accessible.name: "Contraseña de la red oculta"
            onAccepted: root.connectHidden()
            Keys.onEscapePressed: root.hiddenOpen = false
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item {
                Layout.fillWidth: true
            }
            TweakButton {
                theme: root.theme
                text: "Cancelar"
                enabled: !hiddenProcess.running
                onClicked: root.hiddenOpen = false
            }
            TweakButton {
                theme: root.theme
                accented: true
                text: hiddenProcess.running ? "Conectando…" : "Conectar"
                enabled: !hiddenProcess.running && hiddenSsid.text.trim() !== ""
                onClicked: root.connectHidden()
            }
        }
    }
}
