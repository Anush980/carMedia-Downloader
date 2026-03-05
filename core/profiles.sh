#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# core/profiles.sh
#
# PURPOSE:
#   Defines all download profiles as named format strings for yt-dlp's -f flag.
#   Separates VIDEO profiles from MUSIC profiles so each mode has its own
#   sensible defaults without the user needing to know yt-dlp syntax.
#
# VIDEO PROFILES (mode=video):
#   car    - 720p H.264 + AAC in MP4  →  safe for all car head units
#   hd     - 1080p H.264 + AAC in MP4 →  best quality car-compatible
#   fast   - single best MP4 stream   →  no re-encoding needed
#   best   - max quality → MKV        →  archiving
#
# MUSIC PROFILES (mode=music):
#   mp3    - MP3 320kbps + embedded metadata + cover art
#   m4a    - M4A AAC best quality     →  better for Apple CarPlay
#   opus   - Opus (best streaming codec, smallest file size)
#
# USED BY: downloader.sh, ui.sh (combo box population)
# ─────────────────────────────────────────────────────────────────────────────

# ── Video format strings ──────────────────────────────────────────────────────
#
# WHY no vcodec^=avc1 hard filter:
#   YouTube no longer guarantees standalone H.264 DASH streams for every video.
#   A hard [vcodec^=avc1] filter silently finds nothing → "format not available".
#   The [best[height<=720]] fallback also fails since YouTube rarely serves
#   pre-muxed streams anymore.
#
# HOW CarPlay / car head unit compatibility is achieved WITHOUT the filter:
#   1. We prefer [ext=mp4] on the video stream — when available this IS H.264
#   2. --merge-output-format mp4 (set in downloader.sh) wraps everything in MP4
#   3. ffmpeg re-encodes audio to AAC if needed during the merge step
#   YouTube's 720p mp4 streams are almost always H.264 in practice; VP9 is
#   only served as webm. So [ext=mp4] is a soft H.264 preference, not a gamble.
#
PROFILE_CAR_FORMAT='bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best'
PROFILE_HD_FORMAT='bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=1080]+bestaudio[ext=m4a]/bestvideo[height<=1080]+bestaudio/best'
PROFILE_FAST_FORMAT='best[ext=mp4]/best'
PROFILE_BEST_FORMAT='bestvideo+bestaudio/best'

# ── Music format strings ──────────────────────────────────────────────────────
PROFILE_MP3_FORMAT='bestaudio/best'
PROFILE_M4A_FORMAT='bestaudio[ext=m4a]/bestaudio'
PROFILE_OPUS_FORMAT='bestaudio[ext=webm]/bestaudio'

# get_profile_format MODE KEY  →  echoes yt-dlp -f format string
get_profile_format() {
    local mode="$1" key="$2"
    case "${mode}:${key}" in
        video:car)   echo "$PROFILE_CAR_FORMAT"  ;;
        video:hd)    echo "$PROFILE_HD_FORMAT"   ;;
        video:fast)  echo "$PROFILE_FAST_FORMAT" ;;
        video:best)  echo "$PROFILE_BEST_FORMAT" ;;
        music:mp3)   echo "$PROFILE_MP3_FORMAT"  ;;
        music:m4a)   echo "$PROFILE_M4A_FORMAT"  ;;
        music:opus)  echo "$PROFILE_OPUS_FORMAT" ;;
        # Fallback: try key alone for backwards compat
        *:car)   echo "$PROFILE_CAR_FORMAT"  ;;
        *:fast)  echo "$PROFILE_FAST_FORMAT" ;;
        *:mp3)   echo "$PROFILE_MP3_FORMAT"  ;;
        *)       echo "$PROFILE_CAR_FORMAT"  ;;
    esac
}

# get_profile_merge MODE KEY  →  echoes --merge-output-format value
get_profile_merge() {
    local mode="$1" key="$2"
    case "${mode}:${key}" in
        music:*)  echo "mp3" ;;
        video:best) echo "mkv" ;;
        *)        echo "mp4"  ;;
    esac
}

# get_profile_label KEY  →  human-readable label
get_profile_label() {
    case "$1" in
        car)  echo "Car Compatible (720p H.264+AAC)"  ;;
        hd)   echo "HD (1080p H.264+AAC)"             ;;
        fast) echo "Fast (Best single MP4)"            ;;
        best) echo "Best Quality (max res, MKV)"       ;;
        mp3)  echo "MP3 320kbps (Music)"               ;;
        m4a)  echo "M4A AAC (Apple CarPlay Music)"     ;;
        opus) echo "Opus (smallest size)"              ;;
        *)    echo "$1" ;;
    esac
}

# list_video_profiles_yad / list_music_profiles_yad
# Output: "key|label" per line — consumed by ui.sh for combo boxes
list_video_profiles_yad() {
    echo "car|Car Compatible (720p H.264+AAC)"
    echo "hd|HD (1080p H.264+AAC)"
    echo "fast|Fast (Best single MP4)"
    echo "best|Best Quality (max res, MKV)"
}

list_music_profiles_yad() {
    echo "mp3|MP3 320kbps (Music)"
    echo "m4a|M4A AAC (Apple CarPlay Music)"
    echo "opus|Opus (smallest size)"
}

is_music_profile() { [[ "$1" == "mp3" || "$1" == "m4a" || "$1" == "opus" ]]; }
is_video_profile() { ! is_music_profile "$1"; }
