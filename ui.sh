#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ui.sh
#
# PURPOSE:
#   All YAD GUI windows for CarMedia Pro.
#   This file contains ONLY user interface logic.
#   No yt-dlp commands, no path calculations, no sourcing.
#   All service/core functions and BASE_DIR are injected by main.sh.
#
# WINDOWS:
#   show_main_window       →  URL input + profile + mode + settings button
#   show_settings_window   →  preferences, profiles, thresholds, dev mode
#   show_url_type_dialog   →  when video_in_playlist detected, ask user intent
#   _submit                →  validates input, routes to correct flow
#   _handle_single_flow    →  single video / video_in_playlist
#   _handle_playlist_flow  →  playlist → checklist → dm_add_job → dm_start
# ─────────────────────────────────────────────────────────────────────────────

APP_TITLE="CarMedia Pro"
APP_VERSION="2.0.0"

# ─────────────────────────────────────────────────────────────────────────────
# start_ui — called by main.sh after all modules are loaded
# ─────────────────────────────────────────────────────────────────────────────
start_ui() {
    log_info "start_ui: loading preferences"
    local cfg="${BASE_DIR}/config/settings.conf"
    [[ -f "$cfg" ]] && source "$cfg" || log_warn "No config found — using defaults"

    # Apply defaults
    SAVE_DIR="${DEFAULT_DOWNLOAD_DIR:-$HOME/CarMedia}"
    DEFAULT_MODE="${DEFAULT_MODE:-video}"
    DEFAULT_VIDEO_PROFILE="${DEFAULT_VIDEO_PROFILE:-car}"
    DEFAULT_MUSIC_PROFILE="${DEFAULT_MUSIC_PROFILE:-mp3}"
    MAX_PLAYLIST_LIMIT="${MAX_PLAYLIST_LIMIT:-50}"
    AUTO_UPDATE="${AUTO_UPDATE:-false}"
    DEV_MODE="${DEV_MODE:-false}"
    export DEV_MODE

    [[ "$AUTO_UPDATE" == "true" ]] && { log_info "Auto-update on"; update_ytdlp; }

    log_info "Starting main window (mode=$DEFAULT_MODE profile_v=$DEFAULT_VIDEO_PROFILE profile_m=$DEFAULT_MUSIC_PROFILE)"
    show_main_window
}

# ─────────────────────────────────────────────────────────────────────────────
# Profile combo helpers
# ─────────────────────────────────────────────────────────────────────────────
_video_profile_combo() {
    local active="${DEFAULT_VIDEO_PROFILE:-car}" combo=()
    while IFS="|" read -r key label; do
        [[ "$key" == "$active" ]] && combo=("$label" "${combo[@]}") || combo+=("$label")
    done < <(list_video_profiles_yad)
    local IFS="!"; echo "${combo[*]}"
}

_music_profile_combo() {
    local active="${DEFAULT_MUSIC_PROFILE:-mp3}" combo=()
    while IFS="|" read -r key label; do
        [[ "$key" == "$active" ]] && combo=("$label" "${combo[@]}") || combo+=("$label")
    done < <(list_music_profiles_yad)
    local IFS="!"; echo "${combo[*]}"
}

_label_to_video_key() {
    while IFS="|" read -r key label; do
        [[ "$label" == "$1" ]] && echo "$key" && return
    done < <(list_video_profiles_yad)
    echo "car"
}

_label_to_music_key() {
    while IFS="|" read -r key label; do
        [[ "$label" == "$1" ]] && echo "$key" && return
    done < <(list_music_profiles_yad)
    echo "mp3"
}

# ─────────────────────────────────────────────────────────────────────────────
# show_main_window
# ─────────────────────────────────────────────────────────────────────────────
show_main_window() {
    log_info "show_main_window"
    local result btn

    result=$(yad --form \
        --title="$APP_TITLE  v$APP_VERSION" \
        --text="<b>CarMedia Pro</b>  –  YouTube Downloader\nOptimised for car head units and Apple CarPlay." \
        --width=640 --height=460 \
        --center \
        --separator="|" \
        --field="🔗  URL (video or playlist)":TEXT        "" \
        --field="📦  Mode":CB                             "Video!Music" \
        --field="🎬  Video Profile":CB                    "$(_video_profile_combo)" \
        --field="🎵  Music Profile":CB                    "$(_music_profile_combo)" \
        --field="📁  Save To":DIR                         "${SAVE_DIR:-$HOME/CarMedia}" \
        --button=" Settings:2" \
        --button="cancel:1" \
        --button=" Download:0" \
        2>/dev/null)
    btn=$?

    log_info "Main window: btn=$btn"

    case $btn in
        0) _submit "$result" ;;
        1) log_info "User exited"; exit 0 ;;
        2) show_settings_window; show_main_window ;;
        *) log_warn "Unknown btn $btn"; show_main_window ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# _submit — validate input, detect URL type, route to correct flow
# ─────────────────────────────────────────────────────────────────────────────
_submit() {
    local raw="$1"
    log_info "_submit: raw=[$raw]"

    local url mode_label video_label music_label save_dir
    IFS="|" read -r url mode_label video_label music_label save_dir _ <<< "$raw"

    # Dev mode is only via terminal ENV now
    export DEV_MODE="${DEV_MODE:-false}"
    log_info "Dev mode: $DEV_MODE"

    # ── Validate URL ──────────────────────────────────────────────────────────
    url="${url// /}"   # strip whitespace
    if [[ -z "$url" ]]; then
        handle_error "user" "Please enter a YouTube URL."
        show_main_window; return
    fi
    if ! [[ "$url" =~ ^https?:// ]]; then
        handle_error "user" "URL must start with https://\n\nYou entered:\n$url"
        show_main_window; return
    fi

    # ── Platform check ────────────────────────────────────────────────────────
    local platform; platform=$(detect_platform "$url")
    log_info "Platform: $platform"
    if ! is_supported_platform "$platform"; then
        handle_error "user" "Platform not yet supported: $(get_platform_label "$platform")\n\nCurrently supported: YouTube"
        show_main_window; return
    fi

    # ── Mode + profile ────────────────────────────────────────────────────────
    local mode profile_key
    if [[ "$mode_label" == "Music" ]]; then
        mode="music"
        profile_key=$(_label_to_music_key "$music_label")
    else
        mode="video"
        profile_key=$(_label_to_video_key "$video_label")
    fi
    log_info "Mode=$mode profile=$profile_key dir=$save_dir"

    # ── URL type detection ────────────────────────────────────────────────────
    local url_type; url_type=$(detect_url_type "$url")
    log_info "URL type: $url_type"

    # ── Route to correct download flow ────────────────────────────────────────
    case "$url_type" in
        single_video)
            _handle_single_flow "$url" "$mode" "$profile_key" "$save_dir" "single_video"
            ;;
        video_in_playlist)
            _handle_video_in_playlist "$url" "$mode" "$profile_key" "$save_dir"
            ;;
        playlist)
            _handle_playlist_flow "$url" "$mode" "$profile_key" "$save_dir"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# _handle_video_in_playlist
# URL has both a video ID and a playlist ID.
# Ask the user: "Download just this video, or open playlist selector?"
# ─────────────────────────────────────────────────────────────────────────────
_handle_video_in_playlist() {
    local url="$1" mode="$2" profile_key="$3" save_dir="$4"

    log_info "video_in_playlist — asking user intent"

    yad --question \
        --title="$APP_TITLE – Playlist Detected" \
        --text="<b>This URL is a video inside a playlist.</b>\n\nWhat would you like to do?" \
        --button="Download this video only:0" \
        --button="Open playlist selector:1" \
        --button="Cancel:2" \
        --width=400 --center 2>/dev/null
    local choice=$?

    log_info "User chose: $choice"
    case $choice in
        0)  _handle_single_flow "$url" "$mode" "$profile_key" "$save_dir" "video_in_playlist" ;;
        1)  _handle_playlist_flow "$url" "$mode" "$profile_key" "$save_dir" ;;
        *)  show_main_window ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# _handle_single_flow
# Downloads exactly one video. Uses --no-playlist.
# ─────────────────────────────────────────────────────────────────────────────
_handle_single_flow() {
    local url="$1" mode="$2" profile_key="$3" save_dir="$4" url_type="$5"
    log_info "_handle_single_flow: url_type=$url_type"

    # Reset queue
    DM_JOB_IDS=(); DM_NEXT_ID=1; DM_COMPLETED=0; DM_FAILED=0; DM_TOTAL_JOBS=0

    dm_add_job "$url" "$mode" "$profile_key" "$save_dir" "$url_type" ""
    dm_start_session

    _post_download_dialog "$save_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# _handle_playlist_flow
# 1. Show playlist selector (checklist of videos)
# 2. Build comma-separated indices from selection
# 3. Queue one job with those indices
# 4. Start download session
# ─────────────────────────────────────────────────────────────────────────────
_handle_playlist_flow() {
    local url="$1" mode="$2" profile_key="$3" save_dir="$4"
    log_info "_handle_playlist_flow"

    # Show the video checklist
    SELECTED_INDICES=""
    show_playlist_selector "$url" "${MAX_PLAYLIST_LIMIT:-50}"
    local selector_result=$?

    if [[ $selector_result -ne 0 || -z "$SELECTED_INDICES" ]]; then
        log_info "Playlist selection cancelled or empty"
        show_main_window
        return
    fi

    log_info "User selected playlist items: $SELECTED_INDICES"
    local item_count; item_count=$(echo "$SELECTED_INDICES" | tr ',' '\n' | wc -l)
    log_info "Downloading $item_count videos from playlist"

    # Reset queue and add one job with selected indices
    DM_JOB_IDS=(); DM_NEXT_ID=1; DM_COMPLETED=0; DM_FAILED=0; DM_TOTAL_JOBS=0

    dm_add_job "$url" "$mode" "$profile_key" "$save_dir" "playlist" "$SELECTED_INDICES"
    dm_start_session

    _post_download_dialog "$save_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# _post_download_dialog
# Shown after all downloads complete.
# ─────────────────────────────────────────────────────────────────────────────
_post_download_dialog() {
    local save_dir="$1"
    log_info "_post_download_dialog"

    yad --question \
        --title="$APP_TITLE – Done" \
        --text="✅  Download session complete!\n\nFiles saved to:\n<b>${save_dir}</b>\n\nDownload more?" \
        --button="Yes:0" \
        --button="Exit:1" \
        --width=400 --center 2>/dev/null \
        && show_main_window \
        || { log_info "User chose exit"; exit 0; }
}

# ─────────────────────────────────────────────────────────────────────────────
# show_settings_window
# ─────────────────────────────────────────────────────────────────────────────
show_settings_window() {
    log_info "show_settings_window"
    local result btn

    result=$(yad --form \
        --title="$APP_TITLE – Settings" \
        --text="<b>⚙  Preferences</b>" \
        --width=560 --center \
        --separator="|" \
        --field="📁  Default Download Folder":DIR    "${SAVE_DIR:-$HOME/CarMedia}" \
        --field="📦  Default Mode":CB                "Video!Music" \
        --field="🎬  Default Video Profile":CB       "$(_video_profile_combo)" \
        --field="🎵  Default Music Profile":CB       "$(_music_profile_combo)" \
        --field="🔢  Max Playlist Items (threshold)":NUM "${MAX_PLAYLIST_LIMIT:-50}!1..500!1!0" \
        --field="⚡  Concurrent Fragments (speed)":NUM "${YT_CONCURRENT_FRAGS:-5}!1..16!1!0" \
        --field="🔄  Auto-update yt-dlp on start":CHK "${AUTO_UPDATE:-false}" \
        --button="⬆ Update yt-dlp Now:2" \
        --button="gtk-cancel:1" \
        --button="gtk-save:0" \
        2>/dev/null)
    btn=$?

    log_info "Settings: btn=$btn"
    case $btn in
        0) _save_settings "$result" ;;
        2) update_ytdlp_with_ui; show_settings_window ;;
    esac
}

_save_settings() {
    local new_dir mode_label video_label music_label max_pl frags auto_upd
    IFS="|" read -r new_dir mode_label video_label music_label max_pl frags auto_upd <<< "$1"

    local new_video_profile; new_video_profile=$(_label_to_video_key "$video_label")
    local new_music_profile; new_music_profile=$(_label_to_music_key "$music_label")
    local new_mode; [[ "$mode_label" == "Music" ]] && new_mode="music" || new_mode="video"
    [[ "$auto_upd" == "TRUE" ]] && auto_upd="true" || auto_upd="false"
    local frags_int="${frags%%.*}"
    local maxpl_int="${max_pl%%.*}"

    cat > "${BASE_DIR}/config/settings.conf" << CONF
DEFAULT_DOWNLOAD_DIR="${new_dir}"
DEFAULT_MODE="${new_mode}"
DEFAULT_VIDEO_PROFILE="${new_video_profile}"
DEFAULT_MUSIC_PROFILE="${new_music_profile}"
MAX_PLAYLIST_LIMIT=${maxpl_int}
YT_CONCURRENT_FRAGS=${frags_int}
AUTO_UPDATE="${auto_upd}"
CONF

    SAVE_DIR="$new_dir"
    DEFAULT_DOWNLOAD_DIR="$new_dir"
    DEFAULT_MODE="$new_mode"
    DEFAULT_VIDEO_PROFILE="$new_video_profile"
    DEFAULT_MUSIC_PROFILE="$new_music_profile"
    MAX_PLAYLIST_LIMIT="$maxpl_int"
    YT_CONCURRENT_FRAGS="$frags_int"
    AUTO_UPDATE="$auto_upd"

    log_info "Settings saved: dir=$new_dir mode=$new_mode vp=$new_video_profile mp=$new_music_profile maxpl=$maxpl_int frags=$frags_int"
    show_success_dialog "Settings Saved" "Preferences saved successfully."
}
