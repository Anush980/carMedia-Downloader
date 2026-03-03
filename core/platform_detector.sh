#!/usr/bin/env bash
# core/platform_detector.sh

detect_platform() {
    if   [[ "$1" =~ (youtube\.com|youtu\.be) ]]; then echo "youtube"
    elif [[ "$1" =~ facebook\.com ]];             then echo "facebook"
    elif [[ "$1" =~ instagram\.com ]];            then echo "instagram"
    elif [[ "$1" =~ (twitter\.com|x\.com) ]];     then echo "twitter"
    else                                               echo "unknown"
    fi
}

is_supported_platform() { [[ "$1" == "youtube" ]]; }

is_playlist_url() { [[ "$1" =~ (list=|/playlist) ]]; }

get_platform_label() {
    case "$1" in
        youtube)   echo "YouTube"     ;;
        facebook)  echo "Facebook"    ;;
        instagram) echo "Instagram"   ;;
        twitter)   echo "Twitter / X" ;;
        *)         echo "Unknown"     ;;
    esac
}
