#!/usr/bin/env bash
# =============================================================================
# CarMedia Pro — Installer
# =============================================================================
# Usage:
#   git clone <repo> && cd carMedia-Downloader && bash install.sh
#
# What this does:
#   1. Detects your distro (apt/dnf/pacman)
#   2. Installs: ffmpeg, yad, python3-pip
#   3. Installs yt-dlp via pip (gets latest, not stale distro package)
#   4. Makes all scripts executable
#   5. Creates ~/.local/share/applications/carmedia.desktop  (app launcher)
#   6. Creates ~/Desktop/CarMedia.desktop shortcut (if Desktop exists)
#   7. Writes a default config if none exists
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}══ $* ══${RESET}"; }

# ── Resolve install dir (the directory containing this script) ───────────────
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${INSTALL_DIR}/main.sh"
CONFIG_FILE="${INSTALL_DIR}/config/settings.conf"

echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║        CarMedia Pro  —  Installer     ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${RESET}"

# ── 1. Detect package manager ─────────────────────────────────────────────────
header "Detecting system"

PKG_MGR=""
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
    info "Package manager: apt (Debian/Ubuntu/Mint)"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
    info "Package manager: dnf (Fedora/RHEL)"
elif command -v pacman &>/dev/null; then
    PKG_MGR="pacman"
    info "Package manager: pacman (Arch/Manjaro)"
elif command -v zypper &>/dev/null; then
    PKG_MGR="zypper"
    info "Package manager: zypper (openSUSE)"
else
    warn "Could not detect package manager — will try pip for yt-dlp only."
    warn "Please install ffmpeg and yad manually if missing."
fi

# ── 2. Install system packages ────────────────────────────────────────────────
header "Installing system dependencies"

install_pkg() {
    local pkg="$1"
    info "Installing $pkg..."
    case "$PKG_MGR" in
        apt)     sudo apt-get install -y "$pkg" ;;
        dnf)     sudo dnf install -y "$pkg" ;;
        pacman)  sudo pacman -S --noconfirm "$pkg" ;;
        zypper)  sudo zypper install -y "$pkg" ;;
        *)       warn "Skipping $pkg — no supported package manager found" ; return 1 ;;
    esac
}

# ffmpeg — required for merging video+audio streams
if command -v ffmpeg &>/dev/null; then
    success "ffmpeg already installed ($(ffmpeg -version 2>&1 | head -1 | cut -d' ' -f3))"
else
    install_pkg ffmpeg && success "ffmpeg installed" || error "ffmpeg install failed — downloads will not merge properly"
fi

# yad — GUI toolkit used for all dialogs
if command -v yad &>/dev/null; then
    success "yad already installed ($(yad --version 2>/dev/null || echo 'unknown version'))"
else
    case "$PKG_MGR" in
        apt)    install_pkg yad ;;
        dnf)    install_pkg yad || { warn "yad not in default repos — trying copr"; sudo dnf copr enable -y apchmyt/yad 2>/dev/null && install_pkg yad; } ;;
        pacman) install_pkg yad ;;
        zypper) install_pkg yad ;;
        *)      warn "Please install yad manually: https://github.com/v1cont/yad" ;;
    esac
    command -v yad &>/dev/null && success "yad installed" || error "yad install failed — the GUI will not work"
fi

# python3 + pip (needed for yt-dlp)
if ! command -v pip3 &>/dev/null && ! command -v pip &>/dev/null; then
    info "pip not found — installing python3-pip..."
    case "$PKG_MGR" in
        apt)    install_pkg python3-pip ;;
        dnf)    install_pkg python3-pip ;;
        pacman) install_pkg python-pip ;;
        zypper) install_pkg python3-pip ;;
    esac
fi

# ── 3. Install yt-dlp via pip (always latest) ─────────────────────────────────
header "Installing yt-dlp"

PIP_CMD="pip3"
command -v pip3 &>/dev/null || PIP_CMD="pip"

if command -v yt-dlp &>/dev/null; then
    CURRENT_VER=$(yt-dlp --version 2>/dev/null || echo "unknown")
    info "yt-dlp found (current: $CURRENT_VER) — upgrading to latest..."
fi

# Install/upgrade via pip with --break-system-packages for modern distros
if $PIP_CMD install --upgrade yt-dlp --break-system-packages 2>/dev/null \
   || $PIP_CMD install --upgrade yt-dlp 2>/dev/null; then
    NEW_VER=$(yt-dlp --version 2>/dev/null || echo "unknown")
    success "yt-dlp installed/updated: $NEW_VER"
else
    error "pip install failed — trying pipx..."
    if command -v pipx &>/dev/null || install_pkg pipx; then
        pipx install yt-dlp && success "yt-dlp installed via pipx" || error "yt-dlp install failed completely — please install manually"
    fi
fi

# ── 4. Make scripts executable ────────────────────────────────────────────────
header "Setting permissions"

chmod +x "${INSTALL_DIR}/main.sh" \
         "${INSTALL_DIR}/ui.sh" \
         "${INSTALL_DIR}/core/"*.sh \
         "${INSTALL_DIR}/services/"*.sh
success "All scripts are now executable"

# ── 5. Write default config if missing ───────────────────────────────────────
header "Configuration"

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "${INSTALL_DIR}/config"
    cat > "$CONFIG_FILE" << CONF
DEFAULT_DOWNLOAD_DIR="$HOME/CarMedia"
DEFAULT_MODE="video"
DEFAULT_VIDEO_PROFILE="car"
DEFAULT_MUSIC_PROFILE="mp3"
MAX_PLAYLIST_LIMIT=50
YT_CONCURRENT_FRAGS=5
AUTO_UPDATE="false"
COOKIE_BROWSER="none"
CONF
    success "Default config written to config/settings.conf"
else
    info "Config already exists — leaving untouched"
fi

mkdir -p "$HOME/CarMedia"
success "Download folder ready: $HOME/CarMedia"

# ── 6. Create .desktop launcher ──────────────────────────────────────────────
header "Creating app launcher"

DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/carmedia.desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_FILE" << DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=CarMedia Pro
Comment=YouTube downloader optimised for car head units
Exec=bash ${MAIN_SCRIPT}
Icon=video-display
Terminal=false
Categories=AudioVideo;Video;
Keywords=youtube;download;car;media;
StartupNotify=true
DESKTOP

chmod +x "$DESKTOP_FILE"
success "App launcher created: $DESKTOP_FILE"

# Desktop shortcut (if ~/Desktop exists)
if [[ -d "$HOME/Desktop" ]]; then
    cp "$DESKTOP_FILE" "$HOME/Desktop/CarMedia Pro.desktop"
    chmod +x "$HOME/Desktop/CarMedia Pro.desktop"
    # Some DEs need this to trust the launcher
    gio set "$HOME/Desktop/CarMedia Pro.desktop" metadata::trusted true 2>/dev/null || true
    success "Desktop shortcut created"
fi

# ── 7. Final summary ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗"
echo    "║          Installation Complete! ✅       ║"
echo -e "╚══════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}To launch CarMedia Pro:${RESET}"
echo -e "    • From terminal:  ${BLUE}bash ${MAIN_SCRIPT}${RESET}"
echo -e "    • From app menu:  Search for ${BOLD}CarMedia Pro${RESET}"
[[ -d "$HOME/Desktop" ]] && echo -e "    • Desktop icon:   Double-click ${BOLD}CarMedia Pro${RESET}"
echo ""
echo -e "  ${BOLD}Downloads will save to:${RESET} ~/CarMedia"
echo ""
