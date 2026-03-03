#!/usr/bin/env bash
# core/downloader.sh — yt-dlp execution engine

build_yt_dlp_args() {
    local url="$1" profile_key="$2" output_dir="$3" playlist_limit="${4:-0}"

    log_info "Building yt-dlp args: profile=$profile_key dir=$output_dir limit=$playlist_limit"

    local fmt; fmt=$(get_profile_format "$profile_key")
    local merge; merge=$(get_profile_merge "$profile_key")

    YT_DLP_ARGS=()
    YT_DLP_ARGS+=( --output "${output_dir}/%(title)s.%(ext)s" )
    YT_DLP_ARGS+=( --format "$fmt" )

    if is_audio_profile "$profile_key"; then
        YT_DLP_ARGS+=( -x --audio-format mp3 --audio-quality 0 )
    else
        YT_DLP_ARGS+=( --merge-output-format "$merge" )
    fi

    # Speed optimisations
    YT_DLP_ARGS+=( --extractor-args "youtube:player_client=android" )
    YT_DLP_ARGS+=( --concurrent-fragments "${YT_CONCURRENT_FRAGS:-5}" )
    YT_DLP_ARGS+=( --buffer-size 16K )

    # Reliability
    YT_DLP_ARGS+=( --retries 3 --fragment-retries 5 )

    # Playlist limit
    [[ "$playlist_limit" -gt 0 ]] && YT_DLP_ARGS+=( --playlist-end "$playlist_limit" )

    # Metadata
    YT_DLP_ARGS+=( --add-metadata )

    # Progress on separate lines (needed for parsing)
    YT_DLP_ARGS+=( --newline )

    # URL last
    YT_DLP_ARGS+=( "$url" )

    log_info "yt-dlp args built: ${YT_DLP_ARGS[*]}"
}
