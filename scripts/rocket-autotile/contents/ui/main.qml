import QtQuick
import org.kde.kwin

Item {
    id: root

    property var tiledWindows: []
    property int gap: 4
    property var filterApps: ["krunner", "yakuake", "kded", "polkit", "plasmashell", "kwin"]

    function isTileable(window) {
        if (!window.normalWindow) return false
        if (window.fullScreen) return false
        if (window.minimized) return false
        if (window.desktopWindow) return false
        if (window.dock) return false
        if (window.splash) return false
        if (window.toolbar) return false
        if (window.notification) return false
        if (window.onScreenDisplay) return false
        if (window.popupWindow) return false
        if (window.transient) return false

        for (var i = 0; i < filterApps.length; i++) {
            if (window.resourceClass.includes(filterApps[i])) return false
        }
        return true
    }

    function rebuildLayout() {
        var count = tiledWindows.length
        if (count === 0) return

        for (var i = 0; i < count; i++) {
            tiledWindows[i].maximize(true, true)
        }
    }

    function removeWindow(window) {
        var idx = tiledWindows.indexOf(window)
        if (idx >= 0) {
            tiledWindows.splice(idx, 1)
            rebuildLayout()
        }
    }

    function addWindow(window) {
        if (tiledWindows.indexOf(window) < 0) {
            tiledWindows.push(window)
        }
        window.maximize(true, true)
    }

    Connections {
        target: workspace
        function onWindowAdded(window) {
            if (!root.isTileable(window)) return
            root.addWindow(window)
        }
        function onWindowRemoved(window) {
            root.removeWindow(window)
        }
    }

    Component.onCompleted: {
        var clients = workspace.windows
        for (var i = 0; i < clients.length; i++) {
            if (root.isTileable(clients[i])) {
                root.addWindow(clients[i])
            }
        }
    }
}
