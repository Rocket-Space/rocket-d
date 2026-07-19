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
        var screen = workspace.activeOutput
        if (!screen) return

        var area = workspace.clientArea(MaximizeArea, screen, workspace.currentDesktop)
        var x = area.x + gap
        var y = area.y + gap
        var w = area.width - gap * 2
        var h = area.height - gap * 2

        var count = tiledWindows.length
        if (count === 0) return
        if (count === 1) {
            tiledWindows[0].frameGeometry = Qt.rect(x, y, w, h)
            return
        }

        splitArea(x, y, w, h, 0, tiledWindows)
    }

    function splitArea(x, y, w, h, depth, windows) {
        if (windows.length === 0) return
        if (windows.length === 1) {
            windows[0].frameGeometry = Qt.rect(x, y, w, h)
            return
        }

        var splitH = (depth % 2 === 0)

        if (splitH) {
            var leftW = Math.floor(w / 2)
            var rightW = w - leftW - gap
            windows[0].frameGeometry = Qt.rect(x, y, leftW, h)
            splitArea(x + leftW + gap, y, rightW, h, depth + 1, windows.slice(1))
        } else {
            var topH = Math.floor(h / 2)
            var bottomH = h - topH - gap
            windows[0].frameGeometry = Qt.rect(x, y, w, topH)
            splitArea(x, y + topH + gap, w, bottomH, depth + 1, windows.slice(1))
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
        rebuildLayout()
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
