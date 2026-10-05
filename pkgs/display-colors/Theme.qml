pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    readonly property string fontFamily: "Rubik"
    // Serpantinum ships this Nerd Font for its own icons.
    readonly property string iconFamily: "Iosevka Nerd Font"
    property var colors: ({
            base: "#1e1e2e",
            crust: "#11111b",
            text: "#cdd6f4",
            subtext0: "#a6adc8",
            surface0: "#313244",
            surface1: "#45475a",
            mauve: "#cba6f7",
            red: "#f38ba8"
        })
    readonly property color background: colors.base
    // Match the translucent sidebar and accent of Serpantinum's settings guide.
    readonly property color sidebar: Qt.alpha(colors.surface0, 0.4)
    readonly property color text: colors.text
    readonly property color muted: colors.subtext0
    readonly property color surface: colors.surface0
    readonly property color border: colors.surface1
    readonly property color accent: colors.mauve
    readonly property color onAccent: colors.crust
    readonly property color error: colors.red

    // Share Matugen's generated palette without importing the shell or starting it.
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/serpantinum/qs_matugen_colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (!data || typeof data !== "object" || Array.isArray(data))
                    throw new Error("Invalid Matugen palette");
                const palette = {};
                for (const key of Object.keys(root.colors)) {
                    if (typeof data[key] !== "string" || !/^#[0-9a-fA-F]{6}$/.test(data[key]))
                        throw new Error("Invalid Matugen color: " + key);
                    palette[key] = data[key];
                }
                root.colors = palette;
            } catch (error) {
                // Keep the last complete palette during partial writes.
                console.warn("Could not load Matugen palette: " + error);
            }
        }
    }
}
