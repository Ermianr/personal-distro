pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

TextField {
    id: root
    required property Theme theme
    implicitHeight: 42
    leftPadding: 16
    rightPadding: 16
    color: theme.text
    placeholderTextColor: theme.muted
    selectionColor: theme.accent
    selectedTextColor: theme.onAccent
    font.family: theme.fontFamily
    font.pixelSize: 13
    background: Rectangle {
        radius: 10
        color: root.theme.surface
        border.color: root.activeFocus ? root.theme.accent : root.theme.border
    }
}
