#!/usr/bin/env bash
# =============================================================================
# CarMedia Pro — Uninstaller
# Removes the app launcher, desktop shortcut, and config/logs.
# Does NOT touch ffmpeg, yad, yt-dlp, or any system packages.
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "\033[0;34m[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       CarMedia Pro  —  Uninstaller       ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  This will remove:\n"
echo    "    • App launcher from application menu"
echo    "    • Desktop shortcut (if it exists)"
echo    "    • config/settings.conf and config/cookies.txt"
echo    "    • logs/app.log and logs/error.log"
echo -e "\n  This will NOT remove: ffmpeg, yad, yt-dlp, or your downloaded videos.\n"

read -rp "  Continue? [y/N] " confirm
[[ "${confirm,,}" != "y" ]] && { echo "Cancelled."; exit 0; }
echo ""

# App launcher
DESKTOP_FILE="$HOME/.local/share/applications/carmedia.desktop"
if [[ -f "$DESKTOP_FILE" ]]; then
    rm -f "$DESKTOP_FILE"
    success "Removed app launcher: $DESKTOP_FILE"
else
    warn "App launcher not found (already removed?)"
fi

# Desktop shortcut
for shortcut in "$HOME/Desktop/CarMedia Pro.desktop" "$HOME/Desktop/carmedia.desktop"; do
    if [[ -f "$shortcut" ]]; then
        rm -f "$shortcut"
        success "Removed desktop shortcut: $shortcut"
    fi
done

# Config files (settings + cookies — keep user's downloaded videos)
for f in "$INSTALL_DIR/config/settings.conf" "$INSTALL_DIR/config/cookies.txt"; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        success "Removed: $f"
    fi
done

# Logs
for f in "$INSTALL_DIR/logs/app.log" "$INSTALL_DIR/logs/error.log"; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        success "Removed: $f"
    fi
done

echo ""
echo -e "${BOLD}${GREEN}Done.${RESET}"
echo ""
echo "  The app folder itself (${INSTALL_DIR}) was left in place."
echo "  Delete it manually if you want to remove everything:"
echo -e "    ${BOLD}rm -rf ${INSTALL_DIR}${RESET}"
echo ""