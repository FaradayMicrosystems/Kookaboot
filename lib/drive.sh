# shellcheck shell=bash
# Drive detection and safety checks. Every destructive command calls
# kb_drive_assert_safe before touching a device.

# kb_drive_resolve DEV -> canonical /dev path (follows /dev/disk/by-id links)
kb_drive_resolve() {
    local dev
    dev=$(readlink -f -- "$1" 2>/dev/null) || dev=$1
    printf '%s\n' "$dev"
}

# kb_drive_part DEV N -> partition N of DEV (sdb -> sdb1, nvme0n1 -> nvme0n1p1)
kb_drive_part() {
    local dev=$1 n=$2
    if [[ $dev =~ [0-9]$ ]]; then
        printf '%sp%s\n' "$dev" "$n"
    else
        printf '%s%s\n' "$dev" "$n"
    fi
}

# kb_drive_field DEV FIELD -> one lsblk column for the whole disk
kb_drive_field() {
    lsblk -dno "$2" -- "$1" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# kb_drive_system_disks -> whole disks that hold the running system
# (/, /boot, /boot/efi, /usr, /var, /home, live-ISO media and active swap), one per line.
kb_drive_system_disks() {
    local src mp
    {
        # Live ISO media: /cdrom (casper), /run/live/medium (live-boot), /isodevice
        for mp in / /boot /boot/efi /usr /var /home /cdrom /run/live/medium /isodevice; do
            src=$(findmnt -no SOURCE -- "$mp" 2>/dev/null) || continue
            [[ $src == /dev/* ]] && printf '%s\n' "${src%%\[*}"
        done
        [[ -r /proc/swaps ]] && awk 'NR>1 && $1 ~ /^\/dev\// {print $1}' /proc/swaps
    } | while read -r src; do
        lsblk -snlpo NAME,TYPE -- "$src" 2>/dev/null | awk '$2=="disk"{print $1}'
    done | sort -u
}

# kb_drive_mounts DEV -> "PARTITION MOUNTPOINT" for each mounted partition
kb_drive_mounts() {
    lsblk -lnpo NAME,MOUNTPOINT -- "$1" 2>/dev/null | awk 'NF==2 {print $1, $2}'
}

# kb_drive_describe DEV -> human summary printed to stderr
kb_drive_describe() {
    local dev=$1
    kb_info "  Device : $dev"
    kb_info "  Model  : $(kb_drive_field "$dev" MODEL)"
    kb_info "  Size   : $(kb_drive_field "$dev" SIZE)"
    kb_info "  Serial : $(kb_drive_field "$dev" SERIAL)"
    kb_info "  Bus    : $(kb_drive_field "$dev" TRAN)"
}

# kb_drive_assert_safe DEV MODE
#   MODE=wipe     : refuse if any partition is mounted (install)
#   MODE=mounted  : allow the drive's own partitions to be mounted (add, upgrade)
# Always refuses: non-disk devices and disks holding the running system.
kb_drive_assert_safe() {
    local dev=$1 mode=${2:-wipe} type sys mounts
    [[ -b $dev ]] || kb_die "$dev is not a block device."
    type=$(kb_drive_field "$dev" TYPE)
    [[ $type == disk || $type == loop ]] \
        || kb_die "$dev is a '$type', not a whole disk. Give the disk (e.g. /dev/sdb), not a partition."

    while read -r sys; do
        [[ -n $sys && $sys == "$dev" ]] \
            && kb_die "$dev holds the running system. KookaBoot will never write to it."
    done < <(kb_drive_system_disks)

    if [[ $mode == wipe ]]; then
        local bytes
        bytes=$(lsblk -bdno SIZE -- "$dev" 2>/dev/null | tr -d ' ')
        (( ${bytes:-0} >= 1073741824 )) \
            || kb_die "$dev is smaller than 1 GiB. Too small for KookaBoot (floppy or card reader slot?)."
        mounts=$(kb_drive_mounts "$dev")
        if [[ -n $mounts ]]; then
            kb_err "$dev has mounted partitions:"
            printf '        %s\n' "$mounts" >&2
            kb_die "Unmount them first (e.g. 'sudo umount ${dev}*'), then retry."
        fi
    fi
}

# kb_mount_data DEV -> sets KB_MNT to the mounted Ventoy data partition.
# Reuses an existing mount. Mounts it ourselves otherwise and unmounts on exit.
KB_MNT=""
KB_MNT_OWNED=0
kb_mount_data() {
    local part existing
    part=$(kb_drive_part "$1" 1)
    [[ -b $part ]] || kb_die "$part not found. Is $1 a KookaBoot drive?"
    existing=$(findmnt -no TARGET -- "$part" 2>/dev/null | head -n1 || true)
    if [[ -n $existing ]]; then
        KB_MNT=$existing
        return 0
    fi
    KB_MNT=$(mktemp -d /tmp/kookaboot.XXXXXX)
    if ! mount -- "$part" "$KB_MNT" 2>/dev/null; then
        # Kernels without exFAT: fall back to FUSE if installed.
        if ! { kb_have_cmd mount.exfat-fuse && mount.exfat-fuse "$part" "$KB_MNT" >/dev/null 2>&1; }; then
            rmdir -- "$KB_MNT"
            kb_die "Could not mount $part. exFAT needs Linux 5.7+ or the exfat-fuse package."
        fi
    fi
    KB_MNT_OWNED=1
    trap kb_unmount_data EXIT
}

kb_unmount_data() {
    if [[ $KB_MNT_OWNED == 1 && -n $KB_MNT ]]; then
        sync
        umount -- "$KB_MNT" 2>/dev/null && rmdir -- "$KB_MNT" 2>/dev/null
        KB_MNT_OWNED=0
    fi
}
