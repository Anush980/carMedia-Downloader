#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# core/download_manager.sh
#
# PURPOSE:
#   The central controller for all download activity. Manages:
#
#   QUEUE SYSTEM:
#     Downloads are added as "jobs". Each job has:
#       - URL, profile, save dir, URL type, playlist items
#       - Status: queued → downloading → done/failed/cancelled
#     Jobs are tracked in parallel Bash arrays (DM_URL[], DM_STATUS[], etc.)
#
#   PROGRESS WINDOW:
#     Uses yad --progress in TWO modes:
#       Normal mode:  clean UI — filename, progress bar, speed, ETA
#       Dev mode:     same + --enable-log pane shows raw yt-dlp output
#
#     Progress is fed by a "feeder" process that:
#       1. Reads a shared STATE_FILE every 0.5s
#       2. Writes YAD progress protocol lines to a FIFO
#       The worker (yt-dlp) writes to STATE_FILE as it runs.
#
#   PAUSE / RESUME:
#     Uses UNIX signals:
#       Pause  → kill -SIGSTOP $WORKER_PID  (freezes process, keeps partial file)
#       Resume → kill -SIGCONT $WORKER_PID  (continues from exactly where paused)
#     yt-dlp's --retries handles partial file resumption if the process is killed.
#
#   QUEUE COUNTER:
#     The progress label shows "Video X of Y | Completed: N | Remaining: R"
#     These counters are updated by _dm_advance_queue() after each job.
#
#   KDE PLASMA CLOSE FIX:
#     YAD windows on KDE sometimes ignore the X button due to window manager
#     decoration handling. Fix: trap SIGTERM/SIGHUP on the yad process group
#     and also set --kill-parent so YAD kills its parent (us) when closed.
#     We also track the YAD PID and do kill -TERM on it if detected closed.
#
# USED BY: ui.sh (dm_start_session called from _submit)
# ─────────────────────────────────────────────────────────────────────────────

# ── Job queue state arrays ────────────────────────────────────────────────────
declare -a DM_JOB_IDS=()
declare -A DM_URL DM_MODE DM_PROFILE DM_SAVEDIR DM_URLTYPE DM_ITEMS DM_TITLE
declare -A DM_STATUS DM_PCT DM_SPEED DM_ETA DM_DOWNLOADED DM_PID

DM_NEXT_ID=1
DM_CURRENT_JOB=0
DM_TOTAL_JOBS=0
DM_COMPLETED=0
DM_FAILED=0

# Shared IPC
DM_STATE_FILE=""
DM_FIFO=""
DM_YAD_PID=0
DM_WORKER_PID=0
DM_DEV_LOG_FILE=""   # Append-only file; feeder tails it for LOG lines (replaces blocking FIFO)
DM_DEV_LOG_PIPE=""   # Kept for logger.sh compat but no longer used for yt-dlp raw output
DM_PAUSED=false
DM_SESSION_ACTIVE=false  # SIGTERM guard: true while dm_start_session is running

# ─────────────────────────────────────────────────────────────────────────────
# dm_add_job
# Registers one download job into the queue.
# ─────────────────────────────────────────────────────────────────────────────
dm_add_job() {
    local url="$1" mode="$2" profile="$3" savedir="$4" urltype="$5" items="${6:-}"

    local id="$DM_NEXT_ID"
    (( DM_NEXT_ID++ ))
    DM_JOB_IDS+=( "$id" )
    DM_TOTAL_JOBS="${#DM_JOB_IDS[@]}"

    DM_URL[$id]="$url"
    DM_MODE[$id]="$mode"
    DM_PROFILE[$id]="$profile"
    DM_SAVEDIR[$id]="$savedir"
    DM_URLTYPE[$id]="$urltype"
    DM_ITEMS[$id]="$items"
    DM_TITLE[$id]="Fetching..."
    DM_STATUS[$id]="queued"
    DM_PCT[$id]=0
    DM_SPEED[$id]="—"
    DM_ETA[$id]="—"
    DM_DOWNLOADED[$id]="—"
    DM_PID[$id]=0

    log_info "Job #$id queued: url=$url mode=$mode profile=$profile urltype=$urltype items=[$items]"
    return "$id"
}

# ─────────────────────────────────────────────────────────────────────────────
# dm_start_session
# Main entry point: starts the progress window and runs all queued jobs.
# Called from ui.sh after jobs have been added via dm_add_job.
# ─────────────────────────────────────────────────────────────────────────────
dm_start_session() {
    log_info "dm_start_session: ${#DM_JOB_IDS[@]} job(s) queued"
    DM_SESSION_ACTIVE=true

    # Set up IPC
    DM_STATE_FILE=$(mktemp /tmp/carmedia_state_XXXXXX)
    DM_FIFO=$(mktemp -u /tmp/carmedia_fifo_XXXXXX)
    mkfifo "$DM_FIFO"

    if [[ "$DEV_MODE" == "true" ]]; then
        # Use an append-only plain file instead of a FIFO — avoids blocking writes
        DM_DEV_LOG_FILE=$(mktemp /tmp/carmedia_devlog_XXXXXX)
        # Also set DEV_LOG_PIPE for logger.sh compat (logger writes to this path);
        # logger will try -p check which will be false → it won't block.
        DEV_LOG_PIPE="$DM_DEV_LOG_FILE"
    fi

    _dm_init_state

    # Start feeder (pushes state to YAD)
    _dm_feeder "$DM_STATE_FILE" "$DM_FIFO" "$DM_DEV_LOG_FILE" &
    local FEEDER_PID=$!
    log_info "Feeder PID: $FEEDER_PID"

    # Launch YAD window
    _dm_launch_window "$DM_FIFO"
    DM_YAD_PID=$!
    log_info "YAD PID: $DM_YAD_PID"

    # Process each job in sequence
    for job_id in "${DM_JOB_IDS[@]}"; do
        DM_CURRENT_JOB="$job_id"
        log_info "=== Starting job #$job_id ==="

        _dm_run_job "$job_id"
        local job_result=$?

        if [[ $job_result -eq 0 ]]; then
            (( DM_COMPLETED++ ))
            DM_STATUS[$job_id]="done"
        else
            if [[ "${DM_STATUS[$job_id]}" == "cancelled" ]]; then
                log_warn "Job #$job_id was cancelled — stopping queue"
                break
            fi
            (( DM_FAILED++ ))
            DM_STATUS[$job_id]="failed"
        fi
        log_info "Job #$job_id finished: status=${DM_STATUS[$job_id]} completed=$DM_COMPLETED failed=$DM_FAILED"
    done

    # All jobs done — signal feeder to finish
    log_info "All jobs processed. Completed=$DM_COMPLETED Failed=$DM_FAILED"
    echo "ALL_DONE=1" >> "$DM_STATE_FILE"

    # Wait a moment for the window to show completion, then clean up
    sleep 1.5
    kill "$FEEDER_PID" 2>/dev/null || true
    kill "$DM_YAD_PID" 2>/dev/null || true
    wait "$FEEDER_PID" 2>/dev/null || true

    # Cleanup temp files
    rm -f "$DM_STATE_FILE" "$DM_FIFO" "$DM_DEV_LOG_FILE"
    DM_SESSION_ACTIVE=false
    log_info "dm_start_session complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# _dm_launch_window
# Opens the YAD progress window. Dev mode adds --enable-log pane.
# Returns PID of yad process.
# ─────────────────────────────────────────────────────────────────────────────
_dm_launch_window() {
    local fifo="$1"

    local yad_base_args=(
        --progress
        --title="CarMedia Pro – Downloading"
        --text="Downloading... Please wait!"
        --percentage=0
        --width=600
        --center
        --auto-kill
        --enable-log="Logs"
        --log-expanded
    )

    # Buttons (only Cancel now; Pause/Resume removed as they break the progress pipe)
    local btn_args=(
        --button=" Cancel!process-stop:1"
    )

    # KDE Plasma close-button fix:
    #   --kill-parent makes YAD send SIGTERM to its parent (us) when the
    #   window manager X button is clicked, so we can clean up properly.
    local kde_args=( --kill-parent )

    log_info "Launching progress window with inline logs"

    yad "${yad_base_args[@]}" \
        "${btn_args[@]}" \
        "${kde_args[@]}" \
        < "$fifo" 2>/dev/null &

    echo $!

    # Handle button presses in background
    _dm_button_handler &
}

# ─────────────────────────────────────────────────────────────────────────────
# _dm_button_handler
# Waits for YAD to exit, reads the button code, acts accordingly.
# Runs in background while the main session processes jobs.
# ─────────────────────────────────────────────────────────────────────────────
_dm_button_handler() {
    while kill -0 "$DM_YAD_PID" 2>/dev/null; do
        sleep 0.3
    done

    # YAD exited — get exit code from wait
    wait "$DM_YAD_PID" 2>/dev/null
    local btn=$?
    log_info "YAD closed: btn=$btn"

    case $btn in
        1)  # Cancel button or KDE X button
            log_warn "Cancel requested — killing worker PID $DM_WORKER_PID"
            DM_STATUS[$DM_CURRENT_JOB]="cancelled"
            if [[ "$DM_WORKER_PID" -gt 0 ]]; then
                kill_process_tree "$DM_WORKER_PID" "TERM"
                sleep 0.3
                kill_process_tree "$DM_WORKER_PID" "KILL"
            fi
            ;;
        0|*)
            # Window closed normally (auto-close after completion)
            log_info "Progress window closed normally"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# _dm_run_job JOB_ID
# Executes a single download job with retry logic.
# Returns 0 on success, 1 on failure.
# ─────────────────────────────────────────────────────────────────────────────
_dm_run_job() {
    local id="$1"

    local url="${DM_URL[$id]}"
    local mode="${DM_MODE[$id]}"
    local profile="${DM_PROFILE[$id]}"
    local savedir="${DM_SAVEDIR[$id]}"
    local urltype="${DM_URLTYPE[$id]}"
    local items="${DM_ITEMS[$id]}"

    # Validate output directory
    mkdir -p "$savedir" 2>/dev/null || {
        log_error "Cannot create save dir: $savedir"
        handle_error "filesystem" "Cannot create output folder:\n$savedir"
        return 1
    }
    [[ ! -w "$savedir" ]] && {
        handle_error "filesystem" "No write permission:\n$savedir"
        return 1
    }

    # Fetch title for display
    log_info "Fetching title for job #$id..."
    local title
    title=$(fetch_video_title "$url" 2>/dev/null) || title="Downloading..."
    DM_TITLE[$id]="$title"
    log_info "Title: $title"

    # Update state
    _dm_write_state "$id" "⬇ Downloading" 0 "Starting..." "..." "0" "$title"

    # Build yt-dlp args
    build_yt_dlp_args "$url" "$mode" "$profile" "$savedir" "$urltype" "$items"

    local attempt exit_code=1

    for attempt in 1 2; do
        log_info "Job #$id attempt $attempt — running yt-dlp"
        _dm_write_status "$id" "⬇ Downloading (attempt $attempt)"

        # Run yt-dlp in background so we can get its PID for pause/resume
        _dm_run_ytdlp "$id" &
        DM_WORKER_PID=$!
        DM_PID[$id]=$DM_WORKER_PID
        log_info "yt-dlp PID: $DM_WORKER_PID"

        wait "$DM_WORKER_PID"
        exit_code=$?

        log_info "Job #$id attempt $attempt exit_code=$exit_code"

        # Cancelled?
        if [[ "${DM_STATUS[$id]}" == "cancelled" ]]; then
            log_warn "Job #$id was cancelled"
            return 1
        fi

        if [[ $exit_code -eq 0 ]]; then
            _dm_write_state "$id" "Complete" 100 "—" "—" "Done" "$title"
            return 0
        fi

        if [[ $attempt -eq 1 ]]; then
            log_warn "Job #$id: attempt 1 failed — updating yt-dlp before retry"
            _dm_write_status "$id" "Updating yt-dlp, retrying..."
            update_ytdlp
            build_yt_dlp_args "$url" "$mode" "$profile" "$savedir" "$urltype" "$items"
        fi
    done

    log_error "Job #$id failed after 2 attempts"
    _dm_write_status "$id" "Failed"
    handle_error "ytdlp" "Download failed after 2 attempts.\n\nURL: $url\nTitle: $title"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# _dm_run_ytdlp JOB_ID
# Runs yt-dlp, parses each output line, updates the STATE_FILE.
# This runs as a subprocess (background &) so we can get its PID.
# ─────────────────────────────────────────────────────────────────────────────
_dm_run_ytdlp() {
    local id="$1"
    local title="${DM_TITLE[$id]}"
    local completed_so_far=$DM_COMPLETED
    local total=$DM_TOTAL_JOBS

    # Capture yt-dlp's real exit code via a temp file.
    # We cannot use PIPESTATUS inside a process substitution, so we run yt-dlp
    # on the left side of a pipe and save the exit code explicitly.
    local exit_code_file; exit_code_file=$(mktemp /tmp/carmedia_ytdlp_rc_XXXXXX)

    yt-dlp "${YT_DLP_ARGS[@]}" 2>&1 | {
        while IFS= read -r line; do
            # Always log raw line
            log_debug "[yt-dlp] $line"
            # Append raw line to the dev log file (non-blocking) so it shows in YAD
            if [[ -n "$DM_DEV_LOG_FILE" ]]; then
                echo "$line" >> "$DM_DEV_LOG_FILE" 2>/dev/null || true
            fi

            # ── Parse progress line ───────────────────────────────────────────────
            # Format: [download]  68.4% of 321.09MiB at  22.77MiB/s ETA 00:09
            if [[ "$line" =~ \[download\][[:space:]]+([0-9]+)(\.[0-9]+)?% ]]; then
                local pct="${BASH_REMATCH[1]}"
                local speed="—" eta="—" total_size="—"

                [[ "$line" =~ at[[:space:]]+([0-9.]+[[:space:]]?[KMGTkm]i?B/s) ]] \
                    && speed="${BASH_REMATCH[1]}"
                [[ "$line" =~ ETA[[:space:]]+([0-9:]+) ]] \
                    && eta="${BASH_REMATCH[1]}"
                [[ "$line" =~ of[[:space:]]+([0-9.]+[[:space:]]?[KMGTkm]i?B) ]] \
                    && total_size="${BASH_REMATCH[1]}"

                local queue_info="Video $((completed_so_far+1)) of $total | Done: $completed_so_far | Left: $((total-completed_so_far))"

                _dm_write_state "$id" " Downloading" \
                    "$pct" "$speed" "$eta" "$total_size" "$title" "$queue_info"

            # ── Merge / ffmpeg line ───────────────────────────────────────────────
            elif [[ "$line" =~ \[Merger\]|\[ffmpeg\]|\[VideoConvertor\] ]]; then
                _dm_write_state "$id" " Merging streams…" \
                    99 "—" "Almost done…" "—" "$title"

            # ── Destination line (file saved) ─────────────────────────────────────
            elif [[ "$line" =~ \[download\]\ Destination:(.+) ]]; then
                local fname; fname=$(basename "${BASH_REMATCH[1]}")
                log_info "Saving to: $fname"

            # ── Already downloaded ────────────────────────────────────────────────
            elif [[ "$line" =~ \[download\].*has\ already\ been\ downloaded ]]; then
                _dm_write_state "$id" " Already downloaded" \
                    100 "—" "—" "—" "$title"

            # ── Error line ────────────────────────────────────────────────────────
            elif [[ "$line" =~ ERROR: ]]; then
                log_error "yt-dlp: $line"
                _dm_write_status "$id" " ${line:0:80}"
            fi
        done
    }
    # PIPESTATUS[0] is yt-dlp's exit code (left side of pipe), PIPESTATUS[1] is the subshell
    local ytdlp_rc="${PIPESTATUS[0]}"
    echo "$ytdlp_rc" > "$exit_code_file"

    local rc; rc=$(cat "$exit_code_file" 2>/dev/null); rc=${rc:-1}
    rm -f "$exit_code_file"
    log_info "_dm_run_ytdlp exit code: $rc"
    return "$rc"
}

# ─────────────────────────────────────────────────────────────────────────────
# _dm_feeder STATE_FILE FIFO FEEDER_PID
# Background process: reads STATE_FILE every 0.5s, writes YAD protocol lines.
#
# YAD progress protocol (written to stdin FIFO):
#   NUMBER     → set progress bar percentage (0-100)
#   # TEXT     → set the label text (supports Pango markup)
#   LOG TEXT   → append line to dev log pane (only with --enable-log)
# ─────────────────────────────────────────────────────────────────────────────
_dm_feeder() {
    local state_file="$1" fifo="$2" dev_log_file="${3:-}"
    local last_pct=-1
    local dev_log_pos=0   # byte offset — tracks how far we've read the dev log file
    log_info "Feeder started"

    # Open the FIFO once for writing (fd 3). This avoids re-opening on every
    # write iteration which can stall if YAD's reader is momentarily slow.
    exec 3>"$fifo"

    while true; do
        # Read state (source the file — safe, it's our own temp file)
        local PCT=0 SPEED="—" ETA="—" DL_SIZE="—" STATUS="Starting"
        local TITLE="Downloading..." QUEUE_INFO="" ALL_DONE=0
        source "$state_file" 2>/dev/null || true

        if [[ "$ALL_DONE" == "1" ]]; then
            echo "100" >&3
            echo "#  All downloads complete!" >&3
            log_info "Feeder: ALL_DONE — exiting"
            break
        fi

        # Push percentage
        if [[ "$PCT" != "$last_pct" ]]; then
            echo "$PCT" >&3
            last_pct="$PCT"
        fi

        # Push label (multi-line Pango markup)
        {
            printf '# '
            printf '<b>%s</b>\n' "$TITLE"
            printf ' Speed: %s    ETA: %s    %s\n' "$SPEED" "$ETA" "$DL_SIZE"
            printf '%s\n' "$STATUS"
            [[ -n "$QUEUE_INFO" ]] && printf '<small>%s</small>\n' "$QUEUE_INFO"
        } >&3

        # Stream new lines from the dev log file to YAD's always-expanded log pane.
        # Uses tail-style byte-offset reads so we never block or re-send old lines.
        if [[ -n "$dev_log_file" && -f "$dev_log_file" ]]; then
            local new_lines
            new_lines=$(tail -c +$((dev_log_pos + 1)) "$dev_log_file" 2>/dev/null || true)
            if [[ -n "$new_lines" ]]; then
                while IFS= read -r log_line; do
                    printf 'LOG %s\n' "$log_line" >&3
                done <<< "$new_lines"
                dev_log_pos=$(wc -c < "$dev_log_file" 2>/dev/null || echo "$dev_log_pos")
            fi
        fi

        sleep 0.5
    done

    exec 3>&-   # close fd
    log_info "Feeder exited"
}

# ─────────────────────────────────────────────────────────────────────────────
# State file helpers
# ─────────────────────────────────────────────────────────────────────────────
_dm_init_state() {
    cat > "$DM_STATE_FILE" << 'INIT'
PCT=0
SPEED=—
ETA=—
DL_SIZE=—
STATUS=Initialising...
TITLE=CarMedia Pro
QUEUE_INFO=
ALL_DONE=0
INIT
}

_dm_write_state() {
    local id="$1" status="$2" pct="$3" speed="$4" eta="$5" dl_size="$6" title="$7"
    local queue_info="${8:-}"
    cat > "$DM_STATE_FILE" << STATEBLOCK
PCT=${pct}
SPEED=${speed}
ETA=${eta}
DL_SIZE=${dl_size}
STATUS=${status}
TITLE=$(printf '%s' "$title" | tr "'" ' ')
QUEUE_INFO=${queue_info}
ALL_DONE=0
STATEBLOCK
}

_dm_write_status() {
    local id="$1" status="$2"
    echo "STATUS=${status}" >> "$DM_STATE_FILE"
}
