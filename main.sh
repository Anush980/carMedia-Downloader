#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# main.sh  —  CarMedia Pro Entry Point
#
# ARCHITECTURE RULES (enforced here, nowhere else):
#   1. BASE_DIR is calculated ONCE here and exported.
#   2. ALL sourcing happens here, in dependency order.
#   3. No submodule calculates its own path or sources another module.
#   4. No set -e / set -euo pipefail (YAD returns non-zero on cancel etc.)
#
# SOURCE ORDER (matters — later files use functions from earlier ones):
#   services/logger.sh          →  log_info / log_error / log_debug
#   services/error_handler.sh   →  handle_error / check_dependency
#   services/update_service.sh  →  update_ytdlp
#   core/profiles.sh            →  get_profile_format / list_*_profiles_yad
#   core/platform_detector.sh   →  detect_platform / detect_url_type
#   core/metadata_fetcher.sh    →  fetch_video_title / fetch_playlist_items
#   core/downloader.sh          →  build_yt_dlp_args
#   core/playlist_parser.sh     →  show_playlist_selector
#   core/download_manager.sh    →  dm_add_job / dm_start_session
#   ui.sh                       →  start_ui / show_main_window
# ─────────────────────────────────────────────────────────────────────────────

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR
export DEV_MODE="${DEV_MODE:-false}"

echo "[BOOT] CarMedia Pro v2.0.0"
echo "[BOOT] BASE_DIR=$BASE_DIR"
echo "[BOOT] Loading modules..."

source "${BASE_DIR}/services/logger.sh"
source "${BASE_DIR}/services/error_handler.sh"
source "${BASE_DIR}/services/update_service.sh"

source "${BASE_DIR}/core/profiles.sh"
source "${BASE_DIR}/core/platform_detector.sh"
source "${BASE_DIR}/core/metadata_fetcher.sh"
source "${BASE_DIR}/core/downloader.sh"
source "${BASE_DIR}/core/playlist_parser.sh"
source "${BASE_DIR}/core/download_manager.sh"

source "${BASE_DIR}/ui.sh"

echo "[BOOT] All modules loaded."
echo "[BOOT] Checking dependencies..."

check_dependency "yad"    "sudo pacman -S yad  OR  sudo apt install yad"         || exit 1
check_dependency "yt-dlp" "pip install yt-dlp  OR  sudo pacman -S yt-dlp"        || exit 1
check_dependency "ffmpeg" "sudo pacman -S ffmpeg  OR  sudo apt install ffmpeg"    || exit 1

# KDE Plasma: trap SIGTERM (from window manager X button) for clean shutdown.
# --kill-parent on YAD fires SIGTERM when the window closes, including after
# normal completion. We only force-exit if no download session is currently
# running; otherwise we just log it and let dm_start_session finish naturally.
trap '_handle_sigterm' TERM HUP
_handle_sigterm() {
    if [[ "${DM_SESSION_ACTIVE:-false}" == "true" ]]; then
        log_warn "Caught SIGTERM/SIGHUP — session active, prompting user..."
        # Prompt user if they really want to quit
        yad --question \
            --title="Confirm Exit" \
            --text="A download is currently in progress.\nAre you sure you want to stop the download and exit?" \
            --button="Yes!gtk-yes:0" \
            --button="No!gtk-no:1" \
            --center \
            --always-on-top

        if [[ $? -ne 0 ]]; then
            log_info "User cancelled exit, download continuing..."
            return 0
        fi
        
        log_warn "User confirmed exit during active session. Killing workers."
        # If yes, kill session jobs and let the script fall through to the exit below
    fi
    
    log_warn "Caught SIGTERM/SIGHUP — cleaning up and exiting"
    [[ "${DM_WORKER_PID:-0}" -gt 0 ]] && kill_process_tree "$DM_WORKER_PID" "TERM"
    [[ "${DM_YAD_PID:-0}" -gt 0 ]]    && kill_process_tree "$DM_YAD_PID" "TERM"
    exit 0
}

echo "[BOOT] All OK. Launching UI..."
echo "──────────────────────────────────────────────────────"

start_ui

echo "──────────────────────────────────────────────────────"
echo "[EXIT] CarMedia Pro exited cleanly."
