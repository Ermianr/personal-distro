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
        implicitWidth: 940
        implicitHeight: 740
        minimumSize: Qt.size(780, 580)
        color: palette.background
        visible: true
        onClosed: Qt.quit()

        Rectangle {
            anchors.fill: parent
            color: palette.background

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: palette.sidebar

                    MouseArea {
                        anchors.fill: parent
                        onPressed: window.startSystemMove()
                        onDoubleClicked: window.maximized = !window.maximized
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 16
                        spacing: 12
                        Label {
                            text: "Personal Tweaks"
                            color: palette.text
                            font.family: palette.fontFamily
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                        TweakButton {
                            theme: palette
                            text: "−"
                            implicitWidth: 40
                            Accessible.name: "Minimizar"
                            onClicked: window.minimized = true
                        }
                        TweakButton {
                            theme: palette
                            text: "×"
                            implicitWidth: 40
                            Accessible.name: "Cerrar"
                            onClicked: Qt.quit()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    Rectangle {
                        Layout.preferredWidth: 210
                        Layout.fillHeight: true
                        color: palette.sidebar
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 16
                            Label {
                                text: "PERSONALIZACIÓN"
                                color: palette.muted
                                font.family: palette.fontFamily
                                font.pixelSize: 10
                                font.letterSpacing: 1.2
                                Layout.topMargin: 10
                                Layout.bottomMargin: 4
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 48
                                radius: 12
                                color: Qt.alpha(palette.accent, 0.13)
                                border.color: Qt.alpha(palette.accent, 0.25)
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10
                                    Rectangle {
                                        implicitWidth: 8
                                        implicitHeight: 8
                                        radius: 4
                                        color: palette.accent
                                    }
                                    Label {
                                        text: "Colores de pantalla"
                                        color: palette.accent
                                        font.family: palette.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                            Item {
                                Layout.fillHeight: true
                            }
                        }
                    }

                    ScrollView {
                        id: scrollView
                        focus: true
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ColumnLayout {
                            width: scrollView.availableWidth
                            spacing: 0
                            ColorControls {
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
}
