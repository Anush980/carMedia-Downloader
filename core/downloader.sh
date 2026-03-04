#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# core/downloader.sh
#
# PURPOSE:
#   Builds the yt-dlp command argument array based on:
#     - Profile (format string)
#     - URL type (single/playlist/video_in_playlist)
#     - Selected playlist indices
#     - Output directory
#     - Speed settings
#
# KEY DESIGN:
#   The argument array (YT_DLP_ARGS) is the ONLY place yt-dlp flags are set.
#   download_manager.sh just executes: yt-dlp "${YT_DLP_ARGS[@]}"
#   This separation makes it easy to debug — log YT_DLP_ARGS to see exactly
#   what command will run.
#
# CRITICAL FLAGS EXPLAINED:
#
#   --no-playlist
#     MUST be used for single_video and video_in_playlist URL types.
#     Without it, yt-dlp detects the list= param and downloads all ~100 videos.
#     This is the root fix for "downloading whole playlist instead of one video".
#
#   --playlist-items 1,3,5
#     Used for playlist URL type when user has made a selection.
#     Downloads EXACTLY those indices, nothing more, nothing else.
#     Superior to --playlist-end which just says "stop after N" but may
#     still scan/process more videos internally.
#
#   --extractor-args youtube:player_client=android
#     Bypasses YouTube's bot detection. The Android client receives
#     direct CDN stream URLs without throttling, dramatically faster.
#
#   --concurrent-fragments N
#     Downloads N DASH fragments in parallel. Default 5.
#     For a 1080p video, this can 4-5x the effective download speed.
#
# USED BY: download_manager.sh
# ─────────────────────────────────────────────────────────────────────────────

# build_yt_dlp_args
# Parameters:
#   $1  url
#   $2  mode          (video|music)
#   $3  profile_key   (car|hd|fast|best|mp3|m4a|opus)
#   $4  output_dir
#   $5  url_type      (single_video|playlist|video_in_playlist)
#   $6  playlist_items  (comma-separated indices, e.g. "1,3,5" — empty = all)
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

    # ── Output template ──────────────────────────────────────────────────────
    # For playlists: organise into subfolder named after playlist
    if [[ "$url_type" == "playlist" ]]; then
        YT_DLP_ARGS+=( --output "${output_dir}/%(playlist_title)s/%(playlist_index)02d - %(title)s.%(ext)s" )
    else
        YT_DLP_ARGS+=( --output "${output_dir}/%(title)s.%(ext)s" )
    fi

    # ── CRITICAL: Playlist vs single control ─────────────────────────────────
    case "$url_type" in
        single_video|video_in_playlist)
            # MUST use --no-playlist to prevent yt-dlp from expanding list= param
            YT_DLP_ARGS+=( --no-playlist )
            log_info "  Using --no-playlist (url_type=$url_type)"
            ;;
        playlist)
            if [[ -n "$playlist_items" ]]; then
                # Download EXACTLY these indices — the only reliable limit method
                YT_DLP_ARGS+=( --playlist-items "$playlist_items" )
                log_info "  Using --playlist-items $playlist_items"
            fi
            # No --no-playlist here — we want the playlist
            ;;
    esac

    # ── Format selection ──────────────────────────────────────────────────────
    YT_DLP_ARGS+=( --format "$fmt" )

    # ── Post-processing ───────────────────────────────────────────────────────
    if is_music_profile "$profile_key"; then
        # Audio extraction + conversion
        YT_DLP_ARGS+=( -x )
        case "$profile_key" in
            mp3)  YT_DLP_ARGS+=( --audio-format mp3 --audio-quality 0 ) ;;
            m4a)  YT_DLP_ARGS+=( --audio-format m4a --audio-quality 0 ) ;;
            opus) YT_DLP_ARGS+=( --audio-format opus --audio-quality 0 ) ;;
        esac
        # Embed metadata and thumbnail for music
        YT_DLP_ARGS+=( --embed-thumbnail --embed-metadata --add-metadata )
    else
        # Video merge
        YT_DLP_ARGS+=( --merge-output-format "$merge" )
        YT_DLP_ARGS+=( --add-metadata )
    fi

    # ── Speed optimisations ───────────────────────────────────────────────────
    # NOTE: Do NOT force --extractor-args youtube:player_client=android here.
    # The android client now requires a GVS PO Token (mid-2024 YouTube change).
    # Without the token it only serves format 18 (360p), causing strict format
    # strings (car/hd profiles) to find no matching streams → exit code 2.
    # yt-dlp's default client selection (web + safari fallback) gives full
    # HD format access without any token.

    # Parallel fragment download (DASH/HLS)
    YT_DLP_ARGS+=( --concurrent-fragments "${YT_CONCURRENT_FRAGS:-5}" )

    # ── Reliability ───────────────────────────────────────────────────────────
    YT_DLP_ARGS+=( --retries 3 --fragment-retries 5 )
    YT_DLP_ARGS+=( --retry-sleep linear=1::2 )

    # ── Browser Cookies (for age-restricted / login-required videos) ──────────
    # Set COOKIE_BROWSER to chrome, firefox, brave, or chromium in Settings.
    # yt-dlp will read the browser's cookie store so authenticated downloads
    # work even for members-only / age-gated / sign-in-required content.
    local cb="${COOKIE_BROWSER:-none}"
    if [[ "$cb" != "none" && -n "$cb" ]]; then
        YT_DLP_ARGS+=( --cookies-from-browser "$cb" )
        log_info "  Using cookies from browser: $cb"
    fi

    # Skip unavailable videos in a playlist (don't abort the whole batch)
    [[ "$url_type" == "playlist" ]] && YT_DLP_ARGS+=( --ignore-errors )

    # Progress (line-buffered for real-time parsing)
    YT_DLP_ARGS+=( --newline )

    # ── URL — always last ─────────────────────────────────────────────────────
    YT_DLP_ARGS+=( "$url" )

    log_info "  Full yt-dlp command: yt-dlp ${YT_DLP_ARGS[*]}"
}

