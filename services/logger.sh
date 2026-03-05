#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# services/logger.sh
#
# PURPOSE:
#   Unified logging module. Writes to terminal, log files, and optionally
#   to a live dev-mode YAD log window.
#
# HOW IT WORKS:
#   - Every log call goes to: terminal stdout + logs/app.log
#   - ERROR calls also go to: logs/error.log
#   - If DEV_MODE=true AND DEV_LOG_PIPE is a live FIFO, lines are also
#     forwarded to the dev log window in real time.
#
# USED BY: All modules (injected via main.sh)
# ─────────────────────────────────────────────────────────────────────────────

LOG_DIR="${BASE_DIR}/logs"
LOG_APP="${LOG_DIR}/app.log"
LOG_ERROR="${LOG_DIR}/error.log"
mkdir -p "$LOG_DIR"

# Live dev-log FIFO path (set by download_manager when dev mode is on)
DEV_LOG_PIPE=""
DEV_MODE="${DEV_MODE:-false}"

_log() {
    local level="$1" msg="$2"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[$ts][$level] $msg"

    # 1. Terminal
    echo "$line"

    # 2. App log file
    echo "$line" >> "$LOG_APP"

    # 3. Error log file (errors only)
    [[ "$level" == "ERROR" ]] && echo "$line" >> "$LOG_ERROR"

    # 4. Dev mode live pipe
    if [[ "$DEV_MODE" == "true" && -n "$DEV_LOG_PIPE" && -p "$DEV_LOG_PIPE" ]]; then
        echo "$msg" > "$DEV_LOG_PIPE" 2>/dev/null || true
    fi
}

log_info()  { _log "INFO " "$1"; }
log_warn()  { _log "WARN " "$1"; }
log_error() { _log "ERROR" "$1"; }
log_debug() { [[ "$DEV_MODE" == "true" ]] && _log "DEBUG" "$1" || true; }
