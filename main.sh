#!/usr/bin/env bash
# main.sh — Entry point. Defines BASE_DIR. Sources everything. No set -e.
# ─────────────────────────────────────────────────────────────────────────────

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR

echo "[BOOT] BASE_DIR=$BASE_DIR"

# ── Source order: services → core → ui ───────────────────────────────────────
echo "[BOOT] Loading services..."
source "${BASE_DIR}/services/error_handler.sh"
source "${BASE_DIR}/services/update_service.sh"

echo "[BOOT] Loading core modules..."
source "${BASE_DIR}/core/profiles.sh"
source "${BASE_DIR}/core/platform_detector.sh"
source "${BASE_DIR}/core/downloader.sh"
source "${BASE_DIR}/core/download_manager.sh"

echo "[BOOT] Loading UI..."
source "${BASE_DIR}/ui.sh"

# ── Dependency checks ─────────────────────────────────────────────────────────
echo "[BOOT] Checking dependencies..."
check_dependency "yad"    "sudo pacman -S yad" || exit 1
check_dependency "yt-dlp" "pip install yt-dlp OR sudo pacman -S yt-dlp" || exit 1
check_dependency "ffmpeg" "sudo pacman -S ffmpeg" || exit 1

echo "[BOOT] All OK — launching UI"
echo "-------------------------------------------"

# ── Launch ────────────────────────────────────────────────────────────────────
start_ui

echo "[EXIT] CarMedia Downloader exited."
