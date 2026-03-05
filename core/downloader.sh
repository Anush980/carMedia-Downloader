#!/usr/bin/env bash
# core/downloader.sh — builds the YT_DLP_ARGS array for every download job.

build_yt_dlp_args() {
    local url="$1"
    local mode="$2"
    local profile_key="$3"
    local output_dir="$4"
    local url_type="${5:-single_video}"
    local playlist_items="${6:-}"

    log_info "build_yt_dlp_args: mode=$mode profile=$profile_key url_type=$url_type items=[$playlist_items]"

    local fmt; fmt=$(get_profile_format "$mode" "$profile_key")
    local merge; merge=$(get_profile_merge "$mode" "$profile_key")

    YT_DLP_ARGS=()

    # CRITICAL: ignore ~/.config/yt-dlp/config — if it has --cookies-from-browser
    # from a previous manual run it silently overrides everything and causes
    # "format not available" on every video no matter what settings you change.
    YT_DLP_ARGS+=( --ignore-config )

    # Output path
    if [[ "$url_type" == "playlist" ]]; then
        YT_DLP_ARGS+=( --output "${output_dir}/%(playlist_title)s/%(playlist_index)02d - %(title)s.%(ext)s" )
    else
        YT_DLP_ARGS+=( --output "${output_dir}/%(title)s.%(ext)s" )
    fi

    # Playlist / single control
    case "$url_type" in
        single_video|video_in_playlist)
            YT_DLP_ARGS+=( --no-playlist )
            log_info "  Using --no-playlist (url_type=$url_type)"
            ;;
        playlist)
            if [[ -n "$playlist_items" ]]; then
                YT_DLP_ARGS+=( --playlist-items "$playlist_items" )
                log_info "  Using --playlist-items $playlist_items"
            fi
            ;;
    esac

    # Format
    YT_DLP_ARGS+=( --format "$fmt" )

    # Post-processing
    if is_music_profile "$profile_key"; then
        YT_DLP_ARGS+=( -x )
        case "$profile_key" in
            mp3)  YT_DLP_ARGS+=( --audio-format mp3  --audio-quality 0 ) ;;
            m4a)  YT_DLP_ARGS+=( --audio-format m4a  --audio-quality 0 ) ;;
            opus) YT_DLP_ARGS+=( --audio-format opus --audio-quality 0 ) ;;
        esac
        YT_DLP_ARGS+=( --embed-thumbnail --embed-metadata --add-metadata )
    else
        YT_DLP_ARGS+=( --merge-output-format "$merge" )
        YT_DLP_ARGS+=( --add-metadata )
    fi

    # Speed / reliability
    YT_DLP_ARGS+=( --concurrent-fragments "${YT_CONCURRENT_FRAGS:-3}" )
    YT_DLP_ARGS+=( --retries 3 --fragment-retries 5 )
    YT_DLP_ARGS+=( --retry-sleep linear=1::2 )
    YT_DLP_ARGS+=( --socket-timeout 30 )
    YT_DLP_ARGS+=( --throttled-rate 50K )

    # Cookies — priority: cookies.txt file > browser > none
    # NOTE: YouTube now requires cookies on most IPs to avoid bot detection.
    # "Sign in to confirm you're not a bot" = no cookies being sent.
    local cb="${COOKIE_BROWSER:-none}"
    local cookies_file="${BASE_DIR}/config/cookies.txt"
    if [[ -f "$cookies_file" && -s "$cookies_file" ]]; then
        YT_DLP_ARGS+=( --cookies "$cookies_file" )
        log_info "  Cookies: cookies.txt file ($(wc -l < "$cookies_file") lines)"
    elif [[ "$cb" != "none" && -n "$cb" ]]; then
        YT_DLP_ARGS+=( --cookies-from-browser "$cb" )
        log_info "  Cookies: from browser '$cb' (browser must be fully closed)"
    else
        log_warn "  Cookies: NONE — YouTube may block with 'Sign in to confirm you're not a bot'"
        log_warn "  Fix: go to Settings and set a browser, or paste a cookies.txt"
    fi

    # Skip unavailable items in playlists
    [[ "$url_type" == "playlist" ]] && YT_DLP_ARGS+=( --ignore-errors )

    # Live progress output
    YT_DLP_ARGS+=( --newline )

    # URL always last
    YT_DLP_ARGS+=( "$url" )

    log_info "  Full yt-dlp command: yt-dlp ${YT_DLP_ARGS[*]}"
}
