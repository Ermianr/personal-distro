pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Bluetooth

ColumnLayout {
    id: root
    required property Theme theme
    property string connectivityCommand: "personal-tweaks-connectivity"
    // Quickshell.Bluetooth's qmldir omits `depends Quickshell`, so qmllint cannot
    // resolve its adapter types; read the singleton untyped instead.
    readonly property var bluez: Bluetooth
    readonly property var adapter: bluez.defaultAdapter
    readonly property bool adapterOn: adapter !== null && adapter.enabled
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var pairedDevices: devices.filter(device => device.paired || device.bonded).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    // Unnamed advertisers are usually beacons nobody wants to pair with.
    readonly property var availableDevices: devices.filter(device => !device.paired && !device.bonded && device.deviceName !== "").sort((a, b) => a.name.localeCompare(b.name))
    property var prompt: null
    property bool agentReady: false
    property var watchedDevice: null
    property bool watchedConnecting: false
    property string forgetCandidate: ""
    property string message: ""
    property bool messageIsError: false
    spacing: 16

    function deviceIcon(icon: string): string {
        if (icon.startsWith("audio-headset") || icon.startsWith("audio-headphones"))
            return "\u{F02CB}";
        if (icon.startsWith("audio"))
            return "\u{F04C3}";
        if (icon === "input-keyboard")
            return "\u{F030C}";
        if (icon === "input-mouse")
            return "\u{F037D}";
        if (icon === "input-gaming")
            return "\u{F02B4}";
        if (icon === "input-tablet")
            return "\u{F04F6}";
        if (icon === "phone")
            return "\u{F03F2}";
        if (icon === "computer")
            return "\u{F0322}";
        return "\u{F00AF}";
    }

    function statusText(device): string {
        if (device.pairing)
            return "Emparejando…";
        if (device.state === BluetoothDeviceState.Connecting)
            return "Conectando…";
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "Desconectando…";
        const parts = [];
        if (device.connected)
            parts.push("Conectado");
        else if (device.paired || device.bonded)
            parts.push("Emparejado");
        else
            parts.push("Disponible");
        if (device.batteryAvailable)
            parts.push("Batería " + Math.round(device.battery * 100) + " %");
        return parts.join(" · ");
    }

    function deviceName(path: string): string {
        const device = devices.find(candidate => candidate.dbusPath === path);
        return device ? device.name : "Un dispositivo";
    }

    function showMessage(text: string, isError: bool): void {
        message = text;
        messageIsError = isError;
    }

    function watch(device, connecting: bool): void {
        watchedDevice = device;
        watchedConnecting = false;
        showMessage("", false);
        if (connecting)
            connectTimeout.restart();
    }

    function pair(device): void {
        watch(device, false);
        device.pair();
    }

    function connectDevice(device): void {
        watch(device, true);
        device.connect();
    }

    function forget(device): void {
        if (forgetCandidate !== device.address) {
            forgetCandidate = device.address;
            forgetReset.restart();
            return;
        }
        forgetCandidate = "";
        showMessage("Se olvidó «" + device.name + "».", false);
        device.forget();
    }

    function handleAgent(line: string): void {
        let event = null;
        try {
            event = JSON.parse(line);
        } catch (error) {
            return;
        }
        if (!event || typeof event.type !== "string" || typeof event.id !== "number" || typeof event.device !== "string" || typeof event.code !== "string")
            return;
        if (event.type === "ready") {
            agentReady = true;
        } else if (event.type === "error") {
            agentReady = false;
            console.warn("Bluetooth agent: " + event.code);
        } else if (event.type === "cancel") {
            prompt = null;
        } else if (["display", "confirm", "pin", "passkey", "authorize", "service"].includes(event.type)) {
            prompt = event;
        }
    }

    function respond(accept: bool, value: string): void {
        const current = prompt;
        prompt = null;
        // Display prompts are informational; BlueZ does not wait for an answer.
        if (current && current.type !== "display")
            agent.write(JSON.stringify({
                id: current.id,
                accept: accept,
                value: value
            }) + "\n");
    }

    onPromptChanged: {
        if (prompt) {
            promptField.text = "";
            promptDialog.open();
        } else {
            promptDialog.close();
        }
    }

    // Scan and stay discoverable only while this page is on screen.
    Binding {
        when: root.adapterOn
        target: root.adapter
        property: "discovering"
        value: root.visible
    }
    Binding {
        when: root.adapterOn
        target: root.adapter
        property: "discoverable"
        value: root.visible
    }

    Connections {
        target: root.watchedDevice
        function onPairingChanged(): void {
            const device = root.watchedDevice;
            if (device.pairing)
                return;
            if (device.paired || device.bonded) {
                // Trusted devices reconnect without asking the agent again.
                device.trusted = true;
                root.connectDevice(device);
            } else {
                root.showMessage("No se pudo emparejar con «" + device.name + "». Comprueba que esté en modo de emparejamiento y vuelve a intentarlo.", true);
                root.watchedDevice = null;
                root.prompt = null;
            }
        }
        function onStateChanged(): void {
            const device = root.watchedDevice;
            if (device.state === BluetoothDeviceState.Connecting)
                root.watchedConnecting = true;
            else if (device.state === BluetoothDeviceState.Disconnected && root.watchedConnecting) {
                root.showMessage("No se pudo conectar con «" + device.name + "». Comprueba que esté encendido y cerca.", true);
                root.watchedDevice = null;
            }
        }
        function onConnectedChanged(): void {
            if (root.watchedDevice?.connected) {
                root.showMessage("Conectado a «" + root.watchedDevice.name + "».", false);
                root.watchedDevice = null;
                connectTimeout.stop();
            }
        }
    }

    Timer {
        id: connectTimeout
        interval: 30000
        onTriggered: {
            if (root.watchedDevice && !root.watchedDevice.connected && !root.watchedDevice.pairing) {
                root.showMessage("«" + root.watchedDevice.name + "» no respondió. Comprueba que esté encendido y cerca.", true);
                root.watchedDevice = null;
            }
        }
    }

    Timer {
        id: forgetReset
        interval: 4000
        onTriggered: root.forgetCandidate = ""
    }

    Process {
        id: agent
        command: [root.connectivityCommand, "agent"]
        running: root.adapter !== null
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handleAgent(line)
        }
    }

    // Quickshell metadata omits QProcess::ExitStatus; exitCode is enough here.
    Connections {
        target: agent
        function onExited(exitCode: int): void {
            root.agentReady = false;
            root.prompt = null;
            if (root.adapter !== null)
                agentRestart.restart();
        }
    }

    Timer {
        id: agentRestart
        interval: 3000
        // Assigning a plain value would drop the binding that stops the agent without an adapter.
        onTriggered: agent.running = Qt.binding(() => root.adapter !== null)
    }

    Popup {
        id: promptDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 420
        modal: true
        padding: 24
        closePolicy: Popup.CloseOnEscape
        onClosed: {
            if (root.prompt)
                root.respond(false, "");
        }
        background: Rectangle {
            radius: 16
            color: root.theme.background
            border.color: root.theme.border
        }
        contentItem: ColumnLayout {
            spacing: 14
            Label {
                text: root.prompt ? root.deviceName(root.prompt.device) : ""
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 18
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Label {
                text: {
                    switch (root.prompt?.type) {
                    case "confirm":
                        return "Confirma que el dispositivo muestra este código:";
                    case "display":
                        return "Escribe este código en el dispositivo y pulsa Intro:";
                    case "pin":
                        return "Escribe el PIN del dispositivo. Suele ser 0000 o 1234.";
                    case "passkey":
                        return "Escribe el código de 6 dígitos que muestra el dispositivo.";
                    case "authorize":
                        return "Quiere emparejarse con este equipo.";
                    case "service":
                        return "Quiere conectarse a un servicio de este equipo.";
                    default:
                        return "";
                    }
                }
                color: root.theme.muted
                font.family: root.theme.fontFamily
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Label {
                visible: root.prompt !== null && root.prompt.code !== ""
                text: root.prompt ? root.prompt.code : ""
                color: root.theme.accent
                font.family: root.theme.fontFamily
                font.pixelSize: 34
                font.weight: Font.DemiBold
                font.letterSpacing: 6
                Layout.alignment: Qt.AlignHCenter
            }
            TweakField {
                id: promptField
                visible: root.prompt !== null && (root.prompt.type === "pin" || root.prompt.type === "passkey")
                theme: root.theme
                Layout.fillWidth: true
                placeholderText: root.prompt?.type === "passkey" ? "123456" : "PIN"
                maximumLength: root.prompt?.type === "passkey" ? 6 : 16
                inputMethodHints: root.prompt?.type === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
                validator: RegularExpressionValidator {
                    regularExpression: root.prompt?.type === "passkey" ? /[0-9]{0,6}/ : /.{0,16}/
                }
                onAccepted: root.respond(true, text)
                onVisibleChanged: {
                    if (visible)
                        forceActiveFocus();
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
                    text: root.prompt?.type === "display" ? "Cerrar" : "Rechazar"
                    onClicked: root.respond(false, "")
                }
                TweakButton {
                    visible: root.prompt !== null && root.prompt.type !== "display"
                    theme: root.theme
                    accented: true
                    text: root.prompt?.type === "confirm" ? "Coinciden" : (promptField.visible ? "Emparejar" : "Permitir")
                    enabled: !promptField.visible || promptField.text.length > 0
                    onClicked: root.respond(true, promptField.text)
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        Label {
            text: "Bluetooth"
            color: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }
        Label {
            text: "Empareja auriculares, teclados, ratones y teléfonos, y gestiona los dispositivos guardados."
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    ConnectionRow {
        theme: root.theme
        icon: root.adapterOn ? "\u{F00AF}" : "\u{F00B2}"
        title: "Bluetooth"
        subtitle: {
            if (!root.adapter)
                return "No se encontró un adaptador Bluetooth";
            if (root.adapter.state === BluetoothAdapterState.Blocked)
                return "Bloqueado por el modo avión o el interruptor de hardware";
            if (!root.adapter.enabled)
                return "Desactivado";
            return "Visible como «" + root.adapter.name + "» mientras esta página está abierta";
        }
        active: root.adapterOn && root.pairedDevices.some(device => device.connected)
        actions: TweakSwitch {
            theme: root.theme
            checked: root.adapterOn
            enabled: root.adapter !== null && root.adapter.state !== BluetoothAdapterState.Blocked
            Accessible.name: "Activar Bluetooth"
            onToggled: root.adapter.enabled = checked
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

    Label {
        visible: root.adapterOn && !root.agentReady
        text: "El asistente de emparejamiento no está disponible; los dispositivos que piden un código podrían fallar."
        color: root.theme.error
        font.family: root.theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    Label {
        visible: root.adapterOn
        text: "MIS DISPOSITIVOS"
        color: root.theme.muted
        font.family: root.theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    Label {
        visible: root.adapterOn && root.pairedDevices.length === 0
        text: "Todavía no hay dispositivos emparejados."
        color: root.theme.muted
        font.family: root.theme.fontFamily
        font.pixelSize: 12
    }

    Repeater {
        model: root.adapterOn ? root.pairedDevices : []
        delegate: ConnectionRow {
            id: pairedRow
            required property var modelData
            theme: root.theme
            icon: root.deviceIcon(modelData.icon)
            title: modelData.name
            subtitle: root.statusText(modelData)
            active: modelData.connected
            actions: [
                TweakButton {
                    theme: root.theme
                    text: root.forgetCandidate === pairedRow.modelData.address ? "¿Olvidar?" : "Olvidar"
                    Accessible.name: "Olvidar " + pairedRow.modelData.name
                    onClicked: root.forget(pairedRow.modelData)
                },
                TweakButton {
                    theme: root.theme
                    accented: !pairedRow.modelData.connected
                    text: pairedRow.modelData.connected ? "Desconectar" : "Conectar"
                    enabled: pairedRow.modelData.state === BluetoothDeviceState.Connected || pairedRow.modelData.state === BluetoothDeviceState.Disconnected
                    Accessible.name: text + " " + pairedRow.modelData.name
                    onClicked: pairedRow.modelData.connected ? pairedRow.modelData.disconnect() : root.connectDevice(pairedRow.modelData)
                }
            ]
        }
    }

    RowLayout {
        visible: root.adapterOn
        Layout.fillWidth: true
        Layout.topMargin: 8
        Label {
            text: "DISPOSITIVOS CERCANOS"
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 1
            Layout.fillWidth: true
        }
        Label {
            text: root.adapter?.discovering ? "Buscando…" : ""
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: 11
        }
    }

    Label {
        visible: root.adapterOn && root.availableDevices.length === 0
        text: "Pon el dispositivo en modo de emparejamiento para que aparezca aquí."
        color: root.theme.muted
        font.family: root.theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    Repeater {
        model: root.adapterOn ? root.availableDevices : []
        delegate: ConnectionRow {
            id: availableRow
            required property var modelData
            theme: root.theme
            icon: root.deviceIcon(modelData.icon)
            title: modelData.name
            subtitle: root.statusText(modelData)
            actions: TweakButton {
                theme: root.theme
                accented: !availableRow.modelData.pairing
                text: availableRow.modelData.pairing ? "Cancelar" : "Emparejar"
                Accessible.name: text + " " + availableRow.modelData.name
                onClicked: availableRow.modelData.pairing ? availableRow.modelData.cancelPair() : root.pair(availableRow.modelData)
            }
        }
    }
}
