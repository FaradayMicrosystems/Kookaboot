# shellcheck shell=bash
# The Virtual Rookery: folder layout on the Ventoy data partition.
#
#   /rookery/rookery.conf     drive record (KookaBoot + Ventoy versions)
#   /rookery/images/          verified images; the only folder Ventoy shows
#   /rookery/SHA256SUMS       checksum of every image added (for re-checks)
#   /rookery/.quarantine/     copies that failed verification after writing
#   /rookery/.backup/         ventoy/ config backups made before upgrades
#   /ventoy/ventoy.json       Ventoy config written by KookaBoot

KB_IMAGE_EXT_RE='\.(iso|img|wim|vhd|vhdx|efi|vtoy)$'

kb_rookery_is_drive() {
    [[ -f $1/rookery/rookery.conf ]]
}

# kb_rookery_init MNT VENTOY_VERSION
kb_rookery_init() {
    local mnt=$1 vver=$2
    mkdir -p -- "$mnt/rookery/images" "$mnt/rookery/.quarantine" "$mnt/rookery/.backup" "$mnt/ventoy"
    {
        printf '# KookaBoot drive record. Written by kookaboot; edit with care.\n'
        printf 'ROOKERY_FORMAT=1\n'
        printf 'KOOKABOOT_VERSION=%s\n' "$KB_VERSION"
        printf 'VENTOY_VERSION=%s\n' "$vver"
        printf 'CREATED=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$mnt/rookery/rookery.conf"

    if [[ ! -f $mnt/ventoy/ventoy.json ]]; then
        cat > "$mnt/ventoy/ventoy.json" <<'EOF'
{
    "control": [
        { "VTOY_DEFAULT_SEARCH_ROOT": "/rookery/images" },
        { "VTOY_MENU_TIMEOUT": "10" }
    ]
}
EOF
    fi
}

# kb_rookery_conf_set MNT KEY VALUE
kb_rookery_conf_set() {
    local conf=$1/rookery/rookery.conf key=$2 val=$3
    if grep -q "^$key=" "$conf"; then
        sed -i "s|^$key=.*|$key=$val|" "$conf"
    else
        printf '%s=%s\n' "$key" "$val" >> "$conf"
    fi
}

# Checksum ledger: /rookery/SHA256SUMS, GNU format, paths relative to images/.
# kb_rookery_ledger_set MNT NAME HASH
kb_rookery_ledger_set() {
    local ledger=$1/rookery/SHA256SUMS name=$2 hash=$3 tmp
    touch -- "$ledger"
    tmp=$(mktemp)
    awk -v n="$name" '{ f=$0; sub(/^[0-9a-f]+ [ *]/, "", f); if (f!=n) print }' "$ledger" > "$tmp"
    printf '%s  %s\n' "$hash" "$name" >> "$tmp"
    cat -- "$tmp" > "$ledger"
    rm -f -- "$tmp"
}

# kb_rookery_images MNT -> "SIZE<TAB>RELATIVE_PATH" per image, sorted
kb_rookery_images() {
    local root=$1/rookery/images
    [[ -d $root ]] || return 0
    ( cd -- "$root" && find . -type f -printf '%s\t%P\n' ) \
        | { grep -Ei "$KB_IMAGE_EXT_RE" || true; } | sort -t$'\t' -k2
}
