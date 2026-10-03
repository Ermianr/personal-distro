pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Button {
    id: root
    required property Theme theme
    property bool accented: false
    implicitHeight: 40
    leftPadding: 16
    rightPadding: 16
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.45
    contentItem: Text {
        text: root.text
        color: root.accented ? root.theme.sidebar : root.theme.text
        font.family: root.theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 10
        color: root.accented ? root.theme.accent : (root.hovered || root.down ? root.theme.border : root.theme.surface)
        border.width: root.visualFocus ? 2 : 0
        border.color: root.theme.accent
    }
}
