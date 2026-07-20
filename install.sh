#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║                    ROCKET D INSTALLER                           ║
# ║       Lightweight KWin Desktop with Omarchy Visual Style        ║
# ║                                                                  ║
# ║  This installer sets up a complete Rocket D session:             ║
# ║  - KWin as compositor (no full KDE Plasma needed)               ║
# ║  - greetd display manager (no X11, single TTY)                  ║
# ║  - Waybar top bar (minimal resource usage)                      ║
# ║  - Omarchy-like dark forest visual style                        ║
# ║  - Blur, transparency, smooth animations                        ║
# ║  - Works on Arch Linux, Manjaro, EndeavourOS, CachyOS, etc.     ║
# ╚══════════════════════════════════════════════════════════════════╝

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ROCKET_D_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROCKET_D_HOME="$HOME/.config/rocket-d"
INSTALL_ERRORS=0

clean_old() {
    echo -e "${YELLOW}[CLEAN] Removing previous Rocket D installations...${NC}"

    # Kill running Rocket D processes
    killall -q waybar 2>/dev/null || true
    killall -q mako 2>/dev/null || true
    killall -q swaybg 2>/dev/null || true
    killall -q dunst 2>/dev/null || true

    # Unload old KWin scripts
    qdbus6 org.kde.KWin /Scripting unloadScript "tessera" 2>/dev/null || true
    qdbus6 org.kde.KWin /Scripting unloadScript "rocket-autotile" 2>/dev/null || true
    qdbus6 org.kde.KWin /Scripting unloadScript "rocket-dump" 2>/dev/null || true
    qdbus6 org.kde.KWin /Scripting unloadScript "rocket-shot" 2>/dev/null || true
    qdbus6 org.kde.KWin /Scripting unloadScript "rocket-shot2" 2>/dev/null || true
    qdbus6 org.kde.KWin /Scripting unloadScript "screenshot" 2>/dev/null || true
    sleep 0.5

    # Remove old KWin scripts
    rm -rf "$HOME/.local/share/kwin/scripts/tessera"
    rm -rf "$HOME/.local/share/kwin/scripts/rocket-dump"
    rm -rf "$HOME/.local/share/kwin/scripts/rocket-shot"
    rm -rf "$HOME/.local/share/kwin/scripts/rocket-shot2"
    rm -rf "$HOME/.local/share/kwin/scripts/screenshot"
    rm -rf "$HOME/.local/share/kwin/scripts/rocket-autotile"

    # Remove old session/helper files
    sudo rm -f /usr/local/bin/rocket-d-session
    sudo rm -f /usr/local/bin/rocket-d-config
    sudo rm -f /usr/local/bin/rocket-d-uninstall
    sudo rm -f /usr/local/bin/rocket-d-reload-tessera

    # Remove old desktop entries
    sudo rm -f /usr/share/wayland-sessions/rocket-d.desktop
    sudo rm -f /usr/share/wayland-sessions/rocket-desktop.desktop

    # Remove old configs (will be reinstalled fresh)
    rm -f "$HOME/.config/kwinrc"
    rm -f "$HOME/.config/kglobalshortcutsrc"
    rm -f "$HOME/.config/kwinrulesrc"
    rm -f "$HOME/.config/kscreenlockerrc"
    rm -f "$HOME/.config/kdeglobals"

    # Remove old rocket-d home (will be recreated)
    rm -rf "$ROCKET_D_HOME"

    echo -e "${GREEN}  Clean complete${NC}"
}

print_banner() {
    echo -e "${GREEN}"
    cat << 'EOF'
    ██████╗  ██████╗ ██████╗ ███████╗██╗  ██╗██╗███████╗██╗     ██╗
    ██╔══██╗██╔═══██╗██╔══██╗██╔════╝██║  ██║██║██╔════╝██║     ██║
    ██████╔╝██║   ██║██████╔╝███████╗███████║██║█████╗  ██║     ██║
    ██╔══██╗██║   ██║██╔══██╗╚════██║██╔══██║██║██╔══╝  ██║     ██║
    ██║  ██║╚██████╔╝██║  ██║███████║██║  ██║██║███████╗███████╗███████╗
    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚══════╝
    D  E  S  K  T  O  P
    Lightweight · Fast · Beautiful
EOF
    echo -e "${NC}"
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}[ERROR] Do not run this installer as root!${NC}"
        echo -e "${YELLOW}Run as normal user. It will ask for sudo when needed.${NC}"
        exit 1
    fi
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID}"
        DISTRO_LIKE="${ID_LIKE:-}"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE=""
    fi

    if [[ "$DISTRO_ID" == "arch" || "$DISTRO_LIKE" == *"arch"* || "$DISTRO_LIKE" == *"archlinux"* ]]; then
        PKG_MANAGER="pacman"
    elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_LIKE" == *"fedora"* || "$DISTRO_LIKE" == *"rhel"* ]]; then
        PKG_MANAGER="dnf"
    elif [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "debian" || "$DISTRO_LIKE" == *"debian"* || "$DISTRO_LIKE" == *"ubuntu"* ]]; then
        PKG_MANAGER="apt"
    else
        echo -e "${YELLOW}[WARN] Unknown distro: $DISTRO_ID. Will try pacman.${NC}"
        PKG_MANAGER="pacman"
    fi

    echo -e "${CYAN}Detected: ${BOLD}$DISTRO_ID${NC} (package manager: $PKG_MANAGER)"
}

install_pkg_group() {
    local group_name="$1"
    shift
    local pkgs=("$@")

    echo -e "  ${CYAN}▸ $group_name${NC}"
    for pkg in "${pkgs[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            echo -e "    ${GREEN}✓${NC} $pkg (already installed)"
        else
            echo -e "    ${YELLOW}↓${NC} $pkg"
        fi
    done

    if sudo pacman -S --needed --noconfirm "${pkgs[@]}"; then
        echo -e "  ${GREEN}  $group_name: OK${NC}"
    else
        echo -e "  ${RED}  $group_name: Some packages failed (continuing...)${NC}"
        INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    fi
    echo ""
}

install_packages_arch() {
    echo -e "${GREEN}[1/7] Installing packages with pacman...${NC}"
    echo -e "${YELLOW}Using --needed: already-installed packages will be skipped.${NC}"
    echo ""

    # Group 1: KWin core + Qt/Wayland
    install_pkg_group "KWin Core & Qt" \
        "kwin" \
        "kdecoration" \
        "qqc2-breeze-style" \
        "qt6-wayland" \
        "qt6-base" \
        "qt6-declarative" \
        "qt6-svg" \
        "qt6-tools" \
        "qt6-5compat"

    # Group 2: Breeze theme
    install_pkg_group "Breeze Theme" \
        "breeze" \
        "breeze-gtk" \
        "breeze-icons"

    # Group 3: Desktop tools
    install_pkg_group "Desktop Tools" \
        "waybar" \
        "wofi" \
        "mako" \
        "kitty" \
        "swaybg" \
        "btop" \
        "thunar" \
        "tumbler" \
        "polkit-gnome" \
        "xdg-desktop-portal" \
        "xdg-desktop-portal-kde" \
        "xdg-desktop-portal-wlr" \
        "wtype" \
        "wl-clipboard"

    # Group 4: Fonts
    install_pkg_group "Fonts" \
        "noto-fonts" \
        "noto-fonts-emoji" \
        "ttf-jetbrains-mono-nerd" \
        "adwaita-cursors" \
        "adwaita-icon-theme"

    # Group 5: Icons and theming
    install_pkg_group "Icons & Theming" \
        "papirus-icon-theme" \
        "kvantum" \
        "kvantum-qt5" \
        "qt6ct" \
        "qt5ct"

    # Group 5.5: Build tools
    install_pkg_group "Build Tools" \
        "zip" \
        "gcc" \
        "make"

    # Group 6: Audio (PipeWire)
    install_pkg_group "Audio (PipeWire)" \
        "pipewire" \
        "pipewire-pulse" \
        "wireplumber" \
        "pamixer" \
        "pavucontrol" \
        "libpipewire"

    # Group 7: Display manager + Network
    install_pkg_group "Display Manager & Network" \
        "greetd" \
        "greetd-tuigreet" \
        "networkmanager" \
        "nm-connection-editor"

    # Retry any missing critical packages individually
    echo -e "${YELLOW}Retrying missing critical packages...${NC}"
    CRITICAL_PKGS=("mako" "waybar" "wofi" "kitty" "swaybg" "btop" "kwin" "pipewire" "greetd" "greetd-tuigreet")
    RETRY_PKGS=()
    for pkg in "${CRITICAL_PKGS[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            echo -e "  ${YELLOW}Retry: $pkg${NC}"
            RETRY_PKGS+=("$pkg")
        fi
    done
    if [ ${#RETRY_PKGS[@]} -gt 0 ]; then
        sudo pacman -S --needed --noconfirm "${RETRY_PKGS[@]}" || true
    fi
}

install_packages_fedora() {
    echo -e "${GREEN}[1/7] Installing packages with dnf...${NC}"

    ALL_PKGS=(
        "kwin"
        "qqc2-breeze-style"
        "qt6-wayland"
        "qt6-qtbase"
        "qt6-qtdeclarative"
        "kdecoration"
        "breeze-icon-theme"
        "waybar"
        "wofi"
        "mako"
        "kitty"
        "swaybg"
        "btop"
        "polkit"
        "xdg-desktop-portal"
        "xdg-desktop-portal-kde"
        "google-noto-sans-fonts"
        "google-noto-emoji-color-fonts"
        "google-noto-mono-fonts"
        "papirus-icon-theme"
        "adwaita-icon-theme"
        "pipewire"
        "wireplumber"
        "pipewire-pulse-audio"
        "pamixer"
        "NetworkManager"
        "nm-connection-editor"
        "npm"
        "make"
        "zip"
    )

    sudo dnf install -y "${ALL_PKGS[@]}" || {
        echo -e "${YELLOW}[WARN] Some packages failed. Continuing...${NC}"
        INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    }
}

install_packages_debian() {
    echo -e "${GREEN}[1/7] Installing packages with apt...${NC}"

    sudo apt update

    ALL_PKGS=(
        "kwin-wayland"
        "libkdecorations2-5v5"
        "qt6-wayland"
        "qt6-base-dev"
        "qml6-module-qtquick"
        "breeze-cursor-theme"
        "breeze-icon-theme"
        "waybar"
        "wofi"
        "mako"
        "kitty"
        "swaybg"
        "btop"
        "polkit-gnome"
        "xdg-desktop-portal"
        "xdg-desktop-portal-kde"
        "fonts-noto-color-emoji"
        "fonts-jetbrains-mono"
        "papirus-icon-theme"
        "pipewire"
        "wireplumber"
        "pipewire-pulse"
        "pamixer"
        "network-manager"
        "npm"
        "make"
        "zip"
    )

    sudo apt install -y "${ALL_PKGS[@]}" || {
        echo -e "${YELLOW}[WARN] Some packages failed. Continuing...${NC}"
        INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    }
}

install_configs() {
    echo -e "${GREEN}[2/7] Installing Rocket D configurations...${NC}"

    # Backup existing configs
    if [ -d "$ROCKET_D_HOME" ]; then
        BACKUP="$ROCKET_D_HOME.backup.$(date +%Y%m%d%H%M%S)"
        echo -e "${YELLOW}Backing up existing config to: $BACKUP${NC}"
        mv "$ROCKET_D_HOME" "$BACKUP"
    fi

    # Create directories
    mkdir -p "$ROCKET_D_HOME"/{config/{waybar,wofi,kitty,mako},session,theme/{aurorae},wallpapers,scripts}

    echo -e "  Installing KWin config..."
    cp "$ROCKET_D_SOURCE/config/kwinrc" "$ROCKET_D_HOME/config/"
    cp "$ROCKET_D_SOURCE/config/kwinrulesrc" "$ROCKET_D_HOME/config/"
    cp "$ROCKET_D_SOURCE/config/kglobalshortcutsrc" "$ROCKET_D_HOME/config/" 2>/dev/null || true

    echo -e "  Installing Waybar config..."
    cp "$ROCKET_D_SOURCE/config/waybar/config.jsonc" "$ROCKET_D_HOME/config/waybar/"
    cp "$ROCKET_D_SOURCE/config/waybar/style.css" "$ROCKET_D_HOME/config/waybar/"

    echo -e "  Installing Wofi config..."
    mkdir -p "$ROCKET_D_HOME/config/wofi"
    cp "$ROCKET_D_SOURCE/config/wofi/config" "$ROCKET_D_HOME/config/wofi/" 2>/dev/null || true
    cp "$ROCKET_D_SOURCE/config/wofi/config-menu" "$ROCKET_D_HOME/config/wofi/" 2>/dev/null || true
    cp "$ROCKET_D_SOURCE/config/wofi/style.css" "$ROCKET_D_HOME/config/wofi/" 2>/dev/null || true
    cp "$ROCKET_D_SOURCE/config/wofi/style-menu.css" "$ROCKET_D_HOME/config/wofi/" 2>/dev/null || true

    echo -e "  Installing Kitty config..."
    cp "$ROCKET_D_SOURCE/config/kitty/kitty.conf" "$ROCKET_D_HOME/config/kitty/"

    echo -e "  Installing Mako config..."
    cp "$ROCKET_D_SOURCE/config/mako/config" "$ROCKET_D_HOME/config/mako/"

    echo -e "  Installing Screen Locker config..."
    cp "$ROCKET_D_SOURCE/config/kscreenlockerrc" "$ROCKET_D_HOME/config/"

    echo -e "  Installing Thunar config..."
    mkdir -p "$ROCKET_D_HOME/config/Thunar"
    cp "$ROCKET_D_SOURCE/config/Thunar/uca.xml" "$ROCKET_D_HOME/config/Thunar/"

    echo -e "  Installing XFCE4 helpers (terminal default)..."
    mkdir -p "$ROCKET_D_HOME/config/xfce4"
    cp "$ROCKET_D_SOURCE/config/xfce4/helpers.rc" "$ROCKET_D_HOME/config/xfce4/"

    echo -e "  Installing cachy-update desktop file..."
    mkdir -p "$ROCKET_D_HOME/config"
    cp "$ROCKET_D_SOURCE/config/cachy-update.desktop" "$ROCKET_D_HOME/config/"

    echo -e "  Installing systemd overrides..."
    mkdir -p "$ROCKET_D_HOME/config/systemd"
    cp "$ROCKET_D_SOURCE/config/systemd/arch-update-tray-override.conf" "$ROCKET_D_HOME/config/systemd/"

    echo -e "  Installing color scheme..."
    cp "$ROCKET_D_SOURCE/theme/kdeglobals" "$ROCKET_D_HOME/theme/"
    cp "$ROCKET_D_SOURCE/theme/aurorae/rocket-drc" "$ROCKET_D_HOME/theme/aurorae/"

    echo -e "  Installing session scripts..."
    cp "$ROCKET_D_SOURCE/session/rocket-d-start.sh" "$ROCKET_D_HOME/session/"
    chmod +x "$ROCKET_D_HOME/session/"*.sh

    echo -e "  Installing Rocket Auto-Tile script..."
    mkdir -p "$ROCKET_D_HOME/scripts/rocket-autotile"
    cp -r "$ROCKET_D_SOURCE/scripts/rocket-autotile/"* "$ROCKET_D_HOME/scripts/rocket-autotile/" 2>/dev/null || true

    echo -e "  Installing helper scripts..."
    cp "$ROCKET_D_SOURCE/scripts/"*.sh "$ROCKET_D_HOME/scripts/" 2>/dev/null || true
    chmod +x "$ROCKET_D_HOME/scripts/"*.sh 2>/dev/null || true
    cp "$ROCKET_D_SOURCE/scripts/rocket-d-terminal" "$ROCKET_D_HOME/scripts/" 2>/dev/null || true
    chmod +x "$ROCKET_D_HOME/scripts/rocket-d-terminal" 2>/dev/null || true
    cp "$ROCKET_D_SOURCE/scripts/rocket-d-battery-info" "$ROCKET_D_HOME/scripts/" 2>/dev/null || true
    chmod +x "$ROCKET_D_HOME/scripts/rocket-d-battery-info" 2>/dev/null || true
    cp "$ROCKET_D_SOURCE/scripts/rocket-d-menu" "$ROCKET_D_HOME/scripts/" 2>/dev/null || true
    chmod +x "$ROCKET_D_HOME/scripts/rocket-d-menu" 2>/dev/null || true
    cp "$ROCKET_D_SOURCE/scripts/waybar-updates" "$ROCKET_D_HOME/scripts/" 2>/dev/null || true
    chmod +x "$ROCKET_D_HOME/scripts/waybar-updates" 2>/dev/null || true
    cp "$ROCKET_D_SOURCE/scripts/waybar-workspaces" "$ROCKET_D_HOME/scripts/" 2>/dev/null || true
    chmod +x "$ROCKET_D_HOME/scripts/waybar-workspaces" 2>/dev/null || true

    # Apply configs to ~/.config/ so each app finds them on next login
    echo -e "  Deploying configs to app locations..."

    # KWin configs
    cp "$ROCKET_D_HOME/config/kwinrc" "$HOME/.config/kwinrc" 2>/dev/null || true
    cp "$ROCKET_D_HOME/config/kwinrulesrc" "$HOME/.config/kwinrulesrc" 2>/dev/null || true
    cp "$ROCKET_D_HOME/config/kglobalshortcutsrc" "$HOME/.config/kglobalshortcutsrc" 2>/dev/null || true
    cp "$ROCKET_D_HOME/theme/kdeglobals" "$HOME/.config/kdeglobals" 2>/dev/null || true
    
    # KWin config already copied above
    echo -e "  KWin config applied"

    # Waybar
    mkdir -p "$HOME/.config/waybar"
    cp "$ROCKET_D_HOME/config/waybar/config.jsonc" "$HOME/.config/waybar/"
    cp "$ROCKET_D_HOME/config/waybar/style.css" "$HOME/.config/waybar/"

    # Wofi
    mkdir -p "$HOME/.config/wofi"
    cp "$ROCKET_D_HOME/config/wofi/config" "$HOME/.config/wofi/" 2>/dev/null || true
    cp "$ROCKET_D_HOME/config/wofi/config-menu" "$HOME/.config/wofi/" 2>/dev/null || true
    cp "$ROCKET_D_HOME/config/wofi/style.css" "$HOME/.config/wofi/" 2>/dev/null || true
    cp "$ROCKET_D_HOME/config/wofi/style-menu.css" "$HOME/.config/wofi/" 2>/dev/null || true

    # KWin shortcuts (disable ALL)
    cp "$ROCKET_D_HOME/config/kglobalshortcutsrc" "$HOME/.config/kglobalshortcutsrc" 2>/dev/null || true

    # Kitty
    mkdir -p "$HOME/.config/kitty"
    cp "$ROCKET_D_HOME/config/kitty/kitty.conf" "$HOME/.config/kitty/"

    # Mako
    mkdir -p "$HOME/.config/mako"
    cp "$ROCKET_D_HOME/config/mako/config" "$HOME/.config/mako/"

    # Screen Locker (disable - no plasma-workspace greeter)
    cp "$ROCKET_D_HOME/config/kscreenlockerrc" "$HOME/.config/kscreenlockerrc" 2>/dev/null || true

    # Thunar (terminal + context menu actions)
    mkdir -p "$HOME/.config/Thunar"
    cp "$ROCKET_D_HOME/config/Thunar/uca.xml" "$HOME/.config/Thunar/"

    # XFCE4 helpers (sets kitty as default terminal for exo-open)
    mkdir -p "$HOME/.config/xfce4"
    cp "$ROCKET_D_HOME/config/xfce4/helpers.rc" "$HOME/.config/xfce4/"

    # CachyOS Update desktop file (for wofi/apps)
    mkdir -p "$HOME/.local/share/applications"
    cp "$ROCKET_D_HOME/config/cachy-update.desktop" "$HOME/.local/share/applications/"

    # CachyOS Update tray systemd override (Wayland env vars)
    mkdir -p "$HOME/.config/systemd/user/arch-update-tray.service.d"
    cp "$ROCKET_D_HOME/config/systemd/arch-update-tray-override.conf" "$HOME/.config/systemd/user/arch-update-tray.service.d/override.conf"

    # Enable cachy-update tray
    if command -v systemctl &>/dev/null; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable arch-update-tray 2>/dev/null || true
    fi

    # Fix .bash_profile to not interfere with display manager session startup
    if [ -f "$HOME/.bash_profile" ]; then
        if grep -q 'exec systemd-cat.*systemd --user' "$HOME/.bash_profile" && \
           ! grep -q 'DESKTOP_SESSION' "$HOME/.bash_profile"; then
            cp "$HOME/.bash_profile" "$HOME/.bash_profile.bak"
            sed -i 's/\[\[ -z $DISPLAY && -z $WAYLAND_DISPLAY && \$(tty) = \/dev\/tty1 \]\]/[[ -z $DISPLAY \&\& -z $WAYLAND_DISPLAY \&\& -z $DESKTOP_SESSION \&\& $(tty) = \/dev\/tty1 ]]/' "$HOME/.bash_profile"
            echo -e "  Fixed .bash_profile for display manager compatibility"
        fi
    fi

    echo -e "${GREEN}  Configurations installed.${NC}"
}

install_session() {
    echo -e "${GREEN}[3/7] Installing session launcher...${NC}"

    sudo cp "$ROCKET_D_SOURCE/session/rocket-d-session" /usr/local/bin/rocket-d-session
    sudo chmod +x /usr/local/bin/rocket-d-session

    echo -e "${GREEN}  Session file installed to /usr/local/bin/rocket-d-session${NC}"

    configure_display_manager
}

configure_display_manager() {
    echo -e "${GREEN}[3.5/7] Configuring greetd display manager...${NC}"

    if [ -f /usr/bin/greetd ] || pacman -Qi greetd &>/dev/null; then
        # Stop and disable SDDM if present
        if systemctl is-active --quiet sddm.service 2>/dev/null; then
            sudo systemctl stop sddm.service 2>/dev/null || true
            sudo systemctl disable sddm.service 2>/dev/null || true
            echo -e "  ${YELLOW}SDDM stopped and disabled${NC}"
        fi

        # Stop and disable any other display managers
        for dm in sddm gdm lightdm lxdm; do
            if systemctl is-active --quiet "${dm}.service" 2>/dev/null; then
                sudo systemctl stop "${dm}.service" 2>/dev/null || true
                sudo systemctl disable "${dm}.service" 2>/dev/null || true
            fi
        done

        # Configure greetd for direct autologin (no greeter, single TTY)
        sudo mkdir -p /etc/greetd
        sudo tee /etc/greetd/config.toml > /dev/null << GREETD
[terminal]
vt = 1

[default_session]
command = "/usr/local/bin/rocket-d-session"
user = "$USER"
GREETD

        # Enable greetd
        sudo systemctl enable greetd.service 2>/dev/null || true

        echo -e "  greetd configured: direct autologin for $USER"
        echo -e "  No greeter, no X11, single TTY"

    else
        echo -e "  ${YELLOW}greetd not found. Session installed but no display manager configured.${NC}"
        echo -e "  Run: rocket-d-session from a TTY to start"
    fi
}

install_autotile() {
    echo -e "${GREEN}[3.7/7] Installing Rocket Auto-Tile (dwindle tiling)...${NC}"

    AUTOTILE_DIR="$ROCKET_D_SOURCE/scripts/rocket-autotile"
    if [ ! -d "$AUTOTILE_DIR" ]; then
        echo -e "  ${YELLOW}Rocket Auto-Tile source not found. Tiling will not be available.${NC}"
        return 1
    fi

    AUTOTILE_PKG="/tmp/rocket-autotile.kwinscript"
    rm -f "$AUTOTILE_PKG"

    (cd "$AUTOTILE_DIR" && zip -rq "$AUTOTILE_PKG" .) 2>/dev/null || true

    if [ -f "$AUTOTILE_PKG" ]; then
        kpackagetool6 -t KWin/Script -i "$AUTOTILE_PKG" 2>/dev/null || \
        kpackagetool6 -t KWin/Script -u "$AUTOTILE_PKG" 2>/dev/null || true
        rm -f "$AUTOTILE_PKG"
    fi

    if [ ! -d "$HOME/.local/share/kwin/scripts/rocket-autotile" ]; then
        mkdir -p "$HOME/.local/share/kwin/scripts/rocket-autotile"
        cp -r "$AUTOTILE_DIR/"* "$HOME/.local/share/kwin/scripts/rocket-autotile/"
    fi

    echo -e "  ${GREEN}Rocket Auto-Tile installed${NC}"
}

install_media_keys() {
    echo -e "${GREEN}[3.8/7] Building Rocket Media Keys daemon...${NC}"

    local SRC="$ROCKET_D_SOURCE/scripts/rocket-media-keys.c"
    local BIN="/usr/local/bin/rocket-media-keys"

    if [ ! -f "$SRC" ]; then
        echo -e "  ${YELLOW}Source not found: $SRC${NC}"
        return 1
    fi

    if ! command -v gcc &>/dev/null; then
        echo -e "  ${YELLOW}gcc not found. Installing build tools...${NC}"
        sudo pacman -S --needed --noconfirm gcc make 2>/dev/null || true
    fi

    if command -v gcc &>/dev/null; then
        gcc -O2 -o /tmp/rocket-media-keys "$SRC" 2>/dev/null
        if [ $? -eq 0 ]; then
            sudo cp /tmp/rocket-media-keys "$BIN"
            sudo chmod +x "$BIN"
            echo -e "  ${GREEN}Rocket Media Keys installed to $BIN${NC}"
        else
            echo -e "  ${RED}Compilation failed${NC}"
            return 1
        fi
    else
        echo -e "  ${RED}gcc not available, cannot build media keys daemon${NC}"
        return 1
    fi
}

install_wallpapers() {
    echo -e "${GREEN}[4/7] Setting up wallpapers...${NC}"

    if [ ! -f "$ROCKET_D_HOME/wallpapers/default.png" ]; then
        if command -v convert &>/dev/null; then
            convert -size 1920x1080 \
                gradient:"#0a0c10"-"#1a2030" \
                "$ROCKET_D_HOME/wallpapers/default.png" 2>/dev/null || true
            echo -e "  Generated default wallpaper"
        else
            echo -e "  ${YELLOW}ImageMagick not found, skipping wallpaper generation${NC}"
        fi
    fi

    if [ -d "$ROCKET_D_SOURCE/wallpapers" ]; then
        cp "$ROCKET_D_SOURCE/wallpapers/"* "$ROCKET_D_HOME/wallpapers/" 2>/dev/null || true
    fi
}

enable_services() {
    echo -e "${GREEN}[5/7] Enabling services...${NC}"

    if systemctl list-unit-files | grep -q NetworkManager.service; then
        sudo systemctl enable --now NetworkManager.service 2>/dev/null || true
        echo -e "  NetworkManager enabled"
    fi

    if command -v pipewire &>/dev/null; then
        systemctl --user enable --now pipewire.service 2>/dev/null || true
        systemctl --user enable --now pipewire-pulse.service 2>/dev/null || true
        systemctl --user enable --now wireplumber.service 2>/dev/null || true
        echo -e "  PipeWire audio enabled"
    fi
}

install_helper_scripts() {
    echo -e "${GREEN}[5.5/7] Creating helper scripts...${NC}"

    sudo tee /usr/local/bin/rocket-d-config > /dev/null << 'SCRIPT'
#!/bin/bash
if command -v yazi &>/dev/null; then
    rocket-d-terminal yazi "$HOME/.config/rocket-d"
elif command -v ranger &>/dev/null; then
    rocket-d-terminal ranger "$HOME/.config/rocket-d"
else
    rocket-d-terminal bash -c "cd ~/.config/rocket-d && ls -la && exec bash"
fi
SCRIPT
    sudo chmod +x /usr/local/bin/rocket-d-config

    sudo tee /usr/local/bin/rocket-d-uninstall > /dev/null << 'UNINSTALL'
#!/bin/bash
echo "Rocket D Uninstaller"
echo "===================="
echo "This will remove Rocket D session files."
echo "Configs in ~/.config/rocket-d will NOT be deleted."
echo ""
read -p "Continue? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo rm -f /usr/local/bin/rocket-d-session
    sudo rm -f /usr/local/bin/rocket-d-config
    sudo rm -f /usr/local/bin/rocket-d-uninstall
    sudo rm -f /usr/share/wayland-sessions/rocket-d.desktop
    echo "Rocket D session removed."
    echo "Config files kept at ~/.config/rocket-d"
fi
UNINSTALL
    sudo chmod +x /usr/local/bin/rocket-d-uninstall
}

verify_installation() {
    echo -e "${GREEN}[6/7] Verifying installation...${NC}"

    local missing=0

    echo -e "${BOLD}Checking critical packages:${NC}"
    for pkg in kwin waybar wofi kitty swaybg mako pipewire greetd greetd-tuigreet; do
        if command -v "$pkg" &>/dev/null || pacman -Qi "$pkg" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $pkg"
        else
            echo -e "  ${RED}✗${NC} $pkg ${RED}(MISSING)${NC}"
            missing=$((missing + 1))
        fi
    done

    echo ""
    echo -e "${BOLD}Checking config files:${NC}"
    for f in \
        "$ROCKET_D_HOME/config/kwinrc" \
        "$ROCKET_D_HOME/config/kwinrulesrc" \
        "$ROCKET_D_HOME/config/kglobalshortcutsrc" \
        "$ROCKET_D_HOME/config/waybar/config.jsonc" \
        "$ROCKET_D_HOME/config/waybar/style.css" \
        "$ROCKET_D_HOME/config/wofi/config" \
        "$ROCKET_D_HOME/config/wofi/style.css" \
        "$ROCKET_D_HOME/config/kitty/kitty.conf" \
        "$ROCKET_D_HOME/config/mako/config" \
        "$ROCKET_D_HOME/scripts/rocket-autotile/metadata.json" \
        "$ROCKET_D_HOME/session/rocket-d-start.sh" \
        "$ROCKET_D_HOME/theme/kdeglobals" \
        "$ROCKET_D_HOME/wallpapers/default.png" \
        "/usr/local/bin/rocket-d-session" \
        "/etc/greetd/config.toml" \
        "$HOME/.local/share/kwin/scripts/rocket-autotile/metadata.json"; do
        if [ -f "$f" ]; then
            echo -e "  ${GREEN}✓${NC} $(basename "$f")"
        else
            echo -e "  ${RED}✗${NC} $f ${RED}(MISSING)${NC}"
            missing=$((missing + 1))
        fi
    done

    echo ""
    if [ $missing -gt 0 ]; then
        echo -e "${RED}${BOLD}Warning: $missing items are missing.${NC}"
        echo -e "${YELLOW}Run the installer again or install missing packages manually.${NC}"
    else
        echo -e "${GREEN}${BOLD}All checks passed!${NC}"
    fi
}

print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════╗
    ║           ROCKET D - Installation Complete!              ║
    ╚══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo -e "${BOLD}ROCKET D Desktop is now installed!${NC}"
    echo ""
    echo -e "${CYAN}To use:${NC}"
    echo -e "  Just ${BOLD}reboot${NC} - Rocket D loads automatically on boot"
    echo ""
    echo -e "${CYAN}First login tips:${NC}"
    echo -e "  - Click the ${GREEN}R${NC} logo on the bar to open the app launcher"
    echo -e "  - Right-click the R logo to open a terminal"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo -e "  - ${BOLD}rocket-d-session${NC}        - Start session from TTY"
    echo -e "  - ${BOLD}rocket-d-config${NC}         - Open config folder"
    echo -e "  - ${BOLD}rocket-d-uninstall${NC}      - Remove Rocket D"
    echo ""
    echo -e "${CYAN}Tiling:${NC}"
    echo -e "  ${BOLD}Rocket Auto-Tile${NC} enabled (dwindle-style, auto-tiles new windows)"
    echo -e "  ${BOLD}Meta+Left/Right/Up/Down${NC} - Quick tile to screen edge"
    echo -e "  ${BOLD}Meta+T${NC}                  - Toggle tile editor"
    echo ""
    echo -e "${CYAN}Config location:${NC} ${BOLD}$ROCKET_D_HOME${NC}"
    echo -e "${CYAN}Waybar config:${NC}   ${BOLD}$ROCKET_D_HOME/config/waybar/${NC}"
    echo -e "${CYAN}KWin config:${NC}     ${BOLD}$ROCKET_D_HOME/config/kwinrc${NC}"
    echo ""
    if [ $INSTALL_ERRORS -gt 0 ]; then
        echo -e "${YELLOW}Warning: Some package groups had errors. You may need to install them manually.${NC}"
    fi
    echo ""
}

# === MAIN ===
print_banner
check_root
detect_distro
clean_old

echo ""
echo -e "${BOLD}Rocket D will install:${NC}"
echo -e "  - KWin compositor (lightweight, no full Plasma)"
echo -e "  - greetd display manager (no X11, single TTY, fast boot)"
echo -e "  - Rocket Auto-Tile (dwindle auto-tiling for KWin)"
echo -e "  - Waybar (minimal top bar)"
echo -e "  - Kitty (fast terminal)"
echo -e "  - Wofi (app launcher - Wayland native)"
echo -e "  - Mako (notifications)"
echo -e "  - Omarchy dark forest theme"
echo -e "  - Blur, transparency, smooth animations"
echo -e "  - ALL keyboard shortcuts disabled (no Meta+L, no window keys)"
echo -e "  - PipeWire audio"
echo ""

read -p "$(echo -e ${BOLD}'Proceed with installation? (y/N): '${NC})" -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

case "$PKG_MANAGER" in
    pacman)
        install_packages_arch
        ;;
    dnf)
        install_packages_fedora
        ;;
    apt)
        install_packages_debian
        ;;
esac

install_configs
install_session
install_autotile
install_media_keys
install_wallpapers
enable_services
install_helper_scripts
verify_installation
print_summary
