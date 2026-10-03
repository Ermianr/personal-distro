pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    readonly property string fontFamily: "Rubik"
    property var colors: ({
            base: "#1e1e2e",
            mantle: "#181825",
            text: "#cdd6f4",
            subtext0: "#a6adc8",
            surface0: "#313244",
            surface1: "#45475a",
            blue: "#89b4fa",
            red: "#f38ba8"
        })
    readonly property color background: colors.base
    readonly property color sidebar: colors.mantle
    readonly property color text: colors.text
    readonly property color muted: colors.subtext0
    readonly property color surface: colors.surface0
    readonly property color border: colors.surface1
    readonly property color accent: colors.blue
    readonly property color error: colors.red

    // Share Matugen's generated palette without importing the shell or starting it.
    FileView {
        id: paletteFile
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
