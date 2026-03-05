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
#
# Uses an internal while loop so Select All / Deselect All / Show All never
# close or reload the window — they just flip state and re-show the same data.
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
            --title="CarMedia Pro – Loading" \
            --text="Fetching playlist metadata, please wait..." \
            --pulsate --auto-kill \
            --width=400 --center 2>/dev/null &
    local spinner_pid=$!

    # Fetch items (ONCE — never repeated on Select/Deselect All / Show All)
    local raw_items
    raw_items=$(fetch_playlist_items "$url")

    # Kill spinner
    kill "$spinner_pid" 2>/dev/null || true
    wait "$spinner_pid" 2>/dev/null || true

    if [[ -z "$raw_items" ]]; then
        handle_error "playlist" "Could not fetch playlist items.\nCheck the URL and your connection."
        return 1
    fi

    # Count total items
    local total_count
    total_count=$(echo "$raw_items" | wc -l)
    log_info "Playlist has $total_count videos"

    # ── Main selector loop ────────────────────────────────────────────────────
    # State variables — modified by button presses inside the loop.
    #   checked_state : TRUE = all ticked, FALSE = all unticked
    #   show_all      : false = respect max_show limit, true = show everything
    # No extra network calls anywhere in the loop.
    local checked_state="TRUE"
    local show_all=false

    # Start with limited view if threshold applies
    local items_to_show="$raw_items"
    if [[ "$max_show" -gt 0 && "$total_count" -gt "$max_show" ]]; then
        items_to_show=$(echo "$raw_items" | head -"$max_show")
        log_info "Limiting display to first $max_show of $total_count videos"
    fi

    while true; do
        # Build YAD row args with current checked_state for visible rows
        local yad_args=()
        while IFS="|" read -r idx title dur vid_url; do
            [[ -z "$idx" ]] && continue
            title="${title//|/ }"   # Remove pipes that break YAD columns
            dur="${dur:-?}"
            yad_args+=( "$checked_state" "$idx" "$title" "$dur" )
        done <<< "$items_to_show"

        if [[ ${#yad_args[@]} -eq 0 ]]; then
            handle_error "playlist" "No downloadable videos found in this playlist."
            return 1
        fi

        local showing_count=$(( ${#yad_args[@]} / 4 ))
        log_info "Showing playlist selector (checked_state=$checked_state show_all=$show_all showing=$showing_count of $total_count)"

        # Window title/text reflects current view
        local window_text="<b>Playlist: showing ${showing_count} of ${total_count} videos</b>\nTick the videos you want to download.\n<small>Only ticked videos will be downloaded.</small>"
        [[ "$checked_state" == "TRUE" ]] && \
            window_text="<b>All ${showing_count} shown videos selected.</b>\nUntick any you want to skip."

        # Buttons — "Show All" only appears when we're not already showing all
        local btn_show_all=()
        if [[ "$show_all" == "false" && "$total_count" -gt "$showing_count" ]]; then
            btn_show_all=( "--button=📋 Show All ${total_count} Videos:4" )
        fi

        local selection
        selection=$(yad --list \
            --title="CarMedia Pro – Select Videos to Download" \
            --text="$window_text" \
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
            "${btn_show_all[@]}" \
            --button="☑ Select All:2" \
            --button="☐ Deselect All:3" \
            --button="gtk-cancel:1" \
            --button="⬇ Download Selected:0" \
            2>/dev/null)
        local btn=$?

        log_info "Playlist selector btn=$btn selection=[$selection]"

        case $btn in
            0)  # ── Download Selected ─────────────────────────────────────────
                if [[ -z "$selection" ]]; then
                    handle_error "user" "No videos selected.\nPlease tick at least one video."
                    checked_state="FALSE"
                    continue
                fi
                SELECTED_INDICES=$(echo "$selection" | tr -d '|' | tr '\n' ',' | sed 's/,$//')
                log_info "User selected indices: $SELECTED_INDICES"
                return 0
                ;;
            2)  # ── Select All ────────────────────────────────────────────────
                log_info "Select All clicked"
                checked_state="TRUE"
                continue
                ;;
            3)  # ── Deselect All ──────────────────────────────────────────────
                log_info "Deselect All clicked"
                checked_state="FALSE"
                continue
                ;;
            4)  # ── Show All ──────────────────────────────────────────────────
                log_info "Show All clicked — expanding to all $total_count videos"
                show_all=true
                items_to_show="$raw_items"   # already in memory — no network call
                continue
                ;;
            *)  # ── Cancel / window closed ────────────────────────────────────
                log_info "User cancelled playlist selection"
                return 1
                ;;
        esac
    done
}
