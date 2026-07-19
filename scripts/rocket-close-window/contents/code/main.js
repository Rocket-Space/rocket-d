// Rocket D - Close active window via DBus signal
// Native KWin JavaScript script

function closeActiveWindow() {
    var win = workspace.activeWindow;
    if (win && win.normalWindow && win.closeable) {
        win.close();  // Native gentle close
    }
}

// Listen for DBus signal from rocket-media-keys daemon
try {
    var dbus = QDBusConnection.sessionBus();
    dbus.connect("org.kde.rocket", "/CloseWindow", "org.kde.rocket.CloseWindow", "closeRequested", closeActiveWindow);
    print("Rocket Close Window: DBus signal connected");
} catch (e) {
    print("Rocket Close Window: DBus connect failed: " + e);
}

// Also register internal shortcut as fallback
try {
    registerShortcut("RocketCloseWindow", "Cerrar ventana activa (Rocket D)", "", closeActiveWindow);
} catch (e) {
    print("Rocket Close Window: registerShortcut failed: " + e);
}

print("Rocket Close Window script loaded");