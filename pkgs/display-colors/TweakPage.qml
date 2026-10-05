pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Scrollable page that stretches its single column to the available width.
ScrollView {
    id: root
    default property alias content: column.data
    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    ColumnLayout {
        id: column
        width: root.availableWidth
        spacing: 0
    }
}
