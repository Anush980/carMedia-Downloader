#!/usr/bin/env bash
# ui.sh — Pure YAD GUI. No sourcing. No path calculations.
# All functions/vars already in scope from main.sh.

APP_TITLE="CarMedia Downloader"
APP_VERSION="1.2.0"

start_ui() {
    log_info "start_ui called"
    local cfg="${BASE_DIR}/config/settings.conf"
    if [[ -f "$cfg" ]]; then
        log_info "Loading config: $cfg"
        source "$cfg"
    else
        log_warn "No config found at $cfg — using defaults"
    fi

    SAVE_DIR="${DEFAULT_DOWNLOAD_DIR:-$HOME/CarMedia}"
    DEFAULT_PROFILE="${DEFAULT_PROFILE:-car}"
    AUTO_UPDATE="${AUTO_UPDATE:-false}"

    [[ "$AUTO_UPDATE" == "true" ]] && { log_info "Auto-update enabled"; update_ytdlp; }

    log_info "Opening main window (SAVE_DIR=$SAVE_DIR profile=$DEFAULT_PROFILE)"
    show_main_window
}

_profile_combo() {
    local active="${DEFAULT_PROFILE:-car}" combo=()
    while IFS="|" read -r key label; do
        [[ "$key" == "$active" ]] && combo=("$label" "${combo[@]}") || combo+=("$label")
    done < <(list_profiles_yad)
    local IFS="!"; echo "${combo[*]}"
}

_label_to_key() {
    while IFS="|" read -r key label; do
        [[ "$label" == "$1" ]] && echo "$key" && return
    done < <(list_profiles_yad)
    echo "car"
}

show_main_window() {
    log_info "show_main_window"
    local result btn

    result=$(yad --form \
        --title="$APP_TITLE  v$APP_VERSION" \
        --text="<b>CarMedia Downloader</b>\nDownload videos optimised for your car or CarPlay." \
        --width=600 --height=400 \
        --center \
        --separator="|" \
        --field="Video / Playlist URL":TEXT  "" \
        --field="Profile":CB                 "$(_profile_combo)" \
        --field="Save To":DIR                "${SAVE_DIR:-$HOME/CarMedia}" \
        --field="Playlist download":CHK      FALSE \
        --field="Playlist limit (0=all)":NUM "0!0..999!1!0" \
        --button="Settings:2" \
        --button="cancel:1" \
        --button="Download:0" \
        2>/dev/null)
    btn=$?

    log_info "Main window closed with btn=$btn"

    case $btn in
        0) _submit "$result" ;;
        1) log_info "User exited"; exit 0 ;;
        2) show_settings_window; show_main_window ;;
        *) log_warn "Unknown button: $btn"; show_main_window ;;
    esac
}

_submit() {
    local raw="$1"
    log_info "_submit raw=[$raw]"

    local url profile_label save_dir playlist_on playlist_limit
    IFS="|" read -r url profile_label save_dir playlist_on playlist_limit <<< "$raw"

    log_info "Parsed: url=[$url] profile=[$profile_label] dir=[$save_dir] playlist=[$playlist_on] limit=[$playlist_limit]"

    # Validate
    if [[ -z "${url// }" ]]; then
        log_warn "Empty URL submitted"
        handle_error "user" "Please enter a video or playlist URL."
        show_main_window; return
    fi

    if ! [[ "$url" =~ ^https?:// ]]; then
        log_warn "Invalid URL: $url"
        handle_error "user" "URL does not look valid:\n${url}"
        show_main_window; return
    fi

    local platform; platform=$(detect_platform "$url")
    log_info "Detected platform: $platform"

    if ! is_supported_platform "$platform"; then
        log_warn "Unsupported platform: $platform"
        handle_error "user" "Platform not supported: $(get_platform_label "$platform")\nCurrently supported: YouTube"
        show_main_window; return
    fi

    local profile_key; profile_key=$(_label_to_key "$profile_label")
    local limit=0
    [[ "$playlist_on" == "TRUE" ]] && limit="${playlist_limit%%.*}"

    log_info "Starting dm_run: url=$url profile=$profile_key dir=$save_dir limit=$limit"

    dm_run "$url" "$profile_key" "$save_dir" "$limit"

    log_info "dm_run returned — asking user for next action"

    yad --question \
        --title="$APP_TITLE" \
        --text="Download finished!\n\nDownload another?" \
        --button="Yes:0" \
        --button="Exit:1" \
        --width=320 --center 2>/dev/null && show_main_window || { log_info "User chose exit"; exit 0; }
}

show_settings_window() {
    log_info "show_settings_window"
    local result btn

    result=$(yad --form \
        --title="$APP_TITLE – Settings" \
        --text="<b>Preferences</b>" \
        --width=520 --center \
        --separator="|" \
        --field="Default Folder":DIR  "${SAVE_DIR:-$HOME/CarMedia}" \
        --field="Default Profile":CB  "$(_profile_combo)" \
        --field="Auto-update on start":CHK "${AUTO_UPDATE:-false}" \
        --field="Concurrent fragments":NUM  "5!1..16!1!0" \
        --button="Update yt-dlp Now:2" \
        --button="cancel:1" \
        --button="save:0" \
        2>/dev/null)
    btn=$?

    log_info "Settings closed btn=$btn"
    case $btn in
        0) _save_settings "$result" ;;
        2) update_ytdlp_with_ui; show_settings_window ;;
    esac
}

_save_settings() {
    local new_dir new_label auto_upd frags new_profile
    IFS="|" read -r new_dir new_label auto_upd frags <<< "$1"
    new_profile=$(_label_to_key "$new_label")
    [[ "$auto_upd" == "TRUE" ]] && auto_upd="true" || auto_upd="false"
    local frag_count="${frags%%.*}"

    cat > "${BASE_DIR}/config/settings.conf" << CONF
DEFAULT_DOWNLOAD_DIR="${new_dir}"
DEFAULT_PROFILE="${new_profile}"
AUTO_UPDATE="${auto_upd}"
YT_CONCURRENT_FRAGS=${frag_count}
CONF

    SAVE_DIR="$new_dir"; DEFAULT_DOWNLOAD_DIR="$new_dir"
    DEFAULT_PROFILE="$new_profile"; AUTO_UPDATE="$auto_upd"
    YT_CONCURRENT_FRAGS="$frag_count"

    log_info "Settings saved"
    show_success_dialog "Saved" "Preferences saved."
}
