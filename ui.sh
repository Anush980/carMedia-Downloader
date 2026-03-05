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
    COOKIE_BROWSER="${COOKIE_BROWSER:-auto}"

    # ── Auto-detect browser for cookies ──────────────────────────────────────
    # YouTube now requires cookies on most IPs to prove you're not a bot.
    # If COOKIE_BROWSER is "auto" (the default), scan for installed browsers
    # and pick the first one found. User can override in Settings.
    if [[ "${COOKIE_BROWSER,,}" == "auto" || "${COOKIE_BROWSER,,}" == "none" ]]; then
        local detected_browser=""
        for browser in firefox chromium-browser chromium google-chrome brave-browser chrome; do
            if command -v "$browser" &>/dev/null; then
                # Map executable name to yt-dlp browser key
                case "$browser" in
                    firefox)                         detected_browser="firefox"  ;;
                    google-chrome|chrome)            detected_browser="chrome"   ;;
                    brave-browser)                   detected_browser="brave"    ;;
                    chromium|chromium-browser)       detected_browser="chromium" ;;
                esac
                break
            fi
        done
        if [[ -n "$detected_browser" ]]; then
            log_info "Auto-detected browser for cookies: $detected_browser"
            COOKIE_BROWSER="$detected_browser"
            # Persist so Settings shows what's actually being used
            sed -i "s/^COOKIE_BROWSER=.*/COOKIE_BROWSER=\"$detected_browser\"/" "$cfg" 2>/dev/null || true
        else
            log_warn "No supported browser found for cookie auto-detection — downloads may be blocked by YouTube bot check"
            COOKIE_BROWSER="none"
        fi
    fi

    export COOKIE_BROWSER

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
        --field="⚡  First video only (skip playlist selector)":CHK "false" \
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

    local url mode_label video_label music_label save_dir single_only
    IFS="|" read -r url mode_label video_label music_label save_dir single_only _ <<< "$raw"

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
    # "First video only" checkbox: skip all playlist logic, download the video
    # in the URL directly using --no-playlist regardless of list= param.
    if [[ "$single_only" == "TRUE" ]]; then
        log_info "First-video-only mode — skipping playlist selector"
        _handle_single_flow "$url" "$mode" "$profile_key" "$save_dir" "video_in_playlist"
        return
    fi

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

# Add this new function before show_settings_window()

# ─────────────────────────────────────────────────────────────────────────────
# _show_cookie_setup_guide
# Shows step-by-step guide for extracting browser cookies manually
# ─────────────────────────────────────────────────────────────────────────────
_show_cookie_setup_guide() {
    yad --text-info \
        --title="$APP_TITLE – Browser Cookie Setup" \
        --filename=/dev/stdin \
        --width=720 --height=480 \
        --wrap \
        --button="I've Copied Cookies!gtk-ok:0" \
        --button="Cancel!gtk-cancel:1" \
        2>/dev/null << 'GUIDE'
<b>🍪 How to Enable Age-Restricted Videos</b>

Some videos require login. You can either:

<b>OPTION A: Auto-extract from your browser (RECOMMENDED)</b>
  Go to Settings → 🍪 Cookie Source → Select your browser
  The app will automatically use your logged-in session.

<b>OPTION B: Manual cookie paste (if Option A doesn't work)</b>

1️⃣  Open your browser and go to <tt>youtube.com</tt>
2️⃣  Sign in with your account
3️⃣  Open Developer Tools: Press <tt>F12</tt>
4️⃣  Go to <tt>Storage</tt> tab → <tt>Cookies</tt> → <tt>youtube.com</tt>
5️⃣  <b>Install this extension:</b>
    • Chrome: "Get cookies.txt LOCALLY" by @kairi
    • Firefox: "Export Cookies" by @Rotem Dan
6️⃣  Click the extension icon → Download cookies.txt
7️⃣  Copy the file contents (Ctrl+A, Ctrl+C)
8️⃣  Paste in the next dialog

The app will save this and use it for all downloads.

<b>How often?</b> Once per month or when you get login errors.
GUIDE

    [[ $? -eq 0 ]] && _show_cookie_paste_dialog || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# _show_cookie_paste_dialog
# YAD form for pasting raw cookies.txt content
# ─────────────────────────────────────────────────────────────────────────────
_show_cookie_paste_dialog() {
    local cookie_content
    
    cookie_content=$(yad --text-info \
        --title="$APP_TITLE – Paste Cookies" \
        --text="Paste your cookies.txt file contents below:\n(Right-click in text area → Paste)" \
        --width=700 --height=300 \
        --button=" Save Cookies!gtk-ok:0" \
        --button="Cancel!gtk-cancel:1" \
        2>/dev/null)

    local btn=$?
    
    if [[ $btn -eq 0 && -n "$cookie_content" ]]; then
        echo "$cookie_content" > "${BASE_DIR}/config/cookies.txt"
        chmod 600 "${BASE_DIR}/config/cookies.txt"
        log_info "Cookies saved to config/cookies.txt"
        show_success_dialog "Cookies Saved" "Your cookies have been saved.\n\nDownloads will now use your logged-in session."
        return 0
    else
        log_info "Cookie paste cancelled"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Now update show_settings_window to add the setup button
# ─────────────────────────────────────────────────────────────────────────────

show_settings_window() {
    log_info "show_settings_window"
    local result btn

    # Build cookie browser combo (active item first)
    local _cb_active="${COOKIE_BROWSER:-none}"
    local _cb_list="Auto (detect)!None!Firefox!Chrome!Brave!Chromium"
    case "$_cb_active" in
        auto|Auto*) ;;  # stays default
        chrome)   _cb_list="Chrome!Auto (detect)!None!Firefox!Brave!Chromium" ;;
        firefox)  _cb_list="Firefox!Auto (detect)!None!Chrome!Brave!Chromium" ;;
        brave)    _cb_list="Brave!Auto (detect)!None!Chrome!Firefox!Chromium" ;;
        chromium) _cb_list="Chromium!Auto (detect)!None!Chrome!Firefox!Brave" ;;
    esac

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
        --field="🍪  Browser Cookies (auto-extract)":CB "$_cb_list" \
        --button="🍪 Manual Cookie Setup:3" \
        --button="⬆ Update yt-dlp Now:2" \
        --button="gtk-cancel:1" \
        --button="gtk-save:0" \
        2>/dev/null)
    btn=$?

    log_info "Settings: btn=$btn"
    case $btn in
        0) _save_settings "$result" ;;
        2) update_ytdlp_with_ui; show_settings_window ;;
        3) _show_cookie_setup_guide; show_settings_window ;;
    esac
}
# ─────────────────────────────────────────────────────────────────────────────
# _show_cookie_setup_guide
# Shows step-by-step guide for extracting browser cookies manually
# ─────────────────────────────────────────────────────────────────────────────
_show_cookie_setup_guide() {
    yad --text-info \
        --title="$APP_TITLE – Browser Cookie Setup" \
        --filename=/dev/stdin \
        --width=720 --height=480 \
        --wrap \
        --button="I've Copied Cookies!gtk-ok:0" \
        --button="Cancel!gtk-cancel:1" \
        2>/dev/null << 'GUIDE'
<b>🍪 How to Enable Age-Restricted Videos</b>

Some videos require login. You can either:

<b>OPTION A: Auto-extract from your browser (RECOMMENDED)</b>
  Go to Settings → 🍪 Cookie Source → Select your browser
  The app will automatically use your logged-in session.

<b>OPTION B: Manual cookie paste (if Option A doesn't work)</b>

1️⃣  Open your browser and go to <tt>youtube.com</tt>
2️⃣  Sign in with your account
3️⃣  Open Developer Tools: Press <tt>F12</tt>
4️⃣  Go to <tt>Storage</tt> tab → <tt>Cookies</tt> → <tt>youtube.com</tt>
5️⃣  <b>Install this extension:</b>
    • Chrome: "Get cookies.txt LOCALLY" by @kairi
    • Firefox: "Export Cookies" by @Rotem Dan
6️⃣  Click the extension icon → Download cookies.txt
7️⃣  Copy the file contents (Ctrl+A, Ctrl+C)
8️⃣  Paste in the next dialog

The app will save this and use it for all downloads.

<b>How often?</b> Once per month or when you get login errors.
GUIDE

    [[ $? -eq 0 ]] && _show_cookie_paste_dialog || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# _show_cookie_paste_dialog
# YAD form for pasting raw cookies.txt content
# ─────────────────────────────────────────────────────────────────────────────
_show_cookie_paste_dialog() {
    local cookie_content
    
    cookie_content=$(yad --text-info \
        --title="$APP_TITLE – Paste Cookies" \
        --text="Paste your cookies.txt file contents below:\n(Right-click in text area → Paste)" \
        --width=700 --height=300 \
        --button=" Save Cookies!gtk-ok:0" \
        --button="Cancel!gtk-cancel:1" \
        2>/dev/null)

    local btn=$?
    
    if [[ $btn -eq 0 && -n "$cookie_content" ]]; then
        echo "$cookie_content" > "${BASE_DIR}/config/cookies.txt"
        chmod 600 "${BASE_DIR}/config/cookies.txt"
        log_info "Cookies saved to config/cookies.txt"
        show_success_dialog "Cookies Saved" "Your cookies have been saved.\n\nDownloads will now use your logged-in session."
        return 0
    else
        log_info "Cookie paste cancelled"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Now update show_settings_window to add the setup button
# ─────────────────────────────────────────────────────────────────────────────

show_settings_window() {
    log_info "show_settings_window"
    local result btn

    # Build cookie browser combo (active item first)
    local _cb_active="${COOKIE_BROWSER:-none}"
    local _cb_list="Auto (detect)!None!Firefox!Chrome!Brave!Chromium"
    case "$_cb_active" in
        auto|Auto*) ;;  # stays default
        chrome)   _cb_list="Chrome!Auto (detect)!None!Firefox!Brave!Chromium" ;;
        firefox)  _cb_list="Firefox!Auto (detect)!None!Chrome!Brave!Chromium" ;;
        brave)    _cb_list="Brave!Auto (detect)!None!Chrome!Firefox!Chromium" ;;
        chromium) _cb_list="Chromium!Auto (detect)!None!Chrome!Firefox!Brave" ;;
    esac

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
        --field="🍪  Browser Cookies (auto-extract)":CB "$_cb_list" \
        --button="🍪 Manual Cookie Setup:3" \
        --button="⬆ Update yt-dlp Now:2" \
        --button="gtk-cancel:1" \
        --button="gtk-save:0" \
        2>/dev/null)
    btn=$?

    log_info "Settings: btn=$btn"
    case $btn in
        0) _save_settings "$result" ;;
        2) update_ytdlp_with_ui; show_settings_window ;;
        3) _show_cookie_setup_guide; show_settings_window ;;
    esac
}


# ─────────────────────────────────────────────────────────────────────────────
# show_settings_window
# ─────────────────────────────────────────────────────────────────────────────
show_settings_window() {
    log_info "show_settings_window"
    local result btn

    # Build cookie browser combo (active item first)
    local _cb_active="${COOKIE_BROWSER:-none}"
    local _cb_list="Auto (detect)!None!Firefox!Chrome!Brave!Chromium"
    case "$_cb_active" in
        auto|Auto*) ;;  # stays default
        chrome)   _cb_list="Chrome!Auto (detect)!None!Firefox!Brave!Chromium" ;;
        firefox)  _cb_list="Firefox!Auto (detect)!None!Chrome!Brave!Chromium" ;;
        brave)    _cb_list="Brave!Auto (detect)!None!Chrome!Firefox!Chromium" ;;
        chromium) _cb_list="Chromium!Auto (detect)!None!Chrome!Firefox!Brave" ;;
    esac

    local cookies_file="${BASE_DIR}/config/cookies.txt"
    local cookies_status="No cookies.txt (click 📋 to paste one)"
    [[ -f "$cookies_file" && -s "$cookies_file" ]] && \
        cookies_status="✅ cookies.txt active ($(wc -l < "$cookies_file") lines) — overrides browser setting"

    result=$(yad --form \
        --title="$APP_TITLE – Settings" \
        --text="<b>⚙  Preferences</b>" \
        --width=580 --center \
        --separator="|" \
        --field="📁  Default Download Folder":DIR    "${SAVE_DIR:-$HOME/CarMedia}" \
        --field="📦  Default Mode":CB                "Video!Music" \
        --field="🎬  Default Video Profile":CB       "$(_video_profile_combo)" \
        --field="🎵  Default Music Profile":CB       "$(_music_profile_combo)" \
        --field="🔢  Max Playlist Items (threshold)":NUM "${MAX_PLAYLIST_LIMIT:-50}!1..500!1!0" \
        --field="⚡  Concurrent Fragments (speed)":NUM "${YT_CONCURRENT_FRAGS:-3}!1..16!1!0" \
        --field="🔄  Auto-update yt-dlp on start":CHK "${AUTO_UPDATE:-false}" \
        --field="🍪  Browser Cookies (needs browser closed)":CB "$_cb_list" \
        --field="📋  Cookies.txt status":LBL "$cookies_status" \
        --button="📂 Import cookies.txt:3" \
        --button="🗑 Clear cookies.txt:4" \
        --button="⬆ Update yt-dlp Now:2" \
        --button="gtk-cancel:1" \
        --button="gtk-save:0" \
        2>/dev/null)
    btn=$?

    log_info "Settings: btn=$btn"
    case $btn in
        0) _save_settings "$result" ;;
        2) update_ytdlp_with_ui; show_settings_window ;;
        3) _paste_cookies_txt; show_settings_window ;;
        4) rm -f "$cookies_file"; show_success_dialog "Cleared" "cookies.txt removed."; show_settings_window ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# _import_cookies_file
# Opens a file picker so the user can select their exported cookies.txt file.
# Copies it into config/cookies.txt where yt-dlp can read it.
_paste_cookies_txt() {
    local cookies_file="${BASE_DIR}/config/cookies.txt"

    # File picker — user navigates to their cookies.txt and selects it
    local chosen_file
    chosen_file=$(yad --file \
        --title="$APP_TITLE – Select cookies.txt" \
        --text="Select your exported cookies.txt file\n(must be Netscape format from 'Get cookies.txt LOCALLY' extension)" \
        --file-filter="Cookie files (*.txt)|*.txt" \
        --file-filter="All files|*" \
        --width=700 --height=450 --center \
        2>/dev/null)

    local btn=$?
    [[ $btn -ne 0 || -z "$chosen_file" ]] && return 1

    if [[ ! -f "$chosen_file" ]]; then
        handle_error "user" "File not found:\n$chosen_file"
        return 1
    fi

    # Validate it looks like a Netscape cookies file
    if ! head -3 "$chosen_file" | grep -qi "netscape\|http cookie"; then
        yad --question \
            --title="$APP_TITLE – Confirm" \
            --text="⚠  This file doesn't look like a standard cookies.txt\n(missing Netscape HTTP Cookie File header)\n\nIt might still work. Use it anyway?" \
            --button="Yes, use it:0" --button="Cancel:1" \
            --width=420 --center 2>/dev/null || return 1
    fi

    mkdir -p "${BASE_DIR}/config"
    cp "$chosen_file" "$cookies_file"
    chmod 600 "$cookies_file"
    log_info "cookies.txt imported from: $chosen_file ($(wc -l < "$cookies_file") lines)"
    show_success_dialog "Cookies Imported ✅" "cookies.txt imported successfully!\n<b>$(wc -l < "$cookies_file") lines</b> from:\n<tt>$chosen_file</tt>\n\nAll downloads will now use these cookies.\nBrowser cookie setting is ignored when this file exists."
}

_save_settings() {
    local new_dir mode_label video_label music_label max_pl frags auto_upd cookie_label
    IFS="|" read -r new_dir mode_label video_label music_label max_pl frags auto_upd cookie_label <<< "$1"

    local new_video_profile; new_video_profile=$(_label_to_video_key "$video_label")
    local new_music_profile; new_music_profile=$(_label_to_music_key "$music_label")
    local new_mode; [[ "$mode_label" == "Music" ]] && new_mode="music" || new_mode="video"
    [[ "$auto_upd" == "TRUE" ]] && auto_upd="true" || auto_upd="false"
    local frags_int="${frags%%.*}"
    local maxpl_int="${max_pl%%.*}"

    # Translate label → yt-dlp browser name (lowercase, 'none' for disabled)
    local new_cookie
    case "${cookie_label,,}" in   # lowercase the label
        auto*|auto\ *)            new_cookie="auto"     ;;
        chrome)                   new_cookie="chrome"   ;;
        firefox)                  new_cookie="firefox"  ;;
        brave)                    new_cookie="brave"    ;;
        chromium)                 new_cookie="chromium" ;;
        *)                        new_cookie="none"     ;;
    esac

    cat > "${BASE_DIR}/config/settings.conf" << CONF
DEFAULT_DOWNLOAD_DIR="${new_dir}"
DEFAULT_MODE="${new_mode}"
DEFAULT_VIDEO_PROFILE="${new_video_profile}"
DEFAULT_MUSIC_PROFILE="${new_music_profile}"
MAX_PLAYLIST_LIMIT=${maxpl_int}
YT_CONCURRENT_FRAGS=${frags_int}
AUTO_UPDATE="${auto_upd}"
COOKIE_BROWSER="${new_cookie}"
CONF

    SAVE_DIR="$new_dir"
    DEFAULT_DOWNLOAD_DIR="$new_dir"
    DEFAULT_MODE="$new_mode"
    DEFAULT_VIDEO_PROFILE="$new_video_profile"
    DEFAULT_MUSIC_PROFILE="$new_music_profile"
    MAX_PLAYLIST_LIMIT="$maxpl_int"
    YT_CONCURRENT_FRAGS="$frags_int"
    AUTO_UPDATE="$auto_upd"
    COOKIE_BROWSER="$new_cookie"
    export COOKIE_BROWSER

    log_info "Settings saved: dir=$new_dir mode=$new_mode vp=$new_video_profile mp=$new_music_profile maxpl=$maxpl_int frags=$frags_int cookies=$new_cookie"
    show_success_dialog "Settings Saved" "Preferences saved successfully."
}
