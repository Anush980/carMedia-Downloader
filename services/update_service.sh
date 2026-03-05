#!/usr/bin/env bash
# services/update_service.sh — manages yt-dlp self-updates

get_ytdlp_version() {
    yt-dlp --version 2>/dev/null || echo "not installed"
}

# Silent update — called automatically on download failure before retry
# Falls back to pip for package-manager installs where yt-dlp -U fails
update_ytdlp() {
    log_info "yt-dlp silent update starting (current: $(get_ytdlp_version))"
    local updated=false

    # Try built-in self-update first (works for pip/manual installs)
    if yt-dlp -U 2>&1 | tee -a "$LOG_APP" | grep -qv "ERROR:"; then
        updated=true
    fi

    # Fallback: pip upgrade (needed when installed via system package manager)
    if ! $updated; then
        log_info "  yt-dlp -U failed — trying pip upgrade (package manager install)"
        if pip3 install --upgrade yt-dlp --break-system-packages 2>&1 | tee -a "$LOG_APP"; then
            updated=true
        elif pip install --upgrade yt-dlp --break-system-packages 2>&1 | tee -a "$LOG_APP"; then
            updated=true
        fi
    fi

    if $updated; then
        log_info "yt-dlp updated to: $(get_ytdlp_version)"
        return 0
    else
        log_error "yt-dlp update failed — all methods exhausted"
        return 1
    fi
}

# UI update with progress dialog — triggered from Settings window
update_ytdlp_with_ui() {
    log_info "User triggered yt-dlp update"
    (
        echo "10"; echo "# Checking current version..."
        sleep 0.3
        echo "40"; echo "# Downloading latest release..."
        # Try -U first, fall back to pip
        if ! yt-dlp -U 2>&1 | tee -a "$LOG_APP"; then
            pip3 install --upgrade yt-dlp --break-system-packages 2>&1 | tee -a "$LOG_APP" \
            || pip install --upgrade yt-dlp --break-system-packages 2>&1 | tee -a "$LOG_APP" \
            || true
        fi
        echo "100"; echo "# Complete!"
    ) | yad --progress \
            --title="CarMedia Pro – Update" \
            --text="Updating yt-dlp, please wait..." \
            --percentage=0 --auto-close --auto-kill \
            --width=420 --center 2>/dev/null || true
    show_success_dialog "Update Complete" "yt-dlp is now at version:\n<b>$(get_ytdlp_version)</b>"
}
