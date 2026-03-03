#!/usr/bin/env bash
# core/download_manager.sh
# IDM-style download manager using yad --progress + timed polling.
# No --listen pipe (too fragile). Progress bar + live info labels via
# a background polling loop that rewrites a simple YAD info window.

# ─────────────────────────────────────────────────────────────────────────────
# dm_run URL PROFILE_KEY SAVE_DIR LIMIT
# Main entry point called from ui.sh
# ─────────────────────────────────────────────────────────────────────────────
dm_run() {
    local url="$1" profile_key="$2" save_dir="$3" limit="${4:-0}"

    log_info "dm_run: url=$url profile=$profile_key save=$save_dir limit=$limit"

    # State file — worker writes, UI reads
    local STATE_FILE; STATE_FILE=$(mktemp /tmp/carmedia_state_XXXXXX)
    local FIFO; FIFO=$(mktemp -u /tmp/carmedia_fifo_XXXXXX)
    mkfifo "$FIFO"
    local PID_FILE; PID_FILE=$(mktemp /tmp/carmedia_pid_XXXXXX)

    log_info "STATE_FILE=$STATE_FILE  FIFO=$FIFO"

    # Initialise state
    cat > "$STATE_FILE" << 'STATE'
PCT=0
SPEED=Calculating...
ETA=...
DOWNLOADED=0
TOTAL=unknown
STATUS=Starting
TITLE=Fetching info...
DONE=0
FAILED=0
PAUSED=0
STATE

    # ── Start download worker ────────────────────────────────────────────────
    _dm_worker "$url" "$profile_key" "$save_dir" "$limit" "$STATE_FILE" "$FIFO" &
    local WORKER_PID=$!
    echo "$WORKER_PID" > "$PID_FILE"
    log_info "Worker PID: $WORKER_PID"

    # ── Launch the YAD progress dialog (reads from FIFO) ─────────────────────
    _dm_show_window "$url" "$FIFO" "$STATE_FILE" "$WORKER_PID" "$PID_FILE"

    # Cleanup
    rm -f "$STATE_FILE" "$FIFO" "$PID_FILE"
    log_info "dm_run complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# _dm_show_window — YAD progress window + button handler
# ─────────────────────────────────────────────────────────────────────────────
_dm_show_window() {
    local url="$1" fifo="$2" state_file="$3" worker_pid="$4" pid_file="$5"

    log_info "Launching YAD progress window"

    # Feed the FIFO in a side process
    _dm_feeder "$state_file" "$fifo" "$worker_pid" &
    local FEEDER_PID=$!
    log_info "Feeder PID: $FEEDER_PID"

    # YAD progress window
    yad --progress \
        --title="CarMedia  ·  Downloading" \
        --text="Initialising download…\n<small>${url}</small>" \
        --percentage=0 \
        --width=580 \
        --center \
        --enable-log="Download Activity" \
        --log-expanded \
        --log-height=160 \
        --button=" Pause!media-playback-pause:2" \
        --button=" Resume!media-playback-start:3" \
        --button=" Cancel!process-stop:1" \
        < "$fifo" 2>/dev/null
    local BTN=$?

    log_info "YAD exited with button code: $BTN"

    # Kill feeder
    kill "$FEEDER_PID" 2>/dev/null || true

    local worker_pid_actual
    worker_pid_actual=$(cat "$pid_file" 2>/dev/null || echo "$worker_pid")

    case $BTN in
        1)  # Cancel
            log_warn "User cancelled — killing worker $worker_pid_actual"
            kill -TERM "$worker_pid_actual" 2>/dev/null || true
            sleep 0.3
            kill -KILL "$worker_pid_actual" 2>/dev/null || true
            echo "STATUS=Cancelled" >> "$state_file"
            ;;
        2)  # Pause
            log_info "User paused — SIGSTOP to $worker_pid_actual"
            kill -STOP "$worker_pid_actual" 2>/dev/null || true
            # Re-open window so user can resume
            _dm_show_window "$url" "$fifo" "$state_file" "$worker_pid_actual" "$pid_file"
            ;;
        3)  # Resume
            log_info "User resumed — SIGCONT to $worker_pid_actual"
            kill -CONT "$worker_pid_actual" 2>/dev/null || true
            _dm_show_window "$url" "$fifo" "$state_file" "$worker_pid_actual" "$pid_file"
            ;;
        0|*)
            # Window auto-closed (download finished) or closed by user
            wait "$worker_pid_actual" 2>/dev/null || true
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# _dm_feeder — reads state file every 0.5s, writes YAD progress protocol lines
# YAD progress protocol:
#   NUMBER       → set percentage
#   # TEXT       → set label text
#   LOG TEXT     → append to log pane (needs --enable-log)
# ─────────────────────────────────────────────────────────────────────────────
_dm_feeder() {
    local state_file="$1" fifo="$2" worker_pid="$3"
    local last_pct=-1

    log_info "Feeder started"

    while true; do
        # Check worker still alive
        if ! kill -0 "$worker_pid" 2>/dev/null; then
            log_info "Feeder: worker gone, sending 100"
            echo "100"      > "$fifo"
            echo "# Download complete!" > "$fifo"
            sleep 0.5
            break
        fi

        # Read current state
        local PCT=0 SPEED="—" ETA="—" DOWNLOADED="—" TOTAL="—"
        local STATUS="Running" TITLE="Downloading…" DONE=0 FAILED=0
        # shellcheck source=/dev/null
        source "$state_file" 2>/dev/null || true

        # Push percentage (only when changed)
        if [[ "$PCT" != "$last_pct" ]]; then
            echo "$PCT" > "$fifo"
            last_pct="$PCT"
        fi

        # Push label (always refresh)
        printf '# <b>%s</b>\n⚡ Speed: %s   ⏱ ETA: %s\n💾 %s / %s\n🔄 %s\n' \
            "$TITLE" "$SPEED" "$ETA" "$DOWNLOADED" "$TOTAL" "$STATUS" > "$fifo"

        # Push a log line every update
        printf 'LOG %s  |  %s  |  ETA %s  |  %s/%s\n' \
            "$STATUS" "$SPEED" "$ETA" "$DOWNLOADED" "$TOTAL" > "$fifo"

        if [[ "$DONE" == "1" ]]; then
            echo "100" > "$fifo"
            echo "#   Complete! Saved to disk." > "$fifo"
            sleep 0.5
            break
        fi

        if [[ "$FAILED" == "1" ]]; then
            echo "#   Download failed — check terminal for details." > "$fifo"
            sleep 1
            break
        fi

        sleep 0.5
    done

    log_info "Feeder exiting"
}

# ─────────────────────────────────────────────────────────────────────────────
# _dm_worker — runs yt-dlp, parses output, writes to state file
# ─────────────────────────────────────────────────────────────────────────────
_dm_worker() {
    local url="$1" profile_key="$2" save_dir="$3" limit="$4"
    local state_file="$5"
    # $6 = fifo (unused directly, feeder reads state file)

    log_info "Worker: fetching title for $url"

    # Fetch title
    local title
    title=$(yt-dlp --get-title --no-playlist "$url" 2>/dev/null) || title="$(basename "$url")"
    log_info "Worker: title = $title"
    echo "TITLE=$(printf '%q' "$title")" >> "$state_file"

    # Validate save dir
    mkdir -p "$save_dir" 2>/dev/null || {
        log_error "Cannot create save dir: $save_dir"
        echo "FAILED=1" >> "$state_file"
        echo "STATUS=Failed: cannot create folder" >> "$state_file"
        return 1
    }

    build_yt_dlp_args "$url" "$profile_key" "$save_dir" "$limit"

    local attempt exit_code=1

    for attempt in 1 2; do
        log_info "Worker attempt $attempt: yt-dlp ${YT_DLP_ARGS[*]}"
        echo "STATUS=Downloading (attempt $attempt)" >> "$state_file"

        # Run yt-dlp, parse each line
        while IFS= read -r line; do
            # Always echo to terminal
            echo "  [yt-dlp] $line"

            # Parse: [download]  45.2% of 321.09MiB at  22.77MiB/s ETA 00:09
            if [[ "$line" =~ \[download\][[:space:]]+([0-9]+)%? ]]; then
                local pct="${BASH_REMATCH[1]}"

                local speed="—" eta="—" total="—" downloaded="—"

                [[ "$line" =~ at[[:space:]]+([0-9.]+[KMGTkm]i?B/s) ]] && speed="${BASH_REMATCH[1]}"
                [[ "$line" =~ ETA[[:space:]]+([0-9:]+) ]]              && eta="${BASH_REMATCH[1]}"
                [[ "$line" =~ of[[:space:]]+([0-9.]+[KMGTkm]i?B) ]]   && total="${BASH_REMATCH[1]}"

                # Write atomic state update
                cat > "$state_file" << STATEBLOCK
TITLE=$(printf '%q' "$title")
PCT=$pct
SPEED=$speed
ETA=$eta
DOWNLOADED=${pct}% of ${total}
TOTAL=$total
STATUS=Downloading
DONE=0
FAILED=0
STATEBLOCK

            elif [[ "$line" =~ \[Merger\]|\[ffmpeg\] ]]; then
                cat > "$state_file" << STATEBLOCK
TITLE=$(printf '%q' "$title")
PCT=99
SPEED=—
ETA=Merging...
DOWNLOADED=Merging streams
TOTAL=—
STATUS=Merging video+audio
DONE=0
FAILED=0
STATEBLOCK

            elif [[ "$line" =~ ERROR: ]]; then
                log_error "yt-dlp: $line"
            fi

        done < <(yt-dlp "${YT_DLP_ARGS[@]}" 2>&1)
        exit_code=${PIPESTATUS[0]}

        log_info "Worker attempt $attempt exit_code=$exit_code"

        if [[ $exit_code -eq 0 ]]; then
            cat > "$state_file" << STATEBLOCK
TITLE=$(printf '%q' "$title")
PCT=100
SPEED=—
ETA=—
DOWNLOADED=Complete
TOTAL=—
STATUS=Done
DONE=1
FAILED=0
STATEBLOCK
            log_info "Worker: download complete for '$title'"
            return 0
        fi

        if [[ $attempt -eq 1 ]]; then
            log_warn "Worker: attempt 1 failed, updating yt-dlp..."
            echo "STATUS=Updating yt-dlp and retrying..." >> "$state_file"
            update_ytdlp
            build_yt_dlp_args "$url" "$profile_key" "$save_dir" "$limit"
        fi
    done

    # All attempts failed
    cat > "$state_file" << STATEBLOCK
TITLE=$(printf '%q' "$title")
PCT=0
SPEED=—
ETA=—
DOWNLOADED=—
TOTAL=—
STATUS=Failed
DONE=0
FAILED=1
STATEBLOCK
    log_error "Worker: all attempts failed for $url"
    handle_error "ytdlp" "Download failed after 2 attempts.\nURL: $url"
    return 1
}
