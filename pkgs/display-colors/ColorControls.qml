pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: root
    property string controllerCommand: "display-colors"
    required property Theme theme
    property var outputs: []
    property string selectedName: ""
    property real separation: 100
    property real saturation: 100
    property real red: 100
    property real green: 100
    property real blue: 100
    property bool filterEnabled: false
    property bool whiteBalanceEnabled: false
    property bool loaded: false
    property bool pending: false
    property string message: ""
    spacing: 16

    function readStatus(text) {
        try {
            const data = JSON.parse(text);
            if (!data || !Array.isArray(data.outputs) || !data.outputs.every(output => output && typeof output.name === "string" && typeof output.description === "string" && typeof output.enabled === "boolean" && typeof output.white_balance_enabled === "boolean" && Number.isFinite(output.separation) && output.separation >= 0 && output.separation <= 200 && Number.isFinite(output.saturation) && output.saturation >= 0 && output.saturation <= 200 && ["red", "green", "blue"].every(channel => Number.isFinite(output[channel]) && output[channel] >= 0 && output[channel] <= 100)))
                throw new Error("Invalid display color status");
            outputs = data.outputs;
            if (!pending && outputs.length && !outputs.some(output => output.name === selectedName))
                selectedName = outputs[0].name;
            const selected = outputs.find(output => output.name === selectedName);
            loaded = selected !== undefined;
            if (selected && !pending) {
                separation = selected.separation;
                saturation = selected.saturation;
                red = selected.red;
                green = selected.green;
                blue = selected.blue;
                filterEnabled = selected.enabled;
                whiteBalanceEnabled = selected.white_balance_enabled;
            }
            message = loaded ? "" : "No hay una pantalla conectada para ajustar.";
        } catch (error) {
            loaded = false;
            message = "No se pudieron leer los ajustes de color.";
        }
    }

    function refresh() {
        if (backend.running || pending)
            return;
        backend.command = [controllerCommand, "status"];
        backend.running = true;
    }

    function setCommand() {
        return [controllerCommand, "set", "--output", selectedName, "--separation", String(Math.round(separation)), "--saturation", String(Math.round(saturation)), "--red", String(Math.round(red)), "--green", String(Math.round(green)), "--blue", String(Math.round(blue)), "--enabled", String(filterEnabled), "--white-balance-enabled", String(whiteBalanceEnabled)];
    }

    function queueApply() {
        pending = true;
        debounce.restart();
    }

    function flush() {
        if (backend.running) {
            debounce.restart();
            return;
        }
        pending = false;
        backend.command = setCommand();
        backend.running = true;
    }

    Component.onCompleted: refresh()
    onVisibleChanged: {
        if (visible) {
            settingsFile.reload();
            refreshDelay.restart();
        }
    }
    Component.onDestruction: {
        if (pending && loaded)
            Quickshell.execDetached(setCommand());
    }

    // Refresh after controller changes without continuously polling Hyprland.
    FileView {
        id: settingsFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/display-colors/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            refreshDelay.restart();
        }
    }

    Timer {
        id: refreshDelay
        interval: 150
        onTriggered: {
            if (backend.running || root.pending)
                restart();
            else
                root.refresh();
        }
    }

    Process {
        id: backend
        stdout: StdioCollector {
            id: backendOutput
        }
        stderr: StdioCollector {
            id: backendError
        }
    }

    // Quickshell metadata omits QProcess::ExitStatus; exitCode is enough here.
    Connections {
        target: backend
        function onExited(exitCode: int): void {
            if (exitCode === 0)
                root.readStatus(backendOutput.text);
            else {
                console.warn(backendError.text.trim());
                root.message = "No se pudo aplicar el ajuste. Revisa los registros de la sesión.";
            }
            if (root.pending)
                debounce.restart();
        }
    }

    Timer {
        id: debounce
        interval: 150
        onTriggered: root.flush()
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        Label {
            text: "Colores de pantalla"
            color: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }
        Label {
            text: "Ajusta la intensidad del color y corrige el balance de blanco en cada pantalla."
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            Label {
                text: "PANTALLA"
                color: root.theme.muted
                font.family: root.theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 1
            }
            ComboBox {
                id: outputPicker
                Layout.fillWidth: true
                implicitHeight: 42
                leftPadding: 16
                enabled: root.outputs.length > 0 && !backend.running && !root.pending
                model: root.outputs
                textRole: "name"
                currentIndex: root.outputs.findIndex(output => output.name === root.selectedName)
                font.family: root.theme.fontFamily
                font.pixelSize: 13
                palette.button: root.theme.surface
                palette.buttonText: root.theme.text
                palette.text: root.theme.text
                palette.base: root.theme.surface
                palette.highlight: root.theme.accent
                palette.highlightedText: root.theme.onAccent
                Accessible.name: "Pantalla que quieres ajustar"
                background: Rectangle {
                    radius: 10
                    color: root.theme.surface
                    border.color: outputPicker.activeFocus ? root.theme.accent : root.theme.border
                }
                onActivated: {
                    root.selectedName = root.outputs[currentIndex].name;
                    root.readStatus(JSON.stringify({
                        outputs: root.outputs
                    }));
                }
            }
        }
        TweakButton {
            theme: root.theme
            text: "Actualizar"
            Layout.alignment: Qt.AlignBottom
            enabled: !backend.running && !root.pending
            onClicked: root.refresh()
        }
    }

    Repeater {
        model: [
            {
                key: "filterEnabled",
                title: "Realce de color",
                description: "Aplica la separación de color y la saturación."
            },
            {
                key: "whiteBalanceEnabled",
                title: "Balance de blanco",
                description: "Aplica los ajustes de los canales rojo, verde y azul."
            }
        ]
        delegate: Rectangle {
            id: filterControl
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: filterRow.implicitHeight + 32
            radius: 14
            color: root.theme.surface
            RowLayout {
                id: filterRow
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    Label {
                        text: filterControl.modelData.title
                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                    Label {
                        text: root[filterControl.modelData.key] ? filterControl.modelData.description : "Desactivado. Tus valores se conservan."
                        color: root.theme.muted
                        font.family: root.theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
                TweakSwitch {
                    theme: root.theme
                    checked: root[filterControl.modelData.key]
                    enabled: root.loaded
                    Accessible.name: "Activar " + filterControl.modelData.title.toLowerCase()
                    onToggled: {
                        root[filterControl.modelData.key] = checked;
                        root.queueApply();
                    }
                }
            }
        }
    }

    Repeater {
        model: [
            {
                key: "separation",
                title: "Separación de color",
                description: "Amplifica las diferencias entre los canales de color.",
                maximum: 200
            },
            {
                key: "saturation",
                title: "Saturación",
                description: "Aumenta o suaviza la intensidad de los colores.",
                maximum: 200
            },
            {
                key: "red",
                title: "Balance de blanco · rojo",
                description: "Reduce el rojo si los blancos y grises se ven rojizos.",
                maximum: 100
            },
            {
                key: "green",
                title: "Balance de blanco · verde",
                description: "Reduce el verde si los blancos y grises se ven verdosos.",
                maximum: 100
            },
            {
                key: "blue",
                title: "Balance de blanco · azul",
                description: "Reduce el azul si los blancos y grises se ven azulados.",
                maximum: 100
            }
        ]
        delegate: Rectangle {
            id: colorControl
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: controlColumn.implicitHeight + 36
            radius: 14
            color: root.theme.surface
            ColumnLayout {
                id: controlColumn
                anchors.fill: parent
                anchors.margins: 18
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: colorControl.modelData.title
                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    Label {
                        text: Math.round(root[colorControl.modelData.key]) + " %"
                        color: root.theme.accent
                        font.family: root.theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                }
                Label {
                    text: colorControl.modelData.description
                    color: root.theme.muted
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Slider {
                    id: valueSlider
                    Layout.fillWidth: true
                    implicitHeight: 30
                    enabled: root.loaded
                    focus: colorControl.modelData.key === "separation"
                    from: 0
                    to: colorControl.modelData.maximum
                    stepSize: 1
                    snapMode: Slider.SnapAlways
                    Accessible.name: colorControl.modelData.title
                    background: Rectangle {
                        x: valueSlider.leftPadding
                        y: valueSlider.topPadding + (valueSlider.availableHeight - height) / 2
                        width: valueSlider.availableWidth
                        height: 6
                        radius: 3
                        color: root.theme.border
                        Rectangle {
                            width: valueSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 3
                            color: root.theme.accent
                        }
                        Rectangle {
                            x: Math.min(parent.width - width, parent.width * 100 / valueSlider.to)
                            y: -2
                            width: 2
                            height: 10
                            color: root.theme.muted
                        }
                    }
                    handle: Rectangle {
                        x: valueSlider.leftPadding + valueSlider.visualPosition * (valueSlider.availableWidth - width)
                        y: valueSlider.topPadding + (valueSlider.availableHeight - height) / 2
                        implicitWidth: 18
                        implicitHeight: 18
                        radius: 9
                        color: root.theme.accent
                        border.width: valueSlider.visualFocus || valueSlider.pressed ? 3 : 0
                        border.color: root.theme.text
                    }
                    onMoved: {
                        root[colorControl.modelData.key] = Math.round(value);
                        root.queueApply();
                    }
                    // An explicit Binding survives the slider's own value writes and keeps reset working.
                    Binding {
                        target: valueSlider
                        property: "value"
                        value: root[colorControl.modelData.key]
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Repeater {
                        model: colorControl.modelData.maximum === 100 ? ["0 %", "100 % · Original"] : ["0 %", "100 % · Original", "200 %"]
                        Label {
                            required property string modelData
                            required property int index
                            text: modelData
                            color: root.theme.muted
                            font.family: root.theme.fontFamily
                            font.pixelSize: 10
                            horizontalAlignment: index === 0 ? Text.AlignLeft : (index === 1 && colorControl.modelData.maximum === 200 ? Text.AlignHCenter : Text.AlignRight)
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Label {
            text: backend.running || root.pending ? "Aplicando…" : (root.loaded && !root.message ? "Ajustes guardados automáticamente" : "")
            color: root.theme.muted
            font.family: root.theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        TweakButton {
            theme: root.theme
            text: "Restablecer todo"
            enabled: root.loaded
            onClicked: {
                root.separation = 100;
                root.saturation = 100;
                root.red = 100;
                root.green = 100;
                root.blue = 100;
                root.filterEnabled = false;
                root.whiteBalanceEnabled = false;
                root.queueApply();
            }
        }
    }

    Label {
        visible: root.message !== ""
        text: root.message
        color: root.theme.error
        font.family: root.theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}
