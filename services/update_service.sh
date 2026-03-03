#!/usr/bin/env bash
# services/update_service.sh

get_ytdlp_version() {
    yt-dlp --version 2>/dev/null || echo "not installed"
}

update_ytdlp() {
    log_info "Running: yt-dlp -U"
    local before; before=$(get_ytdlp_version)
    if yt-dlp -U 2>&1 | tee -a "$LOG_APP"; then
        local after; after=$(get_ytdlp_version)
        log_info "yt-dlp: $before -> $after"
        return 0
    else
        log_error "yt-dlp update failed"
        return 1
    fi
}

update_ytdlp_with_ui() {
    log_info "User triggered yt-dlp update"
    (
        echo "10"; echo "# Checking version..."
        sleep 0.3
        echo "40"; echo "# Downloading latest yt-dlp..."
        yt-dlp -U 2>&1 | tee -a "$LOG_APP"
        echo "100"; echo "# Done!"
    ) | yad --progress \
            --title="CarMedia – Update" \
            --text="Updating yt-dlp..." \
            --percentage=0 --auto-close --auto-kill \
            --width=400 --center 2>/dev/null || true
    show_success_dialog "Updated" "yt-dlp version: $(get_ytdlp_version)"
}
