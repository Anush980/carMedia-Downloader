#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# core/platform_detector.sh
#
# PURPOSE:
#   Analyses a URL and returns three pieces of information:
#     1. Platform (youtube, facebook, etc.)
#     2. URL type (single_video | playlist | video_in_playlist)
#     3. Whether downloading should use --no-playlist
#
# THE KEY DISTINCTION (fixes the "downloads whole playlist" bug):
#
#   video_in_playlist:
#     URL like: https://youtube.com/watch?v=ABC&list=PLxxx
#     The URL points to ONE video but also contains a playlist ID.
#     yt-dlp by DEFAULT downloads the WHOLE playlist here.
#     FIX: use --no-playlist to get just the one video.
#
#   playlist:
#     URL like: https://youtube.com/playlist?list=PLxxx
#     No video ID — purely a playlist URL.
#     yt-dlp downloads the playlist. We can use --playlist-items to limit.
#
#   single_video:
#     URL like: https://youtube.com/watch?v=ABC (no list= param)
#     Always use --no-playlist.
#
# USED BY: ui.sh (to decide flow), download_manager.sh (to build args)
# ─────────────────────────────────────────────────────────────────────────────

detect_platform() {
    local url="$1"
    if   [[ "$url" =~ (youtube\.com|youtu\.be) ]]; then echo "youtube"
    elif [[ "$url" =~ facebook\.com ]];             then echo "facebook"
    elif [[ "$url" =~ instagram\.com ]];            then echo "instagram"
    elif [[ "$url" =~ (twitter\.com|x\.com) ]];    then echo "twitter"
    else                                                 echo "unknown"
    fi
}

# detect_url_type URL
# Echoes one of: single_video | playlist | video_in_playlist
detect_url_type() {
    local url="$1"

    local has_video=false has_list=false is_playlist_page=false is_radio_mix=false

    # Store patterns in variables — avoids bash issues parsing [?&] inline
    local pat_vid='v=[A-Za-z0-9_-]+'
    local pat_list='list=[A-Za-z0-9_-]+'
    local pat_short='youtu\.be/[A-Za-z0-9_-]+'
    local pat_pl_page='youtube\.com/playlist'
    # YouTube Radio/Mix playlists: list=RD... or list=RDMM...
    # These auto-generated mixes have a video context but ARE playlists.
    local pat_radio='list=RD[A-Za-z0-9_-]+'

    # Has a video ID?
    [[ "$url" =~ $pat_vid   ]] && has_video=true
    [[ "$url" =~ $pat_short ]] && has_video=true

    # Has a list= parameter?
    [[ "$url" =~ $pat_list  ]] && has_list=true

    # Is it a pure playlist page?
    [[ "$url" =~ $pat_pl_page ]] && is_playlist_page=true

    # Is it a YouTube Radio/Mix auto-playlist?
    [[ "$url" =~ $pat_radio ]] && is_radio_mix=true

    log_debug "URL analysis: has_video=$has_video has_list=$has_list is_playlist_page=$is_playlist_page is_radio_mix=$is_radio_mix"

    if $is_playlist_page; then
        echo "playlist"
    elif $is_radio_mix; then
        # Radio Mix: treat as a playlist even though it also has v= video context
        echo "playlist"
    elif $has_video && $has_list; then
        echo "video_in_playlist"   # Contains BOTH — user probably wants just the video
    elif $has_video; then
        echo "single_video"
    elif $has_list; then
        echo "playlist"
    else
        echo "single_video"        # Fallback: let yt-dlp handle it
    fi
}

is_supported_platform() { [[ "$1" == "youtube" ]]; }

get_platform_label() {
    case "$1" in
        youtube)   echo "YouTube"     ;;
        facebook)  echo "Facebook"    ;;
        instagram) echo "Instagram"   ;;
        twitter)   echo "Twitter / X" ;;
        *)         echo "Unknown"     ;;
    esac
}
