#!/usr/bin/env bash
# core/profiles.sh

PROFILE_CAR_FORMAT='bestvideo[vcodec^=avc1][height<=720][ext=mp4]+bestaudio[ext=m4a]/bestvideo[vcodec^=avc1][height<=720]+bestaudio/best[height<=720]'
PROFILE_FAST_FORMAT='best[ext=mp4]/best'
PROFILE_BEST_FORMAT='bestvideo+bestaudio/best'
PROFILE_AUDIO_FORMAT='bestaudio/best'

get_profile_format() {
    case "$1" in
        car)   echo "$PROFILE_CAR_FORMAT"   ;;
        fast)  echo "$PROFILE_FAST_FORMAT"  ;;
        best)  echo "$PROFILE_BEST_FORMAT"  ;;
        audio) echo "$PROFILE_AUDIO_FORMAT" ;;
        *)     echo "$PROFILE_CAR_FORMAT"   ;;
    esac
}

get_profile_merge() {
    case "$1" in
        audio) echo "mp3" ;;
        best)  echo "mkv" ;;
        *)     echo "mp4" ;;
    esac
}

get_profile_label() {
    case "$1" in
        car)   echo "Car Compatible (720p H.264 + AAC)" ;;
        fast)  echo "Fast Mode (Best single MP4)"       ;;
        best)  echo "Best Quality (Max res + audio)"    ;;
        audio) echo "Audio Only (MP3 high quality)"     ;;
        *)     echo "Car Compatible (720p H.264 + AAC)" ;;
    esac
}

list_profiles_yad() {
    echo "car|Car Compatible (720p H.264 + AAC)"
    echo "fast|Fast Mode (Best single MP4)"
    echo "best|Best Quality (Max res + audio)"
    echo "audio|Audio Only (MP3 high quality)"
}

is_audio_profile() { [[ "$1" == "audio" ]]; }
