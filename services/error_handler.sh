#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# services/error_handler.sh
#
# PURPOSE:
#   Centralized error categorization and user-facing error dialogs.
#   All errors flow through handle_error() so they are:
#     1. Logged (via logger.sh)
#     2. Shown to user as a YAD popup with a helpful hint
#
# ERROR TYPES:
#   user        - bad input, unsupported URL
#   network     - connectivity issues
#   ytdlp       - yt-dlp failures (private video, extractor error, etc.)
#   filesystem  - disk full, no write permission
#   playlist    - playlist parsing failures
#
# USED BY: All modules
# ─────────────────────────────────────────────────────────────────────────────

handle_error() {
    local type="$1" msg="$2"
    log_error "[$type] $msg"

    local hint
    case "$type" in
        user)       hint="Check your input and try again." ;;
        network)    hint="Check your internet connection." ;;
        ytdlp)      hint="Check the URL — video may be private, removed, or age-restricted.\nTry updating yt-dlp from Settings." ;;
        filesystem) hint="Check available disk space and folder write permissions." ;;
        playlist)   hint="Playlist may be private or the URL is incorrect." ;;
        *)          hint="See logs/error.log for full details." ;;
    esac

    yad --error \
        --title="CarMedia Pro – Error" \
        --text="<b>${msg}</b>\n\n<i>${hint}</i>" \
        --button="OK:0" \
        --width=460 --center 2>/dev/null || true
}

show_success_dialog() {
    local title="$1" msg="$2"
    log_info "SUCCESS: $title"
    yad --info \
        --title="CarMedia Pro – $title" \
        --text="$msg" \
        --button="OK:0" \
        --width=400 --center 2>/dev/null || true
}

check_dependency() {
    local cmd="$1" hint="${2:-install it}"
    log_info "Checking: $cmd"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "MISSING dependency: $cmd"
        yad --error \
            --title="CarMedia Pro – Missing Dependency" \
            --text="<b>Required tool not found: <tt>$cmd</tt></b>\n\n$hint" \
            --button="OK:0" --width=460 --center 2>/dev/null || true
        return 1
    fi
    log_info "  OK: $cmd ($(command -v "$cmd"))"
    return 0
}

# Recursively kills a process and all its descendants (useful for bash subshells)
kill_process_tree() {
    local pid="$1"
    local sig="${2:-TERM}"
    [[ "$pid" -le 0 ]] && return 0
    
    local children
    children=$(pgrep -P "$pid" 2>/dev/null)
    for child in $children; do
        kill_process_tree "$child" "$sig"
    done
    
    kill -"$sig" "$pid" 2>/dev/null || true
}
