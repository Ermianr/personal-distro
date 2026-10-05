pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// One network or device card: icon, title, status, trailing actions and an
// optional expanded body, such as a password form.
Rectangle {
    id: root
    required property Theme theme
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool expanded: false
    property alias actions: actionRow.data
    default property alias content: body.data

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 24
    radius: 14
    color: root.theme.surface
    border.color: root.active ? Qt.alpha(root.theme.accent, 0.6) : "transparent"

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                implicitWidth: 38
                implicitHeight: 38
                radius: 10
                color: root.active ? root.theme.accent : root.theme.border
                Text {
                    anchors.centerIn: parent
                    text: root.icon
                    color: root.active ? root.theme.onAccent : root.theme.text
                    font.family: root.theme.iconFamily
                    font.pixelSize: 18
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Label {
                    text: root.title
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    visible: text !== ""
                    text: root.subtitle
                    color: root.active ? root.theme.accent : root.theme.muted
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            RowLayout {
                id: actionRow
                spacing: 8
            }
        }

        ColumnLayout {
            id: body
            visible: root.expanded
            Layout.fillWidth: true
            spacing: 10
        }
    }
}
