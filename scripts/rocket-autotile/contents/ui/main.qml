import QtQuick
import org.kde.kwin

Item {
    id: root

    property var filterApps: ["krunner", "yakuake", "kded", "polkit", "plasmashell", "kwin"]

    Timer {
        id: maximizeTimer
        interval: 100
        property var pendingWindow: null
        repeat: false
        onTriggered: {
            if (pendingWindow) {
                pendingWindow.maximize(true, true)
                pendingWindow = null
            }
        }
    }

    Connections {
        target: workspace
        function onWindowAdded(window) {
            if (!window.normalWindow) return
            if (window.fullScreen) return
            if (window.minimized) return
            if (window.desktopWindow) return
            if (window.dock) return
            if (window.splash) return
            if (window.toolbar) return
            if (window.notification) return
            if (window.onScreenDisplay) return
            if (window.popupWindow) return
            if (window.transient) return

            var skip = false
            for (var i = 0; i < root.filterApps.length; i++) {
                if (window.resourceClass.includes(root.filterApps[i])) { skip = true; break }
            }
            if (skip) return

            maximizeTimer.pendingWindow = window
            maximizeTimer.restart()
        }
    }
}
