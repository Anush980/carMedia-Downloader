#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# core/metadata_fetcher.sh
#
# PURPOSE:
#   Fetches video and playlist metadata from yt-dlp WITHOUT downloading.
#   Used for:
#     1. Showing video title in the progress window before download starts
#     2. Building the playlist selection list (titles + durations)
#     3. Validating that a URL is accessible before queueing
#
# HOW IT WORKS:
#   Uses yt-dlp --flat-playlist --print "%(field)s" which is very fast
#   because it only fetches the metadata JSON, not the actual video stream.
#
# USED BY: playlist_parser.sh, download_manager.sh
# ─────────────────────────────────────────────────────────────────────────────

# fetch_video_title URL  →  echoes video title (single video, no playlist)
fetch_video_title() {
    local url="$1"
    log_debug "fetch_video_title: $url"
    yt-dlp --no-playlist --get-title "$url" 2>/dev/null \
        | head -1 \
        || echo "Unknown Title"
}

# fetch_single_video_meta URL
# Echoes: "TITLE|DURATION_STRING|ID"
fetch_single_video_meta() {
    local url="$1"
    log_debug "fetch_single_video_meta: $url"
    yt-dlp --no-playlist \
           --print "%(title)s|%(duration_string)s|%(id)s" \
           "$url" 2>/dev/null \
        | head -1 \
        || echo "Unknown|0:00|unknown"
}

# fetch_playlist_items URL
# Echoes one line per video: "INDEX|TITLE|DURATION|URL"
# Uses --flat-playlist so it's fast (no stream URLs resolved)
fetch_playlist_items() {
    local url="$1"
    log_debug "fetch_playlist_items: $url"
    yt-dlp --flat-playlist \
           --print "%(playlist_index)s|%(title)s|%(duration_string)s|%(url)s" \
           "$url" 2>/dev/null | awk -F'|' '!seen[$4]++'
}

# fetch_playlist_count URL  →  echoes integer count
fetch_playlist_count() {
    local url="$1"
    yt-dlp --flat-playlist --print "%(playlist_count)s" "$url" 2>/dev/null \
        | head -1 \
        || echo "0"
}
