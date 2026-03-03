#!/usr/bin/env bash
# services/error_handler.sh — Logging + error dialogs
# BASE_DIR is set by main.sh

LOG_DIR="${BASE_DIR}/logs"
LOG_APP="${LOG_DIR}/app.log"
LOG_ERROR="${LOG_DIR}/error.log"
mkdir -p "$LOG_DIR"

# Print to terminal AND log file
_log() {
    local level="$1" msg="$2"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[$ts] [$level] $msg"
    echo "$line"                          # always visible in terminal
    echo "$line" >> "$LOG_APP"
    [[ "$level" == "ERROR" ]] && echo "$line" >> "$LOG_ERROR"
}

log_info()  { _log "INFO " "$1"; }
log_warn()  { _log "WARN " "$1"; }
log_error() { _log "ERROR" "$1"; }

handle_error() {
    local type="$1" msg="$2"
    log_error "[$type] $msg"
    local hint
    case "$type" in
        user)       hint="Check your input and try again." ;;
        network)    hint="Check internet connection." ;;
        ytdlp)      hint="Check the URL or update yt-dlp from Settings." ;;
        filesystem) hint="Check disk space and folder permissions." ;;
        *)          hint="See logs/error.log for details." ;;
    esac
    if command -v yad &>/dev/null; then
        yad --error \
            --title="CarMedia – Error" \
            --text="<b>${msg}</b>\n\n${hint}" \
            --button="OK:0" --width=440 --center 2>/dev/null || true
    fi
}

show_success_dialog() {
    local title="$1" msg="$2"
    log_info "SUCCESS: $title — $msg"
    if command -v yad &>/dev/null; then
        yad --info \
            --title="CarMedia – $title" \
            --text="$msg" \
            --button="OK:0" --width=380 --center 2>/dev/null || true
    fi
}

check_dependency() {
    local cmd="$1" hint="${2:-}"
    log_info "Checking dependency: $cmd"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "MISSING: $cmd"
        handle_error "user" "Required tool not found: $cmd\n\nInstall:\n$hint"
        return 1
    fi
    log_info "  OK: $cmd -> $(command -v "$cmd")"
    return 0
}
