#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# core/playlist_parser.sh
#
# PURPOSE:
#   Shows a YAD checklist window populated with all videos in a playlist.
#   The user ticks which videos they want. Only ticked video indices are
#   returned — the download system then uses --playlist-items INDEX,INDEX,...
#   which tells yt-dlp exactly which videos to download, nothing more.
#
# WHY --playlist-items INSTEAD OF --playlist-end:
#   --playlist-end N downloads the first N videos and might still scan more.
#   --playlist-items 1,3,7 downloads EXACTLY those three, nothing else.
#   This is the only reliable fix for "downloads more than selected" bug.
#
# OUTPUT:
#   Sets global SELECTED_INDICES (comma-separated, e.g. "1,3,5")
#   and SELECTED_URLS (newline-separated individual video URLs)
#
# USED BY: ui.sh → _handle_playlist_flow()
# ─────────────────────────────────────────────────────────────────────────────

SELECTED_INDICES=""
SELECTED_URLS=""

# show_playlist_selector URL MAX_SHOW
# MAX_SHOW: how many items to fetch (0=all, respects settings threshold)
show_playlist_selector() {
    local url="$1"
    local max_show="${2:-0}"

    log_info "Fetching playlist metadata from: $url"

    # Show a "fetching" spinner while we load metadata
    (
        sleep 0.2; echo "20"; echo "# Loading playlist info..."
        sleep 0.5; echo "50"; echo "# Fetching video titles..."
        sleep 30   # will be killed once data arrives
    ) | yad --progress \
            --title=" window may close and re-open" \
            --text="Fetching playlist metadata, please wait..." \
            --pulsate --auto-kill \
            --width=400 --center 2>/dev/null &
    local spinner_pid=$!

    # Fetch items
    local raw_items
    raw_items=$(fetch_playlist_items "$url")

    # Kill spinner
    kill "$spinner_pid" 2>/dev/null || true
    wait "$spinner_pid" 2>/dev/null || true

    if [[ -z "$raw_items" ]]; then
        handle_error "playlist" "Could not fetch playlist items.\nCheck the URL and your connection."
        return 1
    fi

    # Count items
    local total_count
    total_count=$(echo "$raw_items" | wc -l)
    log_info "Playlist has $total_count videos"

    # Apply max_show limit (respects settings threshold)
    local items_to_show="$raw_items"
    if [[ "$max_show" -gt 0 && "$total_count" -gt "$max_show" ]]; then
        items_to_show=$(echo "$raw_items" | head -"$max_show")
        log_info "Limiting display to first $max_show of $total_count videos"
    fi

    # Build YAD list arguments
    # Columns: CHECK(bool) | # | Title | Duration
    local yad_args=()
    while IFS="|" read -r idx title dur vid_url; do
        [[ -z "$idx" ]] && continue
        # Clean up title (remove pipe chars that break YAD)
        title="${title//|/ }"
        dur="${dur:-?}"
        yad_args+=( "TRUE" "$idx" "$title" "$dur" )
    done <<< "$items_to_show"

    if [[ ${#yad_args[@]} -eq 0 ]]; then
        handle_error "playlist" "No downloadable videos found in this playlist."
        return 1
    fi

    log_info "Showing playlist selector with ${#yad_args[@]} entries"

    # Show YAD checklist
    local selection
    selection=$(yad --list \
        --title="CarMedia Pro – Select Videos to Download" \
        --text="<b>Playlist: ${total_count} videos</b>\nTick the videos you want to download.\n<small>Only ticked videos will be downloaded.</small>" \
        --width=700 --height=520 \
        --center \
        --checklist \
        --column="✓":CHK \
        --column="#":NUM \
        --column="Title":TEXT \
        --column="Duration":TEXT \
        --separator="|" \
        --print-column=2 \
        "${yad_args[@]}" \
        --button="Select All:2" \
        --button="Deselect All:3" \
        --button="gtk-cancel:1" \
        --button="Download Selected:0" \
        2>/dev/null)
    local btn=$?

    log_info "Playlist selector closed: btn=$btn selection=[$selection]"

    case $btn in
        0)  # Download selected
            if [[ -z "$selection" ]]; then
                handle_error "user" "No videos selected.\nPlease tick at least one video."
                return 1
            fi
            # selection is a newline-separated list of indices with trailing pipes like "1|\n2|\n"
            SELECTED_INDICES=$(echo "$selection" | tr -d '|' | tr '\n' ',' | sed 's/,$//')
            log_info "User selected indices: $SELECTED_INDICES"
            return 0
            ;;
        2)  # Select all — recurse with all=TRUE
            show_playlist_selector_all "$url" "$raw_items"
            return $?
            ;;
        3)  # Deselect all — recurse with all=FALSE
            show_playlist_selector "$url" "$max_show"
            return $?
            ;;
        *)  # Cancel
            log_info "User cancelled playlist selection"
            return 1
            ;;
    esac
}

# show_playlist_selector_all URL RAW_ITEMS
# Called when user hits "Select All" — same window but all pre-ticked
show_playlist_selector_all() {
    local url="$1" raw_items="$2"
    local yad_args=()

    while IFS="|" read -r idx title dur vid_url; do
        [[ -z "$idx" ]] && continue
        title="${title//|/ }"
        dur="${dur:-?}"
        yad_args+=( "TRUE" "$idx" "$title" "$dur" )
    done <<< "$raw_items"

    local selection
    selection=$(yad --list \
        --title="CarMedia Pro – Select Videos (All Selected)" \
        --text="<b>All videos selected.</b> Untick any you want to skip." \
        --width=700 --height=520 \
        --center \
        --checklist \
        --column="✓":CHK \
        --column="#":NUM \
        --column="Title":TEXT \
        --column="Duration":TEXT \
        --separator="|" \
        --print-column=2 \
        "${yad_args[@]}" \
        --button="gtk-cancel:1" \
        --button="Download Selected:0" \
        2>/dev/null)
    local btn=$?

    case $btn in
        0)
            if [[ -z "$selection" ]]; then
                handle_error "user" "No videos selected."
                return 1
            fi
            SELECTED_INDICES=$(echo "$selection" | tr -d '|' | tr '\n' ',' | sed 's/,$//')
            log_info "Select-all result: $SELECTED_INDICES"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
