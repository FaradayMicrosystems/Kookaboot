# shellcheck shell=bash
# KookaBoot v1.1 commands. Each cmd_* parses its own arguments.

kb_settle() {
    local dev=$1 part i
    part=$(kb_drive_part "$dev" 1)
    kb_have_cmd partprobe && partprobe -- "$dev" 2>/dev/null || true
    kb_have_cmd udevadm && udevadm settle 2>/dev/null || true
    for (( i = 0; i < 20; i++ )); do
        [[ -b $part ]] && return 0
        sleep 0.5
    done
    kb_die "Partition $part did not appear after install."
}

# kb_parse_size VALUE -> bytes. VALUE: bytes, 700M, 4G, or an existing file.
kb_parse_size() {
    if [[ -f $1 ]]; then
        stat -c %s -- "$1"
    elif [[ $1 =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$1"
    else
        numfmt --from=iec -- "${1^^}" 2>/dev/null || kb_die "Not a size: $1 (use e.g. 700M, 4G)"
    fi
}

kb_backup_root() { printf '%s\n' "${KB_STATE_DIR:-/var/lib/kookaboot}/backups"; }

# ---------------------------------------------------------------- install
cmd_install() {
    local dev="" gpt=0 sb=1 label=KookaBoot reinstall=0 args=() existing rc=0
    while (( $# )); do
        case $1 in
            --gpt) gpt=1 ;;
            --no-secure-boot) sb=0 ;;
            --label) label=${2:?--label needs a value}; shift ;;
            --reinstall) reinstall=1 ;;
            -*) kb_die "install: unknown option $1" ;;
            *) [[ -z $dev ]] || kb_die "install: one device only"; dev=$1 ;;
        esac
        shift
    done
    [[ -n $dev ]] || kb_die "Usage: kookaboot install /dev/sdX [--gpt] [--no-secure-boot] [--label NAME] [--reinstall]"
    [[ ${#label} -le 11 ]] || kb_die "--label must be 11 characters or fewer (exFAT limit)."

    kb_need_root
    (( gpt )) && kb_need_cmd parted "parted"
    dev=$(kb_drive_resolve "$dev")
    kb_drive_assert_safe "$dev" wipe
    kb_ventoy_dir >/dev/null || exit 1

    kb_info "Target drive:"
    kb_drive_describe "$dev"
    kb_info ""
    kb_info "Health check:"
    kb_health_check "$dev" || rc=$?
    (( rc == 2 )) && kb_die "Refusing to install to a failing drive."

    existing=$(kb_ventoy_disk_version "$dev")
    if [[ -n $existing && $reinstall == 0 ]]; then
        kb_die "$dev already has Ventoy $existing. Use 'kookaboot upgrade-ventoy $dev' to keep images, or add --reinstall to wipe it."
    fi

    kb_info ""
    kb_confirm_typed "$(basename -- "$dev")" \
        "ALL DATA on $dev will be ERASED. Ventoy $KB_VENTOY_VERSION and the Rookery will be installed."

    if [[ -n $existing ]]; then args+=(-I); else args+=(-i); fi
    (( gpt )) && args+=(-g)
    (( sb )) || args+=(-S)
    args+=(-L "$label" "$dev")

    kb_info "Installing Ventoy $KB_VENTOY_VERSION ..."
    kb_ventoy_run "${args[@]}" >&2 || kb_die "Ventoy install failed. See output above."
    kb_settle "$dev"

    kb_mount_data "$dev"
    kb_rookery_init "$KB_MNT" "$KB_VENTOY_VERSION"
    kb_unmount_data
    kb_ok "KookaBoot installed on $dev. Add images with: kookaboot add $dev IMAGE --sums SHA256SUMS"
}

# ---------------------------------------------------------------- health
cmd_health() {
    local dev=${1:-} rc=0
    [[ -n $dev ]] || kb_die "Usage: kookaboot health /dev/sdX"
    kb_need_root
    dev=$(kb_drive_resolve "$dev")
    [[ -b $dev ]] || kb_die "$dev is not a block device."
    kb_drive_describe "$dev"
    kb_health_check "$dev" || rc=$?
    return "$rc"
}

# ---------------------------------------------------------------- space
cmd_space() {
    local dev="" need=0
    while (( $# )); do
        case $1 in
            --need) need=$(kb_parse_size "${2:?--need needs a value}") || exit 1; shift ;;
            -*) kb_die "space: unknown option $1" ;;
            *) dev=$1 ;;
        esac
        shift
    done
    [[ -n $dev ]] || kb_die "Usage: kookaboot space /dev/sdX [--need SIZE|FILE]"
    kb_need_root
    dev=$(kb_drive_resolve "$dev")
    kb_drive_assert_safe "$dev" mounted
    kb_mount_data "$dev"
    kb_space_report "$KB_MNT" "$need"
}

# ---------------------------------------------------------------- add
cmd_add() {
    local dev="" iso="" hash="" sums="" sig="" keyring="" name="" replace=0
    local expected size dest part
    while (( $# )); do
        case $1 in
            --sha256)  hash=${2:?}; shift ;;
            --sums)    sums=${2:?}; shift ;;
            --sig)     sig=${2:?}; shift ;;
            --keyring) keyring=${2:?}; shift ;;
            --name)    name=${2:?}; shift ;;
            --replace) replace=1 ;;
            -*) kb_die "add: unknown option $1" ;;
            *) if [[ -z $dev ]]; then dev=$1; elif [[ -z $iso ]]; then iso=$1; else kb_die "add: too many arguments"; fi ;;
        esac
        shift
    done
    [[ -n $dev && -n $iso ]] || kb_die "Usage: kookaboot add /dev/sdX IMAGE (--sha256 HASH | --sums FILE [--sig FILE] [--keyring FILE]) [--name NAME] [--replace]"
    [[ -f $iso ]] || kb_die "Image not found: $iso"
    [[ $iso =~ $KB_IMAGE_EXT_RE ]] || kb_warn "$(basename -- "$iso") does not look like a bootable image (.iso/.img/...)."
    name=${name:-$(basename -- "$iso")}
    [[ $name != */* ]] || kb_die "--name must be a file name, not a path."

    kb_need_root
    dev=$(kb_drive_resolve "$dev")
    kb_drive_assert_safe "$dev" mounted

    # 1. Verify the source before anything touches the drive.
    expected=$(kb_resolve_expected "$iso" "$hash" "$sums" "$sig" "$keyring") || exit 1
    kb_info "Verifying $(basename -- "$iso") ..."
    kb_verify_image "$iso" "$expected" || kb_die "Source image failed verification. Nothing was written."
    kb_ok "Source checksum matches."

    # 2. Plan space.
    kb_mount_data "$dev"
    kb_rookery_is_drive "$KB_MNT" || kb_die "$dev is not a KookaBoot drive (no /rookery/rookery.conf). Run 'kookaboot install' first."
    dest=$KB_MNT/rookery/images/$name
    if [[ -e $dest && $replace == 0 ]]; then
        kb_die "$name is already on the drive. Add --replace to overwrite it."
    fi
    size=$(stat -c %s -- "$iso")
    if [[ -e $dest ]]; then
        # Replacing frees the old copy's space.
        size=$(( size - $(stat -c %s -- "$dest") ))
        (( size < 0 )) && size=0
    fi
    kb_info "Space check:"
    kb_space_report "$KB_MNT" "$size" || kb_die "Not enough space. Nothing was written."

    # 3. Copy, flush, re-verify the copy on the drive.
    part=$dest.part
    kb_info "Copying to drive ..."
    cp -- "$iso" "$part" || { rm -f -- "$part"; kb_die "Copy failed."; }
    sync -- "$part" 2>/dev/null || sync
    # Drop cached pages so the re-check reads from the drive, not RAM.
    [[ -w /proc/sys/vm/drop_caches ]] && echo 1 > /proc/sys/vm/drop_caches
    kb_info "Re-verifying the copy on the drive ..."
    if ! kb_verify_image "$part" "$expected"; then
        mv -f -- "$part" "$KB_MNT/rookery/.quarantine/$name"
        kb_die "The copy on the drive is corrupt (drive or cable fault?). Moved to /rookery/.quarantine/$name."
    fi
    mv -f -- "$part" "$dest"
    kb_rookery_ledger_set "$KB_MNT" "$name" "$expected"
    kb_ok "$name added to the Rookery."
}

# ---------------------------------------------------------------- list
cmd_list() {
    local dev=${1:-} size path count=0
    [[ -n $dev ]] || kb_die "Usage: kookaboot list /dev/sdX"
    kb_need_root
    dev=$(kb_drive_resolve "$dev")
    kb_drive_assert_safe "$dev" mounted
    kb_mount_data "$dev"
    kb_rookery_is_drive "$KB_MNT" || kb_die "$dev is not a KookaBoot drive."
    grep -E '^(KOOKABOOT_VERSION|VENTOY_VERSION|CREATED)=' "$KB_MNT/rookery/rookery.conf"
    printf '\n'
    while IFS=$'\t' read -r size path; do
        printf '%10s  %s\n' "$(kb_human "$size")" "$path"
        count=$(( count + 1 ))
    done < <(kb_rookery_images "$KB_MNT")
    printf '\n%d image(s)\n' "$count"
}

# ---------------------------------------------------------------- upgrade-ventoy
cmd_upgrade_ventoy() {
    local dev=${1:-} have ts serial host_backup before after rc=0
    [[ -n $dev ]] || kb_die "Usage: kookaboot upgrade-ventoy /dev/sdX"
    kb_need_root
    dev=$(kb_drive_resolve "$dev")
    kb_drive_assert_safe "$dev" mounted
    kb_ventoy_dir >/dev/null || exit 1

    have=$(kb_ventoy_disk_version "$dev")
    [[ -n $have ]] || kb_die "$dev does not have Ventoy installed."
    if [[ $have == "$KB_VENTOY_VERSION" ]]; then
        kb_ok "$dev already has Ventoy $have (the tested version). Nothing to do."
        return 0
    fi
    if kb_version_ge "$have" "$KB_VENTOY_VERSION"; then
        kb_die "$dev has Ventoy $have, newer than the tested $KB_VENTOY_VERSION. Not downgrading."
    fi

    kb_health_check "$dev" || rc=$?
    (( rc == 2 )) && kb_die "Refusing to write to a failing drive. Copy your images off it."

    # Back up config and record the image list.
    kb_mount_data "$dev"
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    serial=$(kb_drive_field "$dev" SERIAL); serial=${serial:-$(basename -- "$dev")}
    host_backup="$(kb_backup_root)/$serial/$ts"
    before=$(kb_rookery_images "$KB_MNT")
    mkdir -p -- "$host_backup" "$KB_MNT/rookery/.backup/$ts"
    if [[ -d $KB_MNT/ventoy ]]; then
        cp -a -- "$KB_MNT/ventoy" "$host_backup/"
        cp -a -- "$KB_MNT/ventoy" "$KB_MNT/rookery/.backup/$ts/"
    fi
    printf '%s\n' "$before" > "$host_backup/images.tsv"
    kb_ok "Config backed up to $host_backup and /rookery/.backup/$ts"
    kb_unmount_data

    # Ventoy needs every partition unmounted to upgrade.
    kb_drive_assert_safe "$dev" wipe

    kb_confirm_typed "$(basename -- "$dev")" \
        "Ventoy on $dev will be upgraded $have -> $KB_VENTOY_VERSION. Images are not touched."
    kb_ventoy_run -u "$dev" >&2 || kb_die "Ventoy upgrade failed. Backups are in $host_backup"
    kb_settle "$dev"

    kb_mount_data "$dev"
    if [[ ! -f $KB_MNT/ventoy/ventoy.json && -f $host_backup/ventoy/ventoy.json ]]; then
        cp -a -- "$host_backup/ventoy" "$KB_MNT/"
        kb_warn "ventoy/ was missing after upgrade and was restored from backup."
    fi
    after=$(kb_rookery_images "$KB_MNT")
    if [[ $before != "$after" ]]; then
        kb_err "Image list changed during upgrade! Before/after lists:"
        diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
        kb_die "Check the drive. Backup: $host_backup"
    fi
    kb_rookery_is_drive "$KB_MNT" && kb_rookery_conf_set "$KB_MNT" VENTOY_VERSION "$KB_VENTOY_VERSION"
    kb_ok "Ventoy upgraded to $KB_VENTOY_VERSION. All $(grep -c . <<<"$after" || true) image(s) intact."
}
