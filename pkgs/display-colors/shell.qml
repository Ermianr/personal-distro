pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

ShellRoot {
    Theme {
        id: palette
    }

    FloatingWindow {
        id: window
        title: "Personal Tweaks"
        implicitWidth: 960
        implicitHeight: 720
        // Equal limits keep the floating window at a fixed size in Hyprland.
        minimumSize: Qt.size(implicitWidth, implicitHeight)
        maximumSize: Qt.size(implicitWidth, implicitHeight)
        color: palette.background
        visible: true
        onClosed: Qt.quit()

        // Hyprland draws rounding, border and shadow; the window only needs its content.
        FocusScope {
            id: root
            property int currentTab: 0
            anchors.fill: parent
            focus: true
            // Unhandled keys bubble up here; open popups consume their own Escape first.
            Keys.onEscapePressed: Qt.quit()

            Rectangle {
                anchors.fill: parent
                color: palette.background
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.preferredWidth: 240
                    Layout.fillHeight: true
                    color: palette.sidebar
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 4
                        Label {
                            text: "Personal Tweaks"
                            color: palette.text
                            font.family: palette.fontFamily
                            font.pixelSize: 15
                            font.bold: true
                            Layout.preferredHeight: 36
                            Layout.leftMargin: 4
                            Layout.bottomMargin: 6
                            verticalAlignment: Text.AlignVCenter
                        }
                        Repeater {
                            model: [
                                {
                                    title: "Colores de pantalla",
                                    icon: "\u{F03D8}"
                                },
                                {
                                    title: "Wi‑Fi",
                                    icon: "\u{F05A9}"
                                },
                                {
                                    title: "Bluetooth",
                                    icon: "\u{F00AF}"
                                }
                            ]
                            delegate: Rectangle {
                                id: tab
                                required property var modelData
                                required property int index
                                readonly property bool current: root.currentTab === index
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: 10
                                color: current ? palette.accent : (tabMouse.containsMouse ? Qt.alpha(palette.border, 0.5) : "transparent")
                                Accessible.role: Accessible.PageTab
                                Accessible.name: modelData.title
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 150
                                    }
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    Rectangle {
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        radius: 8
                                        color: tab.current ? Qt.alpha(palette.onAccent, 0.12) : palette.surface
                                        Text {
                                            anchors.centerIn: parent
                                            text: tab.modelData.icon
                                            color: tab.current ? palette.onAccent : palette.text
                                            font.family: palette.iconFamily
                                            font.pixelSize: 16
                                        }
                                    }
                                    Label {
                                        text: tab.modelData.title
                                        color: tab.current ? palette.onAccent : (tabMouse.containsMouse ? palette.text : palette.muted)
                                        font.family: palette.fontFamily
                                        font.pixelSize: 13
                                        font.weight: tab.current ? Font.Bold : Font.Medium
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.currentTab = tab.index;
                                        pages.children[tab.index].forceActiveFocus();
                                    }
                                }
                            }
                        }
                        Item {
                            Layout.fillHeight: true
                        }
                        Label {
                            text: "Esc para cerrar"
                            color: palette.muted
                            opacity: 0.6
                            font.family: palette.fontFamily
                            font.pixelSize: 11
                            Layout.leftMargin: 4
                        }
                    }
                }

                StackLayout {
                    id: pages
                    currentIndex: root.currentTab
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TweakPage {
                        focus: true
                        ColorControls {
                            theme: palette
                            Layout.fillWidth: true
                            Layout.margins: 30
                        }
                    }
                    TweakPage {
                        WifiPage {
                            theme: palette
                            Layout.fillWidth: true
                            Layout.margins: 30
                        }
                    }
                    TweakPage {
                        BluetoothPage {
                            theme: palette
                            Layout.fillWidth: true
                            Layout.margins: 30
                        }
                    }
                }
            }
        }
    }
}
