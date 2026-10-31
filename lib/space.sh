# shellcheck shell=bash
# Free-space planning for the Ventoy data partition.

KB_MIN_FREE_MB=${KB_MIN_FREE_MB:-1024}

# kb_space_free MNT -> free bytes
kb_space_free() {
    df -B1 --output=avail -- "$1" | tail -n1 | tr -d ' '
}

# kb_space_total MNT -> total bytes
kb_space_total() {
    df -B1 --output=size -- "$1" | tail -n1 | tr -d ' '
}

# kb_space_fits FREE NEED -> 0 if NEED bytes fit and leave KB_MIN_FREE_MB spare
kb_space_fits() {
    local free=$1 need=$2 reserve=$(( KB_MIN_FREE_MB * 1024 * 1024 ))
    (( free - need >= reserve ))
}

# kb_space_report MNT [NEED_BYTES]
kb_space_report() {
    local mnt=$1 need=${2:-0} free total
    free=$(kb_space_free "$mnt")
    total=$(kb_space_total "$mnt")
    kb_info "  Total : $(kb_human "$total")"
    kb_info "  Free  : $(kb_human "$free")"
    kb_info "  Keep  : ${KB_MIN_FREE_MB} MiB spare (KB_MIN_FREE_MB)"
    if (( need > 0 )); then
        kb_info "  Need  : $(kb_human "$need")"
        if kb_space_fits "$free" "$need"; then
            kb_ok "Fits. $(kb_human $(( free - need ))) free afterwards."
            return 0
        fi
        kb_err "Does not fit. Free up $(kb_human $(( need + KB_MIN_FREE_MB*1024*1024 - free ))) or use a bigger drive."
        return 1
    fi
}
