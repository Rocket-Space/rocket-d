#!/bin/bash
# ╔══════════════════════════════════════════════════════════╗
# ║                    ROCKET D SESSION                      ║
# ║       Lightweight KWin + Rocket D Shell                  ║
# ╚══════════════════════════════════════════════════════════╝

ROCKET_D_HOME="$HOME/.config/rocket-d"

# --- Environment Variables ---
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=RocketD
export XDG_SESSION_DESKTOP=RocketD
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export GDK_BACKEND=wayland,x11
export SDL_VIDEODRIVER=wayland
export MOZ_ENABLE_WAYLAND=1
export XCURSOR_SIZE=24
export XCURSOR_THEME=Adwaita
export ELECTRON_OZONE_PLATFORM_HINT=auto
export QT_QPA_PLATFORMTHEME=qt6ct
export XDG_CONFIG_HOME="$HOME/.config"

# --- Apply KWin config ---
if [ -f "$ROCKET_D_HOME/config/kwinrc" ]; then
    cp "$ROCKET_D_HOME/config/kwinrc" "$HOME/.config/kwinrc" 2>/dev/null || true
fi
if [ -f "$ROCKET_D_HOME/config/kwinrulesrc" ]; then
    cp "$ROCKET_D_HOME/config/kwinrulesrc" "$HOME/.config/kwinrulesrc" 2>/dev/null || true
fi
if [ -f "$ROCKET_D_HOME/config/kglobalshortcutsrc" ]; then
    cp "$ROCKET_D_HOME/config/kglobalshortcutsrc" "$HOME/.config/kglobalshortcutsrc" 2>/dev/null || true
fi

# --- Apply color scheme ---
if [ -f "$ROCKET_D_HOME/theme/kdeglobals" ]; then
    cp "$ROCKET_D_HOME/theme/kdeglobals" "$HOME/.config/kdeglobals" 2>/dev/null || true
fi

# --- Deploy app configs ---
mkdir -p "$HOME/.config/kitty"
cp "$ROCKET_D_HOME/config/kitty/kitty.conf" "$HOME/.config/kitty/" 2>/dev/null || true
