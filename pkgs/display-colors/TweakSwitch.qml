pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Switch {
    id: root
    required property Theme theme
    implicitWidth: 50
    implicitHeight: 30
    padding: 0
    indicator: Rectangle {
        implicitWidth: 50
        implicitHeight: 28
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        radius: 14
        color: root.checked ? root.theme.accent : root.theme.border
        opacity: root.enabled ? 1 : 0.45
        border.width: root.visualFocus ? 2 : 0
        border.color: root.theme.text
        Rectangle {
            width: 20
            height: 20
            x: root.checked ? parent.width - width - 4 : 4
            y: 4
            radius: 10
            color: root.checked ? root.theme.onAccent : root.theme.text
            Behavior on x {
                NumberAnimation {
                    duration: 120
                }
            }
        }
    }
}
