# shellcheck shell=bash
# Drive health via SMART (smartmontools).
# Return codes: 0 = healthy, 1 = warning (or no SMART data), 2 = failing.

KB_HEALTH_ATTRS="Reallocated_Sector_Ct Current_Pending_Sector Offline_Uncorrectable Reported_Uncorrect"

# kb_health_read DEV -> smartctl output, trying USB-SATA bridge mode if needed
kb_health_read() {
    local dev=$1 out
    out=$(smartctl -H -A -- "$dev" 2>&1)
    if ! grep -qE 'SMART overall-health|SMART Health Status' <<<"$out"; then
        out=$(smartctl -d sat -H -A -- "$dev" 2>&1)
    fi
    printf '%s\n' "$out"
}

# kb_health_parse < smartctl-output -> prints findings, returns 0/1/2
kb_health_parse() {
    local out attr raw rc=0
    out=$(cat)

    if grep -qE 'SMART overall-health self-assessment test result: FAILED|SMART Health Status: (FAILED|.*FAILURE)' <<<"$out"; then
        kb_err "SMART reports the drive is FAILING."
        return 2
    fi

    if ! grep -qE 'self-assessment test result: PASSED|SMART Health Status: OK' <<<"$out"; then
        kb_warn "No SMART data (normal for most USB sticks). Health unknown."
        return 1
    fi

    # NVMe drives report errors differently.
    raw=$(awk -F: '/^Media and Data Integrity Errors/ {gsub(/[ ,]/,"",$2); print $2}' <<<"$out")
    if [[ -n $raw && $raw != 0 ]]; then
        kb_warn "Media and Data Integrity Errors = $raw"
        rc=1
    fi

    for attr in $KB_HEALTH_ATTRS; do
        # Columns: ID NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE
        raw=$(awk -v a="$attr" '$2==a {print $10}' <<<"$out")
        if [[ -n $raw && $raw =~ ^[0-9]+$ && $raw -gt 0 ]]; then
            kb_warn "$attr = $raw (sectors going bad)"
            rc=1
        fi
    done

    [[ $rc == 0 ]] && kb_ok "SMART health PASSED, no bad-sector counts."
    return "$rc"
}

# kb_health_check DEV -> 0/1/2 as above
kb_health_check() {
    if ! kb_have_cmd smartctl; then
        kb_warn "smartctl not installed (package: smartmontools). Health not checked."
        return 1
    fi
    kb_health_read "$1" | kb_health_parse
}
