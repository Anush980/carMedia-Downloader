#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# services/update_service.sh
#
# PURPOSE:
#   Manages yt-dlp self-updates. Provides both:
#     - Silent update (used on retry after download failure)
#     - UI update (user-triggered from Settings, shows progress bar)
#
# WHY NEEDED:
#   YouTube frequently changes its API. An outdated yt-dlp often causes
#   extractor errors. Auto-updating on first failure and retrying once
#   fixes the majority of "random" download failures.
#
# USED BY: download_manager.sh (auto-retry), ui.sh (settings button)
# ─────────────────────────────────────────────────────────────────────────────

get_ytdlp_version() {
    yt-dlp --version 2>/dev/null || echo "not installed"
}

# Silent update — called automatically on download failure before retry
update_ytdlp() {
    log_info "yt-dlp silent update starting (current: $(get_ytdlp_version))"
    if yt-dlp -U 2>&1 | tee -a "$LOG_APP"; then
        log_info "yt-dlp updated to: $(get_ytdlp_version)"
        return 0
    else
        log_error "yt-dlp silent update failed"
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
        yt-dlp -U 2>&1 | tee -a "$LOG_APP"
        echo "100"; echo "# Complete!"
    ) | yad --progress \
            --title="CarMedia Pro – Update" \
            --text="Updating yt-dlp, please wait..." \
            --percentage=0 --auto-close --auto-kill \
            --width=420 --center 2>/dev/null || true
    show_success_dialog "Update Complete" "yt-dlp is now at version:\n<b>$(get_ytdlp_version)</b>"
}
